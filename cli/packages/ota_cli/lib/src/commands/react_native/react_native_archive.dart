import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

const _block = 512;

/// Packs every file under [directory] into a gzipped tar.
///
/// The output depends only on file paths and contents: entries are sorted and
/// carry no timestamps or owners, so an unchanged bundle hashes the same and
/// `ota patch` can tell there is nothing to publish.
Uint8List packDirectory(Directory directory) {
  final files =
      directory.listSync(recursive: true).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final tar = BytesBuilder(copy: false);
  for (final file in files) {
    final name = p.posix.joinAll(
      p.split(p.relative(file.path, from: directory.path)),
    );
    final bytes = file.readAsBytesSync();
    tar.add(_header(name, bytes.length));
    tar.add(bytes);
    final padding = (_block - bytes.length % _block) % _block;
    tar.add(Uint8List(padding));
  }
  tar.add(Uint8List(_block * 2));
  final gz = Uint8List.fromList(GZipCodec(level: 9).encode(tar.takeBytes()));
  // RFC 1952: byte 9 is the OS that wrote the file. 255 means unknown, so the
  // same bundle hashes the same on every machine.
  gz[9] = 255;
  return gz;
}

Uint8List _header(String name, int size) {
  var path = name;
  var prefix = '';
  if (utf8.encode(path).length > 100) {
    // ustar stores long paths as prefix + '/' + name, split at a slash.
    final parts = p.posix.split(name);
    for (var i = 1; i < parts.length; i++) {
      final head = parts.sublist(0, i).join('/');
      final tail = parts.sublist(i).join('/');
      if (utf8.encode(head).length <= 155 && utf8.encode(tail).length <= 100) {
        prefix = head;
        path = tail;
        break;
      }
    }
    if (prefix.isEmpty) {
      throw ArgumentError('Path too long for the update archive: $name');
    }
  }
  final header = Uint8List(_block);
  void put(int offset, String value) =>
      header.setRange(offset, offset + value.length, utf8.encode(value));
  void octal(int offset, int width, int value) =>
      put(offset, value.toRadixString(8).padLeft(width - 1, '0'));

  put(0, path);
  octal(100, 8, 420); // mode 0644
  octal(108, 8, 0); // uid
  octal(116, 8, 0); // gid
  octal(124, 12, size);
  octal(136, 12, 0); // mtime
  put(148, '        '); // checksum is computed with this field as spaces
  header[156] = 48; // '0': a regular file
  put(257, 'ustar');
  put(263, '00');
  put(345, prefix);
  final checksum = header.fold<int>(0, (sum, byte) => sum + byte);
  put(148, '${checksum.toRadixString(8).padLeft(6, '0')}\u0000 ');
  return header;
}
