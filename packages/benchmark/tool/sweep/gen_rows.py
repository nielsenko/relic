import json, sys, statistics
# Emits the rows array for relic_bench_charts.html from an http_load json.
data = []
for f in sys.argv[1:]: data += json.load(open(f))
rename = {"native":"relic-native","native-handler":"relic-native-handler","native2":"relic-native2","native2-handler":"relic-native2-handler","native4":"relic-native4","native4-handler":"relic-native4-handler",
 "io":"relic-io","io2":"relic-io2","io4":"relic-io4","io-handler":"relic-io-handler"}
what = {
 "hyper2":("bare Rust, 2 threads","native","other",2),
 "dusty2":("bare Zig on zio, 2 executors","native","other",2),
 "shelf2":("shelf on dart:io, 2 isolates","JIT","other",2),
 "relic-native2":("Relic on zio, 2 isolates","JIT","zio",2),
 "relic-native2-handler":("Relic on zio, 2 isolates, no router","JIT","zio",2),
 "hyper":("bare Rust, 1 thread","native","other",1),
 "hyper4":("bare Rust, 4 threads","native","other",4),
 "deno":("bare Deno.serve","native","other",1),
 "dusty":("bare Zig on zio, 1 executor","native","other",1),
 "dusty4":("bare Zig on zio, 4 executors","native","other",4),
 "shelf":("shelf on dart:io","JIT","other",1),
 "shelf4":("shelf on dart:io, 4 isolates","JIT","other",4),
 "relic-io":("Relic IOAdapter on dart:io","JIT","ioadapter",1),
 "relic-io2":("Relic IOAdapter on dart:io, 2 isolates","JIT","ioadapter",2),
 "relic-io4":("Relic IOAdapter on dart:io, 4 isolates","JIT","ioadapter",4),
 "relic-io-handler":("Relic IOAdapter on dart:io, no router","JIT","ioadapter",1),
 "relic-native":("Relic on zio, 1 isolate","JIT","zio",1),
 "relic-native-handler":("Relic on zio, 1 isolate, no router","JIT","zio",1),
 "relic-native4":("Relic on zio, 4 isolates","JIT","zio",4),
 "relic-native4-handler":("Relic on zio, 4 isolates, no router","JIT","zio",4),
}
rows = {}
loads = {0.5: 0, 0.75: 1, 0.9: 2, 0.95: 3, 1.0: 4}
for m in data:
    t = m["target"]
    tls = t.endswith("-tls")
    if tls: t = t[:-4]
    aot = t.endswith("-aot")
    base = t[:-4] if aot else t
    base = rename.get(base, base)
    t = base + ("-aot" if aot else "") + ("-tls" if tls else "")
    w, mode, fam, iso = what[base]
    if aot: mode = "AOT"
    r = rows.setdefault(t, {"name":t,"what":w,"mode":mode,"fam":fam,"iso":iso,"tls":tls})
    i = loads.get(m["load"])
    if i is None: continue
    for col, key in (("p50Ms", "P50"), ("p99Ms", "P99"), ("p999Ms", "P999")):
        r.setdefault(m["workload"] + key, [None] * 5)[i] = round(m[col], 2)
for m in data:
    if m["load"] not in (0.9, 0.95, 1.0): continue
    t = m["target"]
    tls = t.endswith("-tls")
    if tls: t = t[:-4]
    aot = t.endswith("-aot")
    base = t[:-4] if aot else t
    base = rename.get(base, base)
    t = base + ("-aot" if aot else "") + ("-tls" if tls else "")
    w, mode, fam, iso = what[base]
    if aot: mode = "AOT"
    r = rows.setdefault(t, {"name":t,"what":w,"mode":mode,"fam":fam,"iso":iso,"tls":tls})
    w = m["workload"]
    if m["load"] != 1.0:
        r[w + "Open" + str(int(m["load"] * 100))] = round(m["rps"]/1000, 1)
        continue
    r[w] = round(m["offeredRps"]/1000, 1)
    if "cores" in m: r[w+"Cores"] = round(m["cores"], 2)
    r[w+"Open"] = round(m["rps"]/1000, 1)
    runs = m.get("saturationRuns")
    if runs:
        r[w+"Runs"] = len(runs)
        r[w+"Sd"] = round(statistics.pstdev(runs)/1000, 1)
out = sorted(rows.values(), key=lambda r: -r["plaintext"])
print("const rows = [")
for r in out:
    print('  %s,' % json.dumps(r))
print("];")
