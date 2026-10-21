# دائن (Dain) — سياق المشروع

> المرجع الوحيد للمشروع. اقرأه كاملاً قبل أي اقتراح، ثم تحقّق من الشجرة
> الفعلية (لا من الذاكرة). بروتوكول التسليم في
> [`docs/agent-script-protocol.md`](agent-script-protocol.md).
>
> آخر تحديث: 2026-10-22، عند الـ commit `db069b3`.

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
| صفحة المشاركة | `https://abdulmannany.github.io/dain/#<token>` (GitHub Pages من `share/`؛ `DainConfig.shareBaseUrl`) |
| مفتاح توقيع APK | `CN=Dain, O=Dain, C=SA`، alias `upload`، SHA-256 `12:5F:5F:48:45:DC:21:64:04:C8:3D:EA:E4:29:A2:FB:E9:12:2D:B5:98:0A:9B:64:BE:E8:28:26:CD:27:C8:71` |

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
- GitHub Pages يُفعَّل مرة واحدة: Settings ← Pages ← Source: **GitHub Actions**.
  بدونه يفشل workflow «Share page deploy» (هذا ما حدث في تشغيله الأول).
- لا يُبنى APK محلياً (NDK غير متاح على ARM داخل proot)؛ يُنزَّل من CI (§7).
- **مفتاح التوقيع** على الجوال فقط: `~/.dain-keys/upload.jks` وكلمة سره في
  `~/.dain-keys/password.txt` (صلاحية 600)، ونسخة احتياطية خارج الجوال. ولّده
  `dain-16-keystore.sh` مرة واحدة ويرفض استبداله. **لا يُستبدل أبداً**: تطبيق
  موقّع بمفتاح آخر لا يُحدّث النسخة المثبّتة. في GitHub أربعة أسرار:
  `DAIN_KEYSTORE_BASE64` و`DAIN_KEYSTORE_PASSWORD` و`DAIN_KEY_ALIAS` و
  `DAIN_KEY_PASSWORD` (`/settings/secrets/actions`).
- إعدادات المستودع على الجوال تحت **More ▾ ← Settings**؛ و`github.com/settings/...`
  إعدادات الحساب لا المستودع.
  المعاينة عبر:

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
.github/workflows/pages.yml    نشر share/ على GitHub Pages
docs/                          هذا الملف + بروتوكول التسليم
share/                         صفحة الرابط للطرف الآخر (HTML + JS، بلا تبعيات)
  index.html                   الصفحة، و CSP يسمح بـ Supabase فقط
  dain-share.js                المنطق والعرض (عُقد افتراضية ← DOM بـ textContent)
  dain-share.test.mjs          `node --test`، بلا تبعيات
supabase/
  migrations/20261020000000_dain_core.sql   المخطط كاملاً
  migrations/20261021000000_dispute_reason.sql   الاعتراض يحتاج سبباً
  migrations/20261022000000_mark_reminded.sql    تسجيل التذكير (المالك، بوقت الخادم)
  tests/supabase_stub.sql      بديل أدنى لأجزاء Supabase (auth.users, auth.uid, الأدوار)
  tests/ledger_flow_test.sql   54 فحصاً عبر RLS والدوال بنفس أدوار Supabase
  tests/run_tests.sh           ينشئ قاعدة مؤقتة ويطبّق ويختبر ثم يحذفها
