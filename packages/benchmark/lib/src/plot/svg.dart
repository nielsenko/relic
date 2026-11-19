import 'dart:math' as math;

/// The colors of a chart: its surface, its inks and its series hues.
final class PlotTheme {
  final String surface;
  final String primary;
  final String secondary;
  final String muted;
  final String grid;
  final String axis;

  /// The categorical hues, in the order series take them.
  final List<String> series;

  const PlotTheme._({
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.grid,
    required this.axis,
    required this.series,
  });

  static const light = PlotTheme._(
    surface: '#fcfcfb',
    primary: '#0b0b0b',
    secondary: '#52514e',
    muted: '#898781',
    grid: '#e1e0d9',
    axis: '#c3c2b7',
    series: [
      '#2a78d6',
      '#eb6834',
      '#1baf7a',
      '#eda100',
      '#e87ba4',
      '#008300',
      '#6250d6',
      '#e34948',
    ],
  );

  static const dark = PlotTheme._(
    surface: '#1a1a19',
    primary: '#f0efec',
    secondary: '#c3c2b7',
    muted: '#898781',
    grid: '#2c2c2a',
    axis: '#383835',
    series: [
      '#3987e5',
      '#d95926',
      '#199e70',
      '#c98500',
      '#d55181',
      '#0ca30c',
      '#9085e9',
      '#e66767',
    ],
  );

  static PlotTheme named(String name) => name == 'dark' ? dark : light;
}

/// One bar: a value, and the interval around it when there is one.
final class Bar {
  final String label;
  final double value;
  final double? low;
  final double? high;

  /// The text after the value at the bar's tip, such as a change against
  /// a baseline.
  final String note;

  Bar(this.label, this.value, {this.low, this.high, this.note = ''});
}

/// A group of bars that share a scale.
final class BarPanel {
  final String title;
  final List<Bar> bars;

  BarPanel(this.title, this.bars);
}

const _font = 'system-ui, -apple-system, "Segoe UI", sans-serif';
const _width = 880.0;
const _pad = 24.0;

/// The rough width of [text] at [size] px in the system sans.
double _textWidth(String text, double size) => text.length * size * 0.56;

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _n(double value) => value.toStringAsFixed(1);

