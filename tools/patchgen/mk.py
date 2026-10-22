#!/usr/bin/env python3
"""Wraps a patch from gen.py into the delivery script the owner runs.

Usage:
  EXTRA_VERIFY='...bash lines...' \\
  python3 mk.py NAME PATCH.py "file1 file2 ..." MESSAGE.txt "EXTRA_GUARD" BASE OUTDIR

- NAME: dain-NN-what (the script is OUTDIR/NAME.sh).
- files: every file the patch writes; they are the only ones committed.
- MESSAGE.txt: the commit message, ASCII only, ending with
  "Script: NAME.sh".
- EXTRA_GUARD: bash lines run before the patch (e.g. that an earlier script
  was applied: [ -f ... ] || die "run dain-NN first"). May be "".
- BASE: a commit that HEAD must contain.
- EXTRA_VERIFY (env): bash lines run after the Flutter checks, e.g. the
  share page tests or the schema tests when a local Postgres exists.

The script: guards (user dev, ~/dain, origin, BASE, clean tree), the
patch, then the same checks as CI (format of the touched Dart files,
analyze, tests, live tests), then git add of the named files and a commit.
It never pushes.
"""
import base64
import os
import sys

name, patch, files, msg_path, extra_guard, base, outdir = sys.argv[1:8]
files = files.split()
msg = open(msg_path).read()
extra_verify = os.environ.get('EXTRA_VERIFY', '')
pb = base64.b64encode(open(patch, 'rb').read()).decode()
dart_files = ' '.join(f[len('app/'):] for f in files
                      if f.startswith('app/') and f.endswith('.dart')) or 'lib test'
sh = f'''#!/usr/bin/env bash
# {name}: see the commit message at the end. ASCII only.
set -euo pipefail

say() {{ printf '%s\\n' "$*"; }}
die() {{ say "STOP: $*"; exit 1; }}

# ---- guards (nothing is written before they pass)
[ "$(whoami)" = "dev" ] || die "run as dev (now: $(whoami))"
cd /home/dev/dain || die "no /home/dev/dain"
[ -f supabase/migrations/20261020000000_dain_core.sql ] || die "not the dain repo"
[ -f docs/project-context.md ] || die "docs/project-context.md missing"
git remote get-url origin | grep -q 'AbdulmannanY/dain' || die "origin is not AbdulmannanY/dain"
git merge-base --is-ancestor {base} HEAD || die "HEAD does not contain {base}; git pull first"
if [ -n "$(git status --porcelain)" ]; then
  git status --short
  die "uncommitted changes; stash them (see docs/agent-script-protocol.md)"
fi
{extra_guard}
# ---- patch (python checks every anchor before writing any file)
tmp="$(mktemp)"
echo '{pb}' | base64 -d > "$tmp"
python3 "$tmp" || {{ rm -f "$tmp"; die "patch refused; nothing was written"; }}
rm -f "$tmp"

trap 'say "FAILED. To undo: git checkout -- . && git clean -fd app supabase docs share tools"' ERR

# ---- verify, same steps as CI
cd app
flutter pub get
dart format --output=none --set-exit-if-changed {dart_files}
flutter analyze --fatal-infos
flutter test
flutter test test/live --dart-define=DAIN_LIVE=true
cd ..
{extra_verify}
# ---- commit (explicit files, no push)
git add {' '.join(files)}
git commit -F - <<'MSG'
{msg.rstrip()}
MSG
git log --oneline -1
say DONE
'''
sh.encode('ascii')
os.makedirs(outdir, exist_ok=True)
open(os.path.join(outdir, f'{name}.sh'), 'w').write(sh)
print(name, len(sh))
