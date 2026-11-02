import sys, heapq

def parse(path):
    n = 0; cls = []; cur = []
    with open(path) as f:
        for line in f:
            if not line or line[0] in 'c%': 
                if line[:1] == '%': break
                continue
            if line[0] == 'p':
                n = int(line.split()[2]); continue
            for t in line.split():
                x = int(t)
                if x == 0:
                    cls.append(cur); cur = []
                else:
                    cur.append(x)
    if cur: cls.append(cur)
    for c in cls:
        for x in c:
            if abs(x) > n: n = abs(x)
    return n, cls

def luby(i):
    k = 1
    while (1 << k) - 1 < i + 1: k += 1
    while True:
        if (1 << k) - 1 == i + 1: return 1 << (k - 1)
        i -= (1 << (k - 1)) - 1
        k = 1
        while (1 << k) - 1 < i + 1: k += 1

def solve(n, clauses):
    val = [0] * (2 * n + 2)
    level = [0] * (n + 1)
    reason = [None] * (n + 1)
    phase = [1] * (n + 1)  # 1 => assign negative literal
    act = [0.0] * (n + 1)
    trail = []; lims = []
    watches = [[] for _ in range(2 * n + 2)]
    lbd = {}
    learnts = []
    state = {'qhead': 0}

    def enq(l, r):
        val[l] = 1; val[l ^ 1] = -1
        v = l >> 1
        level[v] = len(lims); reason[v] = r
        trail.append(l)

    for c in clauses:
        s = set(); taut = False
        for x in c:
            l = 2 * x if x > 0 else -2 * x + 1
            if l ^ 1 in s: taut = True; break
            s.add(l)
        if taut: continue
        c = list(s)
        if not c: return None
        if len(c) == 1:
            if val[c[0]] == -1: return None
            if val[c[0]] == 0: enq(c[0], None)
        else:
            watches[c[0]].append(c); watches[c[1]].append(c)
    # initial activity: occurrence counts
    for c in clauses:
        for x in c: act[abs(x)] += 1e-3
    heap = [(-act[v], v) for v in range(1, n + 1)]
    heapq.heapify(heap)
    hpush = heapq.heappush; hpop = heapq.heappop

    def propagate():
        qh = state['qhead']
        while qh < len(trail):
            p = trail[qh]; qh += 1
            fl = p ^ 1
            ws = watches[fl]
            i = j = 0; m = len(ws)
            while i < m:
                c = ws[i]; i += 1
                if c[0] == fl:
                    c[0] = c[1]; c[1] = fl
                first = c[0]
                if val[first] == 1:
                    ws[j] = c; j += 1; continue
                for k in range(2, len(c)):
                    lk = c[k]
                    if val[lk] != -1:
                        c[1] = lk; c[k] = fl; watches[lk].append(c); break
                else:
                    ws[j] = c; j += 1
                    if val[first] == -1:
                        while i < m:
                            ws[j] = ws[i]; j += 1; i += 1
                        del ws[j:]
                        state['qhead'] = len(trail)
                        return c
                    enq(first, c)
            del ws[j:]
        state['qhead'] = qh
        return None

    def backtrack(lv):
        if len(lims) <= lv: return
        t = lims[lv]
        for idx in range(len(trail) - 1, t - 1, -1):
            l = trail[idx]; v = l >> 1
            phase[v] = l & 1
            val[l] = 0; val[l ^ 1] = 0
            hpush(heap, (-act[v], v))
        del trail[t:]; del lims[lv:]
        state['qhead'] = t

    inc = 1.0
    seen = [False] * (n + 1)
    conflicts = 0
    restart_i = 0
    next_restart = 64 * luby(0)
    since = 0
    max_learnts = max(2000, len(clauses) // 2)

    if propagate() is not None: return None

    while True:
        confl = propagate()
        if confl is not None:
            conflicts += 1; since += 1
            if not lims: return None
            cur = len(lims)
            learnt = [0]; cnt = 0; p = -1; idx = len(trail) - 1
            bumped = []
            c = confl
            while True:
                if id(c) in lbd and False: pass
                for q in c:
                    if q == p: continue
                    v = q >> 1
                    if not seen[v] and level[v] > 0:
                        seen[v] = True; bumped.append(v)
                        if level[v] >= cur: cnt += 1
                        else: learnt.append(q)
                while not seen[trail[idx] >> 1]: idx -= 1
                p = trail[idx]; idx -= 1
                cnt -= 1
                if cnt == 0: break
                c = reason[p >> 1]
            learnt[0] = p ^ 1
            # minimize
            if len(learnt) > 2:
                out = [learnt[0]]
                for q in learnt[1:]:
                    r = reason[q >> 1]
                    if r is None: out.append(q); continue
                    for x in r:
                        if x != (q ^ 1) and not seen[x >> 1] and level[x >> 1] > 0:
                            out.append(q); break
                learnt = out
            # bump
            for v in bumped:
                act[v] += inc
                if act[v] > 1e100:
                    for u in range(1, n + 1): act[u] *= 1e-100
                    inc *= 1e-100
                    heap[:] = [(-act[u], u) for u in range(1, n + 1) if val[2 * u] == 0]
                    heapq.heapify(heap)
                    break
            for v in bumped:
                seen[v] = False
                if val[2 * v] == 0: hpush(heap, (-act[v], v))
            inc /= 0.95
            if len(learnt) == 1:
                bt = 0
            else:
                mi = 1
                for k in range(2, len(learnt)):
                    if level[learnt[k] >> 1] > level[learnt[mi] >> 1]: mi = k
                learnt[1], learnt[mi] = learnt[mi], learnt[1]
                bt = level[learnt[1] >> 1]
            lv_set = {level[q >> 1] for q in learnt}
            backtrack(bt)
            if len(learnt) == 1:
                enq(learnt[0], None)
            else:
                watches[learnt[0]].append(learnt); watches[learnt[1]].append(learnt)
                lbd[id(learnt)] = len(lv_set)
                learnts.append(learnt)
                enq(learnt[0], learnt)
            continue
        # restart
        if since >= next_restart:
            since = 0; restart_i += 1
            next_restart = 64 * luby(restart_i)
            backtrack(0)
            if len(learnts) > max_learnts:
                locked = {id(reason[l >> 1]) for l in trail if reason[l >> 1] is not None}
                cand = [c for c in learnts if lbd[id(c)] > 2 and id(c) not in locked]
                cand.sort(key=lambda c: (-lbd[id(c)], -len(c)))
                dead = {id(c) for c in cand[:len(cand) // 2]}
                for l in range(2, 2 * n + 2):
                    ws = watches[l]
                    if ws: watches[l] = [c for c in ws if id(c) not in dead]
                learnts = [c for c in learnts if id(c) not in dead]
                for d in dead: lbd.pop(d, None)
                max_learnts = int(max_learnts * 1.1)
            continue
        # decide
        v = 0
        while heap:
            _, u = hpop(heap)
            if val[2 * u] == 0: v = u; break
        if not v: return [1 if val[2 * u] == 1 else 0 for u in range(1, n + 1)]
        lims.append(len(trail))
        enq(2 * v + phase[v], None)

def main():
    n, cls = parse(sys.argv[1])
    r = solve(n, cls)
    if r is None:
        print("s UNSATISFIABLE"); sys.exit(20)
    print("s SATISFIABLE")
    lits = [str(i + 1 if r[i] else -(i + 1)) for i in range(n)]
    for k in range(0, len(lits), 20):
        print("v " + " ".join(lits[k:k + 20]))
    print("v 0")
    sys.exit(10)

if __name__ == '__main__':
    sys.setrecursionlimit(10000)
    main()
