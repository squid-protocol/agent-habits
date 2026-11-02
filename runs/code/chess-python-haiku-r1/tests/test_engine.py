"""Unit and protocol tests for PyChess. Run: python3 tests/test_engine.py"""
import os
import random
import subprocess
import sys
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import importlib.machinery
import importlib.util

_loader = importlib.machinery.SourceFileLoader("pychess", os.path.join(ROOT, "engine"))
_spec = importlib.util.spec_from_loader("pychess", _loader)
E = importlib.util.module_from_spec(_spec)
_loader.exec_module(E)


def snapshot(pos):
    return (pos.key, pos.mg, pos.eg, pos.phase, tuple(pos.npm), tuple(pos.kings), pos.side,
            pos.castle, pos.ep, pos.half, pos.full, tuple(pos.board))


class MoveGenTests(unittest.TestCase):
    def test_incremental_state_matches_refresh(self):
        rng = random.Random(7)
        for _ in range(40):
            pos = E.Position.from_fen(E.START_FEN)
            for _ply in range(120):
                moves = pos.legal()
                if not moves:
                    break
                m = rng.choice(moves)
                before = snapshot(pos)
                u = pos.make(m)
                ref = pos.copy()
                ref.refresh()
                self.assertEqual(pos.key, ref.key, E.move_uci(m))
                self.assertEqual((pos.mg, pos.eg, pos.phase, pos.npm), (ref.mg, ref.eg, ref.phase, ref.npm))
                self.assertEqual(pos.kings, ref.kings)
                pos.unmake(m, u)
                self.assertEqual(snapshot(pos), before)
                pos.make(m)  # keep playing from the new position
                if rng.random() < 0.02:
                    before_null = snapshot(pos)
                    nu = pos.make_null()
                    pos.unmake_null(nu)  # exercise null move bookkeeping
                    self.assertEqual(snapshot(pos), before_null)

    def test_perft_small(self):
        pos = E.Position.from_fen(E.START_FEN)
        self.assertEqual(E.perft(pos, 2), 400)
        pos = E.Position.from_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        self.assertEqual(E.perft(pos, 2), 2039)

    def test_promotion_and_ep(self):
        pos = E.Position.from_fen("8/P6k/8/8/8/8/6p1/K7 w - - 0 1")
        ucis = sorted(E.move_uci(m) for m in pos.legal())
        self.assertIn("a7a8q", ucis)
        self.assertIn("a7a8n", ucis)
        pos = E.Position.from_fen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        self.assertIn("e5d6", [E.move_uci(m) for m in pos.legal()])

    def test_castling_rules(self):
        pos = E.Position.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        ucis = {E.move_uci(m) for m in pos.legal()}
        self.assertIn("e1g1", ucis)
        self.assertIn("e1c1", ucis)
        # f1 attacked by a black rook: no kingside castling
        pos = E.Position.from_fen("r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1")
        ucis = {E.move_uci(m) for m in pos.legal()}
        self.assertNotIn("e1g1", ucis)

    def test_checkmate_and_stalemate(self):
        mated = E.Position.from_fen("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1")
        self.assertEqual(mated.legal(), [])
        self.assertTrue(mated.in_check())
        stale = E.Position.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        self.assertEqual(stale.legal(), [])
        self.assertFalse(stale.in_check())


class ProtocolTests(unittest.TestCase):
    def run_engine(self, lines, timeout=20):
        p = subprocess.run([sys.executable, os.path.join(ROOT, "engine")], input="\n".join(lines) + "\n",
                           capture_output=True, text=True, timeout=timeout)
        return p.stdout.splitlines()

    def test_handshake(self):
        out = self.run_engine(["uci", "isready", "quit"])
        self.assertIn("uciok", out)
        self.assertIn("readyok", out)
        self.assertTrue(any(l.startswith("id name") for l in out))
        self.assertTrue(any(l.startswith("id author") for l in out))

    def test_mated_and_stalemated_positions_give_null_move(self):
        out = self.run_engine(["position fen 7k/6Q1/6K1/8/8/8/8/8 b - - 0 1", "go depth 2", "quit"])
        self.assertEqual(out[-1], "bestmove 0000")
        out = self.run_engine(["position fen 7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", "go depth 2", "quit"])
        self.assertEqual(out[-1], "bestmove 0000")

    def test_promotion_output_format(self):
        out = self.run_engine(["position fen 8/P6k/8/8/8/8/8/K7 w - - 0 1", "go depth 3", "quit"])
        self.assertTrue(out[-1].startswith("bestmove a7a8"), out[-1])

    def test_position_moves_and_perft_format(self):
        out = self.run_engine(["position startpos moves e2e4 e7e5", "go perft 1", "quit"])
        self.assertEqual(out[-1], "Nodes searched: 29")
        self.assertIn("g1f3: 1", out)

    def test_stop_returns_bestmove(self):
        p = subprocess.Popen([sys.executable, os.path.join(ROOT, "engine")], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, text=True)
        p.stdin.write("position startpos\ngo infinite\n")
        p.stdin.flush()
        time.sleep(0.5)
        p.stdin.write("stop\nisready\nquit\n")
        p.stdin.flush()
        out, _ = p.communicate(timeout=20)
        lines = out.splitlines()
        self.assertTrue(any(l.startswith("bestmove ") for l in lines), lines[-3:])
        self.assertEqual(lines[-1], "readyok")

    def test_clock_go(self):
        t0 = time.time()
        out = self.run_engine(["position startpos", "go wtime 60000 btime 60000 winc 0 binc 0", "quit"])
        self.assertTrue(out[-1].startswith("bestmove "))
        self.assertLess(time.time() - t0, 10)


if __name__ == "__main__":
    unittest.main()
