# بروتوكول التسليم — دائن

> كيف تُسلَّم التعديلات لهذا المستودع. السياق في
> [`docs/project-context.md`](project-context.md)، والبداية في
> [`docs/START-HERE.md`](START-HERE.md)، وأدوات توليد السكربتات في
> [`tools/patchgen/`](../tools/patchgen/README.md).

## لماذا هذا الشكل

لوحة المفاتيح العربية في Termux تُفسد الأوامر الإنجليزية، والـ heredoc
الطويل المكتوب يدوياً ينكسر. لذلك لا تُرسل ملفات كاملة ولا أوامر طويلة
للكتابة؛ يُرسل **سكربت واحد** يُنزَّل ويُشغَّل.

## قبل أي اقتراح

1. اقرأ الشجرة الفعلية من `main` (clone أو `raw.githubusercontent.com`)،
   لا الذاكرة. تحقّق من وجود كل ملف ومسار وعمود ودالة تذكرها.
2. تتبّع السلسلة كاملة: الواجهة ← المتحكم ← المستودع ← PostgREST/RPC ←
   RLS والصلاحيات والقيود ← الجدول.
3. ابحث عن الحرّاس: سياسات RLS، صلاحيات الأعمدة، القيود، الـ triggers،
   الـ asserts. تغيير لا يمرّ عبرها لا يعمل.
4. إن احتمل الطلب أكثر من قراءة، اسأل سؤالاً واحداً.

## شكل السكربت

- **سكربت bash واحد لكل إصلاح**، اسمه `dain-NN-<topic>.sh`، **ASCII فقط**.
- الحرّاس أولاً، قبل أي كتابة:
  - `whoami` = `dev`
  - `cd /home/dev/dain`، ووجود `supabase/migrations/20261020000000_dain_core.sql`
  - `origin` يحوي `AbdulmannanY/dain`
  - `git merge-base --is-ancestor <commit سابق> HEAD` إن كان يبني على تسليم سابق
  - شجرة git نظيفة (وإلا يطبع `git status --short` ويتوقف)
- **الباتش** سكربت Python مرمَّز base64 داخل السكربت
  (`echo '<b64>' | base64 -d > tmp.py; python3 tmp.py`):
  - تعديل ملف قائم = `str.replace` على نص حرفي، مع `assert` أن المرساة
    موجودة **مرة واحدة بالضبط**.
  - ملف جديد = محتوى base64، مع `assert` أنه غير موجود (يمنع التطبيق المزدوج).
  - كل الـ asserts تُفحص **قبل** أي كتابة، فلا يترك الفشل الشجرة نصف معدّلة.
- بعد الباتش يُضبط `trap ... ERR` يطبع أمر التراجع
  (`git checkout -- . && git clean -fd app`).
- **التحقق** بنفس خطوات CI، من `app/`:
  `flutter pub get` ← `dart format --output=none --set-exit-if-changed <الملفات>` ←
  `flutter analyze --fatal-infos` ← `flutter test` ←
  `flutter test test/live --dart-define=DAIN_LIVE=true`
- **commit** بأسماء الملفات صراحةً. لا `git add -A`، ولا push. الرسالة تُكتب
  عبر `git commit -F - <<'MSG'`.
- يطبع `git log --oneline -1` ثم `DONE`.

## قبل الإرسال

- طبّق السكربت كمستخدم `dev` على **نسخة جديدة** من `main` حتى `DONE`، ثم
  شغّله مرة ثانية وتأكد أنه يتوقف دون أن يكتب شيئاً.
- كل مرساة يجب أن تكون قد طُبّقت على نسخة نظيفة، وأن الناتج مطابق لنسخة
  العمل بعد `dart format`.
- الاختبار يمرّ عبر نقطة الدخول الحقيقية للميزة: `DainApp` و`SessionController`
  والمستودعات الحقيقية في الاختبار الحي، لا مجرد التحقق من وجود الملفات.
  اختبار يتخطّى الدالة المعيبة لا يكشف شيئاً؛ جرّب طفرة واحدة على الأقل
  وتأكد أن الاختبار يفشل.
- لا placeholders، ولا تبعيات جديدة، ولا تغيير معماري دون موافقة.

## التشغيل على الجوال

```bash
f="$(ls -t /sdcard/Download/dain-NN-*.sh | head -1)"; echo "using: $f"; cp "$f" ~/fix.sh && cd ~/dain && bash ~/fix.sh
```

`ls -t | head -1` يلتقط أحدث نسخة، فلا يضرّ تكرار التنزيل. إن ظهر
`No such file` فالتنزيل لم يكتمل بعد.

بعد `DONE` يدفع المستخدم بنفسه (الدفع يحتاج إذنه في كل جلسة):

```bash
git push origin main
```

ثم يُفحص CI من `github.com/AbdulmannanY/dain/actions`.

إن توقّف بـ «uncommitted changes»:

```bash
git status --short
git stash push -u -m "wip" -- <الملفات>
```

ثم أعد التشغيل، و`git stash pop` بعد الدفع.

## العرض في المحادثة

بالعربية وباختصار. اعرض الأسطر المتغيّرة فقط مع اسم الملف، ومصطلحات الواجهة
بالإنجليزية مع ترجمتها، مثل `Save / حفظ`.
