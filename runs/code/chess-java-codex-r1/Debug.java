public class Debug {public static void main(String[]x){Board b=new Board();Move m=b.parseMove("c2c3");b=b.make(m);for(Move z:b.legalMoves())System.out.println(b.moveText(z));}}