/// [value] in three or four figures: 882, 12.9k, 4.21M.
String compact(double value) {
  final magnitude = value.abs();
  String scaled(double divisor, String suffix) {
    final v = value / divisor;
    return '${v.abs() >= 100
        ? v.toStringAsFixed(0)
        : v.abs() >= 10
        ? v.toStringAsFixed(1)
        : v.toStringAsFixed(2)}$suffix';
  }

  if (magnitude >= 1e9) return scaled(1e9, 'G');
  if (magnitude >= 1e6) return scaled(1e6, 'M');
  if (magnitude >= 1e4) return scaled(1e3, 'k');
  if (magnitude >= 100) return value.toStringAsFixed(0);
  if (magnitude >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

final class _Svg {
  final PlotTheme theme;
  final StringBuffer _body = StringBuffer();

  _Svg(this.theme);

  void text(
    double x,
    double y,
    String text, {
    double size = 12,
    String? fill,
    String anchor = 'start',
    int weight = 400,
    bool tabular = false,
  }) => _body.writeln(
    '<text x="${_n(x)}" y="${_n(y)}" font-size="${_n(size)}" '
    'fill="${fill ?? theme.primary}" text-anchor="$anchor" '
    'font-weight="$weight"'
    '${tabular ? ' style="font-variant-numeric: tabular-nums"' : ''}>'
    '${_escape(text)}</text>',
  );

  void raw(String element) => _body.writeln(element);

  String finish(double height) =>
      '<svg xmlns="http://www.w3.org/2000/svg" width="${_n(_width)}" '
      'height="${_n(height)}" viewBox="0 0 ${_n(_width)} ${_n(height)}" '
      "font-family='$_font'>\n"
      '<rect width="100%" height="100%" fill="${theme.surface}"/>\n'
      '$_body</svg>\n';
}

double _header(_Svg svg, String title, String subtitle) {
  svg.text(_pad, 34, title, size: 16, weight: 600);
  if (subtitle.isEmpty) return 52;
  svg.text(_pad, 54, subtitle, fill: svg.theme.secondary);
  return 74;
}

/// Writes the lines of [footnote] below [y] and returns where they end.
double _footnote(_Svg svg, double y, String footnote) {
  if (footnote.isEmpty) return y;
  final lines = footnote.split('\n');
  for (final (i, line) in lines.indexed) {
    svg.text(_pad, y + 8 + i * 16, line, size: 11, fill: svg.theme.muted);
  }
  return y + 6 + lines.length * 16;
}

/// Horizontal bars in small multiples: one panel per group, each on a scale
/// of its own from zero, with the value at every bar's tip and a whisker
/// over the interval of a bar that has one.
String barChart({
  required String title,
  required List<BarPanel> panels,
  required PlotTheme theme,
  String subtitle = '',
  String footnote = '',
  String Function(double value) format = compact,
}) {
  const rowHeight = 26.0;
  const thickness = 14.0;
  final svg = _Svg(theme);
  var y = _header(svg, title, subtitle);

  final bars = [for (final panel in panels) ...panel.bars];
  final labelWidth = bars.fold<double>(
    0,
    (width, bar) => math.max(width, _textWidth(bar.label, 12)),
  );
  String tip(Bar bar) =>
      '${format(bar.value)}${bar.note.isEmpty ? '' : '  ${bar.note}'}';
  final tipWidth = bars.fold<double>(
    0,
    (width, bar) => math.max(width, _textWidth(tip(bar), 12)),
  );
  final left = _pad + labelWidth + 12;
  final span = _width - left - tipWidth - 12 - _pad;

  for (final panel in panels) {
    if (panel.title.isNotEmpty) {
      svg.text(_pad, y + 12, panel.title, fill: theme.secondary, weight: 600);
      y += 24;
    }
    final top = panel.bars.fold<double>(
      0,
      (most, bar) => math.max(most, bar.high ?? bar.value),
    );
    double x(double value) => top <= 0 ? left : left + value / top * span;
    svg.raw(
      '<line x1="${_n(left)}" y1="${_n(y)}" x2="${_n(left)}" '
      'y2="${_n(y + rowHeight * panel.bars.length)}" stroke="${theme.axis}" '
      'stroke-width="1"/>',
    );
    for (final bar in panel.bars) {
      final middle = y + rowHeight / 2;
      final end = x(bar.value);
      final width = math.max(end - left, 0.5);
      final radius = math.min(4.0, width);
      final low = bar.low;
      final high = bar.high;
      svg
        ..raw('<g>')
        ..raw(
          '<title>${_escape('${bar.label}: ${bar.value.toStringAsFixed(1)}'
          '${low == null || high == null ? '' : ' [${low.toStringAsFixed(1)}, ${high.toStringAsFixed(1)}]'}'
          '${bar.note.isEmpty ? '' : ' ${bar.note}'}')}</title>',
        )
        ..text(
          left - 12,
          middle + 4,
          bar.label,
          fill: theme.secondary,
          anchor: 'end',
        )
        // Square at the baseline, rounded at the data end.
        ..raw(
          '<path d="M${_n(left)},${_n(middle - thickness / 2)} '
          'h${_n(width - radius)} a${_n(radius)},${_n(radius)} 0 0 1 '
          '${_n(radius)},${_n(radius)} v${_n(thickness - 2 * radius)} '
          'a${_n(radius)},${_n(radius)} 0 0 1 -${_n(radius)},${_n(radius)} '
          'h-${_n(width - radius)} z" fill="${theme.series.first}"/>',
        );
      var labelAt = end;
      if (low != null && high != null && x(high) - x(low) >= 3) {
        labelAt = math.max(end, x(high));
        svg.raw(
          '<path d="M${_n(x(low))},${_n(middle)} H${_n(x(high))} '
          'M${_n(x(low))},${_n(middle - 4)} v8 '
          'M${_n(x(high))},${_n(middle - 4)} v8" fill="none" '
          'stroke="${theme.primary}" stroke-width="1.25"/>',
        );
      }
      svg
        ..text(labelAt + 8, middle + 4, format(bar.value), tabular: true)
        ..text(
          labelAt + 8 + _textWidth('${format(bar.value)}  ', 12),
          middle + 4,
          bar.note,
          fill: theme.muted,
          tabular: true,
        )
        ..raw('</g>');
      y += rowHeight;
    }
    y += 16;
  }
  return svg.finish(_footnote(svg, y, footnote) + 8);
}

/// One line of a [lineChart]: a name and a value at each point along x, or
/// null where it has none.
final class Series {
  final String name;
  final List<double?> values;

  Series(this.name, this.values);
}

