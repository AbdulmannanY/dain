import 'package:dain/core/phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePhone', () {
    test('Saudi local and international forms give the same digits', () {
      const want = '966500000001';
      for (final input in [
        '0500000001',
        '500000001',
        '966500000001',
        '+966500000001',
        '00966500000001',
        '+966 50 000 0001',
        '050-000-0001',
        '(050) 000 0001',
      ]) {
        expect(normalizePhone(input), want, reason: input);
      }
    });

    test('Arabic-Indic and Persian digits', () {
      expect(normalizePhone('٠٥٠٠٠٠٠٠٠٢'), '966500000002');
      expect(normalizePhone('۰۵۰۰۰۰۰۰۰۲'), '966500000002');
    });

    test('matches the database check on ledgers.counterparty_phone', () {
      final db = RegExp(r'^[1-9][0-9]{7,14}$');
      expect(db.hasMatch(normalizePhone('0500000001')!), isTrue);
      expect(db.hasMatch(normalizePhone('+967771234567')!), isTrue);
    });

    test('rejects what cannot be a mobile number', () {
      for (final input in [
        '',
        '05',
        '0112345678', // Saudi landline
        '96650000000', // one digit short
        '+966 5000000012', // one digit long
        'abc0500000001',
        '+1234567890123456', // longer than E.164
      ]) {
        expect(normalizePhone(input), isNull, reason: input);
      }
    });
  });

  test('asciiDigits keeps digits only', () {
    expect(asciiDigits('١٢٣ ٤٥٦'), '123456');
    expect(asciiDigits('12-34-56'), '123456');
  });
}
