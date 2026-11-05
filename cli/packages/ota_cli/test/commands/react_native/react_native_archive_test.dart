import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ota_cli/src/commands/react_native/react_native.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A minimal reader, so the test checks the bytes rather than the writer's model.
Map<String, String> readTar(List<int> gz) {
  final bytes = Uint8List.fromList(gzip.decode(gz));
  String field(int start, int length) {
    final slice = bytes.sublist(start, start + length);
    final end = slice.indexOf(0);
    return utf8.decode(end < 0 ? slice : slice.sublist(0, end));
  }

  final entries = <String, String>{};
  var offset = 0;
  while (offset + 512 <= bytes.length) {
    if (bytes.sublist(offset, offset + 512).every((b) => b == 0)) break;
    final name = field(offset, 100);
    final prefix = field(offset + 345, 155);
    final size = int.parse(field(offset + 124, 12).trim(), radix: 8);
    final contents = utf8.decode(bytes.sublist(offset + 512, offset + 512 + size));
    entries[prefix.isEmpty ? name : '$prefix/$name'] = contents;
    offset += 512 + ((size + 511) ~/ 512) * 512;
  }
  return entries;
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ota_archive_test'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String contents) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  test('packs every file with its relative path', () {
    write('main.jsbundle', 'bundle');
    write('assets/img/logo.png', 'png');
    expect(readTar(packDirectory(root)), {
      'assets/img/logo.png': 'png',
      'main.jsbundle': 'bundle',
    });
  });

  test('long paths split into prefix and name', () {
    final long = 'assets/${'node_modules/some-package/' * 5}icon.png';
    expect(long.length, greaterThan(100));
    write(long, 'png');
    expect(readTar(packDirectory(root)), {long: 'png'});
  });

  test('a path too long for ustar fails loudly', () {
    write('${'a' * 120}/${'b' * 120}.png', 'png');
    expect(() => packDirectory(root), throwsArgumentError);
  });

  test('the same contents always produce the same bytes', () {
    write('main.jsbundle', 'bundle');
    write('assets/a.png', 'a');
    final first = packDirectory(root);
    // Rewriting changes the modified time. The archive must not notice.
    sleep(const Duration(milliseconds: 1100));
    write('main.jsbundle', 'bundle');
    expect(packDirectory(root), first);
  });

  test('different contents produce different bytes', () {
    write('main.jsbundle', 'one');
    final first = packDirectory(root);
    write('main.jsbundle', 'two');
    expect(packDirectory(root), isNot(first));
  });

  test('header checksum is valid', () {
    write('main.jsbundle', 'bundle');
    final bytes = gzip.decode(packDirectory(root));
    final header = bytes.sublist(0, 512);
    final stored = int.parse(
      utf8.decode(header.sublist(148, 154)).trim(),
      radix: 8,
    );
    final computed = header.asMap().entries.fold<int>(
      0,
      (sum, e) => sum + (e.key >= 148 && e.key < 156 ? 32 : e.value),
    );
    expect(stored, computed);
  });
}
