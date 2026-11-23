import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// The counts of an HdrHistogram, in its V2 compressed form on the wire.
///
/// zrk writes one as `latency_histogram`, in microseconds. Histograms of the
/// same layout [merge] exactly, which percentiles do not.
final class Histogram {
  /// The V2 header after the cookie and payload length: normalizing index
  /// offset, significant digits, lowest and highest trackable value and the
  /// integer to double ratio, 32 bytes. Histograms merge only when theirs
  /// are the same.
  final Uint8List _layout;

  /// The base-2 magnitude of the smallest value a bucket tells apart.
  final int _unitMagnitude;

  /// The base-2 magnitude of half the sub-buckets per bucket.
  final int _subBucketHalfCountMagnitude;

  /// The count of each index, with no zeros after the last value.
  final List<int> counts;

  Histogram._(this._layout, this.counts)
    : _unitMagnitude = _magnitudes(_layout).unit,
      _subBucketHalfCountMagnitude = _magnitudes(_layout).subBucketHalfCount;

  /// Decodes [encoded], the base64 text of a compressed V2 histogram.
  ///
  /// Throws a [FormatException] for any other encoding.
  factory Histogram.decode(String encoded) {
    final outer = ByteData.sublistView(base64Decode(encoded));
    if (outer.getInt32(0) != _compressedCookie) {
      throw const FormatException('Not a compressed V2 HdrHistogram');
    }
    final length = outer.getInt32(4);
    final bytes = Uint8List.fromList(
      zlib.decode(Uint8List.sublistView(outer, 8, 8 + length)),
    );
    final inner = ByteData.sublistView(bytes);
    if (inner.getInt32(0) != _encodingCookie) {
      throw const FormatException('Not a V2 HdrHistogram encoding');
    }
    final end = _headerLength + inner.getInt32(4);
    final counts = <int>[];
    var at = _headerLength;
    while (at < end) {
      var raw = 0;
      var shift = 0;
      while (true) {
        final byte = bytes[at++];
        raw |= (byte & 0x7f) << shift;
        if (byte & 0x80 == 0 || shift == 56) break;
        shift += 7;
      }
      final value = (raw >>> 1) ^ -(raw & 1);
      if (value < 0) {
        counts.addAll(List.filled(-value, 0));
      } else {
        counts.add(value);
      }
    }
    return Histogram._(
      Uint8List.fromList(bytes.sublist(8, _headerLength)),
      [...counts]..length = _trimmedLength(counts),
    );
  }

  /// The histogram that holds the values of every one of [histograms].
  ///
  /// Throws an [ArgumentError] when their layouts differ.
  static Histogram merge(Iterable<Histogram> histograms) {
    final all = histograms.toList();
    final layout = all.first._layout;
    final counts = List.filled(
      all.map((h) => h.counts.length).reduce(math.max),
      0,
    );
    for (final h in all) {
      if (!_sameBytes(h._layout, layout)) {
        throw ArgumentError('Histograms of different layouts');
      }
      for (var i = 0; i < h.counts.length; i++) {
        counts[i] += h.counts[i];
      }
    }
    return Histogram._(layout, counts);
  }

  /// The base64 text of the histogram as a compressed V2 histogram, which
  /// [Histogram.decode] and HdrHistogram's own decoders read.
  String encode() {
    final payload = BytesBuilder();
    void put(int value) {
      var raw = (value << 1) ^ (value >> 63);
      while (raw >>> 7 != 0) {
        payload.addByte((raw & 0x7f) | 0x80);
        raw >>>= 7;
      }
      payload.addByte(raw);
    }

    for (var i = 0; i < counts.length;) {
      var zeros = 0;
      while (i + zeros < counts.length && counts[i + zeros] == 0) {
        zeros++;
      }
      if (zeros > 1) {
        put(-zeros);
        i += zeros;
      } else {
        put(counts[i++]);
      }
    }
    final body = payload.takeBytes();
    final inner = Uint8List(_headerLength + body.length);
    ByteData.sublistView(inner)
      ..setInt32(0, _encodingCookie)
      ..setInt32(4, body.length);
    inner
      ..setRange(8, _headerLength, _layout)
      ..setRange(_headerLength, inner.length, body);
    final compressed = zlib.encode(inner);
    final outer = Uint8List(8 + compressed.length);
    ByteData.sublistView(outer)
      ..setInt32(0, _compressedCookie)
      ..setInt32(4, compressed.length);
    outer.setRange(8, outer.length, compressed);
    return base64Encode(outer);
  }

  /// How many values the histogram holds.
  int get total => counts.fold(0, (a, b) => a + b);

  /// The value at [percentile], as the middle of its bucket.
  ///
  /// The rank rounds to the nearest value and the bucket reads as its
  /// middle, as zrk's own lookup does, so a percentile read here matches
  /// the one in its report.
  int valueAt(double percentile) {
    final total = this.total;
    if (total == 0) return 0;
    final wanted = math.max(1, (percentile / 100 * total).round());
    var seen = 0;
    for (var i = 0; i < counts.length; i++) {
      seen += counts[i];
      if (seen >= wanted) return _middle(i);
    }
    return _middle(counts.length - 1);
  }

  int _middle(int index) {
    final halfCount = 1 << _subBucketHalfCountMagnitude;
    var bucket = (index >> _subBucketHalfCountMagnitude) - 1;
    var subBucket = (index & (halfCount - 1)) + halfCount;
    if (bucket < 0) {
      subBucket -= halfCount;
      bucket = 0;
    }
    final shift = bucket + _unitMagnitude;
    return (subBucket << shift) + ((1 << shift) >> 1);
  }

  static ({int unit, int subBucketHalfCount}) _magnitudes(Uint8List layout) {
    final header = ByteData.sublistView(layout);
    final digits = header.getInt32(4);
    final lowest = header.getInt64(8);
    final subBuckets = 2 * math.pow(10, digits).toInt();
    return (
      unit: (math.log(lowest) / math.ln2).floor(),
      subBucketHalfCount:
          math.max((math.log(subBuckets) / math.ln2).ceil(), 1) - 1,
    );
  }

  static int _trimmedLength(List<int> counts) {
    var length = counts.length;
    while (length > 0 && counts[length - 1] == 0) {
      length--;
    }
    return length;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static const _compressedCookie = 0x1c849314;
  static const _encodingCookie = 0x1c849313;
  static const _headerLength = 40;
}
