package engine;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.util.concurrent.atomic.AtomicBoolean;

/** The UCI protocol loop. Searches run on a worker thread so that stop, isready and quit are answered promptly. */
public final class Uci {
    private static final int DEFAULT_MAX_DEPTH = 64;

    private final TT tt = new TT(20);
    private final PrintStream out = System.out;
    private Board board = Board.fromFen(Board.START_FEN);
    private Thread worker;
    private AtomicBoolean stopFlag = new AtomicBoolean(false);

    public void loop() throws IOException {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        String line;
        while ((line = in.readLine()) != null) {
            String t = line.trim();
            if (t.isEmpty()) {
                continue;
            }
            if (handle(t.split("\\s+"))) {
                break;
            }
        }
        stopSearch();
    }

    private synchronized void send(String s) {
        out.print(s);
        out.print('\n');
        out.flush();
    }

    /** Returns true when the program should exit. */
    private boolean handle(String[] tok) {
        try {
            switch (tok[0]) {
                case "uci":
                    send("id name JavaFish 1.0");
                    send("id author JavaFish authors");
                    send("uciok");
                    break;
                case "isready":
                    send("readyok");
                    break;
                case "ucinewgame":
                    stopSearch();
                    tt.clear();
                    board = Board.fromFen(Board.START_FEN);
                    break;
                case "position":
                    stopSearch();
                    setPosition(tok);
                    break;
                case "go":
                    stopSearch();
                    go(tok);
                    break;
                case "stop":
                    stopSearch();
                    break;
                case "quit":
                    stopSearch();
                    return true;
                default:
                    break; // setoption, debug, register and unknown commands are ignored
            }
        } catch (RuntimeException e) {
            send("info string error: " + e);
        }
        return false;
    }

    private void stopSearch() {
        if (worker != null) {
            stopFlag.set(true);
            try {
                worker.join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            worker = null;
        }
    }

    private void setPosition(String[] tok) {
        int i;
        Board b;
        if (tok.length > 1 && tok[1].equals("fen")) {
            StringBuilder fen = new StringBuilder();
            i = 2;
            while (i < tok.length && !tok[i].equals("moves")) {
                fen.append(tok[i]).append(' ');
                i++;
            }
            b = Board.fromFen(fen.toString());
        } else {
            b = Board.fromFen(Board.START_FEN);
            i = 2;
        }
        if (i < tok.length && tok[i].equals("moves")) {
            for (int j = i + 1; j < tok.length; j++) {
                int m = findLegal(b, tok[j]);
                if (m == 0) {
                    break;
                }
                b.make(m);
            }
        }
        board = b;
    }

    private static int findLegal(Board b, String uci) {
        int[] list = new int[256];
        int n = MoveGen.genLegal(b, list);
        for (int i = 0; i < n; i++) {
            if (Move.toUci(list[i]).equals(uci)) {
                return list[i];
            }
        }
        return 0;
    }

    private static long parseLong(String[] tok, int i) {
        return i < tok.length ? Long.parseLong(tok[i]) : 0;
    }

    private void go(String[] tok) {
        int depth = 0;
        int perftDepth = -1;
        long movetime = 0, wtime = -1, btime = -1, winc = 0, binc = 0;
        int movestogo = 0;
        boolean infinite = false;
        for (int i = 1; i < tok.length; i++) {
            switch (tok[i]) {
                case "perft": perftDepth = (int) parseLong(tok, i + 1); i++; break;
                case "depth": depth = (int) parseLong(tok, i + 1); i++; break;
                case "movetime": movetime = parseLong(tok, i + 1); i++; break;
                case "wtime": wtime = parseLong(tok, i + 1); i++; break;
                case "btime": btime = parseLong(tok, i + 1); i++; break;
                case "winc": winc = parseLong(tok, i + 1); i++; break;
                case "binc": binc = parseLong(tok, i + 1); i++; break;
                case "movestogo": movestogo = (int) parseLong(tok, i + 1); i++; break;
                case "infinite": infinite = true; break;
                default: break;
            }
        }
        if (perftDepth >= 0) {
            perft(board.copy(), perftDepth);
            return;
        }

        long budgetMs = 0;
        if (movetime > 0) {
            budgetMs = Math.max(1, movetime - Math.max(15, movetime / 10));
        } else if ((wtime >= 0 || btime >= 0) && depth == 0 && !infinite) {
            boolean white = board.side == Board.WHITE;
            long left = Math.max(1, white ? wtime : btime);
            long inc = white ? winc : binc;
            long mtg = movestogo > 0 ? movestogo : 30;
            budgetMs = Math.max(1, Math.min(left / mtg + inc * 3 / 4, left / 2));
        }
        final long deadline = budgetMs > 0 ? System.nanoTime() + budgetMs * 1_000_000L : 0;
        final int maxDepth = depth > 0 ? depth : DEFAULT_MAX_DEPTH;
        // "go infinite" and a bare "go" must not answer before "stop"; a depth-limited search answers at once.
        final boolean waitForStop = infinite || (depth == 0 && deadline == 0);

        final AtomicBoolean flag = new AtomicBoolean(false);
        stopFlag = flag;
        final Search search = new Search(board.copy(), tt, flag, deadline, this::send);
        worker = new Thread(() -> {
            int m = search.run(maxDepth);
            if (waitForStop) {
                while (!flag.get()) {
                    try {
                        Thread.sleep(1);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
            send("bestmove " + Move.toUci(m));
        }, "search");
        worker.setDaemon(true);
        worker.start();
    }

    private void perft(Board b, int depth) {
        if (depth <= 0) {
            send("Nodes searched: 1");
            return;
        }
        int[][] lists = new int[depth + 1][256];
        int n = MoveGen.genLegal(b, lists[0]);
        int us = b.side;
        long total = 0;
        for (int i = 0; i < n; i++) {
            int m = lists[0][i];
            b.make(m);
            long c = Perft.perft(b, depth - 1, 1, lists);
            b.unmake();
            total += c;
            send(Move.toUci(m) + ": " + c);
        }
        send("Nodes searched: " + total);
    }
}
