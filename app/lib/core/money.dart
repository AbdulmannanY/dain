/// Formats an amount in minor units (halalas for SAR) for display:
/// 4550 -> '45.50 ر.س', 500000 -> '5,000 ر.س'. The sign is dropped; callers
/// say "لك" / "عليك" instead.
String formatMoney(int minor, String currency) {
  final abs = minor.abs();
  final whole = abs ~/ 100;
  final cents = abs % 100;

  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  if (cents != 0) grouped.write('.${cents.toString().padLeft(2, '0')}');

  final symbol = currency == 'SAR' ? 'ر.س' : currency;
  return '$grouped $symbol';
}

/// Largest amount the database accepts (`entries.amount_minor`).
const maxAmountMinor = 100000000000;

/// Parses an amount as typed into minor units: '45.5' -> 4550,
/// '٥٬٠٠٠' -> 500000. Accepts Arabic-Indic and Persian digits, '.' or '٫'
/// as the decimal point, ',' or '٬' between thousands, and at most two
/// decimals. Returns null for anything else, for zero, and above
/// [maxAmountMinor].
int? parseMoney(String input) {
  final buffer = StringBuffer();
  for (final rune in input.trim().runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.write(rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.write(rune - 0x06F0);
    } else if (rune == 0x066B || rune == 0x2E) {
      buffer.write('.'); // '٫' or '.'
    } else if (rune == 0x066C || rune == 0x2C) {
      continue; // '٬' or ','
    } else {
      buffer.writeCharCode(rune);
    }
  }
  final m = RegExp(r'^([0-9]{1,12})(?:\.([0-9]{1,2}))?$').firstMatch('$buffer');
  if (m == null) return null;
  final minor =
      int.parse(m[1]!) * 100 + int.parse((m[2] ?? '0').padRight(2, '0'));
  return minor < 1 || minor > maxAmountMinor ? null : minor;
}
