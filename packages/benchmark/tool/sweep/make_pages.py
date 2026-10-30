# Writes the sub report from relic_bench_charts.html:
#   relic_bench_dart.html    Relic (io and native) and shelf only
import os, re, sys
S = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'report') + '/'
src=open(S+'out/relic_bench_charts.html').read()

def fam_of(line):
    m=re.search(r'"fam": "(\w+)"', line); return m.group(1) if m else None
def name_of(line):
    m=re.search(r'"name": "([^"]+)"', line); return m.group(1) if m else None

def build(keep_row, drop_legend, subs, out):
    lines=[]
    for l in src.split('\n'):
        if l.startswith('  {"name"') and not keep_row(l): continue
        if any(d in l for d in drop_legend): continue
        lines.append(l)
    t='\n'.join(lines)
    for a,b in subs:
        assert a in t, a[:60]
        t=t.replace(a,b)
    open(S+'out/'+out,'w').write(t)
    print(out, 'rows', t.count('  {"name"'))

# Relic and shelf.
build(lambda l: fam_of(l) in ('zio','ioadapter') or name_of(l).startswith('shelf'),
      [],
      [('<span><i style="background:var(--other)"></i>hyper, dusty, deno, shelf</span>', '<span><i style="background:var(--other)"></i>shelf on dart:io</span>'),
       (' hyper runs 1, 2 or 4 tokio workers, dusty 1, 2 or 4 executors, the Dart servers 1, 2 or 4 isolates, so a four-way server plus oha stays within the 8 cores.', ' The servers run 1, 2 or 4 isolates, so a four-way server plus oha stays within the 8 cores.'),
       ('<li><b>Threads.</b> hyper runs 1, 2 or 4 tokio workers (a current-thread runtime for 1), dusty 1, 2 or 4 zio executors, the Dart servers 1, 2 or 4 isolates each with its own listener on a shared port.</li>', '<li><b>Isolates.</b> The servers run 1, 2 or 4 isolates, each with its own listener on a shared port.</li>'),
       (' hyper uses rustls, dusty tls.zig, deno its built-in, the Dart servers SecureSocket (dart:io) or tls.zig (relic_native).', ' The dart:io servers use SecureSocket, relic_native tls.zig.'),
       (' hyper 1.12.0 on tokio 1.53.2 with rustls 0.23.45, rustc 1.99.1. dusty on Zig 0.17.0 and the same zio commit relic_native pins. Deno 2.9.6. shelf on dart:io HttpServer.', ' relic_native on Zig 0.17.0. shelf on dart:io HttpServer.'),
       ('Above about 140k requests per second the machine, not the server, sets the rate:', 'Above about 140k requests per second the machine, not the server, sets the rate (bare Rust and Zig servers hit the same ceiling):'),
       ('<h1>Relic Load Sweep</h1>', '<h1>Relic Load Sweep: Relic and shelf</h1>')],
      'relic_bench_dart.html')
