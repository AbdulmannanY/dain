import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

LedgerSummary ledger({String? shop}) => LedgerSummary(
  id: 'L1',
  iAmOwner: true,
  title: 'سعد',
  subtitle: shop,
  currency: 'SAR',
  myConfirmedMinor: 4000,
  myOpenMinor: 4000,
  pendingCount: 0,
  disputedCount: 0,
  otherPartyJoined: true,
);

LedgerEntry payment(int delta, {EntryStatus status = EntryStatus.pending}) =>
    LedgerEntry(
      id: 'abcdef12-0000-4000-8000-000000000001',
      myDeltaMinor: delta,
      note: null,
      occurredOn: DateTime(2026, 10, 21),
      status: status,
      createdByMe: false,
      responseNote: null,
      isPayment: true,
    );

EntryEvent event(
  EntryEventKind kind, {
  bool byMe = false,
  bool viaLink = false,
  bool known = true,
  String? note,
}) => EntryEvent(
  kind: kind,
  byMe: byMe,
  viaLink: viaLink,
  actorKnown: known,
  note: note,
  at: DateTime(2026, 10, 22, 9, 5),
);

void main() {
  test('eventLine: what, who and when', () {
    expect(
      eventLine(event(EntryEventKind.created, byMe: true)),
      'سُجّل · أنت · 22/10/2026 09:05',
    );
    expect(
      eventLine(event(EntryEventKind.disputed, note: 'ليس لي')),
      'اعتُرض عليه: ليس لي · الطرف الآخر · 22/10/2026 09:05',
    );
    expect(
      eventLine(event(EntryEventKind.confirmed, viaLink: true, known: false)),
      'أُكّد · عبر الرابط · 22/10/2026 09:05',
    );
    expect(
      eventLine(event(EntryEventKind.voided, known: false)),
      'سُحب · غير معروف · 22/10/2026 09:05',
    );
  });

  test('buildEvents reads the rows from my side', () {
    final built = buildEvents([
      {
        'event': 'created',
        'actor': 'me',
        'via': 'app',
        'note': null,
        'at': '2026-10-22T06:05:00+00:00',
      },
      {
        'event': 'confirmed',
        'actor': null,
        'via': 'link',
        'note': null,
        'at': '2026-10-22T07:00:00+00:00',
      },
    ], myId: 'me');
    expect(built.map((e) => (e.kind, e.byMe, e.viaLink, e.actorKnown)), [
      (EntryEventKind.created, true, false, true),
      (EntryEventKind.confirmed, false, true, false),
    ]);
    expect(built.first.at, DateTime.utc(2026, 10, 22, 6, 5));
  });

  test('paymentReceipt: who paid whom, the reference and the status', () {
    expect(
      paymentReceipt(payment(-4000), ledger(shop: 'فرع الرياض')),
      'إيصال سداد من دائن\n'
      'الرقم: ABCDEF12\n'
      'المبلغ: 40 ر.س\n'
      'من: سعد (فرع الرياض)\n'
      'إلى: أنا\n'
      'التاريخ: 21/10/2026\n'
      'الحالة: بانتظار تأكيد الطرف الآخر',
    );
    final mine = paymentReceipt(
      payment(1550, status: EntryStatus.confirmed),
      ledger(),
    );
    expect(mine, contains('من: أنا\nإلى: سعد\n'));
    expect(mine, endsWith('الحالة: مؤكد من الطرفين'));
  });

  group('in the entry sheet', () {
    late FakeLedgers ledgers;
    late List<String> clipboard;

    Future<void> openEntry(WidgetTester tester, LedgerEntry e) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      clipboard = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final auth = FakeAuth(signedInAs: '966500000001');
      final profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
      ledgers.ledgers = [ledger()];
      ledgers.entries['L1'] = [e];
      final c = SessionController(auth: auth, profiles: profiles);
      await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
      await c.start();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ledger_L1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('entry_${e.id}')));
      await tester.pumpAndSettle();
    }

    setUp(() => ledgers = FakeLedgers());

    testWidgets('a payment shows its receipt, copied to send, and its trail', (
      tester,
    ) async {
      final p = payment(-4000);
      ledgers.events[p.id] = [
        event(EntryEventKind.created),
        event(EntryEventKind.disputed, byMe: true, note: 'لم يصل'),
        event(EntryEventKind.confirmed, byMe: true),
      ];
      await openEntry(tester, p);

      final receipt = paymentReceipt(p, ledger());
      expect(
        find.descendant(
          of: find.byKey(const Key('payment_receipt')),
          matching: find.text(receipt),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('copy_receipt_button')));
      await tester.pumpAndSettle();
      expect(clipboard, [receipt]);
      expect(find.text('نُسخ الإيصال'), findsOneWidget);

      for (final line in [
        'سُجّل · الطرف الآخر · 22/10/2026 09:05',
        'اعتُرض عليه: لم يصل · أنت · 22/10/2026 09:05',
        'أُكّد · أنت · 22/10/2026 09:05',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(const Key('entry_trail')),
            matching: find.text(line),
          ),
          findsOneWidget,
          reason: line,
        );
      }
    });

    testWidgets('a debt has no receipt; a trail that fails to load says so', (
      tester,
    ) async {
      ledgers.failEventsWith = const PostgrestException(
        message: 'x',
        code: '500',
      );
      await openEntry(
        tester,
        LedgerEntry(
          id: 'd1',
          myDeltaMinor: 500,
          note: null,
          occurredOn: DateTime(2026, 10, 20),
          status: EntryStatus.pending,
          createdByMe: true,
          responseNote: null,
        ),
      );
      expect(find.byKey(const Key('payment_receipt')), findsNothing);
      expect(find.byKey(const Key('trail_error')), findsOneWidget);
      // The actions still work.
      expect(find.byKey(const Key('withdraw_entry_button')), findsOneWidget);
    });
  });
}
