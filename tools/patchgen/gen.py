#!/usr/bin/env python3
"""Builds an ASCII-only Python patch that turns BASE into TARGET.

Usage (run from anywhere; BASE and TARGET are two checkouts of the repo):
  GUARD='path/in/repo|marker text' \\
  python3 gen.py BASE TARGET out.py modified/file1 modified/file2 -- new/file1 new/file2

- Each change becomes str.replace on an anchor (the changed lines plus
  context) that must occur exactly once; the anchor grows until it does.
- Applying the anchors in order to BASE is checked to give TARGET exactly.
- Every string is base64 inside the patch, so the patch itself is ASCII.
- Changes closer than a few lines share one anchor (the gap grows until
  the anchors rebuild TARGET), so no anchor's context reaches into text an
  earlier replacement already changed.
- GUARD: the patch refuses to run when the marker is already in that file
  (the change was applied before). Pick text the change adds.
- The generated patch checks every anchor in memory first and writes no
  file until all of them passed.
"""
import base64
import difflib
import os
import sys

base, target, out = sys.argv[1:4]
rest = sys.argv[4:]
i = rest.index('--')
mods, news = rest[:i], rest[i + 1:]


def b64(t):
    return base64.b64encode(t.encode()).decode()


plan = []
for f in mods:
    old = open(f'{base}/{f}', encoding='utf-8').read()
    new = open(f'{target}/{f}', encoding='utf-8').read()
    ol, nl = old.splitlines(True), new.splitlines(True)
    raw = [o[1:] for o in difflib.SequenceMatcher(None, ol, nl, autojunk=False)
           .get_opcodes() if o[0] != 'equal']

    def build(gap):
        # Changes closer than `gap` lines become one anchor, so no anchor's
        # context reaches into text an earlier replacement already changed.
        ops = []
        for op in raw:
            if ops and op[0] - ops[-1][1] < gap:
                p = ops[-1]
                ops[-1] = (p[0], op[1], p[2], op[3])
            else:
                ops.append(op)
        reps = []
        for i1, i2, j1, j2 in ops:
            ctx = 1
            while True:
                a0, a1 = max(0, i1 - ctx), min(len(ol), i2 + ctx)
                anchor = ''.join(ol[a0:a1])
                repl = ''.join(ol[a0:i1]) + ''.join(nl[j1:j2]) + ''.join(ol[i2:a1])
                if old.count(anchor) == 1 and len(anchor.strip()) > 20:
                    break
                ctx += 1
            reps.append((anchor, repl))
        t = old
        for a, r in reps:
            if t.count(a) != 1:
                return None
            t = t.replace(a, r)
        return reps if t == new else None

    for gap in (2, 4, 8, 16, 32, 64, 10**9):
        reps = build(gap)
        if reps is not None:
            break
    assert reps is not None, f'anchors do not rebuild {f}'
    plan.append(('mod', f, reps))
for f in news:
    plan.append(('new', f, open(f'{target}/{f}', encoding='utf-8').read()))

guard_path, guard_marker = os.environ['GUARD'].split('|')
L = ['import base64, os, sys',
     'd = lambda s: base64.b64decode(s).decode("utf-8")',
     f'assert d({b64(guard_marker)!r}) not in open({guard_path!r}, '
     'encoding="utf-8").read(), "already applied"',
     'out = {}']
for kind, f, x in plan:
    L.append(f'p = {f!r}')
    if kind == 'mod':
        L.append('s = open(p, encoding="utf-8").read()')
        for a, r in x:
            L.append(f'a = d({b64(a)!r})')
            L.append(f'r = d({b64(r)!r})')
            L.append('assert s.count(a) == 1, '
                     '("anchor not found exactly once", p, s.count(a))')
            L.append('s = s.replace(a, r)')
        L.append('out[p] = s')
    else:
        L.append('assert not os.path.exists(p), ("already exists", p)')
        L.append(f'out[p] = d({b64(x)!r})')
L += ['# every anchor was checked above; nothing is written before this line',
      'for p, s in out.items():',
      '    if os.path.dirname(p):',
      '        os.makedirs(os.path.dirname(p), exist_ok=True)',
      '    open(p, "w", encoding="utf-8").write(s)',
      '    print("wrote", p)']
src = '\n'.join(L) + '\n'
src.encode('ascii')
open(out, 'w').write(src)
print(out, len(src), 'bytes;', sum(len(x[2]) for x in plan if x[0] == 'mod'),
      'anchors')
