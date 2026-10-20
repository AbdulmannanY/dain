# دائن (Dain) — سياق المشروع

> المرجع الوحيد للمشروع. اقرأه كاملاً قبل أي اقتراح، ثم تحقّق من الشجرة
> الفعلية (لا من الذاكرة). بروتوكول التسليم في
> [`docs/agent-script-protocol.md`](agent-script-protocol.md).
>
> آخر تحديث: 2026-10-21، عند الـ commit `dce7669`.

## 1. الفكرة

دفتر ديون بين طرفين للأفراد والمحلات. كل دفتر بين **مالك** (شخص، وقد يعمل
باسم محل) و**طرف آخر** يُعرَّف برقم جواله. أي طرف يسجّل قيداً، و**الطرف
الآخر** يؤكده أو يعترض عليه؛ فالرصيد المتفق عليه هو ما أكّده الطرفان.
مستقل تماماً عن مشروع نُخبة.

## 2. الهويات والموارد

| المورد | القيمة |
|---|---|
| المستودع | `github.com/AbdulmannanY/dain` (عام)، الفرع `main` |
| حساب GitHub | `AbdulmannanY` (منفصل عن `adbrhman` الخاص بنُخبة) |
| Supabase | منظمة `Dain` (Free)، مشروع `dain-backend`، فرانكفورت، ref `mxnjwaofjlxxdjizjsfb` |
| Supabase URL | `https://mxnjwaofjlxxdjizjsfb.supabase.co` |
| Publishable key | `sb_publishable_JTVwmwscU9kAwi3PM2EQMQ_shfAYx5X` (علني بالتصميم، RLS يحمي البيانات؛ موجود في `app/lib/core/config.dart`) |
| معرّف التطبيق | `app.dain.dain`، الاسم الظاهر «دائن» |
| Flutter | `3.44.0` (Dart 3.12)، مثبّت في `.fvmrc` ويقرأه CI |

### الدخول بالجوال (إعداد Supabase)

Authentication ← Sign In / Providers ← **Phone**:

- مزوّد SMS هو Twilio **بقيم وهمية** (`AC000…`)، أي لا تُرسل رسائل حقيقية.
  الدخول يعمل الآن بأرقام الاختبار فقط.
- **Test Phone Numbers and OTPs**: `966500000001=123456,966500000002=123456`
  (مفصولة بفاصلة على سطر واحد، لا سطر لكل رقم).
- **Test OTPs Valid Until**: **2027-01-20**. بعده تتوقف أرقام الاختبار،
  ويفشل الاختبار الحي بـ `sms_send_failed`. جدّده قبل ذلك.
- الحفظ يتم بزر Save **داخل لوحة Phone** نفسها.

## 3. بيئة التطوير

- كل العمل على Android: Termux ← proot-distro Ubuntu، المستخدم `dev`،
  المستودع في `/home/dev/dain`.
- اعتماد git خاص بدائن فقط: `credential.helper = store --file=/home/dev/.git-credentials-dain`
  (لا يمسّ نُخبة). التوكن fine-grained باسم **dain-push-2**، وصلاحياته على
  المستودع: **Contents = Read and write** و**Workflows = Read and write**.
  بدون Workflows يرفض GitHub أي دفع يلمس `.github/workflows/`
  (`refusing to allow a Personal Access Token ... without workflow scope`).
- لا يُبنى APK محلياً (NDK غير متاح على ARM داخل proot). المعاينة عبر:

  ```bash
  cd ~/dain/app && flutter run -d web-server --web-port 8081 --web-hostname 0.0.0.0
  ```

  ثم `http://localhost:8081` في متصفح الجوال.

### جلسات Claude (بيئة السحابة)

البوابة تحجب كل نطاق غير مسموح. يجب أن تكون في
Settings ← Capabilities ← Allow network egress ← Additional allowed domains:

- `storage.googleapis.com` (Flutter/Dart SDK)
- `pub.dev` (الحزم)
- `*.supabase.co` (أو `mxnjwaofjlxxdjizjsfb.supabase.co`) للاختبار الحي