app/                           تطبيق Flutter (android + web)
  lib/main.dart                runApp(DainBoot) فوراً، والتهيئة خلفه
  lib/boot.dart                DainBoot: «جارٍ البدء…»، ثم التطبيق؛ أو الخطأ وإعادة المحاولة
  lib/app.dart                 MaterialApp عربي RTL، ثيم أخضر 0xFF0E6B4F
  lib/core/config.dart         URL والمفتاح (قابلان للتغيير بـ --dart-define)
  lib/core/phone_number.dart   normalizePhone / asciiDigits
  lib/core/errors.dart         رسالة عربية لكل خطأ
  lib/core/money.dart          formatMoney(minor, currency)، parseMoney(input)
  lib/data/auth_repository.dart      OTP: sendOtp / verifyOtp / signOut
  lib/data/profile_repository.dart   profiles + link_my_ledgers()
  lib/data/ledger_repository.dart    LedgerSummary, buildSummaries, totalsByCurrency،
                                     Business، myPhone، المحلات، openLedger،
                                     LedgerEntry، entryDirection، buildEntries،
                                     entryActions، القيود والردود والسحب
  lib/session/session_controller.dart   مراحل الدخول
  lib/ledgers/ledgers_controller.dart   تحميل/تحديث القائمة
  lib/ledgers/open_ledger_controller.dart   نموذج «دفتر جديد»
  lib/ledgers/ledger_controller.dart   شاشة الدفتر: تحميل، قيد جديد، تأكيد/اعتراض/سحب، الرابط، التذكير
  lib/ledgers/shops_controller.dart    «محلاتي»: تحميل، إعادة تسمية، حذف
  lib/ui/session_gate.dart     يعرض شاشة المرحلة الحالية
  lib/ui/screens.dart          الجوال، الرمز، الاسم، فشل التحميل
  lib/ui/ledgers_screen.dart   «دفاتري» (الشاشة الرئيسية بعد الدخول)
  lib/ui/open_ledger_screen.dart   «دفتر جديد»
  lib/ui/ledger_screen.dart    الدفتر: الرصيد، القيود، «أعطيت/أخذت»، نافذة القيد
  lib/ui/common.dart           LoadError، owedToMeColor
  lib/ui/shops_screen.dart     «محلاتي»
  test/                        وحدات + واجهة + test/live (حي، اختياري)
