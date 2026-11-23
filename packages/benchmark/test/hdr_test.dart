import 'package:benchmark/src/hdr.dart';
import 'package:test/test.dart';

// Reports of zrk 3.0.5 against a local server: an open loop of three
// seconds at 400 requests per second, its rows of a second, and a closed
// loop.
const _openLoop =
    'HISTFAAAATZ4nDVRQU4DMQx0Z2dd14RotUUVEtx4CC/hIdyREKo49SkceAFv4BFcOHFmnMKuEtvjsZ1Mbp9Oe7PNj52/6c9uRnB6tvvvM/A2w4AdDXtMcg1b/ZfDghVDDKdcGjFRCEE3WhDhGIBbwB2eiknAxKcPFsrFf5mahJuYos3BZM0UCalEDRskq7byxzYmiVL9lYjKKh/NTfPJLF5HqE6LgiLZIrw5F5n06JGZgvp1Rjv03nNtvbMdfImlHda4Wnr3ntnXRcQ1us4eKlK5ZqtfknU5wVA/HQKR3nSBRvfUWJ1bYWuCdbTiL8p7LbAXoi5MG7Yu4y7Xla0reikkSUqxAkrGuSRUWNJiyIgil0gXeqppqCV80kvttGZsuRN8gzvtezzgCHwQrwu+Eu9bvAQe8YmCfwHjEBYG';
const _openLoopRows = [
  'HISTFAAAAOZ4nDVQyW0DMQykR7PcK4YfC/uVTxCkjlSSPpJ/gMDw08UYrsQF+JlPSsiMtF6uKA45HEp6/j4vEZvPaF9Z900F5594/2uJa4ctFvQIrV7xDnsUCM5yZKCTCYayozIiBEdTBE0pjsfWNdNMdpXdUYKi09ziChQzMlgNxpGGngSkjMgY5CaQQ5JMefE4IZmhOv2TT1ripmrWsSuP41ibGim6JBBNoc7xkevEqgOLqmmo3Z7edFIyYYYmPq7vuyu1FsAdHK5FXXT289TuLd70Qi94VbzgA/cDfidcehwHfOEGnIB/e7oPWg==',
  'HISTFAAAAMl4nC1QMQ4CMQwLbmoq3cDACiMjb+BJfAKJkYGn8DGegJ1wldI6sZ3kTo/3MWJ3j/7G/94VeD/j9u3EZ+KAM67YEDqYDhiKU8dw5UhgYyRB5nDSpKiTEgKZE6oQoYfQKIfAYN+Ce8v2GaopKClbt7JI5e5ZDHmGOibMwqo0lhXOLQZJ4VSb1FSi0pMtGi1xVAXtQ9iDg6W0b0+zUBtUQvJg4/Q0FnVvdJjysye8lOc0bTD+/yD7rmdoy61Ufpve61/6F7wSP32ZCac=',
  'HISTFAAAAMh4nC1PyZECQQwzao3Hc/woHhSkQAx8yYCEtmoDmGA2rQ0BqZu+bMuy7L7/HOeI0yvGal976sHxG8//AfxN2PAGLgwsaNCzFRYqDEx6BcnzYRMuEHMHKCcjF4iSlIFSg6pUiN1cEgQtBRJNN1KK1Si9cI2sxbCal25GJrMbIaWdFVyRu5KV6861VKssWIwy1zsZvUpaniGpHvI9hmH2fmaipYIMj9WxMnvcGkNC2ezF/oRGzw03bGbPMDbrZ1c8FE2yR+EDYUwKHg==',
];
// The closed loop's histogram with two significant digits in its header.
const _twoDigits =
    'HISTFAAAAuZ4nC2Uy41lRQyGq33cbo/HU5ia4upOazYIIcQKiT1iNWEQBhEAIoBZEQUhEAhJEAKfq/vePrfr+PH7Ub/98ffP78d4/HG8fOT1/0P/XJ//HD//9yL4O0X+eJCv5Xv5VoZcoj/JE4cPOuRRnnToJTJUhg3kF5qh/dZ/vKjI8UJpioO+lWNiuHAQvAFyHoRXe13W9na15yuC+RAbZu0nqh3RHJtjohmKCrk5Wr7u5jxqqqhSEfvRaiDkqBLJj04j/UQsLiC3d4bF9GPl0Zi6zDwtwIhybz2pBAjCMXKo+wxMSAPtlkUgFGrhsjwivI3jhM8bttLJrlWFbOlA1zYWCn4lp13Ick119TUrp02fGavuMc0F8OoQdXdeQ7NiBw9FZoIQOhNft1qUEytBB3zPmuQbC/eJsPZKnfuO6E4Bmzoryvb+uGZW7loEnZ4TbDsVbpKqrJlrTx0oZtXalORr5c7uU5avvIU/R2wC8r4btep+I3rlc9f6XPft1GgYr7K5ulGAEiAagiakz5nJNa7VzVk5yczoX9oGv0qDSwNxNRI3M+kbN5n9LUGkXv7sAXhMuRW2COamMu5W/D5JyKbRqb7VhDBlt9i6OGVZfxqzSJjyT20024eGu+QgOldAH5pk6NsLiEObVMGXDCYcgELwdBK+a+vQXJOkW8CiJoo1eWkF/YOqTXBTh/jNX+6tqdgD4E1tMHHmBFua/eQwpDnRfEukLW+y99QQuHkLloBMhvC5h7PDwXvp6eBjQEfLXRizjg+l+/9j23lH9TOqww5zewI5nZmTS5nc0cliTG/oUwy3AdPO+HYRB8R7QZCd9BAzxmfA/CQjb+QlYWnYl91w7DqqnQXQyZ5htzPxvWvOanj1w+0skK6PjaJPre3Ezo4avWGuXk6dvhyjs5PI/iTzJG+0Xz/IO5zlLVtNjt838qW8J71uxXciX8kXPL/IO7CQ//aA+gf5V+QvlV/lEw6f5B+R/wFxCS+k';
