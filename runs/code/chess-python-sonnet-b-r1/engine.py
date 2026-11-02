#!/usr/bin/env python3
import sys, time, random, threading

VAL = [0, 100, 320, 330, 500, 900, 0]
MATE = 30000
PST = {
1: [0,0,0,0,0,0,0,0, 50,50,50,50,50,50,50,50, 10,10,20,30,30,20,10,10, 5,5,10,25,25,10,5,5,
    0,0,0,20,20,0,0,0, 5,-5,-10,0,0,-10,-5,5, 5,10,10,-20,-20,10,10,5, 0,0,0,0,0,0,0,0],
2: [-50,-40,-30,-30,-30,-30,-40,-50, -40,-20,0,0,0,0,-20,-40, -30,0,10,15,15,10,0,-30, -30,5,15,20,20,15,5,-30,
    -30,0,15,20,20,15,0,-30, -30,5,10,15,15,10,5,-30, -40,-20,0,5,5,0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50],
3: [-20,-10,-10,-10,-10,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,10,10,5,0,-10, -10,5,5,10,10,5,5,-10,
    -10,0,10,10,10,10,0,-10, -10,10,10,10,10,10,10,-10, -10,5,0,0,0,0,5,-10, -20,-10,-10,-10,-10,-10,-10,-20],
4: [0,0,0,0,0,0,0,0, 5,10,10,10,10,10,10,5] + [-5,0,0,0,0,0,0,-5]*5 + [0,0,0,5,5,0,0,0],
5: [-20,-10,-10,-5,-5,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,5,5,5,0,-10, -5,0,5,5,5,5,0,-5,
    0,0,5,5,5,5,0,-5, -10,5,5,5,5,5,0,-10, -10,0,5,0,0,0,0,-10, -20,-10,-10,-5,-5,-10,-10,-20],
6: [-30,-40,-40,-50,-50,-40,-40,-30]*4 + [-20,-30,-30,-40,-40,-30,-30,-20, -10,-20,-20,-20,-20,-20,-20,-10,
    20,20,0,0,0,0,20,20, 20,30,10,0,0,10,30,20],
}
SQS = [r * 16 + f for r in range(8) for f in range(8)]
PV = [[0] * 128 for _ in range(15)]
KMGW = [0] * 128
KMGB = [0] * 128
CD = [0] * 128
for sq in SQS:
    r, f = sq >> 4, sq & 7
    CD[sq] = max(3 - r, r - 4) + max(3 - f, f - 4)
    for t in range(1, 6):
        PV[t][sq] = VAL[t] + PST[t][(7 - r) * 8 + f]
        PV[t + 8][sq] = -(VAL[t] + PST[t][r * 8 + f])
    KMGW[sq] = PST[6][(7 - r) * 8 + f]
    KMGB[sq] = -PST[6][r * 8 + f]

rnd = random.Random(12345)
Z = [[rnd.getrandbits(64) for _ in range(128)] for _ in range(15)]
ZS = rnd.getrandbits(64)
ZC = [rnd.getrandbits(64) for _ in range(16)]
ZE = [rnd.getrandbits(64) for _ in range(128)]
ZE[0] = 0
CMASK = [15] * 128
for s, m in ((0, 13), (7, 14), (4, 12), (112, 7), (119, 11), (116, 3)):
    CMASK[s] = m
KN = (33, 31, 18, 14, -33, -31, -18, -14)
KG = (1, -1, 16, -16, 15, -15, 17, -17)
BD = (15, -15, 17, -17)
RD = (1, -1, 16, -16)
PCH = ".PNBRQK"


def sqname(s):
    return "abcdefgh"[s & 7] + str((s >> 4) + 1)


def mstr(m):
    s = sqname(m & 127) + sqname((m >> 7) & 127)
    pr = (m >> 14) & 7
    return s + ("  nbrq"[pr] if pr else "")