```

## 5. قاعدة البيانات (المخطط المطبّق والمتحقَّق منه)

**اصطلاح الإشارة، دائماً نسبةً لمالك الدفتر:**
`out` = المالك أعطى الطرف (الطرف مدين أكثر)، `in` = الطرف أعطى المالك.
الرصيد > 0 يعني أن الطرف مدين للمالك. المبالغ أعداد صحيحة بالهللة
(500.00 ر.س = 50000)، والحد 1..100,000,000,000.

**تطبيق migration على الإنتاج يدوي:** Supabase ← SQL Editor ← لصق الملف ←
Run، **قبل** تشغيل السكربت الذي يضيفه (اختباره الحي يفشل حتى يُطبَّق، ويقول
ذلك في رسالته). CI يطبّق كل الملفات بالترتيب على `postgres:17` نظيفة.

**الاعتراض يحتاج سبباً** (`20261021000000`): `_apply_response` يرفض
`disputed` بلا سبب بعد `btrim` بـ `22023`، بعد فحص الحالة (فالمؤكد يبقى
`55000`)، ويخزّن الملاحظة مقصوصة. يسري على `respond_entry` و`respond_by_token`.

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
- `normalizePhone` تقبل الصيغ المحلية **السعودية** (`05…`، `5…` ← `9665…`)
  و**اليمنية** (`07…`، `7…` ← `9677…`)، وجوالاتهما لا تتداخل، و`966`/`967`
  بلا `+`، والفواصل والأرقام العربية والفارسية، وتنتج صيغة قيد
  `counterparty_phone` نفسها. أي دولة أخرى تحتاج `+` أو `00`: الرقم المجرّد
  لا يُقرأ دولياً أبداً (كان `774040697` يُرسل إلى `+7`). 966 يجب أن يكون
  `9665XXXXXXXX` و967 `9677XXXXXXXX`. الرسالة والتلميح ثابتان في
  `invalidPhoneMessage` و`phoneHint`.
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

**«دفتر جديد»** (`OpenLedgerScreen` + `OpenLedgerController`)، من زر
`New ledger / دفتر جديد` في «دفاتري»، ثم تُفتح شاشة الدفتر الجديد مباشرة:

- اسم الطرف ورقمه (`normalizePhone`)، و«الدفتر باسم»: شخصي، أو أحد محلاتي،
  أو «محل جديد» بالاسم. العملة SAR (الافتراضي)، والتذكير لا يُضبط.
- رقمي أنا يُرفض قبل أي كتابة: القاعدة تقبله، لكن `link_my_ledgers` لا تربط
  دفتراً بمالكه، فيبقى «لم ينضم بعد» للأبد. رقمي من `auth.currentUser.phone`.
- المحل الجديد يُنشأ بطلب منفصل قبل الدفتر. بعد إنشائه يصبح هو المختار،
  فإعادة المحاولة بعد فشل الدفتر لا تنشئ محلاً ثانياً (بلا migration).
- `23505` من المفتاح الفريد له رسالة في المتحكم (لا في `errors.dart` لأن
  الرمز نفسه يظهر في جداول أخرى): «لهذا الرقم دفتر في هذا المحل بالفعل.» أو
  «لديك دفتر شخصي لهذا الرقم بالفعل.».
- `fetchMyBusinesses` يصفّي بـ `owner_id = me`، لأن RLS يُظهر للزبون محل
  المالك أيضاً بعد الربط.

**شاشة الدفتر** (`LedgerScreen` + `LedgerController`)، بالضغط على دفتر، والقائمة
تُعاد قراءتها عند العودة:

- الرصيد المتفق عليه من جهتي، و«مع المعلّق»، وعدد المعلّق والمعترض عليه، وتنبيه
  «لم ينضم بعد». `fetchLedger(id)` يبني الملخص بنفس `buildSummaries`.
- القيود من الأحدث (`occurred_on` ثم `created_at` تنازلياً)، وكل قيد من جهتي:
  «أعطيت» (موجب) أو «أخذت» (سالب)، والتاريخ، ومن سجّله، والحالة («بانتظار
  تأكيدك» لقيود الطرف الآخر)، والرد.
- زرّا `أعطيت` و`أخذت` يسجّلان قيداً معلّقاً بتاريخ اليوم المحلي، بمبلغ
  (`parseMoney`: أرقام عربية، و`.` أو `٫`، وخانتان عشريتان كحد أقصى)
  وملاحظة اختيارية ≤200.
- **الاتجاه يُخزَّن نسبةً للمالك**: `entryDirection` تجعل «أعطيت» من الطرف الآخر
  `in`، و`buildEntries` تعيده إلى جهتي. الإدراج بالأعمدة المسموحة فقط.
- الضغط على قيد يعرض الإجراءات التي تسمح بها القاعدة فقط (`entryActions`):
  للطرف الآخر «تأكيد» و«اعتراض» على المعلّق، و«تأكيد» على المعترض عليه؛
  وللمنشئ «سحب القيد» بضغطة ثانية. المؤكد والمسحوب نهائيان.
- **سبب الاعتراض إجباري** (1..200، يُخزَّن في `response_note`) ليعرف المنشئ
  ماذا يصحّح. التطبيق والصفحة يتحققان منه، والقاعدة تفرضه أيضاً
  (`20261021000000`) على من يستدعي الدوال مباشرة.
- إن سبق الطرفُ الآخر (`55000`): «تغيّرت حالة هذا القيد. أُعيد تحميل الدفتر.»
  ويُعاد التحميل، فتعرض النافذة الحالة الجديدة.

**رابط للطرف الآخر** (المالك فقط، زر الرابط في شريط شاشة الدفتر):

- `create_share_link` (30 يوماً) يرجع الرمز مرة واحدة؛ يُبنى الرابط
  `DainConfig.shareUrl(token)` = `shareBaseUrl#token` ويُنسخ (`Clipboard`، بلا
  تبعية). الرمز بعد `#` فلا يصل إلى أي خادم أو سجل.
