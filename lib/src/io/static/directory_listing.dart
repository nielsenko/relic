import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../../body/body.dart';
import '../../message/response.dart';

String _getHeader(final String sanitizedHeading) => '''<!DOCTYPE html>
<html>
<head>
  <title>Directory listing for $sanitizedHeading</title>
  <style>
  html, body {
    margin: 0;
    padding: 0;
  }
  body {
    font-family: sans-serif;
  }
  h1 {
    background-color: #4078c0;
    color: white;
    font-weight: normal;
    margin: 0 0 10px 0;
    padding: 16px 32px;
    white-space: nowrap;
  }
  ul {
    margin: 0;
  }
  li {
    padding: 0;
  }
  a {
    line-height: 1.4em;
  }
  </style>
</head>
<body>
  <h1>$sanitizedHeading</h1>
  <ul>
''';

const String _trailer = '''  </ul>
</body>
</html>
''';

Response listDirectory(final String fileSystemPath, final String dirPath) {
  final controller = StreamController<Uint8List>();
  const encoding = Utf8Codec();
  const sanitizer = HtmlEscape();

  void add(final String string) {
    controller.add(encoding.encode(string));
  }

  var heading = path.relative(dirPath, from: fileSystemPath);
  if (heading == '.') {
    heading = '/';
  } else {
    heading = '/$heading/';
  }

  add(_getHeader(sanitizer.convert(heading)));

  // Return a sorted listing of the directory contents asynchronously.
  Directory(dirPath).list().toList().then((final entities) {
    entities.sort((final e1, final e2) {
      if (e1 is Directory && e2 is! Directory) {
        return -1;
      }
      if (e1 is! Directory && e2 is Directory) {
        return 1;
      }
      return e1.path.compareTo(e2.path);
    });

    for (final entity in entities) {
      var name = path.relative(entity.path, from: dirPath);
      if (entity is Directory) name += '/';
      final sanitizedName = sanitizer.convert(name);
      add('    <li><a href="$sanitizedName">$sanitizedName</a></li>\n');
    }

    add(_trailer);
    controller.close();
  });

  return Response.ok(
    body: Body.fromDataStream(
      controller.stream,
    ),
    encoding: encoding,
  );
}
