import 'dart:convert';
import 'dart:io';

import 'package:ota_cli/src/commands/react_native/react_native.dart';
import 'package:ota_client/ota_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ota_rn_test'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String contents) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  void writePackageJson({bool sdk = true}) => write(
    'package.json',
    json.encode({
      'name': 'demo',
      'dependencies': {
        'react-native': '0.88.1',
        if (sdk) reactNativeSdkPackage: '0.1.0',
      },
    }),
  );

  group('parseAndroidVersion', () {
    test('reads Groovy syntax', () {
      expect(
        parseAndroidVersion('versionCode 7\n  versionName "1.2.3"'),
        '1.2.3+7',
      );
    });

    test('reads Kotlin syntax', () {
      expect(
        parseAndroidVersion('versionCode = 7\n  versionName = "1.2.3"'),
        '1.2.3+7',
      );
    });

    test('is null when either value is missing', () {
      expect(parseAndroidVersion('versionCode 7'), isNull);
      expect(parseAndroidVersion('versionName "1.2.3"'), isNull);
    });
  });

  group('parseIosVersion', () {
    test('reads the first build settings', () {
      expect(
        parseIosVersion('''
CURRENT_PROJECT_VERSION = 12;
MARKETING_VERSION = 2.0;
CURRENT_PROJECT_VERSION = 99;
'''),
        '2.0+12',
      );
    });

    test('accepts quoted values', () {
      expect(
        parseIosVersion(
          'CURRENT_PROJECT_VERSION = "3";\nMARKETING_VERSION = "1.0.1";',
        ),
        '1.0.1+3',
      );
    });

    test('is null when a setting is missing', () {
      expect(parseIosVersion('MARKETING_VERSION = 1.0;'), isNull);
    });
  });

  group('ReactNativeProject', () {
    test('find walks up to the project root', () {
      writePackageJson();
      final nested = Directory(p.join(root.path, 'src', 'screens'))
        ..createSync(recursive: true);
      expect(ReactNativeProject.find(cwd: nested)?.root.path, root.path);
    });

    test('find ignores a package without react-native', () {
      write('package.json', json.encode({'name': 'not-react-native'}));
      expect(ReactNativeProject.find(cwd: root), isNull);
    });

    test('hasSdk reads the dependencies', () {
      writePackageJson(sdk: false);
      expect(ReactNativeProject(root).hasSdk, isFalse);
      writePackageJson();
      expect(ReactNativeProject(root).hasSdk, isTrue);
    });

    test('runtime pins the installed React Native version', () {
      writePackageJson();
      write(
        'node_modules/react-native/package.json',
        json.encode({'version': '0.88.1'}),
      );
      expect(ReactNativeProject(root).runtime, 'react-native@0.88.1');
    });

    test('platforms lists the native projects that exist', () {
      Directory(p.join(root.path, 'android')).createSync();
      expect(ReactNativeProject(root).platforms, [ReleasePlatform.android]);
      Directory(p.join(root.path, 'ios')).createSync();
      expect(ReactNativeProject(root).platforms, [
        ReleasePlatform.android,
        ReleasePlatform.ios,
      ]);
    });

    test('entryLoadsSdk finds the import', () {
      write('index.js', "import 'ota-react-native';\n");
      write('other.js', "import 'react-native';\n");
      expect(ReactNativeProject(root).entryLoadsSdk('index.js'), isTrue);
      expect(ReactNativeProject(root).entryLoadsSdk('other.js'), isFalse);
      expect(ReactNativeProject(root).entryLoadsSdk('missing.js'), isFalse);
    });

    test('usesHermes honours the opt-outs', () {
      expect(ReactNativeProject(root).usesHermes(ReleasePlatform.android), isTrue);
      write('android/gradle.properties', 'hermesEnabled=false\n');
      expect(ReactNativeProject(root).usesHermes(ReleasePlatform.android), isFalse);
      write('ios/Podfile', 'use_react_native!(:hermes_enabled => false)\n');
      expect(ReactNativeProject(root).usesHermes(ReleasePlatform.ios), isFalse);
    });

    test('releaseVersion reads the native project', () {
      write(
        'android/app/build.gradle',
        'versionCode 4\nversionName "1.0"\n',
      );
      write(
        'ios/App.xcodeproj/project.pbxproj',
        'CURRENT_PROJECT_VERSION = 5;\nMARKETING_VERSION = 2.0;\n',
      );
      final project = ReactNativeProject(root);
      expect(project.releaseVersion(ReleasePlatform.android), '1.0+4');
      expect(project.releaseVersion(ReleasePlatform.ios), '2.0+5');
    });
  });
}