- «رابط جديد» يُبطل السابق، و«إيقاف الرابط» (`revoke_share_link`) يُبطله.
  الرمز لا يُقرأ ثانية (يُخزَّن SHA-256 فقط)، فيظهر في الجلسة التي أُنشئ فيها.

**صفحة الرابط** (`share/`، لمن لا يملك التطبيق، بدور `anon`):

- `fetch` إلى `/rest/v1/rpc/get_shared_ledger` و`respond_by_token` بترويسة
  `apikey` فقط (المفتاح المنشور يكفي، وCORS يسمح بأي أصل).
- تعرض الدفتر **من جهة الزائر**: الرصيد مقلوب، و`out` من المالك = «أخذت».
  التأكيد والاعتراض على قيود المالك فقط (`can_respond`)، والاعتراض على
  المعلّق فقط، و**سبب الاعتراض إجباري** كما في التطبيق.
- الأسماء والملاحظات (يكتبها المالك) تُعرض بـ `textContent` فقط، وCSP يمنع أي
  سكربت أو اتصال غير Supabase. `P0002` = رابط غير صالح أو منتهٍ، بلا إعادة
  محاولة؛ و`55000` يعيد التحميل.

**محلاتي** (`ShopsScreen` + `ShopsController`، زر المتجر في شريط «دفاتري»):

- الضغط على محل: إعادة تسمية (1..80 بعد القصّ)، أو حذف بضغطة ثانية.
- المحل الذي فيه دفاتر لا يُحذف: القاعدة ترفض (`23503`، المفتاح الأجنبي)
  لأن الدفتر سجل مشترك لا يُحذف. لا migration: `update (name)` و`delete`
  ممنوحان أصلاً وRLS يحصرهما في المالك (صف فارغ لغيره ← «المحل غير موجود.»).

**التذكير** (المالك فقط؛ لا SMS ولا إشعارات، فيرسله المالك بنفسه):

- زر الجرس في شاشة الدفتر: إيقاف أو كل 3/7/14/30 يوماً (`remind_every_days`،
  ممنوح التعديل أصلاً للمالك).
- `reminderDue`: مستحق حين يكون للمالك رصيد **متفق عليه** موجب ومرّت المدة منذ
  آخر تذكير (أو لم يُرسل قط). يظهر «تذكير مستحق» في «دفاتري» وزر في بطاقة
  الرصيد.
- الزر ينشئ رابطاً جديداً (يُبطل السابق)، وينسخ `reminderMessage` (الاسم والمحل
  والمبلغ والرابط) ليرسلها المالك عبر واتساب، ثم `mark_reminded` يسجّل الوقت
  **بساعة الخادم** (`last_reminded_at` غير ممنوح التعديل).

**غير مبني بعد:** تذكير يُرسل تلقائياً (يحتاج SMS حقيقياً أو إشعارات)، وتعديل
اسم الطرف ورقمه قبل انضمامه.

**التبعيات:** `supabase_flutter ^2.18.3` و`flutter_localizations` (SDK) فقط.
لا Riverpod؛ الحالة عبر `ChangeNotifier` + `ListenableBuilder`. أي تبعية
جديدة تحتاج موافقة.

## 7. الاختبارات وCI

