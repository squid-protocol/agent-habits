package engine;

/** Entry point: runs the UCI loop on standard input and output. */
public final class Main {
    private Main() {}

    public static void main(String[] args) throws Exception {
        new Uci().loop();
    }
}
