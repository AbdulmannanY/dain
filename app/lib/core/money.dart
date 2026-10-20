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