| الأمر | ماذا يغطي |
|---|---|
| `cd app && flutter test` | 70 اختباراً (منها شاشة البدء، وحارس إضافات الإصدار): تطبيع الأرقام والمبالغ، تسلسل الدخول عبر `DainApp` كاملاً بمستودعات وهمية، الملخصات والمجاميع، الاتجاه والإشارة وإجراءات القيد لكل حالة، شاشة الدفاتر و«دفتر جديد» وشاشة الدفتر ونافذة القيد ورابط المشاركة بعرض جوال 360 بكسل |
| `cd app && flutter test test/live --dart-define=DAIN_LIVE=true` | على Supabase الحقيقي بالرقمين، عبر `SessionController` والمستودعات الحقيقية: (1) أ يفتح محلاً ودفتراً لرقم ب، ثم ب يدخل فيُربط له؛ (2) أ يسجّل 123.45 و3.45، ب يؤكد الأول، ثم يُتحقَّق من الرصيد من الجهتين (+12345/−12345، مفتوح 12000، معلّق 1)؛ (3) أ يفتح دفتراً في محل جديد عبر `OpenLedgerController`: رقمه مرفوض، والتكرار `23505`، ثم يُربط لـ ب، ومحل أ ليس من محلات ب؛ (4) عبر `LedgerController` من الجهتين: أ «أعطيت 100» يُخزَّن `out`، ب «أعطيت ٣٠» يُخزَّن `in`، ثم +7000/−7000؛ (5) اعتراض بلا سبب يُرفض محلياً، وبسبب يُخزَّن، والثاني `55000`، ثم سحب، واعتراض فتأكيد، وسحب المؤكد مرفوض، ثم +2000/−2000؛ (6) رابط من `LedgerController`: الطرف الآخر لا ينشئه، ثم بدور anon شكل `get_shared_ledger` الذي تعتمده `share/` (المفاتيح والاتجاه و`can_respond`)، واعتراض عبر الرابط يراه المالك، والرابط الجديد يُبطل القديم، والإيقاف يُبطل الجديد؛ (7) القاعدة نفسها ترفض الاعتراض بلا سبب أو بسبب فارغ (`22023`) عبر `respond_entry` وعبر الرابط، وتخزّن السبب مقصوصاً؛ (8) «محلاتي»: إعادة تسمية، وحذف الفارغ، والمحل ذو الدفتر يبقى (`23503`)، وب لا يعيد تسمية محل أ؛ (9) التذكير: الضبط، والاستحقاق، ورسالة برابط صالح، ووقت الخادم، ثم لا استحقاق، وب لا يضبط ولا يسجّل (`P0002`) |
| `node --test share/dain-share.test.mjs` | 12 اختباراً لمنطق الصفحة: الرمز، المبالغ، قلب الجهة، الأزرار لكل حالة، سبب الاعتراض، التحميل والتأكيد والاعتراض و`55000` و`P0002` بـ fetch وهمي، و`mount` نصوصاً لا markup |
| `PGHOST=... PGPORT=... PGUSER=postgres bash supabase/tests/run_tests.sh` | المخطط و54 فحصاً (Postgres 15+)، منها 7 لسبب الاعتراض و8 للتذكير |

- الاختبار الحي يُتخطّى ما لم يُمرَّر `DAIN_LIVE=true`. كل تشغيل يضيف محلات
  ودفاتر وقيوداً جديدة لحسابَي الاختبار، وهذا مقصود: كل تشغيل يثبت ربطاً
  وأرصدة جديدة بدل الاعتماد على حالة سابقة.
- كل رقم يدخل **مرة واحدة** في التشغيل (`setUpAll`)، والربط اللاحق عبر
  `relaunch()` أي `SessionController.start()` بالجلسة المحفوظة. لا تُعِد
  تشغيل الاختبار الحي قبل مرور دقيقة.
- اختبارات الطفرات (mutation) أُجريت يدوياً: تعطيل `link_my_ledgers` أو قلب
  الإشارة يُفشل الاختبارات، وكذلك حذف فحص رقمي، أو إعادة استخدام المحل، أو
  فلتر `owner_id`، أو الربط عند إعادة الفتح، أو قلب `entryDirection` أو
  إشارة `buildEntries`، أو الاعتراض على المعترض عليه، أو شرط السبب، أو قلب
  قرار `respond_entry` (يكشفه الاختبار الحي وحده)، أو نسخ الرابط، أو `#` في
  الرابط، أو قلب الجهة أو الرصيد أو شرط السبب في الصفحة.
