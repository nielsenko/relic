import 'package:http_parser/http_parser.dart' as parser;
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

void main() {
  test('Given no hold, when the date is read, '
      'then it is the current time to the second', () {
    final before = DateTime.now().toUtc();

    final date = parser.parseHttpDate(httpDate());

    expect(date.difference(before).inSeconds.abs(), lessThanOrEqualTo(1));
  });

  test('Given a held date, when more than a second passes, '
      'then the date stays as it was until the hold is released', () async {
    holdHttpDate();
    final held = httpDate();

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final stillHeld = httpDate();
    releaseHttpDate();
    final released = httpDate();

    expect(stillHeld, held);
    expect(released, isNot(held));
  });

  test('Given two nested holds, when the inner one is released, '
      'then the date is still held', () async {
    holdHttpDate();
    holdHttpDate();
    final held = httpDate();
    releaseHttpDate();

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final afterInner = httpDate();
    releaseHttpDate();

    expect(afterInner, held);
  });
}
