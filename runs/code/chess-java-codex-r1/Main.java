import java.io.*;
import java.util.*;

public class Main {
    static final String NAME="DenseJava";
    static volatile Thread searchThread;
    static volatile boolean stop;
    static Board board=new Board();
    public static void main(String[] args) throws Exception {
        BufferedReader in=new BufferedReader(new InputStreamReader(System.in)); String line;
        while((line=in.readLine())!=null){ line=line.trim(); if(line.isEmpty())continue;
            String[] t=line.split("\\s+");
            switch(t[0]){
                case "uci" -> {out("id name "+NAME);out("id author OpenAI");out("uciok");}
                case "isready" -> out("readyok");
                case "ucinewgame" -> {halt();board=new Board();}
                case "position" -> {halt(); setPosition(t);}
                case "go" -> {halt(); if(t.length>1&&t[1].equals("perft")){int d=Integer.parseInt(t[2]);perftRoot(board,d);}else startSearch(t);}
                case "stop" -> halt();
                case "quit" -> {halt();return;}
            }
        }
    }
    static synchronized void out(String s){System.out.println(s);System.out.flush();}
    static void halt(){Thread th=searchThread;if(th!=null){stop=true;try{th.join(3000);}catch(InterruptedException ignored){}searchThread=null;}}
    static void setPosition(String[] t){try{
        int i=1; if(t[i].equals("startpos")){board=new Board();i++;} else if(t[i].equals("fen")){StringBuilder f=new StringBuilder();i++;int n=0;while(i<t.length&&!t[i].equals("moves")&&n<6){if(n>0)f.append(' ');f.append(t[i++]);n++;}board=Board.fromFen(f.toString());}
        if(i<t.length&&t[i].equals("moves")){i++;for(;i<t.length;i++){Move m=board.parseMove(t[i]);if(m!=null)board=board.make(m);}}
    }catch(Exception e){board=new Board();}}
    static void perftRoot(Board b,int depth){List<Move> ms=b.legalMoves();long total=0;for(Move m:ms){long n=b.make(m).perft(depth-1);out(b.moveText(m)+": "+n);total+=n;}out("Nodes searched: "+total);}
    static void startSearch(String[] t){long ms=10000;int depth=64;boolean timed=false;for(int i=1;i<t.length;i++){try{switch(t[i]){case "depth" -> depth=Integer.parseInt(t[++i]);case "movetime" -> {ms=Long.parseLong(t[++i])-20;timed=true;}case "wtime" -> {long w=Long.parseLong(t[++i]);long b=w;for(int j=1;j<t.length-1;j++)if(t[j].equals("btime"))b=Long.parseLong(t[j+1]);ms=(board.white?w:b)/25+30;timed=true;}case "btime","winc","binc" -> i++;}}catch(Exception ignored){}}
        final int maxDepth=depth;final long budget=Math.max(20,ms);stop=false;
        searchThread=new Thread(()->{Search s=new Search();Move best=null;long end=System.nanoTime()+budget*1_000_000L;
            List<Move> root=board.legalMoves();if(root.isEmpty()){out("bestmove 0000");return;}best=root.get(0);
            for(int d=1;d<=maxDepth&&!stop;d++){try{Move m=s.root(board,d,end);if(m!=null)best=m;}catch(AbortSearch e){break;}}
            out("bestmove "+board.moveText(best));});searchThread.setDaemon(true);searchThread.start();
    }
}

record Move(int from,int to,int promo,int flags) { }
class AbortSearch extends RuntimeException { }