- الصفحة جُرّبت أيضاً في jsdom على Supabase الحقيقي برابط حقيقي (عرض،
  اعتراض بلا سبب ثم بسبب، ورمز خاطئ)؛ jsdom ليس تبعية للمشروع.
- **CI** (`.github/workflows/ci.yml`) عند push إلى `main` وعند PR:
  - **Flutter app**: `pub get` ← `dart format --set-exit-if-changed` ←
    `flutter analyze --fatal-infos` ← `flutter test`.
  - **Android APK** (بعد نجاح Flutter app، ليس في PR): `flutter build apk
    --release` ويُرفع artifact باسم `dain-apk-<رقم التشغيل>` لمدة 14 يوماً.
    موقّع **بمفتاح الرفع الثابت** من الأسرار: الخطوة «Upload key from secrets»
    تقصّ المسافات والأسطر الملصوقة، وتفشل إن نقص سرّ أو إن لم يفتح `keytool`
    المفتاح بكلمة السر (في ثوانٍ لا بعد البناء). بعد البناء يجب أن يُظهر
    `apksigner` `CN=Dain`، فلا يُرفع APK موقّع بمفتاح debug أبداً. النسخ
    الجديدة تُثبَّت فوق السابقة (النسخ حتى `dain-apk-10` موقّعة بمفتاح debug:
    احذفها مرة واحدة). `build.gradle.kts` يقرأ `android/key.properties` إن وُجد،
    وإلا يستخدم مفتاح debug للبناء المحلي فقط.
  - **Share page**: `node --test share/dain-share.test.mjs` (Node 22).
  - **Database schema tests**: حاوية `postgres:17` ← `run_tests.sh`.
  - تشغيل يدوي: Run workflow مع `live=true` يضيف الاختبار الحي.
  - الإجراءات على إصدارات Node 24 (`checkout@v5`، `setup-node@v5`،
    `setup-java@v5`، `upload-artifact@v6`، `configure-pages@v6`،
    `upload-pages-artifact@v5`، `deploy-pages@v5`)، والمشغّلات مثبّتة على
    `ubuntu-24.04` بدل `ubuntu-latest` (الذي ينتقل إلى 26).
- **Share page deploy** (`.github/workflows/pages.yml`) عند push يلمس `share/`:
  الاختبارات ثم نشر `index.html` و`dain-share.js` فقط.

## 8. السجل

