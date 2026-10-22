# patchgen: how the delivery scripts are made

The owner works in Termux (proot Ubuntu, user `dev`, repo at `~/dain`) with
an Arabic keyboard that breaks typed English, so changes arrive as one
downloaded bash script per fix. See `docs/agent-script-protocol.md` and
`docs/START-HERE.md` (section 8).

## Steps

1. Clone `main` twice: `base` (untouched) and `target` (make the change
   there: code, tests, `dart format`, `flutter analyze --fatal-infos`,
   `flutter test`, live tests).
2. Patch:

       GUARD='app/lib/x.dart|text the change adds' \
       python3 tools/patchgen/gen.py base target /tmp/pNN.py \
         app/lib/x.dart app/test/y.dart -- app/lib/new_file.dart

3. Script (commit message in an ASCII file ending "Script: NAME.sh"):

       EXTRA_VERIFY='' python3 tools/patchgen/mk.py dain-NN-what /tmp/pNN.py \
         "app/lib/x.dart app/test/y.dart app/lib/new_file.dart" msg.txt \
         '[ -f some/marker ] || die "run dain-MM first"' <base-commit> /out

4. Test it the way the owner runs it: a fresh clone in `/home/dev/dain`, as
   user `dev`, until `DONE`; run it again and expect
   `STOP: patch refused; nothing was written`; run later scripts of a batch
   in order. Only when a migration is not yet in production may a copy skip
   the live step for this check (say so to the owner).

## Batches and docs

- Several scripts in one batch: build each on the previous target, give
  each a guard that the previous one was applied, and run them in order
  with a minute between them (one OTP per phone per minute, live tests).
- Docs scripts in a batch cannot know the hashes of commits made on the
  phone: write `@@HNN@@` in the target and add, before the line
  "# every anchor was checked above", a lookup by commit subject:

      log = subprocess.check_output(["git", "log", "-n", "60",
                                     "--format=%h %s"], text=True).splitlines()
      hits = [l.split(" ", 1)[0] for l in log
              if l.split(" ", 1)[1] == "<exact subject>"]
      assert len(hits) == 1
      s = s.replace("@@HNN@@", hits[0])

  Lines that already hold a phone-made hash (the "last updated" header)
  must be matched by a regular expression, not a literal anchor.