class Board {
    int[] sq=new int[64]; boolean white=true; int rights=15, ep=-1, half=0, full=1;
    static final int WK=1,WQ=2,BK=4,BQ=8;
    Board(){this("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");}
    Board(String fen){String[] p=fen.split(" ");String[] rows=p[0].split("/");for(int r=0;r<8;r++){int f=0;for(char c:rows[r].toCharArray()){if(Character.isDigit(c))f+=c-'0';else sq[(7-r)*8+f++]=piece(c);}}white=p.length<2||p[1].equals("w");rights=0;if(p.length>2){if(p[2].contains("K"))rights|=WK;if(p[2].contains("Q"))rights|=WQ;if(p[2].contains("k"))rights|=BK;if(p[2].contains("q"))rights|=BQ;}if(p.length>3&&!p[3].equals("-"))ep=parseSq(p[3]);if(p.length>4)half=Integer.parseInt(p[4]);if(p.length>5)full=Integer.parseInt(p[5]);}
    static Board fromFen(String f){return new Board(f);}
    static int piece(char c){String s=" pnbrqk";int v=s.indexOf(Character.toLowerCase(c));return Character.isUpperCase(c)?v:-v;}
    static int parseSq(String s){return s.charAt(0)-'a'+8*(s.charAt(1)-'1');}
    Board copy(){Board b=new Board();b.sq=sq.clone();b.white=white;b.rights=rights;b.ep=ep;b.half=half;b.full=full;return b;}
    int king(boolean w){for(int i=0;i<64;i++)if(sq[i]==(w?6:-6))return i;return -1;}
    boolean attacked(int x,boolean byWhite){int pawn=byWhite?1:-1;int r=x/8,f=x%8;int pr=r+(byWhite?-1:1);for(int df:new int[]{-1,1})if(pr>=0&&pr<8&&f+df>=0&&f+df<8&&sq[pr*8+f+df]==pawn)return true;
        int[] kn={-17,-15,-10,-6,6,10,15,17};for(int d:kn){int y=x+d;if(valid(x,y)&&sq[y]==(byWhite?2:-2))return true;}
        int[] dirs={1,-1,8,-8,9,-9,7,-7};for(int d:dirs){int y=x+d;while(valid(y-d,y)){int v=sq[y];if(v!=0){if((byWhite&&v>0)||(!byWhite&&v<0)){int a=Math.abs(v);if(a==5||a==4&&(d==1||d==-1||d==8||d==-8)||a==3&&(d==9||d==-9||d==7||d==-7))return true;}break;}y+=d;}}
        for(int d:new int[]{1,-1,8,-8,9,-9,7,-7}){int y=x+d;if(valid(x,y)&&sq[y]==(byWhite?6:-6))return true;}return false;}
    static boolean valid(int a,int b){return b>=0&&b<64&&Math.abs(a%8-b%8)<=2;}
    boolean inCheck(boolean w){int k=king(w);return k<0||attacked(k,!w);}
    List<Move> pseudo(){ArrayList<Move> a=new ArrayList<>();for(int x=0;x<64;x++){int p=sq[x];if(p==0||(p>0)!=white)continue;int type=Math.abs(p),r=x/8,f=x%8;
        if(type==1){int dir=white?8:-8, start=white?1:6,last=white?7:0,y=x+dir;if(y>=0&&y<64&&sq[y]==0){pawnMove(a,x,y,last);if(r==start&&sq[y+dir]==0)a.add(new Move(x,y+dir,0,0));}for(int df:new int[]{-1,1})if(f+df>=0&&f+df<8){y=x+dir+df;if(y>=0&&y<64&&((sq[y]!=0&&(sq[y]>0)!=white)||y==ep)){pawnMove(a,x,y,last);if(y==ep)a.set(a.size()-1,new Move(x,y,0,2));}}}
        else if(type==2){for(int d:new int[]{-17,-15,-10,-6,6,10,15,17}){int y=x+d;if(valid(x,y)&&canTake(y))a.add(new Move(x,y,0,0));}}
        else if(type==3||type==4||type==5) {int[] ds=type==3?new int[]{9,-9,7,-7}:type==4?new int[]{1,-1,8,-8}:new int[]{1,-1,8,-8,9,-9,7,-7};for(int d:ds){int y=x+d;while(valid(y-d,y)){if(sq[y]==0)a.add(new Move(x,y,0,0));else{if(canTake(y))a.add(new Move(x,y,0,0));break;}y+=d;}}}
        if(type==6){for(int d:new int[]{1,-1,8,-8,9,-9,7,-7}){int y=x+d;if(valid(x,y)&&canTake(y))a.add(new Move(x,y,0,0));}}
    }
    if(white&&sq[4]==6&&!inCheck(true)){if((rights&WK)!=0&&sq[5]==0&&sq[6]==0&&!attacked(5,false)&&!attacked(6,false))a.add(new Move(4,6,0,4));if((rights&WQ)!=0&&sq[3]==0&&sq[2]==0&&sq[1]==0&&!attacked(3,false)&&!attacked(2,false))a.add(new Move(4,2,0,4));}
    if(!white&&sq[60]==-6&&!inCheck(false)){if((rights&BK)!=0&&sq[61]==0&&sq[62]==0&&!attacked(61,true)&&!attacked(62,true))a.add(new Move(60,62,0,4));if((rights&BQ)!=0&&sq[59]==0&&sq[58]==0&&sq[57]==0&&!attacked(59,true)&&!attacked(58,true))a.add(new Move(60,58,0,4));}return a;}
    void pawnMove(List<Move>a,int x,int y,int last){if(y/8==last)for(int q:new int[]{5,4,3,2})a.add(new Move(x,y,q,0));else a.add(new Move(x,y,0,0));}
    boolean canTake(int y){return sq[y]==0||(sq[y]>0)!=white;}
    List<Move> legalMoves(){ArrayList<Move> l=new ArrayList<>();for(Move m:pseudo()){Board n=make(m);if(!n.inCheck(white))l.add(m);}return l;}
    Board make(Move m){Board b=copy();int p=b.sq[m.from()],capt=b.sq[m.to()];b.sq[m.from()]=0;if((m.flags()&2)!=0)b.sq[m.to()+(white?-8:8)]=0;if((m.flags()&4)!=0){if(m.to()==6){b.sq[5]=b.sq[7];b.sq[7]=0;}else if(m.to()==2){b.sq[3]=b.sq[0];b.sq[0]=0;}else if(m.to()==62){b.sq[61]=b.sq[63];b.sq[63]=0;}else{b.sq[59]=b.sq[56];b.sq[56]=0;}}
        b.sq[m.to()]=m.promo()!=0?(white?m.promo():-m.promo()):p;b.ep=-1;if(Math.abs(p)==1&&Math.abs(m.to()-m.from())==16)b.ep=(m.to()+m.from())/2;
        if(p==6)b.rights&=~(WK|WQ);if(p==-6)b.rights&=~(BK|BQ);if(m.from()==0||m.to()==0)b.rights&=~WQ;if(m.from()==7||m.to()==7)b.rights&=~WK;if(m.from()==56||m.to()==56)b.rights&=~BQ;if(m.from()==63||m.to()==63)b.rights&=~BK;
        b.half=(Math.abs(p)==1||capt!=0||m.flags()==2)?0:b.half+1;if(!white)b.full++;b.white=!white;return b;}
    String moveText(Move m){String s=""+(char)('a'+m.from()%8)+(char)('1'+m.from()/8)+(char)('a'+m.to()%8)+(char)('1'+m.to()/8);if(m.promo()!=0)s+=" pnbrq".charAt(m.promo());return s;}
    Move parseMove(String s){for(Move m:legalMoves())if(moveText(m).equals(s.toLowerCase()))return m;return null;}
    long perft(int d){if(d<=0)return 1;long n=0;for(Move m:legalMoves())n+=make(m).perft(d-1);return n;}
}

