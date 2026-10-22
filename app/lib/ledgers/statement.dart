import '../core/money.dart';
import '../data/ledger_repository.dart';

/// The span a statement covers, ending today unless said otherwise.
enum StatementPeriod {
  /// From the first of this month to today.
  thisMonth,

  /// The whole of last month.
  lastMonth,

  /// From the first of January to today.
  thisYear,

  /// Every entry up to today.
  all,
}

/// The first and last day of [period] seen from [today]; [from] is null for
/// [StatementPeriod.all].
({DateTime? from, DateTime to}) statementRange(
  StatementPeriod period,
  DateTime today,
) {
  final day = DateTime(today.year, today.month, today.day);
  return switch (period) {
    StatementPeriod.thisMonth => (from: DateTime(day.year, day.month), to: day),
    // Day 0 of this month is the last day of the one before.
    StatementPeriod.lastMonth => (
      from: DateTime(day.year, day.month - 1),
      to: DateTime(day.year, day.month, 0),
    ),
    StatementPeriod.thisYear => (from: DateTime(day.year), to: day),
    StatementPeriod.all => (from: null, to: day),
  };
}

/// One agreed movement of a statement and the balance right after it.
class StatementLine {
  const StatementLine(this.entry, this.balanceMinor);

  final LedgerEntry entry;

  /// The agreed balance from my side after this entry: positive = لك.
  final int balanceMinor;
}

/// A ledger's statement between two days, from my side. Only entries both
/// sides confirmed move a balance, as in the agreed balance itself; the
/// day of an entry is its `occurred_on`.
class Statement {
  const Statement({
    required this.ledger,
    required this.from,
    required this.to,
    required this.openingMinor,
    required this.lines,
    required this.closingMinor,
    required this.unconfirmedCount,
  });

  final LedgerSummary ledger;

  /// Null when the statement starts with the first entry.
  final DateTime? from;
  final DateTime to;

  /// The agreed balance before [from] (zero when [from] is null).
  final int openingMinor;

  /// Confirmed entries from [from] to [to], oldest first.
  final List<StatementLine> lines;

  /// The agreed balance at the end of [to].
  final int closingMinor;

  /// Entries in the period still pending or disputed, left out.
  final int unconfirmedCount;

  /// What the period added to what is owed to me, and what it took off.
  int get increasedMinor => lines.fold(
    0,
    (sum, l) => l.entry.myDeltaMinor > 0 ? sum + l.entry.myDeltaMinor : sum,
  );
  int get decreasedMinor => lines.fold(
    0,
    (sum, l) => l.entry.myDeltaMinor < 0 ? sum - l.entry.myDeltaMinor : sum,
  );
}

/// Builds the statement of [ledger] from [entries] as [LedgerRepository
/// .fetchEntries] returns them (newest first: by day, then by when they
/// were recorded) for the days [from] (null = from the start) to [to].
Statement buildStatement(
  LedgerSummary ledger,
  List<LedgerEntry> entries, {
  required DateTime? from,
  required DateTime to,
}) {
  // Oldest first; entries of one day keep the order they were recorded in.
  final ordered = entries.reversed.toList();
  var opening = 0;
  var balance = 0;
  var unconfirmed = 0;
  final lines = <StatementLine>[];
  for (final e in ordered) {
    final day = e.occurredOn;
    if (day.isAfter(to)) continue;
    final before = from != null && day.isBefore(from);
    if (e.status != EntryStatus.confirmed) {
      final open =
          e.status == EntryStatus.pending || e.status == EntryStatus.disputed;
      if (open && !before) unconfirmed++;
      continue;
    }
    if (before) {
      opening += e.myDeltaMinor;
      balance = opening;
      continue;
    }
    balance += e.myDeltaMinor;
    lines.add(StatementLine(e, balance));
  }
  return Statement(
    ledger: ledger,
    from: from,
    to: to,
    openingMinor: opening,
    lines: lines,
    closingMinor: balance,
    unconfirmedCount: unconfirmed,
  );
}

