import java.io.*;
import java.nio.file.*;
import java.util.*;

public class Main {
    static final class Clause {
        int[] lits;
        Clause(int[] l) { lits=l; }
    }
    static final class Solver {
        final int n;
        final ArrayList<Clause> clauses=new ArrayList<>();
        ArrayList<Integer>[] watches;
        int[] val, level, reason, seen, phase;
        double[] activity;
        int[] trail, limits;
        int trailSize=0, qhead=0, nlimits=0, seenStamp=0;
        double increment=1.0;
        Solver(int n) {
            this.n=n; val=new int[n+1]; level=new int[n+1]; reason=new int[n+1];
            Arrays.fill(reason,-1); seen=new int[n+1]; phase=new int[n+1];
            activity=new double[n+1]; trail=new int[Math.max(16,n*4+16)]; limits=new int[Math.max(16,n+16)];
            watches=new ArrayList[2*n+2]; for(int i=0;i<watches.length;i++) watches[i]=new ArrayList<>();
        }
        int wi(int lit) { return lit>0 ? lit*2 : -lit*2+1; }
        int value(int lit) { int v=val[Math.abs(lit)]; return lit>0?v:-v; }
        void attach(Clause c) {
            if(c.lits.length>=2){ watches[wi(c.lits[0])].add(clauses.size()); watches[wi(c.lits[1])].add(clauses.size()); }
            clauses.add(c);
        }
        boolean addOriginal(int[] lits) {
            if(lits.length==0) return false;
            Clause c=new Clause(lits); attach(c); return true;
        }
        boolean enqueue(int lit,int why) {
            int v=Math.abs(lit), want=lit>0?1:-1;
            if(val[v]!=0) return val[v]==want;
            val[v]=want; phase[v]=want; level[v]=nlimits; reason[v]=why;
            if(trailSize==trail.length) trail=Arrays.copyOf(trail,trail.length*2);
            trail[trailSize++]=lit; return true;
        }
        void backtrack(int lev) {
            if(nlimits<=lev)return;
            int target=limits[lev];
            for(int i=trailSize-1;i>=target;i--){ int v=Math.abs(trail[i]); val[v]=0; reason[v]=-1; level[v]=0; }
            trailSize=target; qhead=Math.min(qhead,target); nlimits=lev;
        }
        int propagate() {
            while(qhead<trailSize) {
                int falseLit=-trail[qhead++]; ArrayList<Integer> ws=watches[wi(falseLit)];
                for(int i=0;i<ws.size();) {
                    int ci=ws.get(i); Clause c=clauses.get(ci); int[] a=c.lits;
                    if(a[0]==falseLit){int t=a[0];a[0]=a[1];a[1]=t;}
                    if(a[1]!=falseLit){ i++; continue; }
                    int other=a[0];
                    if(value(other)>0){i++;continue;}
                    int k=2; while(k<a.length && value(a[k])<0)k++;
                    if(k<a.length){a[1]=a[k];a[k]=falseLit; ws.set(i,ws.get(ws.size()-1));ws.remove(ws.size()-1);watches[wi(a[1])].add(ci);continue;}
                    if(value(other)<0)return ci;
                    if(!enqueue(other,ci))return ci;
                    i++;
                }
            }
            return -1;
        }
        void bump(int v) { activity[v]+=increment; if(activity[v]>1e100){for(int i=1;i<=n;i++)activity[i]*=1e-100;increment*=1e-100;} }
        int pick() { int best=0; double score=-1; for(int v=1;v<=n;v++)if(val[v]==0 && activity[v]>=score){score=activity[v];best=v;} return best; }
        int analyze(int conflict, ArrayList<Integer> learnt) {
            learnt.clear(); learnt.add(0); int path=0, p=0, idx=trailSize-1, ci=conflict;
            do {
                Clause c=clauses.get(ci);
                for(int q:c.lits) {
                    int v=Math.abs(q);
                    if(v==Math.abs(p) || seen[v]==seenStamp || level[v]==0)continue;
                    seen[v]=seenStamp; bump(v);
                    if(level[v]==nlimits)path++; else learnt.add(q);
                }
                while(idx>=0 && seen[Math.abs(trail[idx])]!=seenStamp)idx--;
                p=trail[idx--]; ci=reason[Math.abs(p)]; path--;
            } while(path>0 && ci>=0);
            learnt.set(0,-p);
            int back=0, maxIndex=1;
            for(int i=1;i<learnt.size();i++){int l=level[Math.abs(learnt.get(i))];if(l>back){back=l;maxIndex=i;}}
            if(learnt.size()>2){int t=learnt.get(1);learnt.set(1,learnt.get(maxIndex));learnt.set(maxIndex,t);}
            increment*=1.05; return back;
        }
        int solve() {
            for(int i=0;i<clauses.size();i++)if(clauses.get(i).lits.length==1&&!enqueue(clauses.get(i).lits[0],i))return -1;
            int confl=propagate();if(confl>=0)return -1;
            ArrayList<Integer> learnt=new ArrayList<>(); long conflicts=0, restartAt=100;
            while(true) {
                confl=propagate();
                if(confl>=0) {
                    conflicts++;
                    if(nlimits==0)return -1;
                    seenStamp++; int back=analyze(confl,learnt); backtrack(back);
                    Clause c=new Clause(learnt.stream().mapToInt(Integer::intValue).toArray()); attach(c);
                    enqueue(c.lits[0],clauses.size()-1);
                    if(conflicts>=restartAt){backtrack(0); restartAt+=Math.min(1000,100+conflicts/10);}
                    continue;
                }
                int v=pick(); if(v==0)return 1;
                if(nlimits==limits.length)limits=Arrays.copyOf(limits,limits.length*2);
                limits[nlimits++]=trailSize;
                enqueue(phase[v]==0?v:phase[v]*v,-1);
            }
        }
    }
    static int parseInt(String s) { return Integer.parseInt(s); }
    public static void main(String[] args) {
        if(args.length!=1){System.err.println("Usage: ./solver FILE");System.exit(1);}
        try { run(args[0]); } catch(Exception e){System.err.println("c parse/error: "+e.getMessage());System.exit(1);}
    }
    static void run(String file) throws Exception {
        List<String> lines=Files.readAllLines(Path.of(file)); int n=-1,m=-1; ArrayList<Integer> pending=new ArrayList<>(); ArrayList<int[]> input=new ArrayList<>();
        for(String raw:lines){String s=raw.trim();if(s.isEmpty()||s.startsWith("c"))continue;String[] t=s.split("\\s+");
            if(t[0].equals("p")){if(t.length<4||!t[1].equals("cnf"))throw new IOException("invalid header");n=parseInt(t[2]);m=parseInt(t[3]);continue;}
            for(String x:t){int lit=parseInt(x);if(lit==0){int[] a=pending.stream().mapToInt(Integer::intValue).toArray();input.add(a);pending.clear();}else pending.add(lit);}
        }
        if(n<0||m<0||!pending.isEmpty()||input.size()!=m)throw new IOException("invalid DIMACS formula");
        Solver s=new Solver(n); for(int[] c:input){for(int l:c)if(Math.abs(l)>n)throw new IOException("literal exceeds variable count"); if(!s.addOriginal(c)){System.out.println("s UNSATISFIABLE");System.exit(20);}}
        int result=s.solve(); if(result<0){System.out.println("s UNSATISFIABLE");System.exit(20);}
        System.out.println("s SATISFIABLE");StringBuilder b=new StringBuilder("v"); for(int v=1;v<=n;v++){int lit=s.val[v]==0?v:s.val[v]*v;b.append(' ').append(lit);if(v%200==0){b.append(" 0");System.out.println(b);b=new StringBuilder("v");}} b.append(" 0");System.out.println(b);System.exit(10);
    }
}