GitHub مسموح أصلاً (clone/fetch للمستودعات العامة). واجهة GitHub API غير
متاحة للمستودع من الجلسة؛ نتائج Actions تُقرأ من صفحة
`github.com/AbdulmannanY/dain/actions` العامة.

## 4. الشجرة

```
.fvmrc                         Flutter 3.44.0
.github/workflows/ci.yml       CI (انظر §7)
docs/                          هذا الملف + بروتوكول التسليم
supabase/
  migrations/20261020000000_dain_core.sql   المخطط كاملاً
  tests/supabase_stub.sql      بديل أدنى لأجزاء Supabase (auth.users, auth.uid, الأدوار)
  tests/ledger_flow_test.sql   39 فحصاً عبر RLS والدوال بنفس أدوار Supabase
  tests/run_tests.sh           ينشئ قاعدة مؤقتة ويطبّق ويختبر ثم يحذفها
app/                           تطبيق Flutter (android + web)
  lib/main.dart                Supabase.initialize ثم DainApp
  lib/app.dart                 MaterialApp عربي RTL، ثيم أخضر 0xFF0E6B4F
  lib/core/config.dart         URL والمفتاح (قابلان للتغيير بـ --dart-define)
  lib/core/phone_number.dart   normalizePhone / asciiDigits
  lib/core/errors.dart         رسالة عربية لكل خطأ
  lib/core/money.dart          formatMoney(minor, currency)
  lib/data/auth_repository.dart      OTP: sendOtp / verifyOtp / signOut
  lib/data/profile_repository.dart   profiles + link_my_ledgers()
  lib/data/ledger_repository.dart    LedgerSummary, buildSummaries, totalsByCurrency
  lib/session/session_controller.dart   مراحل الدخول
  lib/ledgers/ledgers_controller.dart   تحميل/تحديث القائمة
  lib/ui/session_gate.dart     يعرض شاشة المرحلة الحالية
  lib/ui/screens.dart          الجوال، الرمز، الاسم، فشل التحميل
  lib/ui/ledgers_screen.dart   «دفاتري» (الشاشة الرئيسية بعد الدخول)
  test/                        وحدات + واجهة + test/live (حي، اختياري)
```

## 5. قاعدة البيانات (المخطط المطبّق والمتحقَّق منه)

**اصطلاح الإشارة، دائماً نسبةً لمالك الدفتر:**
`out` = المالك أعطى الطرف (الطرف مدين أكثر)، `in` = الطرف أعطى المالك.
الرصيد > 0 يعني أن الطرف مدين للمالك. المبالغ أعداد صحيحة بالهللة
(500.00 ر.س = 50000)، والحد 1..100,000,000,000.

| الجدول | أهم الأعمدة والقيود |
|---|---|
| `profiles` | `id` = `auth.users.id`، `full_name` 1..80 |
| `businesses` | `owner_id` (افتراضي `auth.uid()`)، `name` 1..80 |
| `ledgers` | `owner_id`، `business_id` اختياري (يجب أن يملكه نفس المالك)، `counterparty_name`، `counterparty_phone` بصيغة E.164 بلا `+` (`^[1-9][0-9]{7,14}$`)، `counterparty_id` (لا يضبطه إلا `link_my_ledgers`)، `currency` (افتراضي SAR)، `remind_every_days` 1..90، فريد على `(owner_id, business_id, counterparty_phone)` مع NULLS NOT DISTINCT |
| `entries` | `direction` (`out`/`in`)، `amount_minor`، `note` ≤200، `occurred_on`، `status` (`pending`/`confirmed`/`disputed`/`voided`)، `response_note`، `responded_via` (`app`/`link`)، `created_by` |
| `share_links` | رابط واحد لكل دفتر، يُخزَّن SHA-256 للرمز فقط، `expires_at` |
| `ledger_balances` (view, security_invoker) | `confirmed_balance_minor`، `open_balance_minor` (مؤكد + معلّق)، `pending_count`، `disputed_count` |

**الحرّاس:**

- RLS على كل الجداول. الطرف الآخر يرى الدفتر فقط بعد ربطه
  (`counterparty_id = auth.uid()`). لا سياسة حذف للدفاتر.
