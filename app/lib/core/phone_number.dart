/// Turns what a person types into the E.164 digits (no '+') that the
/// database stores in `ledgers.counterparty_phone` and that Supabase Auth
/// keeps in `auth.users.phone`. `link_my_ledgers()` matches the two, so both
/// sides must go through the same form.
///
/// Local forms are Saudi (05XXXXXXXX, 5XXXXXXXX -> 9665...) and Yemeni
/// (07XXXXXXXX, 7XXXXXXXX -> 9677...): their mobiles never overlap. Any other
/// country needs '+' or '00'; a bare number is never read as international,
/// so 774040697 is not sent to +7. Also accepts 966/967 typed without '+',
/// separators, and Arabic-Indic or Persian digits. Returns null when the
/// input cannot be a valid mobile number.
String? normalizePhone(String input) {
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
  } else if (!s.startsWith('966') && !s.startsWith('967')) {
    final local = s.startsWith('0') ? s.substring(1) : s;
    if (local.length != 9) return null;
    if (local.startsWith('5')) {
      s = '966$local';
    } else if (local.startsWith('7')) {
      s = '967$local';
    } else {
      return null;
    }
  }

  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(s)) return null;
  // Numbers handed to OTP must be mobiles: 9665XXXXXXXX, 9677XXXXXXXX.
  if (s.startsWith('966') && !RegExp(r'^9665[0-9]{8}$').hasMatch(s)) {
    return null;
  }
  if (s.startsWith('967') && !RegExp(r'^9677[0-9]{8}$').hasMatch(s)) {
    return null;
  }
  return s;
}

/// What a phone field says when [normalizePhone] refuses the input.
const invalidPhoneMessage =
    'أدخل رقم جوال صحيحاً: سعودي مثل 05XXXXXXXX، أو يمني مثل 7XXXXXXXX، '
    'أو غيرهما يبدأ بـ +.';

/// The hint inside phone fields.
const phoneHint = '05XXXXXXXX / 7XXXXXXXX';

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