class Board:
    def __init__(self):
        self.set_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

    def set_fen(self, fen):
        p = fen.split()
        b = [0] * 128
        r, f = 7, 0
        for ch in p[0]:
            if ch == '/':
                r -= 1; f = 0
            elif ch.isdigit():
                f += int(ch)
            else:
                t = PCH.index(ch.upper()) if ch.upper() in PCH else "NBRQK".index(ch.upper()) + 2
                b[r * 16 + f] = t + (8 if ch.islower() else 0)
                f += 1
        self.b = b
        self.side = 0 if len(p) < 2 or p[1] == 'w' else 1
        c = 0
        if len(p) > 2:
            for ch in p[2]:
                c |= {'K': 1, 'Q': 2, 'k': 4, 'q': 8}.get(ch, 0)
        self.castle = c
        self.ep = 0
        if len(p) > 3 and p[3] != '-':
            self.ep = (int(p[3][1]) - 1) * 16 + "abcdefgh".index(p[3][0])
        self.half = int(p[4]) if len(p) > 4 else 0
        self.ksq = [0, 0]
        sc = 0
        npm = 0
        h = 0
        for sq in SQS:
            x = b[sq]
            if x:
                sc += PV[x][sq]
                h ^= Z[x][sq]
                if x & 7 == 6:
                    self.ksq[x >> 3] = sq
                elif x & 7 != 1:
                    npm += VAL[x & 7]
        self.score = sc
        self.npm = npm
        h ^= ZC[c] ^ ZE[self.ep]
        if self.side:
            h ^= ZS
        self.hash = h
        self.stack = []
        self.hist = [h]

    def attacked(self, sq, c):
        b = self.b
        if c == 0:
            s = sq - 15
            if not s & 0x88 and b[s] == 1: return True
            s = sq - 17
            if not s & 0x88 and b[s] == 1: return True
        else:
            s = sq + 15
            if not s & 0x88 and b[s] == 9: return True
            s = sq + 17
            if not s & 0x88 and b[s] == 9: return True
        o = c << 3
        n = 2 | o
        for d in KN:
            s = sq + d
            if not s & 0x88 and b[s] == n: return True
        k = 6 | o
        for d in KG:
            s = sq + d
            if not s & 0x88 and b[s] == k: return True
        bi = 3 | o; ro = 4 | o; q = 5 | o
        for d in BD:
            s = sq + d
            while not s & 0x88:
                x = b[s]
                if x:
                    if x == bi or x == q: return True
                    break
                s += d
        for d in RD:
            s = sq + d
            while not s & 0x88:
                x = b[s]
                if x:
                    if x == ro or x == q: return True
                    break
                s += d
        return False

    def gen(self, caps=False):
        b = self.b
        side = self.side
        moves = []
        add = moves.append
        for frm in SQS:
            p = b[frm]
            if not p or (p >> 3) != side:
                continue
            t = p & 7
            if t == 1:
                if side == 0:
                    d = 16; start = 1; pr7 = 6
                else:
                    d = -16; start = 6; pr7 = 1
                r = frm >> 4
                to = frm + d
                if not b[to]:
                    if r == pr7:
                        add(frm | to << 7 | 5 << 14)
                        if not caps:
                            add(frm | to << 7 | 4 << 14); add(frm | to << 7 | 3 << 14); add(frm | to << 7 | 2 << 14)
                    elif not caps:
                        add(frm | to << 7)
                        if r == start and not b[to + d]:
                            add(frm | (to + d) << 7 | 4 << 17)
                for to in (frm + d - 1, frm + d + 1):
                    if to & 0x88: continue
                    x = b[to]
                    if x:
                        if (x >> 3) != side:
                            if r == pr7:
                                add(frm | to << 7 | 5 << 14)
                                if not caps:
                                    add(frm | to << 7 | 4 << 14); add(frm | to << 7 | 3 << 14); add(frm | to << 7 | 2 << 14)
                            else:
                                add(frm | to << 7)
                    elif to == self.ep:
                        add(frm | to << 7 | 1 << 17)
            elif t == 2 or t == 6:
                for d in (KN if t == 2 else KG):
                    to = frm + d
                    if to & 0x88: continue
                    x = b[to]
                    if x:
                        if (x >> 3) != side:
                            add(frm | to << 7)
                    elif not caps:
                        add(frm | to << 7)
            else:
                for d in (BD if t == 3 else RD if t == 4 else KG):
                    to = frm + d
                    while not to & 0x88:
                        x = b[to]
                        if x:
                            if (x >> 3) != side:
                                add(frm | to << 7)
                            break
                        if not caps:
                            add(frm | to << 7)
                        to += d
        if not caps and self.castle:
            c = self.castle
            if side == 0:
                if c & 3 and b[4] == 6:
                    if c & 1 and not b[5] and not b[6] and b[7] == 4 and not self.attacked(4, 1) and not self.attacked(5, 1):
                        add(4 | 6 << 7 | 2 << 17)
                    if c & 2 and not b[3] and not b[2] and not b[1] and b[0] == 4 and not self.attacked(4, 1) and not self.attacked(3, 1):
                        add(4 | 2 << 7 | 2 << 17)
            else:
                if c & 12 and b[116] == 14:
                    if c & 4 and not b[117] and not b[118] and b[119] == 12 and not self.attacked(116, 0) and not self.attacked(117, 0):
                        add(116 | 118 << 7 | 2 << 17)
                    if c & 8 and not b[115] and not b[114] and not b[113] and b[112] == 12 and not self.attacked(116, 0) and not self.attacked(115, 0):
                        add(116 | 114 << 7 | 2 << 17)
        return moves

    def make(self, m):
        b = self.b
        frm = m & 127; to = (m >> 7) & 127; pr = (m >> 14) & 7; fl = m >> 17
        p = b[frm]; cap = b[to]; side = self.side
        self.stack.append((cap, self.castle, self.ep, self.half, self.hash, self.score, self.npm))
        h = self.hash ^ ZS ^ ZC[self.castle] ^ ZE[self.ep]
        sc = self.score
        h ^= Z[p][frm]; sc -= PV[p][frm]
        if cap:
            h ^= Z[cap][to]; sc -= PV[cap][to]
            if cap & 7 != 1: self.npm -= VAL[cap & 7]
        b[frm] = 0
        if fl == 1:
            cs = to - 16 if side == 0 else to + 16
            cp = b[cs]; b[cs] = 0
            h ^= Z[cp][cs]; sc -= PV[cp][cs]
        elif fl == 2:
            if to > frm: rf, rt = frm + 3, frm + 1
            else: rf, rt = frm - 4, frm - 1
            rk = b[rf]; b[rf] = 0; b[rt] = rk
            h ^= Z[rk][rf] ^ Z[rk][rt]; sc += PV[rk][rt] - PV[rk][rf]
        if pr:
            np_ = pr | (side << 3)
            self.npm += VAL[pr]
        else:
            np_ = p
        b[to] = np_
        h ^= Z[np_][to]; sc += PV[np_][to]
        if p & 7 == 6: self.ksq[side] = to
        self.castle &= CMASK[frm] & CMASK[to]
        self.half = 0 if (p & 7 == 1 or cap or fl == 1) else self.half + 1
        self.ep = (frm + to) >> 1 if fl == 4 else 0
        self.side = side ^ 1
        self.hash = h ^ ZC[self.castle] ^ ZE[self.ep]
        self.score = sc
        self.hist.append(self.hash)

    def unmake(self, m):
        b = self.b
        frm = m & 127; to = (m >> 7) & 127; pr = (m >> 14) & 7; fl = m >> 17
        cap, self.castle, self.ep, self.half, self.hash, self.score, self.npm = self.stack.pop()
        self.hist.pop()
        self.side ^= 1
        side = self.side
        p = b[to]
        if pr: p = 1 | (side << 3)
        b[frm] = p
        b[to] = cap
        if fl == 1:
            b[to - 16 if side == 0 else to + 16] = 1 | ((side ^ 1) << 3)
        elif fl == 2:
            if to > frm: rf, rt = frm + 3, frm + 1
            else: rf, rt = frm - 4, frm - 1
            b[rf] = b[rt]; b[rt] = 0
        if p & 7 == 6: self.ksq[side] = frm

    def make_null(self):
        self.stack.append((0, self.castle, self.ep, self.half, self.hash, self.score, self.npm))
        self.hash ^= ZS ^ ZE[self.ep]
        self.ep = 0
        self.side ^= 1
        self.half += 1
        self.hist.append(self.hash)

    def unmake_null(self):
        _, self.castle, self.ep, self.half, self.hash, self.score, self.npm = self.stack.pop()
        self.hist.pop()
        self.side ^= 1

    def legal(self):
        res = []
        side = self.side
        for m in self.gen():
            self.make(m)
            if not self.attacked(self.ksq[side], side ^ 1):
                res.append(m)
            self.unmake(m)
        return res

    def perft(self, d):
        side = self.side
        n = 0
        for m in self.gen():
            self.make(m)
            if not self.attacked(self.ksq[side], side ^ 1):
                n += 1 if d == 1 else self.perft(d - 1)
            self.unmake(m)
        return n

    def evaluate(self):
        s = self.score
        wk, bk = self.ksq
        if self.npm > 2400:
            s += KMGW[wk] - KMGB[bk]
        else:
            s += 6 * (CD[bk] - CD[wk])
            dist = abs((wk >> 4) - (bk >> 4)) + abs((wk & 7) - (bk & 7))
            if s > 200:
                s += 10 * CD[bk] + 4 * (14 - dist)
            elif s < -200:
                s -= 10 * CD[wk] + 4 * (14 - dist)
        return (s if self.side == 0 else -s) + 8


