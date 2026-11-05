import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/code_push_client_wrapper.dart';
import 'package:ota_cli/src/config/config.dart';
import 'package:ota_cli/src/doctor.dart';
import 'package:ota_cli/src/executables/executables.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/platform/platform.dart';
import 'package:ota_cli/src/pubspec_editor.dart';
import 'package:ota_cli/src/ota_command.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_validator.dart';
import 'package:ota_client/ota_client.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// {@template init_command}
///
/// `ota init`
/// Initialize OTA.
/// {@endtemplate}
class InitCommand extends OtaCommand {
  /// {@macro init_command}
  InitCommand() {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Initialize the app even if a "ota.yaml" already exists.',
        negatable: false,
      )
      ..addOption('display-name', help: 'The display name of the app.')
      ..addOption('organization-id', help: 'The organization ID to use.');
  }

  @override
  String get description => 'Register this app on your OTA server.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    try {
      await otaValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    try {
      if (!otaEnv.hasPubspecYaml) {
        logger.err('''
Could not find a "pubspec.yaml".
Please make sure you are running "ota init" from within your Flutter project.
''');
        return ExitCode.noInput.code;
      }
    } on Exception catch (error) {
      logger.err('Error parsing "pubspec.yaml": $error');
      return ExitCode.software.code;
    }

    final organizationMemberships = await codePushClientWrapper
        .getOrganizationMemberships();
    if (organizationMemberships.isEmpty) {
      logger.err(
        '''Your account has no organization. Register again in the console.''',
      );
      return ExitCode.software.code;
    }

    final Organization organization;
    final orgIdArg = results['organization-id'] as String?;
    if (orgIdArg != null) {
      final orgId = int.tryParse(orgIdArg);
      if (orgId == null) {
        logger.err('Invalid organization ID: "$orgIdArg"');
        return ExitCode.usage.code;
      }

      final organizationMembership = organizationMemberships.firstWhereOrNull(
        (o) => o.organization.id == orgId,
      );
      if (organizationMembership == null) {
        logger.err('Organization with ID "$orgId" not found.');
        _logAvailableOrganizations(organizationMemberships);
        return ExitCode.usage.code;
      }
      organization = organizationMembership.organization;
    } else if (organizationMemberships.length > 1) {
      if (!otaEnv.canAcceptUserInput) {
        logger.err(
          'Multiple organizations found. '
          'Use --organization-id to specify one:',
        );
        _logAvailableOrganizations(organizationMemberships);
        return ExitCode.usage.code;
      }
      organization = logger.chooseOne(
        'Which organization should this app belong to?',
        choices: organizationMemberships.map((o) => o.organization).toList(),
        display: (o) => o.name,
      );
    } else {
      organization = organizationMemberships.first.organization;
    }

    final force = results['force'] == true;

    Set<String>? androidFlavors;
    Set<String>? iosFlavors;
    Set<String>? macosFlavors;
    var productFlavors = <String>{};
    final projectRoot = otaEnv.getFlutterProjectRoot()!;
    final initializeGradleProgress = logger.progress('Initializing gradlew');
    final bool shouldStartGradleDaemon;
    try {
      shouldStartGradleDaemon = await _shouldStartGradleDaemon(
        projectRoot.path,
      );
    } on Exception {
      initializeGradleProgress.fail();
      logger.err('Unable to initialize gradlew.');
      return ExitCode.software.code;
    }
    initializeGradleProgress.complete();

    if (shouldStartGradleDaemon) {
      try {
        await gradlew.startDaemon(projectRoot.path);
      } on Exception {
        logger.err('Unable to start gradle daemon.');
        return ExitCode.software.code;
      }
    }

    final detectFlavorsProgress = logger.progress('Detecting product flavors');
    try {
      androidFlavors = await _maybeGetAndroidFlavors(projectRoot.path);
      iosFlavors = apple.flavors(platform: ApplePlatform.ios);
      macosFlavors = apple.flavors(platform: ApplePlatform.macos);
      productFlavors = <String>{
        if (androidFlavors != null) ...androidFlavors,
        if (iosFlavors != null) ...iosFlavors,
        if (macosFlavors != null) ...macosFlavors,
      };
      if (productFlavors.isEmpty) {
        detectFlavorsProgress.complete('No product flavors detected.');
      } else {
        detectFlavorsProgress.complete(
          '${productFlavors.length} product flavors detected:',
        );
        for (final flavor in productFlavors) {
          logger.info('  - $flavor');
        }
      }
    } on Exception catch (error) {
      detectFlavorsProgress.fail();
      logger.err('Unable to extract product flavors.\n$error');
      return ExitCode.software.code;
    }

    final otaYaml = otaEnv.getOtaYaml();
    final existingFlavors = otaYaml?.flavors;
    Set<String> newFlavors;
    if (existingFlavors != null) {
      final existingFlavorNames = existingFlavors.keys.toSet();
      newFlavors = productFlavors.difference(existingFlavorNames);
    } else if (otaYaml != null) {
      // Existing ota.yaml without flavors — treat all detected flavors
      // as new so they can be added without resetting the base app_id.
      newFlavors = productFlavors;
    } else {
      newFlavors = {};
    }

    // New flavors not being empty means that there is already an existing app
    // and we just need to add the new flavor entries.
    // If the --force flag is present, we will completely reinit the app and
    // don't care about which flavors are new.
    if (!force && newFlavors.isNotEmpty) {
      logger.info('New flavors detected: ${newFlavors.join(', ')}');
      final updateOtaYamlProgress = logger.progress(
        'Adding flavors to ota.yaml',
      );

      final AppMetadata existingApp;
      try {
        existingApp = await codePushClientWrapper.getApp(
          appId: otaYaml!.appId,
        );
      } on Exception catch (e) {
        updateOtaYamlProgress.fail('Failed to get existing app info: $e');
        return ExitCode.software.code;
      }

      final deflavoredAppName = existingApp.displayName
          .replaceAll(RegExp(r'\(.*\)'), '')
          .trim();
      final flavorsToAppIds = otaYaml.flavors ?? {};
      for (final flavor in newFlavors) {
        final app = await codePushClientWrapper.createApp(
          appName: '$deflavoredAppName ($flavor)',
          organizationId: organization.id,
        );
        flavorsToAppIds[flavor] = app.id;
      }
      _addOtaYamlToProject(
        projectRoot: projectRoot,
        appId: otaYaml.appId,
        flavors: flavorsToAppIds,
      );
      updateOtaYamlProgress.complete('Flavors added to ota.yaml');
      return ExitCode.success.code;
    }

    if (!force && otaEnv.hasOtaYaml) {
      logger
        ..err('A "ota.yaml" file already exists and seems up-to-date.')
        ..info(
          '''If you want to reinitialize OTA, please run ${lightCyan.wrap('ota init --force')}.''',
        );
      return ExitCode.software.code;
    }

    final String appId;
    Map<String, String>? flavors;
    try {
      final needsConfirmation = !force && otaEnv.canAcceptUserInput;
      final pubspecName = otaEnv.getPubspecYaml()!.name;
      var displayName = results['display-name'] as String?;
      displayName ??= needsConfirmation
          ? logger.prompt(
              '${lightGreen.wrap('?')} How should we refer to this app?',
              defaultValue: pubspecName,
            )
          : pubspecName;
      final hasNoFlavors = productFlavors.isEmpty;
      final hasSomeFlavors =
          productFlavors.isNotEmpty &&
          ((androidFlavors?.isEmpty ?? false) ||
              (iosFlavors?.isEmpty ?? false));

      if (hasNoFlavors) {
        // No platforms have any flavors so we just create a single app
        // and assign it as the default.
        final app = await codePushClientWrapper.createApp(
          appName: displayName,
          organizationId: organization.id,
        );
        appId = app.id;
      } else if (hasSomeFlavors) {
        // Some platforms have flavors and some do not so we create an app
        // for the default (no flavor) and then create an app per flavor.
        final app = await codePushClientWrapper.createApp(
          appName: displayName,
          organizationId: organization.id,
        );
        appId = app.id;
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          final app = await codePushClientWrapper.createApp(
            appName: '$displayName ($flavor)',
            organizationId: organization.id,
          );
          values[flavor] = app.id;
        }
        flavors = values;
      } else {
        // All platforms have flavors so we create an app per flavor
        // and assign the default to the first flavor.
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          final app = await codePushClientWrapper.createApp(
            appName: '$displayName ($flavor)',
            organizationId: organization.id,
          );
          values[flavor] = app.id;
        }
        flavors = values;
        appId = flavors.values.first;
      }
    } on Exception catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    _addOtaYamlToProject(
      projectRoot: projectRoot,
      appId: appId,
      flavors: flavors,
    );

    if (!otaEnv.pubspecContainsOtaYaml) {
      pubspecEditor.addOtaYamlToPubspecAssets();
    }

    logger.info(
      '''

${lightGreen.wrap('🚀 OTA initialized successfully!')}

✅ The app has been registered on ${otaEnv.hostedUri}.
✅ "ota.yaml" has been created.
✅ "pubspec.yaml" now lists "ota.yaml" as an asset.

Reference the following commands to get started:

📦 To create a new release use: "${lightCyan.wrap('ota release')}".
🚀 To push an update use: "${lightCyan.wrap('ota patch')}".
👀 To preview a release use: "${lightCyan.wrap('ota preview')}".

Console: ${link(uri: otaEnv.consoleUri)}''',
    );

    await doctor.runValidators(doctor.generalValidators, applyFixes: true);

    return ExitCode.success.code;
  }

  Future<bool> _shouldStartGradleDaemon(String projectPath) async {
    try {
      final isAvailable = await gradlew.isDaemonAvailable(projectPath);
      return !isAvailable;
    } on MissingAndroidProjectException {
      return false;
    }
  }

  Future<Set<String>?> _maybeGetAndroidFlavors(String projectPath) async {
    try {
      return await gradlew.productFlavors(projectPath);
    } on MissingAndroidProjectException {
      return null;
    }
  }

  OtaYaml _addOtaYamlToProject({
    required String appId,
    required Directory projectRoot,
    Map<String, String>? flavors,
  }) {
    final content =
        '''
# Over-the-air update settings for this app.
# This file is not secret and should be checked into version control.

# The unique identifier of this app on your OTA server.
app_id:

# Your OTA server. Baked into the app at build time.
base_url: ${otaEnv.hostedUri}

# auto_update controls whether the app checks for updates in the background on launch.
# Set to false to check for updates yourself.
# auto_update: false
''';

    final editor = YamlEditor(content)..update(['app_id'], appId);

    if (flavors != null) editor.update(['flavors'], flavors);

    otaEnv
        .getOtaYamlFile(cwd: projectRoot)
        .writeAsStringSync(editor.toString());

    return OtaYaml(appId: appId);
  }

  void _logAvailableOrganizations(
    List<OrganizationMembership> memberships,
  ) {
    logger.info('Available organizations:');
    for (final membership in memberships) {
      final org = membership.organization;
      logger.info('  ${org.name} (id: ${org.id})');
    }
  }
}
