#!/usr/bin/env python3
import sys, time, random, threading

random.seed(12345)
FILES = "abcdefgh"
VAL = [0, 100, 320, 330, 500, 900, 0]
PH = [0, 0, 1, 1, 2, 4, 0]
MATE = 30000
SQS = [r * 16 + f for r in range(8) for f in range(8)]
KN = (31, 33, 14, 18, -31, -33, -14, -18)
KG = (1, -1, 16, -16, 15, 17, -15, -17)
BD = (15, 17, -15, -17)
RD = (1, -1, 16, -16)
QD = BD + RD
CM = [15] * 128
for s, m in ((0, 13), (7, 14), (4, 12), (112, 7), (119, 11), (116, 3)):
    CM[s] = m

T = {}
T[1] = [0,0,0,0,0,0,0,0, 50,50,50,50,50,50,50,50, 10,10,20,30,30,20,10,10, 5,5,10,25,25,10,5,5,
        0,0,0,20,20,0,0,0, 5,-5,-10,0,0,-10,-5,5, 5,10,10,-20,-20,10,10,5, 0,0,0,0,0,0,0,0]
T[2] = [-50,-40,-30,-30,-30,-30,-40,-50, -40,-20,0,0,0,0,-20,-40, -30,0,10,15,15,10,0,-30,
        -30,5,15,20,20,15,5,-30, -30,0,15,20,20,15,0,-30, -30,5,10,15,15,10,5,-30,
        -40,-20,0,5,5,0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50]
T[3] = [-20,-10,-10,-10,-10,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,10,10,5,0,-10,
        -10,5,5,10,10,5,5,-10, -10,0,10,10,10,10,0,-10, -10,10,10,10,10,10,10,-10,
        -10,5,0,0,0,0,5,-10, -20,-10,-10,-10,-10,-10,-10,-20]
T[4] = [0,0,0,0,0,0,0,0, 5,10,10,10,10,10,10,5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5,
        -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, 0,0,0,5,5,0,0,0]
T[5] = [-20,-10,-10,-5,-5,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,5,5,5,0,-10, -5,0,5,5,5,5,0,-5,
        0,0,5,5,5,5,0,-5, -10,5,5,5,5,5,0,-10, -10,0,5,0,0,0,0,-10, -20,-10,-10,-5,-5,-10,-10,-20]
KMG = [-30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30,
       -30,-40,-40,-50,-50,-40,-40,-30, -20,-30,-30,-40,-40,-30,-30,-20, -10,-20,-20,-20,-20,-20,-20,-10,
       20,20,0,0,0,0,20,20, 20,30,10,0,0,10,30,20]
KEG = [-50,-40,-30,-20,-20,-30,-40,-50, -30,-20,-10,0,0,-10,-20,-30, -30,-10,20,30,30,20,-10,-30,
       -30,-10,30,40,40,30,-10,-30, -30,-10,30,40,40,30,-10,-30, -30,-10,20,30,30,20,-10,-30,
       -30,-30,0,0,0,0,-30,-30, -50,-30,-30,-30,-30,-30,-30,-50]
PEG = [0, 0, 5, 10, 20, 35, 60, 0]
PMG = [[0] * 128 for _ in range(15)]
PEGT = [[0] * 128 for _ in range(15)]
for pt in range(1, 7):
    for r in range(8):
        for f in range(8):
            sq = r * 16 + f
            wi = (7 - r) * 8 + f
            bi = r * 8 + f
            if pt == 6:
                mg, eg = KMG, KEG
                a, e = mg[wi], eg[wi]
                c, d = mg[bi], eg[bi]
                v = 0
            else:
                tb = T[pt]
                a, c = tb[wi], tb[bi]
                e, d = a, c
                v = VAL[pt]
                if pt == 1:
                    e = a + PEG[r] ; d = c + PEG[7 - r]
            PMG[pt][sq] = v + a; PMG[pt + 8][sq] = -(v + c)
            PEGT[pt][sq] = v + e; PEGT[pt + 8][sq] = -(v + d)
            if pt == 6:
                PEGT[pt][sq] = e; PEGT[pt + 8][sq] = -d

