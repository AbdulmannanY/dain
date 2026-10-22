#!/usr/bin/env python3
"""Lets a docs patch name commits made on the owner's phone.

A docs script in a batch cannot know the hashes of the commits the earlier
scripts make on the phone. Write @@HNN@@ in the target docs, then:

  python3 hashes.py PATCH.py 44=msgs/dain-44-payments.txt 45=msgs/dain-45-audit.txt

Each MESSAGE file is the commit message of script NN; its first line is the
commit subject. The patch then finds, at run time, the one commit in the last
60 with that subject and writes its short hash in place of @@HNN@@, and stops
if any placeholder is left. Lines that already hold a phone-made hash must be
matched by a regular expression, not a literal anchor.
"""
import sys

patch, pairs = sys.argv[1], sys.argv[2:]
src = open(patch).read()
anchor = '# every anchor was checked above'
assert src.count(anchor) == 1, 'not a patch made by gen.py'
subjects = {}
for pair in pairs:
    n, path = pair.split('=', 1)
    subjects[int(n)] = open(path, encoding='ascii').readline().strip()
code = (
    'import subprocess\n'
    'log = subprocess.check_output(["git", "log", "-n", "60", "--format=%h %s"], text=True).splitlines()\n'
    f'subjects = {subjects!r}\n'
    'for n, subject in subjects.items():\n'
    '    hits = [l.split(" ", 1)[0] for l in log if l.split(" ", 1)[1] == subject]\n'
    '    assert len(hits) == 1, ("commit of dain-%d not found once" % n, hits)\n'
    '    for k in out:\n'
    '        out[k] = out[k].replace("@@H%d@@" % n, hits[0])\n'
    'assert not any("@@H" in v for v in out.values()), "a hash placeholder is left"\n'
)
src = src.replace(anchor, code + anchor)
src.encode('ascii')
open(patch, 'w').write(src)
print(patch, 'looks up', ', '.join(f'dain-{n}' for n in subjects))
