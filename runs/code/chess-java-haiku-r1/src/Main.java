import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.concurrent.atomic.AtomicBoolean;

/** UCI front end: reads commands on stdin, runs searches on a worker thread so that "stop" works. */
public final class Main {
    private static final String NAME = "JavaChess 1.0";
    private static final String AUTHOR = "JavaChess authors";

    private Position pos = Position.startpos();
    private final AtomicBoolean stop = new AtomicBoolean(false);
    private Thread searchThread;

    public static void main(String[] args) throws IOException {
        new Main().loop();
    }

    private synchronized void out(String s) {
        System.out.println(s);
        System.out.flush();
    }

    private void loop() throws IOException {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        String line;
        while ((line = in.readLine()) != null) {
            String[] t = line.trim().split("\\s+");
            if (t.length == 0 || t[0].isEmpty()) continue;
            try {
                if (!command(t)) return;
            } catch (RuntimeException e) {
                // A malformed command must not kill the engine; ignore it and keep reading.
            }
        }
        // stdin closed: let a running search finish and print its bestmove.
        joinSearch();
    }

    /** Handles one UCI command. Returns false when the engine should quit. */
    private boolean command(String[] t) {
        switch (t[0]) {
            case "uci":
                out("id name " + NAME);
                out("id author " + AUTHOR);
                out("uciok");
                break;
            case "isready":
                out("readyok");
                break;
            case "setoption":
            case "register":
                break;
            case "ucinewgame":
                stopSearch();
                Search.clearTT();
                pos = Position.startpos();
                break;
            case "position":
                stopSearch();
                position(t);
                break;
            case "go":
                go(t);
                break;
            case "stop":
                stop.set(true);
                break;
            case "quit":
                stopSearch();
                return false;
            case "d":
                out(pos.side == Position.WHITE ? "side to move: white" : "side to move: black");
                break;
            default:
                break;
        }
        return true;
    }

    private void stopSearch() {
        stop.set(true);
        joinSearch();
    }

    private void joinSearch() {
        if (searchThread != null) {
            try {
                searchThread.join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        searchThread = null;
    }

    private void position(String[] t) {
        Position p = new Position();
        int i = 1;
        if (i < t.length && t[i].equals("startpos")) {
            p.setFen(Position.START_FEN);
            i++;
        } else if (i < t.length && t[i].equals("fen")) {
            StringBuilder fen = new StringBuilder();
            for (i = i + 1; i < t.length && !t[i].equals("moves"); i++) {
                if (fen.length() > 0) fen.append(' ');
                fen.append(t[i]);
            }
            p.setFen(fen.toString());
        } else {
            return;
        }
        if (i < t.length && t[i].equals("moves")) {
            for (int j = i + 1; j < t.length; j++) {
                int m = p.parseMove(t[j]);
                if (m == 0) break;
                p.make(m);
            }
        }
        pos = p;
    }

    private static long num(String[] t, int i) {
        return i < t.length ? Long.parseLong(t[i]) : -1;
    }

    private void go(String[] t) {
        stopSearch();
        if (t.length > 2 && t[1].equals("perft")) {
            perftRoot((int) num(t, 2));
            return;
        }
        long depth = -1, movetime = -1, wtime = -1, btime = -1, winc = 0, binc = 0, movestogo = -1;
        for (int i = 1; i < t.length; i++) {
            switch (t[i]) {
                case "depth": depth = num(t, ++i); break;
                case "movetime": movetime = num(t, ++i); break;
                case "wtime": wtime = num(t, ++i); break;
                case "btime": btime = num(t, ++i); break;
                case "winc": winc = Math.max(0, num(t, ++i)); break;
                case "binc": binc = Math.max(0, num(t, ++i)); break;
                case "movestogo": movestogo = num(t, ++i); break;
                default: break;
            }
        }
        long now = System.nanoTime();
        long budgetMs = -1;
        if (movetime >= 0) {
            budgetMs = movetime;
        } else if (pos.side == Position.WHITE ? wtime >= 0 : btime >= 0) {
            long rem = pos.side == Position.WHITE ? wtime : btime;
            long inc = pos.side == Position.WHITE ? winc : binc;
            long b = movestogo > 0 ? rem / (movestogo + 1) + inc : rem / 25 + inc * 3 / 4;
            budgetMs = Math.max(1, Math.min(b, rem / 2));
        }
        long deadline = Long.MAX_VALUE;
        if (budgetMs >= 0) {
            long safety = Math.min(10, budgetMs / 10);
            deadline = now + Math.max(1, budgetMs - safety) * 1_000_000L;
        }
        int maxDepth = depth > 0 ? (int) depth : Search.MAX_DEPTH;
        Search s = new Search(pos.copy(), stop, deadline, maxDepth, this::out);
        stop.set(false);
        searchThread = new Thread(null, () -> {
            int m = s.run();
            out("bestmove " + (m == 0 ? "0000" : Position.uci(m)));
        }, "search", 1L << 26);
        searchThread.setDaemon(true);
        searchThread.start();
    }

    private void perftRoot(int depth) {
        if (depth <= 0) {
            out("Nodes searched: 1");
            return;
        }
        int[] root = new int[256];
        int n = pos.legal(root);
        long total = 0;
        for (int i = 0; i < n; i++) {
            pos.make(root[i]);
            long c = perft(pos, depth - 1);
            pos.unmake();
            out(Position.uci(root[i]) + ": " + c);
            total += c;
        }
        out("Nodes searched: " + total);
    }

    static long perft(Position p, int depth) {
        if (depth == 0) return 1;
        int[] mv = new int[256];
        int n = p.gen(mv, false);
        long count = 0;
        for (int i = 0; i < n; i++) {
            p.make(mv[i]);
            if (p.legalAfterMake()) count += perft(p, depth - 1);
            p.unmake();
        }
        return count;
    }
}