/// Lines over the ordered points [xLabels], one per series, on a log scale
/// when the values span more than a factor of 20. At most eight series.
String lineChart({
  required String title,
  required List<String> xLabels,
  required List<Series> series,
  required PlotTheme theme,
  String subtitle = '',
  String xTitle = '',
  String footnote = '',
}) {
  assert(series.length <= theme.series.length, 'more series than hues');
  final svg = _Svg(theme);
  var y = _header(svg, title, subtitle);

  // The legend, always there for two or more series.
  if (series.length > 1) {
    var x = _pad;
    for (final (i, line) in series.indexed) {
      final width = 34 + _textWidth(line.name, 12) + 18;
      if (x + width > _width - _pad) {
        x = _pad;
        y += 20;
      }
      svg
        ..raw(
          '<line x1="${_n(x)}" y1="${_n(y + 6)}" x2="${_n(x + 22)}" '
          'y2="${_n(y + 6)}" stroke="${theme.series[i]}" stroke-width="2" '
          'stroke-linecap="round"/>',
        )
        ..raw(
          '<circle cx="${_n(x + 11)}" cy="${_n(y + 6)}" r="4" '
          'fill="${theme.series[i]}" stroke="${theme.surface}" '
          'stroke-width="2"/>',
        )
        ..text(x + 30, y + 10, line.name, fill: theme.secondary);
      x += width;
    }
    y += 30;
  }

  final values = [
    for (final line in series) ...line.values.nonNulls.where((v) => v > 0),
  ];
  if (values.isEmpty) return svg.finish(y + 8);
  final lowest = values.reduce(math.min);
  final highest = values.reduce(math.max);
  final log = highest / lowest > 20;
  final ticks = log ? _logTicks(lowest, highest) : _linearTicks(highest);
  final bottom = log ? ticks.first : 0.0;
  final top = ticks.last;

  const plotHeight = 300.0;
  final direct = series.length <= 4;
  final endWidth = direct
      ? series.fold<double>(
          0,
          (width, line) => math.max(width, _textWidth(line.name, 12)),
        )
      : 0.0;
  final left =
      _pad +
      ticks.fold<double>(
        0,
        (width, tick) => math.max(width, _textWidth(compact(tick), 11)),
      ) +
      10;
  final right = _width - _pad - (direct ? endWidth + 14 : 0);
  final plotTop = y + 8;
  final plotBottom = plotTop + plotHeight;
  double px(int index) => xLabels.length == 1
      ? (left + right) / 2
      : left + 16 + index / (xLabels.length - 1) * (right - left - 32);
  double py(double value) {
    final share = log
        ? (math.log(value) - math.log(bottom)) /
              (math.log(top) - math.log(bottom))
        : (value - bottom) / (top - bottom);
    return plotBottom - share * plotHeight;
  }

  for (final tick in ticks) {
    svg
      ..raw(
        '<line x1="${_n(left)}" y1="${_n(py(tick))}" x2="${_n(right)}" '
        'y2="${_n(py(tick))}" '
        'stroke="${tick == bottom ? theme.axis : theme.grid}" '
        'stroke-width="1"/>',
      )
      ..text(
        left - 8,
        py(tick) + 4,
        compact(tick),
        size: 11,
        fill: theme.muted,
        anchor: 'end',
        tabular: true,
      );
  }
  for (final (i, label) in xLabels.indexed) {
    svg.text(
      px(i),
      plotBottom + 18,
      label,
      size: 11,
      fill: theme.muted,
      anchor: 'middle',
      tabular: true,
    );
  }
  if (xTitle.isNotEmpty) {
    svg.text(
      (left + right) / 2,
      plotBottom + 38,
      xTitle,
      size: 11,
      fill: theme.muted,
      anchor: 'middle',
    );
  }

  final ends = <(double, String)>[];
  for (final (i, line) in series.indexed) {
    final points = [
      for (final (index, value) in line.values.indexed)
        if (value != null && value > 0) (px(index), py(value), index, value),
    ];
    if (points.isEmpty) continue;
    svg.raw(
      '<polyline points="${points.map((p) => '${_n(p.$1)},${_n(p.$2)}').join(' ')}" '
      'fill="none" stroke="${theme.series[i]}" stroke-width="2" '
      'stroke-linejoin="round" stroke-linecap="round"/>',
    );
    for (final (x, y, index, value) in points) {
      svg.raw(
        '<circle cx="${_n(x)}" cy="${_n(y)}" r="4" fill="${theme.series[i]}" '
        'stroke="${theme.surface}" stroke-width="2"><title>'
        '${_escape('${line.name}, ${xLabels[index]}: ${compact(value)}')}'
        '</title></circle>',
      );
    }
    ends.add((points.last.$2, line.name));
  }
  // Names at the line ends, unless two of them would sit on each other.
  ends.sort((a, b) => a.$1.compareTo(b.$1));
  final apart = [
    for (var i = 1; i < ends.length; i++) ends[i].$1 - ends[i - 1].$1,
  ].every((gap) => gap >= 14);
  if (direct && apart) {
    for (final (y, name) in ends) {
      svg.text(right + 10, y + 4, name, fill: theme.secondary);
    }
  }
  y = plotBottom + (xTitle.isEmpty ? 30 : 50);
  return svg.finish(_footnote(svg, y, footnote) + 8);
}

/// Clean ticks from zero to at or above [highest].
List<double> _linearTicks(double highest) {
  final rough = highest / 4;
  final power = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final step = [
    1,
    2,
    5,
    10,
  ].map((m) => m * power).firstWhere((s) => s >= rough);
  return [for (var tick = 0.0; tick < highest + step; tick += step) tick];
}

/// Ticks at 1, 2 and 5 of every decade around [lowest] and [highest].
List<double> _logTicks(double lowest, double highest) {
  final ticks = <double>[];
  var decade = math.pow(10, (math.log(lowest) / math.ln10).floor()).toDouble();
  while (decade <= highest * 10) {
    for (final m in const [1, 2, 5]) {
      ticks.add(m * decade);
    }
    decade *= 10;
  }
  final from = ticks.lastIndexWhere((tick) => tick <= lowest);
  final to = ticks.indexWhere((tick) => tick >= highest);
  return ticks.sublist(math.max(from, 0), to + 1);
}