class Searcher:
    def __init__(self, board):
        self.bd = board
        self.tt = {}
        self.killers = [[0, 0] for _ in range(128)]
        self.hist = {}
        self.stop = False
        self.deadline = None
        self.nodes = 0

    def order(self, moves, ttm, ply):
        b = self.bd.b
        k1, k2 = self.killers[ply]
        hist = self.hist
        sc = []
        for m in moves:
            if m == ttm:
                s = 10000000
            else:
                to = (m >> 7) & 127
                v = b[to]
                if v:
                    s = 1000000 + 10 * VAL[v & 7] - (b[m & 127] & 7)
                elif m >> 17 == 1:
                    s = 1000090
                elif (m >> 14) & 7:
                    s = 1000000 + VAL[(m >> 14) & 7]
                elif m == k1: s = 900000
                elif m == k2: s = 899999
                else: s = hist.get(m, 0)
            sc.append(s)
        idx = sorted(range(len(moves)), key=sc.__getitem__, reverse=True)
        return [moves[i] for i in idx]

    def qs(self, alpha, beta, ply):
        bd = self.bd
        self.nodes += 1
        if self.nodes & 2047 == 0 and self.deadline and time.time() > self.deadline:
            self.stop = True
        if self.stop: return 0
        stand = bd.evaluate()
        if stand >= beta: return stand
        if stand > alpha: alpha = stand
        if ply > 60: return stand
        side = bd.side
        b = bd.b
        for m in self.order(bd.gen(True), 0, 127):
            v = VAL[b[(m >> 7) & 127] & 7]
            if stand + v + 200 < alpha and not (m >> 14) & 7:
                continue
            bd.make(m)
            if bd.attacked(bd.ksq[side], side ^ 1):
                bd.unmake(m); continue
            s = -self.qs(-beta, -alpha, ply + 1)
            bd.unmake(m)
            if self.stop: return 0
            if s > stand:
                stand = s
                if s > alpha:
                    alpha = s
                    if s >= beta: break
        return stand

    def search(self, depth, alpha, beta, ply, nullok):
        bd = self.bd
        self.nodes += 1
        if self.nodes & 2047 == 0 and self.deadline and time.time() > self.deadline:
            self.stop = True
        if self.stop: return 0
        h = bd.hash
        hl = bd.hist
        if bd.half >= 100: return 0
        n = len(hl)
        for i in range(n - 3, max(n - bd.half - 2, -1), -2):
            if hl[i] == h: return 0
        side = bd.side
        incheck = bd.attacked(bd.ksq[side], side ^ 1)
        if incheck and ply < 40: depth += 1
        if depth <= 0:
            return self.qs(alpha, beta, ply)
        # mate distance pruning
        if alpha < -MATE + ply: alpha = max(alpha, -MATE + ply)
        if beta > MATE - ply - 1: beta = min(beta, MATE - ply - 1)
        if alpha >= beta: return alpha
        ttm = 0
        e = self.tt.get(h)
        if e:
            ed, ef, es, ettm = e
            ttm = ettm
            if ed >= depth and ply > 0:
                if es > MATE - 200: es -= ply
                elif es < -MATE + 200: es += ply
                if ef == 0: return es
                if ef == 1 and es >= beta: return es
                if ef == 2 and es <= alpha: return es
        if nullok and not incheck and depth >= 3 and bd.npm > 800 and beta < MATE - 200:
            bd.make_null()
            s = -self.search(depth - 3, -beta, -beta + 1, ply + 1, False)
            bd.unmake_null()
            if self.stop: return 0
            if s >= beta: return beta
        orig = alpha
        best = -MATE
        bestm = 0
        legalc = 0
        b = bd.b
        for m in self.order(bd.gen(), ttm, ply):
            bd.make(m)
            if bd.attacked(bd.ksq[side], side ^ 1):
                bd.unmake(m); continue
            legalc += 1
            quiet = not (m >> 14) & 7 and m >> 17 != 1 and not bd.stack[-1][0]
            if legalc == 1:
                s = -self.search(depth - 1, -beta, -alpha, ply + 1, True)
            else:
                r = 0
                if depth >= 3 and legalc > 4 and quiet and not incheck:
                    r = 1 if legalc < 10 else 2
                s = -self.search(depth - 1 - r, -alpha - 1, -alpha, ply + 1, True)
                if s > alpha and r:
                    s = -self.search(depth - 1, -alpha - 1, -alpha, ply + 1, True)
                if s > alpha and s < beta:
                    s = -self.search(depth - 1, -beta, -alpha, ply + 1, True)
            bd.unmake(m)
            if self.stop: return 0
            if s > best:
                best = s; bestm = m
                if s > alpha:
                    alpha = s
                    if s >= beta:
                        if quiet:
                            k = self.killers[ply]
                            if k[0] != m:
                                k[1] = k[0]; k[0] = m
                            self.hist[m] = self.hist.get(m, 0) + depth * depth
                        break
        if not legalc:
            return -MATE + ply if incheck else 0
        if len(self.tt) > 1500000: self.tt.clear()
        sv = best
        if sv > MATE - 200: sv += ply
        elif sv < -MATE + 200: sv -= ply
        flag = 1 if best >= beta else (0 if best > orig else 2)
        self.tt[h] = (depth, flag, sv, bestm)
        return best

    def go(self, maxdepth, movetime, out):
        bd = self.bd
        start = time.time()
        self.deadline = start + movetime if movetime else None
        self.stop = False
        self.nodes = 0
        self.killers = [[0, 0] for _ in range(128)]
        self.hist = {}
        moves = bd.legal()
        if not moves:
            out("bestmove 0000"); return
        best = moves[0]
        side = bd.side
        for depth in range(1, maxdepth + 1):
            alpha, beta = -MATE, MATE
            ordered = self.order(moves, best, 0)
            cur = 0; curs = -MATE
            for i, m in enumerate(ordered):
                bd.make(m)
                if i == 0:
                    s = -self.search(depth - 1, -beta, -alpha, 1, True)
                else:
                    s = -self.search(depth - 1, -alpha - 1, -alpha, 1, True)
                    if s > alpha and not self.stop:
                        s = -self.search(depth - 1, -beta, -alpha, 1, True)
                bd.unmake(m)
                if self.stop: break
                if s > curs:
                    curs = s; cur = m
                    if s > alpha: alpha = s
            if cur and (not self.stop or depth == 1 or curs > -MATE):
                if not self.stop or True:
                    best = cur
            if self.stop:
                break
            el = time.time() - start
            if abs(curs) > MATE - 200:
                sc = "mate %d" % ((MATE - abs(curs) + 1) // 2 * (1 if curs > 0 else -1))
            else:
                sc = "cp %d" % curs
            out("info depth %d score %s nodes %d time %d nps %d pv %s" % (
                depth, sc, self.nodes, int(el * 1000), int(self.nodes / max(el, 1e-3)), mstr(best)))
            if curs > MATE - 200: break
            if self.deadline and time.time() - start > movetime * 0.45: break
        out("bestmove " + mstr(best))


def main():
    bd = Board()
    sr = Searcher(bd)
    lock = threading.Lock()

    def out(s):
        with lock:
            sys.stdout.write(s + "\n"); sys.stdout.flush()

    th = [None]

    def wait():
        if th[0]:
            th[0].join(); th[0] = None

    def halt():
        sr.stop = True
        wait()

    for line in sys.stdin:
        a = line.split()
        if not a: continue
        c = a[0]
        if c == "uci":
            out("id name PyChess"); out("id author agent"); out("uciok")
        elif c == "isready":
            out("readyok")
        elif c == "ucinewgame":
            halt(); sr.tt.clear(); bd.set_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        elif c == "position":
            halt()
            i = 1
            if a[1] == "startpos":
                bd.set_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"); i = 2
            elif a[1] == "fen":
                j = a.index("moves") if "moves" in a else len(a)
                bd.set_fen(" ".join(a[2:j])); i = j
            if i < len(a) and a[i] == "moves":
                for mv in a[i + 1:]:
                    for m in bd.legal():
                        if mstr(m) == mv:
                            bd.make(m); break
        elif c == "go":
            halt()
            if "perft" in a:
                d = int(a[a.index("perft") + 1])
                tot = 0
                side = bd.side
                for m in bd.gen():
                    bd.make(m)
                    if not bd.attacked(bd.ksq[side], side ^ 1):
                        n = 1 if d <= 1 else bd.perft(d - 1)
                        tot += n
                        out("%s: %d" % (mstr(m), n))
                    bd.unmake(m)
                out("Nodes searched: %d" % tot)
                continue
            g = {}
            for k in range(1, len(a) - 1):
                if a[k] in ("depth", "movetime", "wtime", "btime", "winc", "binc", "movestogo"):
                    try: g[a[k]] = int(a[k + 1])
                    except ValueError: pass
            md = 64; mt = None
            if "depth" in g:
                md = g["depth"]
            if "movetime" in g:
                mt = max(0.02, g["movetime"] / 1000.0 - 0.06)
            elif "wtime" in g or "btime" in g:
                me = g.get("wtime" if bd.side == 0 else "btime", 1000)
                inc = g.get("winc" if bd.side == 0 else "binc", 0)
                mtg = g.get("movestogo", 30)
                mt = me / 1000.0 / (mtg + 2) + inc / 1000.0 * 0.7
                mt = max(0.02, min(mt, me / 1000.0 * 0.4 - 0.05))
            elif "depth" not in g and "infinite" not in a:
                mt = 1.0
            t = threading.Thread(target=sr.go, args=(md, mt, out))
            th[0] = t
            t.start()
        elif c == "stop":
            halt()
        elif c == "quit":
            halt(); return
    wait()


if __name__ == "__main__":
    main()