ZP = [[random.getrandbits(64) for _ in range(128)] for _ in range(15)]
ZS = random.getrandbits(64)
ZC = [random.getrandbits(64) for _ in range(16)]
ZE = [random.getrandbits(64) for _ in range(128)]


def sqname(s):
    return FILES[s & 7] + str((s >> 4) + 1)


def mstr(m):
    s = sqname(m & 127) + sqname((m >> 7) & 127)
    pr = m >> 14
    if pr:
        s += " nnbrq"[pr - 1 + 1] if False else "  nbrq"[pr]
    return s


class Abort(Exception):
    pass


class Board:
    def __init__(self):
        self.set_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

    def set_fen(self, fen):
        p = fen.split()
        b = [0] * 128
        r, f = 7, 0
        codes = {c: i + 1 for i, c in enumerate("pnbrqk")}
        for ch in p[0]:
            if ch == '/':
                r -= 1; f = 0
            elif ch.isdigit():
                f += int(ch)
            else:
                pc = codes[ch.lower()] + (0 if ch.isupper() else 8)
                b[r * 16 + f] = pc; f += 1
        self.b = b
        self.side = 0 if p[1] == 'w' else 1
        c = 0
        cs = p[2] if len(p) > 2 else '-'
        for ch, v in (('K', 1), ('Q', 2), ('k', 4), ('q', 8)):
            if ch in cs: c |= v
        self.castle = c
        self.ep = -1
        if len(p) > 3 and p[3] != '-':
            self.ep = (int(p[3][1]) - 1) * 16 + FILES.index(p[3][0])
        self.half = int(p[4]) if len(p) > 4 else 0
        self.ksq = [0, 0]
        for s in SQS:
            if b[s] == 6: self.ksq[0] = s
            if b[s] == 14: self.ksq[1] = s
        h = 0; mg = 0; eg = 0; ph = 0
        for s in SQS:
            pc = b[s]
            if pc:
                h ^= ZP[pc][s]; mg += PMG[pc][s]; eg += PEGT[pc][s]; ph += PH[pc & 7]
        if self.side: h ^= ZS
        h ^= ZC[self.castle]
        if self.ep >= 0: h ^= ZE[self.ep]
        self.h = h; self.mg = mg; self.eg = eg; self.phase = ph
        self.stack = []
        self.keys = [h]

    def attacked(self, sq, by):
        b = self.b
        o = by << 3
        if by == 0:
            for d in (-15, -17):
                s = sq + d
                if not s & 0x88 and b[s] == 1: return True
        else:
            for d in (15, 17):
                s = sq + d
                if not s & 0x88 and b[s] == 9: return True
        n = 2 + o
        for d in KN:
            s = sq + d
            if not s & 0x88 and b[s] == n: return True
        k = 6 + o
        for d in KG:
            s = sq + d
            if not s & 0x88 and b[s] == k: return True
        r = 4 + o; q = 5 + o; bi = 3 + o
        for d in RD:
            s = sq + d
            while not s & 0x88:
                c = b[s]
                if c:
                    if c == r or c == q: return True
                    break
                s += d
        for d in BD:
            s = sq + d
            while not s & 0x88:
                c = b[s]
                if c:
                    if c == bi or c == q: return True
                    break
                s += d
        return False

    def incheck(self):
        return self.attacked(self.ksq[self.side], self.side ^ 1)

    def gen(self, qonly=False):
        b = self.b; side = self.side; ep = self.ep
        moves = []; add = moves.append
        for s in SQS:
            p = b[s]
            if not p or (p >> 3) != side: continue
            pt = p & 7
            if pt == 1:
                d = 16 if side == 0 else -16
                t = s + d
                promo = (t >> 4) == (7 if side == 0 else 0)
                if not b[t]:
                    if promo:
                        add(s | t << 7 | 5 << 14)
                        if not qonly:
                            add(s | t << 7 | 2 << 14); add(s | t << 7 | 3 << 14); add(s | t << 7 | 4 << 14)
                    elif not qonly:
                        add(s | t << 7)
                        if (s >> 4) == (1 if side == 0 else 6) and not b[t + d]:
                            add(s | (t + d) << 7)
                for e in (t - 1, t + 1):
                    if e & 0x88: continue
                    c = b[e]
                    if (c and (c >> 3) != side) or e == ep:
                        if promo:
                            add(s | e << 7 | 5 << 14)
                            add(s | e << 7 | 2 << 14); add(s | e << 7 | 3 << 14); add(s | e << 7 | 4 << 14)
                        else:
                            add(s | e << 7)
            elif pt == 2 or pt == 6:
                for d in (KN if pt == 2 else KG):
                    t = s + d
                    if t & 0x88: continue
                    c = b[t]
                    if c == 0:
                        if not qonly: add(s | t << 7)
                    elif (c >> 3) != side:
                        add(s | t << 7)
            else:
                for d in (BD if pt == 3 else RD if pt == 4 else QD):
                    t = s + d
                    while not t & 0x88:
                        c = b[t]
                        if c == 0:
                            if not qonly: add(s | t << 7)
                        else:
                            if (c >> 3) != side: add(s | t << 7)
                            break
                        t += d
        if not qonly:
            cs = self.castle
            if side == 0:
                if b[4] == 6:
                    if cs & 1 and not b[5] and not b[6] and b[7] == 4 and not self.attacked(4, 1) and not self.attacked(5, 1):
                        add(4 | 6 << 7)
                    if cs & 2 and not b[3] and not b[2] and not b[1] and b[0] == 4 and not self.attacked(4, 1) and not self.attacked(3, 1):
                        add(4 | 2 << 7)
            else:
                if b[116] == 14:
                    if cs & 4 and not b[117] and not b[118] and b[119] == 12 and not self.attacked(116, 0) and not self.attacked(117, 0):
                        add(116 | 118 << 7)
                    if cs & 8 and not b[115] and not b[114] and not b[113] and b[112] == 12 and not self.attacked(116, 0) and not self.attacked(115, 0):
                        add(116 | 114 << 7)
        return moves

    def make(self, m):
        b = self.b
        f = m & 127; t = (m >> 7) & 127; pr = m >> 14
        p = b[f]; cap = b[t]; side = self.side
        pt = p & 7
        capsq = t
        if pt == 1 and t == self.ep and (f ^ t) & 15:
            capsq = t - 16 if side == 0 else t + 16
            cap = b[capsq]; b[capsq] = 0
        self.stack.append((m, cap, self.castle, self.ep, self.half, self.h, self.mg, self.eg, self.phase))
        h = self.h ^ ZS ^ ZC[self.castle]
        if self.ep >= 0: h ^= ZE[self.ep]
        mg = self.mg; eg = self.eg; ph = self.phase
        self.half += 1
        if pt == 1: self.half = 0
        if cap:
            h ^= ZP[cap][capsq]; mg -= PMG[cap][capsq]; eg -= PEGT[cap][capsq]; ph -= PH[cap & 7]
            self.half = 0
        b[f] = 0
        np = (pr | side << 3) if pr else p
        b[t] = np
        h ^= ZP[p][f] ^ ZP[np][t]
        mg += PMG[np][t] - PMG[p][f]; eg += PEGT[np][t] - PEGT[p][f]
        if pr: ph += PH[pr]
        if pt == 6:
            self.ksq[side] = t
            if t - f == 2 or f - t == 2:
                if t > f: rf = t + 1; rt = t - 1
                else: rf = t - 2; rt = t + 1
                r = b[rf]; b[rf] = 0; b[rt] = r
                h ^= ZP[r][rf] ^ ZP[r][rt]
                mg += PMG[r][rt] - PMG[r][rf]; eg += PEGT[r][rt] - PEGT[r][rf]
        self.castle &= CM[f] & CM[t]
        if pt == 1 and (t - f == 32 or f - t == 32):
            self.ep = (f + t) >> 1
            h ^= ZE[self.ep]
        else:
            self.ep = -1
        h ^= ZC[self.castle]
        self.h = h; self.mg = mg; self.eg = eg; self.phase = ph
        self.side = side ^ 1
        self.keys.append(h)

    def unmake(self):
        m, cap, castle, ep, half, h, mg, eg, ph = self.stack.pop()
        self.keys.pop()
        side = self.side ^ 1
        self.side = side
        b = self.b
        if m:
            f = m & 127; t = (m >> 7) & 127; pr = m >> 14
            p = b[t]
            if pr: p = 1 | side << 3
            b[f] = p
            pt = p & 7
            if pt == 1 and t == ep and (f ^ t) & 15:
                b[t] = 0
                b[t - 16 if side == 0 else t + 16] = cap
            else:
                b[t] = cap
            if pt == 6:
                self.ksq[side] = f
                if t - f == 2 or f - t == 2:
                    if t > f: rf = t + 1; rt = t - 1
                    else: rf = t - 2; rt = t + 1
                    b[rf] = b[rt]; b[rt] = 0
        self.castle = castle; self.ep = ep; self.half = half
        self.h = h; self.mg = mg; self.eg = eg; self.phase = ph

    def make_null(self):
        self.stack.append((0, 0, self.castle, self.ep, self.half, self.h, self.mg, self.eg, self.phase))
        h = self.h ^ ZS
        if self.ep >= 0: h ^= ZE[self.ep]
        self.ep = -1; self.h = h; self.side ^= 1; self.half += 1
        self.keys.append(h)

    def legal_moves(self):
        res = []
        side = self.side
        for m in self.gen():
            self.make(m)
            if not self.attacked(self.ksq[side], side ^ 1): res.append(m)
            self.unmake()
        return res

    def perft(self, d):
        if d == 0: return 1
        side = self.side
        n = 0
        for m in self.gen():
            self.make(m)
            if not self.attacked(self.ksq[side], side ^ 1):
                n += 1 if d == 1 else self.perft(d - 1)
            self.unmake()
        return n

    def evaluate(self):
        ph = self.phase
        if ph > 24: ph = 24
        sc = (self.mg * ph + self.eg * (24 - ph)) // 24
        if ph < 10:
            # mop-up: drive the losing king to the edge, bring kings together
            wk = self.ksq[0]; bk = self.ksq[1]
            def cd(s):
                r = s >> 4; f = s & 7
                return max(3 - r, r - 4) + max(3 - f, f - 4)
            dist = abs((wk >> 4) - (bk >> 4)) + abs((wk & 7) - (bk & 7))
            if sc > 200: sc += (cd(bk) * 10 + (14 - dist) * 4) * (10 - ph) // 10
            elif sc < -200: sc -= (cd(wk) * 10 + (14 - dist) * 4) * (10 - ph) // 10
        return (sc if self.side == 0 else -sc) + 10

    def parse_move(self, s):
        for m in self.legal_moves():
            if mstr(m) == s: return m
        return None


