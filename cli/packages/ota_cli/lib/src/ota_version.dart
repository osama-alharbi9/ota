import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:ota_cli/src/executables/executables.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [OtaVersion] instance.
final otaVersionRef = create(OtaVersion.new);

/// The [OtaVersion] instance available in the current zone.
OtaVersion get otaVersion => read(otaVersionRef);

/// {@template ota_version}
/// Provides information about installed and available versions of OTA.
/// {@endtemplate}
class OtaVersion {
  String get _workingDirectory => p.dirname(Platform.script.toFilePath());

  /// Whether the current version of OTA is the latest available.
  Future<bool> isLatest() async {
    final currentVersion = await fetchCurrentGitHash();
    final latestVersion = await fetchLatestGitHash();

    return currentVersion == latestVersion;
  }

  /// Returns the remote HEAD ota hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchLatestGitHash() async {
    // Dependabot pushed branches with the same name breaking all clients
    // and requiring a prune to repair them.
    await git.remote(directory: _workingDirectory, args: ['prune', 'origin']);
    // Fetch upstream branch's commits and tags
    await git.fetch(directory: _workingDirectory, args: ['--tags']);
    // Get the latest commit revision of the upstream
    return git.revParse(revision: '@{upstream}', directory: _workingDirectory);
  }

  /// Returns the local HEAD ota hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchCurrentGitHash() async {
    // Get the commit revision of HEAD
    return git.revParse(revision: 'HEAD', directory: _workingDirectory);
  }

  /// Attempts a hard reset to the given revision.
  ///
  /// This is a reset instead of fast forward because if we are on a release
  /// branch with cherry picks, there may not be a direct fast-forward route
  /// to the next release.
  Future<void> attemptReset({required String revision}) async {
    return git.reset(
      revision: revision,
      directory: _workingDirectory,
      args: ['--hard'],
    );
  }

  /// Whether the current version of ota is tracking the stable branch. If
  /// we are not tracking stable, we should not check for newer versions of
  /// ota or try to auto-update.
  Future<bool> isTrackingStable() async {
    return (await git.currentBranch(directory: Directory(_workingDirectory))) ==
        'stable';
  }
}