- الصلاحيات مضيَّقة بالأعمدة: إدخال `entries` يقبل
  `ledger_id, direction, amount_minor, note, occurred_on` فقط، وبحالة `pending`.
  تغيير الحالة عبر الدوال فقط.
- trigger `ledgers_guard_phone`: لا يتغير الرقم بعد الربط، وأي تصحيح للرقم
  يحذف رابط المشاركة.

**الدوال (RPC):**

| الدالة | لمن | ماذا تفعل |
|---|---|---|
| `link_my_ledgers()` | authenticated | تربط كل دفتر مسجّل على رقمي **المؤكَّد** (`phone_confirmed_at`)؛ تتطلب ملفاً شخصياً (وإلا `42501`)؛ ترجع العدد؛ متكررة بأمان |
| `respond_entry(id, decision, note)` | authenticated | الطرف **الآخر** يؤكد أو يعترض؛ `pending→confirmed/disputed`، `disputed→confirmed` |
| `void_entry(id)` | authenticated | المنشئ يسحب قيداً معلّقاً أو معترضاً عليه. المؤكد لا يُعدَّل، يُصحَّح بقيد معاكس |
| `create_share_link(ledger, days)` / `revoke_share_link` | المالك | رابط لمن لا يملك التطبيق (1..90 يوماً)، والرمز يُرجَع مرة واحدة |
| `get_shared_ledger(token)` / `respond_by_token(...)` | anon | صفحة ويب للتأكيد بلا تطبيق؛ يستطيع التأكيد فقط على قيود سجّلها المالك |

## 6. التطبيق (ما بُني)

**تسلسل الدخول** (`SessionController`):
`starting` ← `enterPhone` ← `enterCode` ← `needsProfile` (إن لم يوجد ملف)
← `ready`، مع `failed` وزر إعادة محاولة.

- `link_my_ledgers()` يُستدعى عند **كل** دخول إلى `ready`، وليس أول مرة فقط،
  لأن من يسجّل ديناً برقمك لاحقاً يجب أن يظهر عندك في الفتح التالي.
- `normalizePhone` تقبل `05…` و`5…` و`+966…` و`00966…` والفواصل والأرقام
  العربية والفارسية، وتنتج صيغة قيد `counterparty_phone` نفسها. الأرقام
  السعودية يجب أن تكون جوالات (`9665XXXXXXXX`).
- إنشاء الملف الشخصي متكرر بأمان: عند `23505` يُقرأ الملف الموجود.

**«دفاتري»** (`LedgersScreen`):

- استعلامان عبر RLS: `ledgers` مع
  `business:businesses(name)` و`owner:profiles!ledgers_owner_id_fkey(full_name)`،
  ثم `ledger_balances`. لا يمكن دمجهما في استعلام واحد، لأن PostgREST لا
  يرى علاقة مع الواجهة (`PGRST200`).
- `buildSummaries` تقلب الإشارة لغير المالك، فيكون الرصيد دائماً من جهتي
  (موجب = «لك»، سالب = «عليك»).
- العنوان: عند المالك اسم الطرف (والمحل تحته)، وعند الزبون اسم المحل (أو
  المالك) واسم المالك تحته.
- لكل دفتر: «N بانتظار التأكيد»، و«N معترض عليه»، و«لم ينضم بعد».
- مجموع «لك» ومجموع «عليك» لكل عملة، والسحب للتحديث (يُبقي القائمة عند
  الفشل)، وإعادة المحاولة عند فشل أول تحميل، وشريط «أُضيف إلى حسابك N دفاتر».
- الترتيب حسب حجم الرصيد المتفق عليه، ثم الاسم.
- المبالغ: `45.50 ر.س`، و`5,000 ر.س` (بلا `.00`).

**غير مبني بعد:** فتح دفتر، شاشة الدفتر وقيوده، تسجيل قيد، التأكيد أو
الاعتراض أو السحب من التطبيق، رابط المشاركة وصفحة الويب، التذكير
(`remind_every_days` بلا مُشغّل)، المحلات من التطبيق، بناء APK في CI.