class Searcher:
    def __init__(self, board):
        self.bd = board
        self.tt = {}
        self.stop = False
        self.killers = [[0, 0] for _ in range(128)]
        self.hist = {}
        self.nodes = 0

    def order(self, moves, ttm, ply):
        b = self.bd.b; k = self.killers[ply]; hist = self.hist
        sc = []
        for m in moves:
            if m == ttm: s = 10000000
            else:
                v = b[(m >> 7) & 127]
                if v:
                    s = 1000000 + 10 * VAL[v & 7] - VAL[b[m & 127] & 7] // 10
                elif m >> 14: s = 900000 + (m >> 14)
                elif m == k[0]: s = 800000
                elif m == k[1]: s = 700000
                else: s = hist.get(m, 0)
            sc.append((s, m))
        sc.sort(reverse=True)
        return [m for _, m in sc]

    def check_time(self):
        if self.stop or time.time() >= self.deadline:
            raise Abort()

    def qs(self, alpha, beta, ply):
        self.nodes += 1
        if not self.nodes & 1023: self.check_time()
        bd = self.bd
        st = bd.evaluate()
        if st >= beta: return st
        if st > alpha: alpha = st
        if ply >= 100: return st
        side = bd.side
        for m in self.order(bd.gen(True), 0, ply):
            bd.make(m)
            if bd.attacked(bd.ksq[side], side ^ 1):
                bd.unmake(); continue
            sc = -self.qs(-beta, -alpha, ply + 1)
            bd.unmake()
            if sc >= beta: return sc
            if sc > alpha: alpha = sc
        return alpha

    def ab(self, depth, alpha, beta, ply, nullok):
        bd = self.bd
        self.nodes += 1
        if not self.nodes & 1023: self.check_time()
        if ply > 0:
            if bd.half >= 100: return 0
            keys = bd.keys; h = bd.h
            i = len(keys) - 3; lim = len(keys) - 1 - bd.half
            while i >= lim and i >= 0:
                if keys[i] == h: return 0
                i -= 2
            # mate distance pruning
            if alpha < -MATE + ply: alpha = -MATE + ply
            if beta > MATE - ply - 1: beta = MATE - ply - 1
            if alpha >= beta: return alpha
        side = bd.side
        chk = bd.attacked(bd.ksq[side], side ^ 1)
        if chk and ply < 60: depth += 1
        if depth <= 0: return self.qs(alpha, beta, ply)
        h = bd.h
        ttm = 0
        e = self.tt.get(h)
        pv = beta - alpha > 1
        if e:
            ttm = e[3]
            if e[0] >= depth and ply > 0 and not pv:
                s = e[2]
                if s > MATE - 200: s -= ply
                elif s < -MATE + 200: s += ply
                if e[1] == 0 or (e[1] == 1 and s >= beta) or (e[1] == 2 and s <= alpha):
                    return s
        if nullok and not chk and depth >= 3 and not pv and bd.phase > 2:
            bd.make_null()
            sc = -self.ab(depth - 3 - (depth >= 6), -beta, -beta + 1, ply + 1, False)
            bd.unmake()
            if sc >= beta: return beta
        moves = self.order(bd.gen(), ttm, ply)
        b = bd.b
        legal = 0
        best = -MATE - 1; bestm = 0
        a0 = alpha
        for m in moves:
            iscap = b[(m >> 7) & 127] != 0
            bd.make(m)
            if bd.attacked(bd.ksq[side], side ^ 1):
                bd.unmake(); continue
            legal += 1
            quiet = not iscap and not (m >> 14)
            if legal == 1:
                sc = -self.ab(depth - 1, -beta, -alpha, ply + 1, True)
            else:
                red = 0
                if legal > 4 and depth >= 3 and quiet and not chk:
                    red = 1 + (legal > 10)
                sc = -self.ab(depth - 1 - red, -alpha - 1, -alpha, ply + 1, True)
                if sc > alpha and (red or sc < beta):
                    sc = -self.ab(depth - 1, -beta, -alpha, ply + 1, True)
            bd.unmake()
            if sc > best:
                best = sc; bestm = m
                if sc > alpha:
                    alpha = sc
                    if ply == 0: self.rootbest = m; self.rootscore = sc
                    if sc >= beta:
                        if quiet:
                            k = self.killers[ply]
                            if k[0] != m: k[1] = k[0]; k[0] = m
                            self.hist[m] = self.hist.get(m, 0) + depth * depth
                        break
        if not legal:
            return -MATE + ply if chk else 0
        flag = 0
        if best >= beta: flag = 1
        elif best <= a0: flag = 2
        s = best
        if s > MATE - 200: s += ply
        elif s < -MATE + 200: s -= ply
        if len(self.tt) > 1500000: self.tt.clear()
        self.tt[h] = (depth, flag, s, bestm)
        return best

    def search(self, maxdepth, tlimit):
        bd = self.bd
        self.stop = False
        self.deadline = time.time() + tlimit
        start = time.time()
        self.nodes = 0
        self.hist = {}
        self.killers = [[0, 0] for _ in range(128)]
        legal = bd.legal_moves()
        if not legal: return None
        best = legal[0]
        if len(legal) == 1 and maxdepth >= 64:
            return best
        base = len(bd.stack)
        for d in range(1, maxdepth + 1):
            self.rootbest = 0
            try:
                sc = self.ab(d, -MATE - 1, MATE + 1, 0, False)
                if self.rootbest: best = self.rootbest
                done = True
            except Abort:
                while len(bd.stack) > base: bd.unmake()
                if self.rootbest and d > 1: best = self.rootbest
                break
            el = int((time.time() - start) * 1000)
            if abs(sc) < MATE - 200:
                ss = "cp %d" % sc
            else:
                n = (MATE - abs(sc) + 1) // 2
                ss = "mate %d" % (n if sc > 0 else -n)
            print("info depth %d score %s nodes %d time %d pv %s" % (d, ss, self.nodes, el, mstr(best)), flush=True)
            if abs(sc) > MATE - 200 and MATE - abs(sc) <= d: break
            if time.time() - start > tlimit * 0.5 and maxdepth >= 64: break
        return best


