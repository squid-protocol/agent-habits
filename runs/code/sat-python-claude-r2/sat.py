import sys, heapq

def parse(path):
    nv = 0; clauses = []; cur = []
    with open(path) as f:
        for line in f:
            if not line or line[0] in 'c%':
                if line[:1] == '%': break
                continue
            if line[0] == 'p':
                nv = int(line.split()[2]); continue
            for t in line.split():
                x = int(t)
                if x == 0:
                    clauses.append(cur); cur = []
                else:
                    cur.append(x)
    if cur: clauses.append(cur)
    for c in clauses:
        for x in c:
            if abs(x) > nv: nv = abs(x)
    return nv, clauses

def luby(i):
    k = 1
    while (1 << k) - 1 < i: k += 1
    while True:
        if i == (1 << k) - 1: return 1 << (k - 1)
        i -= (1 << (k - 1)) - 1
        k = 1
        while (1 << k) - 1 < i: k += 1

def solve(nv, raw):
    N = nv + 1
    val = [0] * (2 * N)          # per literal: 1 true, -1 false
    level = [0] * N
    reason = [None] * N
    phase = [1] * N              # saved phase: literal parity (1 => negative)
    act = [0.0] * N
    watches = [[] for _ in range(2 * N)]
    trail = []; lim = []
    units = []
    clauses = []
    for c in raw:
        s = set(); taut = False
        for x in c:
            l = 2 * x if x > 0 else -2 * x + 1
            if l ^ 1 in s: taut = True; break
            s.add(l)
        if taut: continue
        if not s: return None
        if len(s) == 1: units.append(next(iter(s))); continue
        c = list(s)
        clauses.append(c)
        watches[c[0]].append(c); watches[c[1]].append(c)
        for l in c: act[l >> 1] += 1.0
    for v in range(1, N): act[v] *= 1e-3
    heap = [(-act[v], v) for v in range(1, N)]
    heapq.heapify(heap)
    qh = 0
    for u in units:
        if val[u] == -1: return None
        if val[u] == 0:
            val[u] = 1; val[u ^ 1] = -1; level[u >> 1] = 0; trail.append(u)
    inc = 1.0
    learnts = []
    seen = [False] * N
    conflicts = 0; restart_n = 1
    next_restart = 100 * luby(1)
    next_reduce = 4000
    hpush = heapq.heappush; hpop = heapq.heappop

    while True:
        # propagate
        confl = None
        while qh < len(trail):
            p = trail[qh]; qh += 1
            fl = p ^ 1
            ws = watches[fl]
            i = j = 0; n = len(ws)
            while i < n:
                c = ws[i]; i += 1
                if c[0] == fl:
                    c[0] = c[1]; c[1] = fl
                f = c[0]
                if val[f] == 1:
                    ws[j] = c; j += 1; continue
                for k in range(2, len(c)):
                    q = c[k]
                    if val[q] != -1:
                        c[1] = q; c[k] = fl; watches[q].append(c); break
                else:
                    ws[j] = c; j += 1
                    if val[f] == -1:
                        while i < n:
                            ws[j] = ws[i]; j += 1; i += 1
                        confl = c
                    else:
                        val[f] = 1; val[f ^ 1] = -1
                        v = f >> 1
                        level[v] = len(lim); reason[v] = c; trail.append(f)
            del ws[j:]
            if confl is not None: break
        if confl is None:
            if len(trail) == nv - 0 or False:
                pass
            # decide
            lit = 0
            while heap:
                a, v = hpop(heap)
                if val[2 * v] == 0 and -a == act[v]:
                    lit = 2 * v + phase[v]; break
            if lit == 0:
                # maybe stale entries only; scan
                for v in range(1, N):
                    if val[2 * v] == 0:
                        lit = 2 * v + phase[v]; break
                if lit == 0:
                    return [(v if val[2 * v] == 1 else -v) for v in range(1, N)]
            lim.append(len(trail))
            val[lit] = 1; val[lit ^ 1] = -1
            level[lit >> 1] = len(lim); reason[lit >> 1] = None
            trail.append(lit)
            continue
        # conflict
        conflicts += 1
        dl = len(lim)
        if dl == 0: return None
        learnt = [0]
        pathc = 0; p = -1; idx = len(trail) - 1
        c = confl
        toclear = []
        while True:
            for q in c:
                if q == p: continue
                v = q >> 1
                if not seen[v] and level[v] > 0:
                    seen[v] = True; toclear.append(v)
                    act[v] += inc
                    if act[v] > 1e100:
                        for u in range(1, N): act[u] *= 1e-100
                        inc *= 1e-100
                        heap = [(-act[u], u) for u in range(1, N) if val[2*u] == 0]
                        heapq.heapify(heap)
                    if level[v] >= dl: pathc += 1
                    else: learnt.append(q)
            while not seen[trail[idx] >> 1]: idx -= 1
            p = trail[idx]; idx -= 1
            v = p >> 1
            seen[v] = False
            pathc -= 1
            if pathc == 0: break
            c = reason[v]
        learnt[0] = p ^ 1
        # minimize (local)
        out = [learnt[0]]
        for q in learnt[1:]:
            r = reason[q >> 1]
            if r is None: out.append(q); continue
            for x in r:
                if x != (q ^ 1) and not seen[x >> 1] and level[x >> 1] > 0:
                    out.append(q); break
        learnt = out
        for v in toclear: seen[v] = False
        # lbd + backjump level
        if len(learnt) == 1:
            bl = 0
        else:
            m = 1
            for k in range(2, len(learnt)):
                if level[learnt[k] >> 1] > level[learnt[m] >> 1]: m = k
            learnt[1], learnt[m] = learnt[m], learnt[1]
            bl = level[learnt[1] >> 1]
        lbd = len({level[q >> 1] for q in learnt})
        inc /= 0.95
        # backtrack
        if len(lim) > bl:
            t = lim[bl]
            for k in range(len(trail) - 1, t - 1, -1):
                l = trail[k]; v = l >> 1
                val[l] = 0; val[l ^ 1] = 0
                phase[v] = l & 1
                hpush(heap, (-act[v], v))
            del trail[t:]; del lim[bl:]
            qh = t
        if len(learnt) == 1:
            l = learnt[0]
            val[l] = 1; val[l ^ 1] = -1; level[l >> 1] = 0; reason[l >> 1] = None
            trail.append(l)
        else:
            watches[learnt[0]].append(learnt); watches[learnt[1]].append(learnt)
            l = learnt[0]
            val[l] = 1; val[l ^ 1] = -1; level[l >> 1] = len(lim)
            reason[l >> 1] = learnt; trail.append(l)
            learnts.append((lbd, learnt))
        # restart
        if conflicts >= next_restart:
            restart_n += 1
            next_restart = conflicts + 100 * luby(restart_n)
            if lim:
                t = lim[0]
                for k in range(len(trail) - 1, t - 1, -1):
                    l = trail[k]; v = l >> 1
                    val[l] = 0; val[l ^ 1] = 0
                    phase[v] = l & 1
                del trail[t:]; del lim[:]
                qh = t
            heap = [(-act[u], u) for u in range(1, N) if val[2*u] == 0]
            heapq.heapify(heap)
            if conflicts >= next_reduce:
                next_reduce = conflicts + 4000 + 300 * (conflicts // 4000)
                learnts.sort(key=lambda x: (x[0], len(x[1])))
                keep = learnts[:len(learnts) // 2]
                dead = set()
                for lb, cl in learnts[len(learnts) // 2:]:
                    if lb <= 2 or reason[cl[0] >> 1] is cl:
                        keep.append((lb, cl))
                    else:
                        dead.add(id(cl))
                learnts = keep
                if dead:
                    for l in range(2, 2 * N):
                        w = watches[l]
                        if w: watches[l] = [x for x in w if id(x) not in dead]

def main(argv):
    nv, cl = parse(argv[1])
    sys.setrecursionlimit(10000)
    r = solve(nv, cl)
    if r is None:
        print("s UNSATISFIABLE"); sys.stdout.flush(); sys.exit(20)
    print("s SATISFIABLE")
    line = "v"
    for x in r:
        s = " %d" % x
        if len(line) + len(s) > 78:
            print(line); line = "v"
        line += s
    print(line + " 0")
    sys.stdout.flush(); sys.exit(10)