| commit | التاريخ | المحتوى | CI |
|---|---|---|---|
| `4743e60` | 2026-10-20 | المخطط والـ RLS والدوال واختبارات SQL | — |
| `7f49645` | 2026-10-20 | التطبيق: دخول OTP، ملف شخصي، `link_my_ledgers`، CI (سكربت `dain-01-app.sh`) | #1 ✅ 1:38 |
| `dce7669` | 2026-10-21 | قائمة الدفاتر بالأرصدة، checkout v5 (سكربت `dain-02-ledgers.sh`) | #2 ✅ 0:52 |
| `2e48034` | 2026-10-21 | هذا الملف وبروتوكول التسليم | #3 ✅ 0:52 |
| `29a244c` | 2026-10-21 | الاختبار الحي: دخول واحد لكل رقم (سكربت `dain-03-live-once.sh`) | دُفع مع التالي |
| `de88147` | 2026-10-21 | «دفتر جديد»: شخصي أو لمحل (سكربت `dain-04-open-ledger.sh`) | #4 ✅ 1:01 |
| `1e10c65` | 2026-10-21 | هذا الملف بعد «دفتر جديد» (سكربت `dain-05-docs.sh`) | #5 ✅ 0:57 |
| `3f3cb47` | 2026-10-21 | شاشة الدفتر وتسجيل «أعطيت/أخذت» (سكربت `dain-06-ledger-screen.sh`) | #6 ✅ 0:51 |
| `d8b166f` | 2026-10-21 | تأكيد القيد والاعتراض بسبب والسحب (سكربت `dain-07-respond.sh`) | #7 ✅ 0:56 |
| `7f8b3fa` | 2026-10-21 | هذا الملف بعد شاشة الدفتر (سكربت `dain-08-docs.sh`) | #8 ✅ 1:07 |
| `f9d54cd` | 2026-10-21 | رابط للطرف الآخر من شاشة الدفتر (سكربت `dain-09-share-link.sh`) | دُفعت 09..12 معاً |
| `85b679e` | 2026-10-21 | صفحة الرابط `share/` ونشرها على Pages (سكربت `dain-10-web-page.sh`) | — |
| `19f8b78` | 2026-10-21 | APK في CI (سكربت `dain-11-apk-ci.sh`) | — |
| `28259ff` | 2026-10-21 | هذا الملف بعد الرابط والصفحة وAPK (سكربت `dain-12-docs.sh`) | #9 ✅ 5:29، و`dain-apk-9`؛ Pages #1 ❌ (لم يكن مفعّلاً) |
| `84bb363` | 2026-10-21 | الاعتراض يحتاج سبباً في القاعدة (سكربت `dain-13-dispute-reason.sh`) | دُفعت 13..15 معاً |
| `871134e` | 2026-10-21 | إجراءات Node 24 و`ubuntu-24.04` (سكربت `dain-14-actions.sh`) | — |
| `05a0220` | 2026-10-21 | هذا الملف بعد سبب الاعتراض (سكربت `dain-15-docs.sh`) | #10 ✅ 5:18؛ Pages #2 ❌ ثم #3 ✅ يدوياً بعد تفعيل Pages |
| `26744ca` | 2026-10-21 | توقيع APK من الأسرار (سكربت `dain-17-apk-signing.sh`، بعد `dain-16-keystore.sh` على الجوال) | #11 ❌ `keystore password was incorrect` (قيمة السر الملصوقة) |
| `a1e6be1` | 2026-10-21 | فحص المفتاح قبل البناء وقصّ الأسرار (سكربت `dain-18-key-check.sh`) | #12 ✅ 6:09، و`dain-apk-12` موقّع بمفتاح الرفع |
| `de61505` | 2026-10-21 | هذا الملف بعد توقيع APK (سكربت `dain-19-docs.sh`) | #13 ✅ 6:19 |
| `c64e173` | 2026-10-22 | «محلاتي»: إعادة تسمية وحذف (سكربت `dain-20-shops.sh`) | دُفعت 20..22 معاً |
| `63dafcc` | 2026-10-22 | التذكير و`mark_reminded` (سكربت `dain-21-reminders.sh`) | — |
| `6f4a33e` | 2026-10-22 | هذا الملف بعد المحلات والتذكير (سكربت `dain-22-docs.sh`) | #14 ✅ 5:51 |
| `55de7c6` | 2026-10-22 | الرسم قبل التهيئة وإظهار أخطائها (سكربت `dain-23-boot.sh`) | #15 ✅ 6:21؛ `dain-apk-15` أظهر السبب: `NoSuchMethodError` في shared_preferences |
| `cad7f02` | 2026-10-22 | تثبيت `shared_preferences_android` تحت 2.5 (سكربت `dain-24-prefs-pin.sh`) | دُفعت 24..25 معاً |
| `9e1482b` | 2026-10-22 | هذا الملف بعد إصلاح بدء الإصدار (سكربت `dain-25-docs.sh`) | #16 ✅؛ `dain-apk-16` يفتح على شاشة الدخول |
| `db069b3` | 2026-10-22 | الأرقام اليمنية المحلية، ولا رقم مجرّد يُقرأ دولياً (سكربت `dain-26-yemen-phones.sh`) | دُفعت 26..27 معاً |

دروس الجلسة:

