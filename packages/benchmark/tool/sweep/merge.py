# Merges a sweep's per-target files into load.md and load.json beside
# this package, and all.json in the sweep directory for the report.
#
#   python3 tool/sweep/merge.py <sweep-dir> "<how the sweep ran>"
#
# The second argument is the paragraph under the HTTP table: machine,
# date and anything a reader needs to judge the numbers. The table
# header line comes from http_load's own output.
import json, os, sys
S = os.path.dirname(os.path.abspath(__file__))
B = os.path.normpath(os.path.join(S, '..', '..'))
N = sys.argv[1]
how = sys.argv[2]
order = [l.split()[1] for l in open(os.path.join(S, 'sweep.sh')) if l.startswith('scenario ')]
rows = []; md = {}; missing = []
for name in order:
    j = os.path.join(N, name + '.json'); m = os.path.join(N, name + '.md')
    if not os.path.exists(j):
        missing.append(name); continue
    rows += json.load(open(j))
    md[name] = [l for l in open(m) if l.startswith('| ') and not l.startswith('| target')]
json.dump(rows, open(os.path.join(N, 'all.json'), 'w'), indent=2)
json.dump(rows, open(os.path.join(B, 'load.json'), 'w'), indent=2)
first = next(n for n in order if n in md)
head = [l.rstrip('\n') for l in open(os.path.join(N, first + '.md'))][:4]
intro = head[0]
table_head = '\n'.join(l for l in head if l.startswith('|'))
http = [n for n in order if not n.endswith('-tls')]
tls = [n for n in order if n.endswith('-tls')]
old_path = os.path.join(B, 'load.md')
old = open(old_path).read() if os.path.exists(old_path) else ''
wasm = old[old.index('\nThe wasm hosts'):] if '\nThe wasm hosts' in old else ''
text = intro + '\n\n' + table_head + '\n' + ''.join(''.join(md[n]) for n in http if n in md)
text += '\n' + how + ' The closed-loop rates behind every saturation figure are in load.json as `saturationRuns`. The `-aot` rows are `dart build cli` bundles of the same servers, the rest run under `dart run`.\n'
text += '\nThe same routes over HTTPS, TLS 1.3 with the relic_native test certificate, from the same sweep. oha keeps its 64 connections open, so the cost is per record, not per handshake.\n\n'
text += table_head + '\n' + ''.join(''.join(md[n]) for n in tls if n in md)
text += wasm
open(old_path, 'w').write(text)
print('merged', len(rows), 'rows, missing:', missing)
