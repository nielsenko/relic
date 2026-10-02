import 'package:http_parser/http_parser.dart' as parser;

final _clock = Stopwatch()..start();
var _refreshAtMs = -1;
var _value = '';
var _holds = 0;

/// The Date header value for now, RFC 9110 5.6.7 IMF-fixdate.
///
/// The wall clock is read once per second, at the second's boundary, and
/// the stopwatch tells when. A response pays a stopwatch read, not a
/// clock read and a format, and not that either while the date is held
/// with [holdHttpDate].
String httpDate() {
  if (_holds != 0) return _value;
  final ms = _clock.elapsedMilliseconds;
  if (ms >= _refreshAtMs) {
    final now = DateTime.now().toUtc();
    _value = parser.formatHttpDate(now);
    _refreshAtMs = ms + 1000 - now.millisecond;
  }
  return _value;
}

/// Brings the date up to now and holds it there until [releaseHttpDate],
/// so the calls in between read no clock.
///
/// For an adapter that answers a batch of requests in one synchronous
/// stretch: it holds the date for the stretch, which must be short
/// against the one second the value resolves. Holds nest.
void holdHttpDate() {
  if (_holds == 0) httpDate();
  _holds++;
}

/// Ends a hold begun with [holdHttpDate].
void releaseHttpDate() {
  assert(_holds > 0, 'releaseHttpDate without a hold');
  _holds--;
}
