"""The tables of a kernel.sh run, from its output directory.

    python3 tool/sweep/kernel_rows.py kernel-out > kernel-out/kernel.md

User and system time per request come from the /proc ticks around the
time window. System calls per request come from perf's per-thread
tracepoint counts and from strace's summary, each over a window of its
own, divided by the requests oha completed in that window. strace stops
the server at every call, so its windows run slower and batch less.
"""

import json
import os
import re
import sys
from collections import Counter, defaultdict

out = sys.argv[1]


def read(name):
    path = os.path.join(out, name)
    return open(path).read() if os.path.exists(path) else None


def requests(name):
    text = read(name)
    if not text:
        return None, None
    data = json.loads(text)
    return sum(data['statusCodeDistribution'].values()), data['summary']['requestsPerSec']


def perf_counts(name):
    """All calls, calls per named syscall and all calls per thread name.

    From perf stat --per-thread -x, over raw_syscalls:sys_enter, which
    counts every call, and syscalls:sys_enter_<name> for the named ones.
    """
    text = read(name)
    if not text:
        return None
    total, calls, threads = 0, Counter(), Counter()
    for line in text.splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split(',')
        at = next((i for i, f in enumerate(fields) if 'sys_enter' in f), None)
        if at is None or at < 2 or not fields[at - 2].strip().isdigit():
            continue
        count = int(fields[at - 2])
        if fields[at] == 'raw_syscalls:sys_enter':
            total += count
            if count:
                threads[re.sub(r'-\d+$', '', ','.join(fields[:at - 2]).strip())] += count
        elif count:
            calls[fields[at][len('syscalls:sys_enter_'):]] += count
    return total, calls, threads


def strace_counts(name):
    """Calls per syscall, from strace -c."""
    text = read(name)
    if not text:
        return None
    calls = Counter()
    for line in text.splitlines():
        tokens = line.split()
        if len(tokens) < 5 or tokens[-1] == 'total' or not re.match(r'^[\d.]+$', tokens[0]):
            continue
        calls[tokens[-1]] += int(tokens[3])
    return calls


def counter_counts(name):
    """Each event's count and each thread's instructions, from perf stat --per-thread -x,."""
    text = read(name)
    if not text:
        return None
    events, threads = Counter(), Counter()
    for line in text.splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split(',')
        at = next((i for i, f in enumerate(fields) if f.startswith(('instructions', 'cycles'))), None)
        if at is None or at < 2 or not fields[at - 2].strip().isdigit():
            continue
        count = int(fields[at - 2])
        events[fields[at]] += count
        if fields[at].startswith('instructions'):
            threads[re.sub(r'-\d+$', '', ','.join(fields[:at - 2]).strip())] += count
    return events, threads


def top(counter, n, per, limit=8):
    return ', '.join(f'{k} {v / n:.2f}' for k, v in counter.most_common(limit)) if per else ''


machine = read('machine.txt') or ''
hz = int(re.search(r'clock ticks: (\d+)', machine).group(1)) if 'clock ticks' in machine else 100

print('# Kernel time per request\n')
print('```')
print(machine.strip())
print('```\n')
print('## User and system time\n')
print('Microseconds of server CPU per request, from /proc over the time window.\n')
print('| server | workload | requests/s | user us | system us | total us | system share |')
print('|---|---|---:|---:|---:|---:|---:|')
order = []
for line in (read('ticks.txt') or '').splitlines():
    name, route, _, u0, s0, u1, s1 = line.split()
    order.append((name, route))
    n, rps = requests(f'{name}.{route}.time.json')
    if not n:
        print(f'| {name} | {route} | no requests | | | | |')
        continue
    user = (int(u1) - int(u0)) / hz / n * 1e6
    system = (int(s1) - int(s0)) / hz / n * 1e6
    total = user + system
    share = system / total * 100 if total else 0
    print(f'| {name} | {route} | {rps:,.0f} | {user:.2f} | {system:.2f} | {total:.2f} | {share:.0f}% |')

if any(name.endswith('.counters.csv') for name in os.listdir(out)):
    print('\n## Instructions and cycles\n')
    print('Thousands per request, from perf stat over the PMU, user and kernel mode.\n')
    print('| server | workload | requests/s | instructions user | instructions kernel | '
          'kernel share | cycles user | cycles kernel | threads, k instructions |')
    print('|---|---|---:|---:|---:|---:|---:|---:|---|')
    for name, route in order:
        n, rps = requests(f'{name}.{route}.counters.json')
        counts = counter_counts(f'{name}.{route}.counters.csv')
        if not n or counts is None:
            print(f'| {name} | {route} | not measured | | | | | | |')
            continue
        events, threads = counts
        iu, ik = events['instructions:u'] / n / 1e3, events['instructions:k'] / n / 1e3
        cu, ck = events['cycles:u'] / n / 1e3, events['cycles:k'] / n / 1e3
        share = ik / (iu + ik) * 100 if iu + ik else 0
        threads_k = ', '.join(f'{k} {v / n / 1e3:.1f}' for k, v in threads.most_common(4))
        print(f'| {name} | {route} | {rps:,.0f} | {iu:.1f} | {ik:.1f} | {share:.0f}% | '
              f'{cu:.1f} | {ck:.1f} | {threads_k} |')

for tool, reader, note in (
    ('perf', perf_counts, 'perf stat --per-thread over the syscall tracepoints, no slowdown'),
    ('strace', strace_counts, 'strace -f -c, which stops the server at every call'),
):
    print(f'\n## System calls per request, {tool}\n')
    print(f'{note}.\n')
    print('| server | workload | requests/s | calls per request | largest, per request | threads, calls per request |')
    print('|---|---|---:|---:|---|---|')
    for name, route in order:
        n, rps = requests(f'{name}.{route}.{tool}.json')
        counts = reader(f'{name}.{route}.{tool}.{"csv" if tool == "perf" else "txt"}')
        if not n or counts is None:
            print(f'| {name} | {route} | not measured | | | |')
            continue
        if tool == 'perf':
            total, calls, threads = counts
        else:
            total, calls, threads = sum(counts.values()), counts, None
        print(f'| {name} | {route} | {rps:,.0f} | {total / n:.2f} | {top(calls, n, True)} | '
              f'{top(threads, n, threads is not None, 4)} |')
