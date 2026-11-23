import 'dart:convert';
import 'dart:io';

/// What one zrk run measured.
///
/// Latencies are in milliseconds.
final class ZrkResult {
  final double rps;
  final double p50;
  final double p99;
  final double p999;

  /// Responses of any status.
  final int responses;

  /// Requests that got no response.
  final int failed;

  /// Responses with a status outside 2xx.
  final int nonOk;

  ZrkResult({
    required this.rps,
    required this.p50,
    required this.p99,
    required this.p999,
    required this.responses,
    required this.failed,
    required this.nonOk,
  });
}

/// The command that runs zrk: `BENCH_ZRK`, a JSON list, when it is set, and
/// the zrk of the PATH otherwise.
///
/// A sweep over a veth pair sets it, so that zrk runs in the network
/// namespace of the load tools while this process runs in the servers'.
List<String> zrkCommand() {
  final configured = Platform.environment['BENCH_ZRK'];
  if (configured == null || configured.isEmpty) return const ['zrk'];
  return (jsonDecode(configured) as List<dynamic>).cast<String>();
}

/// The zrk arguments of one run against [url] for [seconds], with the
/// JSON report written to [report].
///
/// A null [rate] is a closed loop at [connections] in flight, otherwise an
/// open loop at that many requests per second. Each of [headers] is a
/// `Name: value` line. An https [url] goes unverified, since the servers
/// here present test certificates.
List<String> zrkArguments(
  String url, {
  required int connections,
  required int seconds,
  required String report,
  int? rate,
  List<String> headers = const [],
  String? body,
  int? threads,
}) => [
  '--plain',
  '--format',
  'json',
  '-o',
  report,
  if (threads != null) ...['-t', '$threads'],
  '-c',
  '$connections',
  '-d',
  '${seconds}s',
  if (rate == null) '--closed' else ...['-R', '$rate'],
  if (url.startsWith('https:')) '-k',
  for (final header in headers) ...['-H', header],
  if (body != null) ...['-m', 'POST', '-b', body],
  url,
];

/// One zrk run against [url] for [seconds], as [zrkArguments] describes.
/// Needs `zrk` on the PATH, or `BENCH_ZRK`.
///
/// In open loop zrk measures each request's latency from when it was due,
/// so a server that falls behind the offered rate shows it in the tail as
/// well as in [ZrkResult.rps] against the rate.
Future<ZrkResult> runZrk(
  String url, {
  required int connections,
  required int seconds,
  int? rate,
  List<String> headers = const [],
  String? body,
  int? threads,
}) async {
  final zrk = zrkCommand();
  final dir = Directory.systemTemp.createTempSync('zrk');
  try {
    final report = '${dir.path}/report.json';
    final result = await Process.run(zrk.first, [
      ...zrk.sublist(1),
      ...zrkArguments(
        url,
        connections: connections,
        seconds: seconds,
        report: report,
        rate: rate,
        headers: headers,
        body: body,
        threads: threads,
      ),
    ]);
    final file = File(report);
    if (result.exitCode != 0 || !file.existsSync()) {
      throw ProcessException('zrk', [url], '${result.stderr}');
    }
    return parseZrkReport(file.readAsStringSync(), url);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// The [ZrkResult] of a zrk JSON report of a run against [url].
ZrkResult parseZrkReport(String text, String url) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  final latency = json['latency_us'] as Map<String, dynamic>;
  final statuses = json['status_codes'] as Map<String, dynamic>;
  final errors = json['errors'] as Map<String, dynamic>;
  // zrk counts responses by status class.
  var responses = 0;
  var nonOk = 0;
  for (final MapEntry(:key, :value) in statuses.entries) {
    responses += value as int;
    if (key != '2xx') nonOk += value;
  }
  // No percentiles without a response: a run with none is a dead server,
  // not a measurement.
  if (responses == 0) {
    throw ProcessException('zrk', [url], 'No responses from $url: $errors');
  }
  var failed = 0;
  for (final MapEntry(:key, :value) in errors.entries) {
    if (key != 'non_2xx_3xx') failed += value as int;
  }
  double ms(String key) => (latency[key] as num) / 1000;
  return ZrkResult(
    rps: (json['achieved_rate'] as num).toDouble(),
    p50: ms('p50'),
    p99: ms('p99'),
    p999: ms('p99_9'),
    responses: responses,
    failed: failed,
    nonOk: nonOk,
  );
}