const _closedLoop =
    'HISTFAAAAuV4nC2U3Y1kRQyFa3w9Hq/XW5jaotU72heEEOIJiXfE04ZBGEQAiAD2iSgIgUBIghD4XDPdc6fr+uf4p4798ffP78d4/HG8fK7X34fz8vnP8fN/L4K/U+SPB/lavpdvZcgl+pM8cfigQx7lSYdeIkNl2EB+oRnab/3Hi4ocL5SmOOhbOSaGCwfBGyDnQXi112Vtb1d7viKYD7Fh1n6i2hHNsTkmmqGokJuj5etuzqOmiioVsR+tBkKOKpH802mkn4jFBeT2zrCYfqw8GlOXmacFGFHurSeVAEE4Rg51n4EJaaDdsgiEQi1clkeEt3Gc8HnDVjrZtaqQLR3o2sZCwa/ktAtZrqmuvmbltOkzY9U9prkAXh2i7s5raFbs4KHITBBCZ+LrVotyYiXogO9Zk3xj4T4R1l6pc98R3SlgU2dF2d4f18zKXYug03OCbafCTVKVNXPtqQPFrFqbknyt3Nl9yvKVt/DniE1A3nejVt1vRK987lqf676dGg3jVTZXNwpQAkRD0IT0OTO5xrW6OSsnmRn9S9vgV2lwaSCuRuJmJn3jJrO/JYjUy589AI8pt8IWwdxUxt2K3ycJ2TQ61beaEKbsFlsXpyzrT2MWCVP+qY1m+9BwlxxE5wroQ5MMfXsBcWiTKviSwYQDUAieTsJ3bR2aa5J0C1jURLEmL62gf1C1CW7qEL/5y701FXsAvKkNJs6cYEuznxyGNCeab4m05U32nhoCN2/BEpDJED73cHY4eC89HXwM6Gi5C2PW8aF0/z62nXdUP6M6ekKOQc/KmTm5lMkdnSzG9IY+xXAbMO2MbxdxQLwXBNlJDzFjfAbMTzLyRl4SloZ92Q3HrqPaWQCd7Bl2OxPfu+ashlc/3M4C6frYKPrU2k7s7KjRG+bq5dTpyzE6O4nsTzJP8kb79YO8w1nestXk+H0jX8p70utWfCfylXzB84u8Awv5bw+of5B/Rf5S+VU+4fBJ/hH5H3ZUL6U=';

void main() {
  test("Given zrk's histogram of an open loop, "
      'when its percentiles are read, '
      'then they are the ones zrk reported', () {
    final histogram = Histogram.decode(_openLoop);
    expect(histogram.total, 1200);
    expect(
      {
        for (final p in [50.0, 75.0, 90.0, 99.0, 99.9, 99.99])
          p: histogram.valueAt(p),
      },
      {50.0: 638, 75.0: 710, 90.0: 760, 99.0: 908, 99.9: 10260, 99.99: 11340},
    );
  });

  test("Given zrk's histogram of a closed loop with a sparse tail, "
      'when its percentiles are read, '
      'then they are the ones zrk reported', () {
    final histogram = Histogram.decode(_closedLoop);
    expect(histogram.total, 4577);
    expect(
      {
        for (final p in [50.0, 75.0, 90.0, 99.0, 99.9, 99.99])
          p: histogram.valueAt(p),
      },
      {50.0: 1565, 75.0: 1757, 90.0: 1973, 99.0: 2459, 99.9: 4037, 99.99: 5158},
    );
  });

  test("Given the histograms of zrk's rows of a second, "
      'when they are merged, '
      "then the merge holds the counts of the run's own histogram", () {
    final merged = Histogram.merge(_openLoopRows.map(Histogram.decode));
    expect(merged.counts, Histogram.decode(_openLoop).counts);
  });

  test('Given a decoded histogram, '
      'when it is encoded and decoded again, '
      'then the counts are the same.', () {
    final histogram = Histogram.decode(_closedLoop);
    expect(Histogram.decode(histogram.encode()).counts, histogram.counts);
  });

  test('Given histograms of different significant digits, '
      'when they are merged, '
      'then the merge throws an ArgumentError.', () {
    expect(
      () => Histogram.merge([
        Histogram.decode(_closedLoop),
        Histogram.decode(_twoDigits),
      ]),
      throwsArgumentError,
    );
  });
}