**التبعيات:** `supabase_flutter ^2.18.3` و`flutter_localizations` (SDK) فقط.
لا Riverpod؛ الحالة عبر `ChangeNotifier` + `ListenableBuilder`. أي تبعية
جديدة تحتاج موافقة.

## 7. الاختبارات وCI

| الأمر | ماذا يغطي |
|---|---|
| `cd app && flutter test` | 24 اختباراً: تطبيع الأرقام، تسلسل الدخول عبر `DainApp` كاملاً بمستودعات وهمية، الملخصات والمجاميع والمبالغ، شاشة الدفاتر بعرض جوال 360 بكسل |
| `cd app && flutter test test/live --dart-define=DAIN_LIVE=true` | على Supabase الحقيقي بالرقمين، عبر `SessionController` والمستودعات الحقيقية: (1) أ يفتح محلاً ودفتراً لرقم ب، ثم ب يدخل فيُربط له؛ (2) أ يسجّل 123.45 و3.45، ب يؤكد الأول، ثم يُتحقَّق من الرصيد من الجهتين (+12345/−12345، مفتوح 12000، معلّق 1) |
| `PGHOST=... PGPORT=... PGUSER=postgres bash supabase/tests/run_tests.sh` | المخطط و39 فحصاً (Postgres 15+) |

- الاختبار الحي يُتخطّى ما لم يُمرَّر `DAIN_LIVE=true`. كل تشغيل يضيف محلات
  ودفاتر وقيوداً جديدة لحسابَي الاختبار، وهذا مقصود: كل تشغيل يثبت ربطاً
  وأرصدة جديدة بدل الاعتماد على حالة سابقة.
- اختبارات الطفرات (mutation) أُجريت يدوياً: تعطيل `link_my_ledgers` أو قلب
  الإشارة يُفشل الاختبارات.
- **CI** (`.github/workflows/ci.yml`) عند push إلى `main` وعند PR:
  - **Flutter app**: `pub get` ← `dart format --set-exit-if-changed` ←
    `flutter analyze --fatal-infos` ← `flutter test`.
  - **Database schema tests**: حاوية `postgres:17` ← `run_tests.sh`.
  - تشغيل يدوي: Run workflow مع `live=true` يضيف الاختبار الحي.
  - `actions/checkout@v5`.

## 8. السجل

| commit | التاريخ | المحتوى | CI |
|---|---|---|---|
| `4743e60` | 2026-10-20 | المخطط والـ RLS والدوال واختبارات SQL | — |
| `7f49645` | 2026-10-20 | التطبيق: دخول OTP، ملف شخصي، `link_my_ledgers`، CI (سكربت `dain-01-app.sh`) | #1 ✅ 1:38 |
| `dce7669` | 2026-10-21 | قائمة الدفاتر بالأرصدة، checkout v5 (سكربت `dain-02-ledgers.sh`) | #2 ✅ 0:52 |

دروس الجلسة:

- `sms_send_failed` مع `AC000…` يعني أن أرقام الاختبار غير مفعّلة: إما صيغة
  الحقل خاطئة، أو تاريخ الصلاحية فارغ، أو الحفظ تم في القسم الخطأ.
- رفض الدفع بسبب `workflow scope` حلّه صلاحية Workflows في التوكن، لا تعديل الملفات.
- `dart:io` لا يُستورد في `lib/` لأن التطبيق يُبنى للويب أيضاً.

## 9. الخطوة التالية المقترحة

1. **فتح دفتر**: اسم الطرف، رقمه (`normalizePhone`)، شخصي أو لمحل (مع إنشاء
   المحل). انتبه لتصادم المفتاح الفريد (`23505`) عند تكرار الرقم.
2. **شاشة الدفتر**: القيود، وتسجيل دين أو سداد، والتأكيد أو الاعتراض
   (`respond_entry`) للطرف الآخر فقط، والسحب (`void_entry`) للمنشئ.
3. رابط المشاركة وصفحة التأكيد على الويب.
4. مزوّد SMS حقيقي قبل أي مستخدم فعلي.
5. بناء APK في CI.
