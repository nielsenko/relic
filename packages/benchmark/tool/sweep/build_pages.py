# Builds the two report pages under report/out from a sweep's all.json
# and the template in report/relic_bench_template.html.
#
#   python3 tool/sweep/build_pages.py <sweep-dir> "<when the sweep ran>"
#
# The texts that depend on the data, the run count, the load list and
# the top open-loop point, are filled from all.json. The second argument
# replaces SWEEPDATES in the methodology.
import json, os, subprocess, sys
S = os.path.dirname(os.path.abspath(__file__))
P = os.path.normpath(os.path.join(S, '..', '..', 'report')) + '/'
N = sys.argv[1]
os.makedirs(P + 'out', exist_ok=True)
rows = subprocess.run(['python3', os.path.join(S, 'gen_rows.py'), os.path.join(N, 'all.json')], capture_output=True, text=True, check=True).stdout
t = open(P + 'relic_bench_template.html').read()
a = t.index('const rows = [\n'); b = t.index('\n];\n', a) + 4
t = t[:a] + rows + t[b:]
data = json.load(open(os.path.join(N, 'all.json')))
loads = sorted({m['load'] for m in data})
runs = sorted({len(m.get('saturationRuns', [])) for m in data if m['load'] == 1.0})
words = {1: 'one', 2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six'}
pct = [str(int(l * 100)) for l in loads]
t = t.replace('SATRUNS', words.get(runs[-1], str(runs[-1])))
t = t.replace('LOADLIST', ', '.join(pct[:-1]) + ' and ' + pct[-1])
has95 = 0.95 in loads
t = t.replace('TOPLOAD', '95' if has95 else '100')
t = t.replace('NINETY', ' The hover also gives what the 90 and 95 percent runs delivered.' if has95 else '')
t = t.replace('SAFER', 'The 90 or 95 percent figure is the safer one to quote there.' if has95 else 'A rate a little under the bar is the safer one to quote there.')
t = t.replace('SWEEPDATES', sys.argv[2] if len(sys.argv) > 2 else 'SWEEPDATES')
open(P + 'out/relic_bench_charts.html', 'w').write(t)
print('rows', t.count('  {"name"'))
subprocess.run(['python3', os.path.join(S, 'make_pages.py')], check=True)
