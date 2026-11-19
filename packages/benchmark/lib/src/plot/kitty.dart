import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Whether stdout is a terminal that draws images sent by the kitty
/// graphics protocol: kitty, Ghostty, WezTerm and Konsole.
bool terminalDrawsImages() {
  // Not stdout.hasTerminal, which also wants a window size.
  if (stdioType(stdout) != StdioType.terminal) return false;
  final environment = Platform.environment;
  final term = environment['TERM'] ?? '';
  final program = environment['TERM_PROGRAM'] ?? '';
  return term.contains('kitty') ||
      term.contains('ghostty') ||
      program == 'ghostty' ||
      program == 'WezTerm' ||
      environment.containsKey('KITTY_WINDOW_ID') ||
      environment.containsKey('KONSOLE_VERSION');
}

/// [svg] as a PNG at [zoom] times its size, by `rsvg-convert`, or null when
/// that is not installed or fails.
Future<List<int>?> rasterize(String svg, {double zoom = 2}) async {
  final Process process;
  try {
    process = await Process.start('rsvg-convert', [
      '--format=png',
      '--zoom=$zoom',
    ]);
  } on ProcessException {
    return null;
  }
  process.stdin.write(svg);
  final png = BytesBuilder(copy: false);
  final (_, _, _, exitCode) = await (
    process.stdin.close(),
    process.stdout.forEach(png.add),
    process.stderr.drain<void>(),
    process.exitCode,
  ).wait;
  return exitCode == 0 ? png.takeBytes() : null;
}

/// The kitty graphics protocol escape codes that draw [png] at the cursor,
/// over [columns] columns of the terminal when given and at its own size
/// otherwise.
///
/// The image goes as base64 in chunks of 4096 bytes, each in an escape code
/// of its own. Only the first carries the keys: `f=100` for PNG and `a=T`
/// to transmit and display. `m=1` says that more follows.
String kittyImage(List<int> png, {int? columns}) {
  const chunk = 4096;
  final data = base64.encode(png);
  final buffer = StringBuffer();
  for (var at = 0; at < data.length; at += chunk) {
    final end = at + chunk < data.length ? at + chunk : data.length;
    final keys = [
      if (at == 0) ...['f=100', 'a=T', if (columns != null) 'c=$columns'],
      'm=${end < data.length ? 1 : 0}',
    ].join(',');
    buffer.write('\x1b_G$keys;${data.substring(at, end)}\x1b\\');
  }
  return buffer.toString();
}