class Search {
    long end; long nodes; static final int INF=32000,MATE=30000;
    Move root(Board b,int depth,long deadline){end=deadline;List<Move> moves=ordered(b,b.legalMoves(),null);Move best=moves.isEmpty()?null:moves.get(0);int alpha=-INF;
        for(Move m:moves){checkTime();int v=-neg(b.make(m),depth-1,-INF,-alpha,1);if(v>alpha){alpha=v;best=m;}}return best;}
    int neg(Board b,int d,int alpha,int beta,int ply){nodes++;if((nodes&1023)==0)checkTime();if(d<=0)return q(b,alpha,beta);List<Move> ms=ordered(b,b.legalMoves(),null);if(ms.isEmpty())return b.inCheck(b.white)?-MATE+ply:0;int best=-INF;for(Move m:ms){int v=-neg(b.make(m),d-1,-beta,-alpha,ply+1);if(v>best)best=v;if(v>alpha)alpha=v;if(alpha>=beta)break;}return best;}
    int q(Board b,int alpha,int beta){nodes++;if((nodes&1023)==0)checkTime();int stand=eval(b);if(stand>=beta)return beta;if(stand>alpha)alpha=stand;for(Move m:ordered(b,b.legalMoves(),null)){if(b.sq[m.to()]==0&&m.promo()==0&&m.flags()!=2)continue;int v=-q(b.make(m),-beta,-alpha);if(v>=beta)return beta;if(v>alpha)alpha=v;}return alpha;}
    List<Move> ordered(Board b,List<Move> ms,Move tt){ms.sort((a,c)->Integer.compare(score(b,c,tt),score(b,a,tt)));return ms;}
    int score(Board b,Move m,Move tt){if(tt!=null&&m.equals(tt))return 100000;int p=Math.abs(b.sq[m.from()]),v=Math.abs(b.sq[m.to()]);return (v==0?0:10000+v*10-p)+(m.promo()!=0?9000+m.promo()*10:0);}
    int eval(Board b){int[] val={0,100,320,335,500,950,0};int s=0;for(int i=0;i<64;i++){int p=b.sq[i];if(p==0)continue;int a=Math.abs(p),r=i/8,f=i%8;int positional=a==1?(p>0?r:7-r)*5: (3-Math.abs(3-f)-Math.abs(3-r))*2;s+=(p>0?1:-1)*(val[a]+positional);}return b.white?s:-s;}
    void checkTime(){if(Main.stop||System.nanoTime()>end)throw new AbortSearch();}
}