def main():
    bd = Board()
    sr = Searcher(bd)
    th = [None]

    def do_go(args):
        depth = 64; mt = None; wt = bt = None; wi = bi = 0; inf = False
        i = 0
        if args and args[0] == 'perft':
            d = int(args[1]); tot = 0
            side = bd.side
            for m in bd.legal_moves():
                bd.make(m)
                n = bd.perft(d - 1) if d > 1 else 1
                bd.unmake()
                print("%s: %d" % (mstr(m), n)); tot += n
            print("Nodes searched: %d" % tot, flush=True)
            return
        while i < len(args):
            a = args[i]
            if a in ('depth', 'movetime', 'wtime', 'btime', 'winc', 'binc', 'movestogo', 'nodes'):
                v = int(args[i + 1]); i += 2
                if a == 'depth': depth = v
                elif a == 'movetime': mt = v / 1000.0
                elif a == 'wtime': wt = v
                elif a == 'btime': bt = v
                elif a == 'winc': wi = v
                elif a == 'binc': bi = v
                elif a == 'movestogo': mtg = v
            else:
                if a == 'infinite': inf = True
                i += 1
        if mt is not None: tl = max(0.02, mt - 0.04)
        elif wt is not None or bt is not None:
            rem, inc = (wt, wi) if bd.side == 0 else (bt, bi)
            rem = rem or 1000
            tl = max(0.03, min(rem / 1000.0 * 0.3, rem / 1000.0 / 25 + inc / 1000.0 * 0.7 - 0.05))
        elif inf or depth < 64: tl = 1e9
        else: tl = 10.0
        best = sr.search(depth, tl)
        if inf:
            pass
        print("bestmove %s" % (mstr(best) if best else "0000"), flush=True)

    def run_go(args):
        try:
            do_go(args)
        except Exception as ex:
            print("info string error %r" % (ex,), flush=True)
            print("bestmove 0000", flush=True)

    for line in sys.stdin:
        p = line.split()
        if not p: continue
        c = p[0]
        if c == 'uci':
            print("id name PyChess 1.0\nid author Claude\nuciok", flush=True)
        elif c == 'isready':
            print("readyok", flush=True)
        elif c == 'ucinewgame':
            sr.tt.clear()
        elif c == 'position':
            i = 1
            if p[1] == 'startpos':
                bd.set_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"); i = 2
            elif p[1] == 'fen':
                j = p.index('moves') if 'moves' in p else len(p)
                bd.set_fen(" ".join(p[2:j])); i = j
            if i < len(p) and p[i] == 'moves':
                for s in p[i + 1:]:
                    m = bd.parse_move(s)
                    if m is None: break
                    bd.make(m)
        elif c == 'go':
            if th[0] and th[0].is_alive():
                sr.stop = True; th[0].join()
            t = threading.Thread(target=run_go, args=(p[1:],), daemon=True)
            th[0] = t; t.start()
        elif c == 'stop':
            sr.stop = True
            if th[0]: th[0].join()
        elif c == 'quit':
            sr.stop = True
            if th[0]: th[0].join()
            break
    if th[0]: th[0].join()


if __name__ == '__main__':
    main()
