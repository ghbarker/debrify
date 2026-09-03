import 'dart:math';

/// Reproducible fuzz helpers. Always pass [seed] so a failure can be replayed.
class SeededFuzz {
  SeededFuzz(this.seed) : _random = Random(seed);

  final int seed;
  final Random _random;

  int nextInt(int max) => _random.nextInt(max);

  String garbage({int maxLen = 64}) {
    final len = _random.nextInt(maxLen);
    return String.fromCharCodes(
      List<int>.generate(len, (_) => 32 + _random.nextInt(95)),
    );
  }

  String unicodeJunk({int maxLen = 32}) {
    const cps = [0x00, 0x09, 0x0A, 0x1F, 0x7F, 0xA0, 0x2603, 0x1F4A9, 0xFFFD];
    final len = _random.nextInt(maxLen);
    return String.fromCharCodes([
      for (var i = 0; i < len; i++) cps[_random.nextInt(cps.length)],
    ]);
  }

  String huge(int length) => 'A' * length;
}