- `sms_send_failed` مع `AC000…` يعني أن أرقام الاختبار غير مفعّلة: إما صيغة
  الحقل خاطئة، أو تاريخ الصلاحية فارغ، أو الحفظ تم في القسم الخطأ.
- رفض الدفع بسبب `workflow scope` حلّه صلاحية Workflows في التوكن، لا تعديل الملفات.
- `dart:io` لا يُستورد في `lib/` لأن التطبيق يُبنى للويب أيضاً.
- **APK الإصدار كان يفتح على شاشة بيضاء**: `main()` كانت تنتظر
  `Supabase.initialize` قبل `runApp`، فأي فشل لا يُرى. `DainBoot` يرسم أولاً
  ويعرض الخطأ، فظهر السبب: `shared_preferences_android` 2.5.x يستدعي
  `SharedPreferencesApiRegistrar.getAll` عبر JNI بالاسم، وR8 يغيّر الأسماء في
  الإصدار ← `NoSuchMethodError`. الحل: قيد `>=2.4.28 <2.5.0` في `pubspec.yaml`
  (يعود تنفيذ method channel، ويخرج `jni` من القفل)، و`release_plugins_test.dart`
  يمنع رجوعه. اختبارات الواجهة ونسخ debug لا ترى أخطاء R8 أبداً.
- الاختبار الحي يفشل إن دخلت جهة أخرى بالرقم `0500000002` أثناءه (يُربط الدفتر
  قبله فيعيد `0`)؛ لا يُشغَّل اختباران حيّان معاً.
- Supabase يرفض رمزاً ثانياً للرقم نفسه خلال نحو دقيقة
  (`over_sms_send_rate_limit`)، حتى لأرقام الاختبار. لذلك كان الاختبار الحي
  الثاني يفشل دائماً على `2e48034`، ولذلك يُفصل بين سكربتين يشغّلان الاختبار
  الحي بدقيقة.
- في supabase_dart الدالة `.order()` **تنازلية افتراضياً**؛ التصاعدي يحتاج
  `ascending: true` صراحةً.
- في اختبارات الواجهة: `tester.pageBack()` يبحث عن تلميح `Back` الإنجليزي،
  والتطبيق عربي، فيُستخدم `find.byType(BackButton)`. و`find.descendant` لا
  يطابق الجذر نفسه إلا مع `matchRoot: true`.
- PostgREST يرجع `P0002` بحالة HTTP 500؛ الصفحة تقرأ `code` من JSON لا الحالة.
- لا CI ولا Pages يُجرَّبان من الجلسة (APK يحتاج Android SDK، وgithub.io غير
  مسموح)؛ يُتحقَّق منهما في صفحة Actions بعد الدفع. سجلات الخطوات تحتاج
  تسجيل الدخول، فتُطلب لقطة منها.
- PKCS12 يرد `keystore password was incorrect` لكلمة سر خاطئة **ولملف تالف**
  معاً (فحص MAC)؛ فحص `keytool -list` قبل البناء يفرّق بثوانٍ.
- GitHub يخفي قيم الأسرار في السجلات أينما ظهرت: `upload` صار `***` حتى في
  `actions/***-artifact` و`***-keystore.jks`.

## 9. الخطوة التالية المقترحة

1. رفع قيد `shared_preferences_android` حين يُصلح upstream قواعد R8 لـ JNI.
2. مزوّد SMS حقيقي قبل أي مستخدم فعلي (حساب Twilio ولوحة Supabase، لا سكربت)،
   ويشمل اليمن (+967). حتى ذلك الحين يعمل الدخول بالرقمين التجريبيين فقط.
   بعده يمكن إرسال التذكير تلقائياً (مُشغّل مجدول).
3. تعديل اسم الطرف ورقمه قبل انضمامه (`counterparty_name`/`counterparty_phone`
   ممنوحان، والرقم يُقفل بعد الربط بـ `55000`).
