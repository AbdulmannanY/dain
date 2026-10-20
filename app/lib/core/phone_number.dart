/// Turns what a person types into the E.164 digits (no '+') that the
/// database stores in `ledgers.counterparty_phone` and that Supabase Auth
/// keeps in `auth.users.phone`. `link_my_ledgers()` matches the two, so both
/// sides must go through the same form.
///
/// Accepts Saudi local forms (05XXXXXXXX, 5XXXXXXXX), international forms
/// (+9665..., 009665...), separators, and Arabic-Indic or Persian digits.
/// Returns null when the input cannot be a valid number.
String? normalizePhone(String input, {String defaultCountryCode = '966'}) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final c = String.fromCharCode(rune);
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.write(rune - 0x0660); // Arabic-Indic digits
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.write(rune - 0x06F0); // Persian digits
    } else if (RegExp(r'[0-9+]').hasMatch(c)) {
      buffer.write(c);
    } else if (RegExp(r'[\s\-().‎‏]').hasMatch(c)) {
      continue;
    } else {
      return null;
    }
  }

  var s = buffer.toString();
  if (s.startsWith('+')) {
    s = s.substring(1);
  } else if (s.startsWith('00')) {
    s = s.substring(2);
  } else if (s.startsWith('0')) {
    s = defaultCountryCode + s.substring(1);
  } else if (s.length == 9 && s.startsWith('5')) {
    s = defaultCountryCode + s;
  }

  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(s)) return null;
  // Saudi numbers handed to OTP must be mobiles: 9665XXXXXXXX.
  if (s.startsWith('966') && !RegExp(r'^9665[0-9]{8}$').hasMatch(s)) {
    return null;
  }
  return s;
}

/// Converts Arabic-Indic and Persian digits to ASCII and drops everything
/// that is not a digit. Used for the OTP code field.
String asciiDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.write(rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.write(rune - 0x06F0);
    } else if (rune >= 0x30 && rune <= 0x39) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