/// "أعطيت" / "أخذت" for a debt, "سدّدت" / "استلمت سداداً" for a payment,
/// from my side.
String movementVerb(LedgerEntry e) => e.isPayment
    ? (e.myDeltaMinor > 0 ? 'سدّدت' : 'استلمت سداداً')
    : (e.myDeltaMinor > 0 ? 'أعطيت' : 'أخذت');

/// "70 ر.س لك", "70 ر.س عليك" or "0 ر.س".
String balanceWords(int minor, String currency) {
  final amount = formatMoney(minor, currency);
  return minor > 0
      ? '$amount لك'
      : minor < 0
      ? '$amount عليك'
      : amount;
}

/// The statement as text, to read or send.
String statementText(Statement s) {
  final l = s.ledger;
  final c = l.currency;
  final shop = l.subtitle == null ? '' : ' (${l.subtitle})';
  final span = s.from == null
      ? 'حتى ${shortDay(s.to)}'
      : 'من ${shortDay(s.from!)} إلى ${shortDay(s.to)}';
  final out = StringBuffer()
    ..writeln('كشف حساب ${l.title}$shop')
    ..writeln('الفترة: $span')
    ..writeln('الرصيد السابق: ${balanceWords(s.openingMinor, c)}');
  if (s.lines.isEmpty) out.writeln('لا حركات مؤكدة في الفترة.');
  for (final line in s.lines) {
    final e = line.entry;
    final note = e.note == null ? '' : ' · ${e.note}';
    out.writeln(
      '${shortDay(e.occurredOn)} · ${movementVerb(e)} '
      '${formatMoney(e.myDeltaMinor, c)}$note · '
      'الرصيد ${balanceWords(line.balanceMinor, c)}',
    );
  }
  out.writeln('الرصيد النهائي: ${balanceWords(s.closingMinor, c)}');
  if (s.unconfirmedCount > 0) {
    out.writeln('لا يشمل قيوداً لم تُؤكَّد بعد: ${s.unconfirmedCount}.');
  }
  out.write('من دائن: القيود التي أكّدها الطرفان فقط.');
  return out.toString();
}

/// A signed amount as a spreadsheet reads it: 4550 -> '45.50',
/// -3000 -> '-30'.
String _signedPlain(int minor) =>
    minor < 0 ? '-${plainAmount(minor)}' : plainAmount(minor);

/// One CSV field: text that could start a formula gets a leading quote
/// (the note is written by either side), and a field with a comma, a quote
/// or a line break is quoted.
String _csvField(String text) {
  var t = text;
  if (t.isNotEmpty && '=+-@\t\r'.contains(t[0])) t = "'$t";
  if (t.contains(RegExp('[",\r\n]'))) t = '"${t.replaceAll('"', '""')}"';
  return t;
}

/// The statement as CSV (RFC 4180, CRLF): a row for the opening balance,
/// one per movement, and one for the closing balance. Amounts and balances
/// are signed from my side (positive = لك), with a point for decimals.
String statementCsv(Statement s) {
  final c = s.ledger.currency;
  String row(List<String> fields) => '${fields.join(',')}\r\n';
  final out = StringBuffer()
    ..write(
      row([
        'التاريخ',
        'البيان',
        _csvField('المبلغ ($c)'),
        _csvField('الرصيد ($c)'),
        'الملاحظة',
        'الرقم',
      ]),
    )
    ..write(
      row([
        s.from == null ? '' : isoDay(s.from!),
        'الرصيد السابق',
        '',
        _signedPlain(s.openingMinor),
        '',
        '',
      ]),
    );
  for (final line in s.lines) {
    final e = line.entry;
    out.write(
      row([
        isoDay(e.occurredOn),
        _csvField(movementVerb(e)),
        _signedPlain(e.myDeltaMinor),
        _signedPlain(line.balanceMinor),
        _csvField(e.note ?? ''),
        entryRef(e.id),
      ]),
    );
  }
  out.write(
    row([
      isoDay(s.to),
      'الرصيد النهائي',
      '',
      _signedPlain(s.closingMinor),
      '',
      '',
    ]),
  );
  return out.toString();
}
