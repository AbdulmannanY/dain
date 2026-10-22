import 'dart:math';

final _random = Random.secure();

/// A random (version 4) UUID, made on the phone so a save sent again after
/// a lost answer carries the same id and the database refuses the copy
/// (23505) instead of recording the entry twice.
String newEntryId([Random? random]) {
  final r = random ?? _random;
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
