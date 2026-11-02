import java.io.*;
import java.util.*;

public class Main {
    static final class Clause { int[] l; int lbd; boolean learnt, del; Clause(int[] l){this.l=l;} }
    static int nv;
    static byte[] val; static int[] level; static Clause[] reason;
    static int[] trail; static int tn, qhead; static int[] lim = new int[16]; static int dl;
    static Clause[][] ws; static int[] wn;
    static double[] act; static double inc = 1; static int[] heap, pos; static int hn;
    static boolean[] phase; static boolean[] seen;
    static ArrayList<Clause> learnts = new ArrayList<>();
    static int[] stamp; static int stampN;

    static boolean less(int a, int b){ return act[a] > act[b]; }
    static void up(int i){ int x=heap[i]; while(i>0){int p=(i-1)>>1; if(!less(x,heap[p]))break; heap[i]=heap[p];pos[heap[i]]=i;i=p;} heap[i]=x;pos[x]=i; }
    static void down(int i){ int x=heap[i]; while(true){int c=2*i+1; if(c>=hn)break; if(c+1<hn&&less(heap[c+1],heap[c]))c++; if(!less(heap[c],x))break; heap[i]=heap[c];pos[heap[i]]=i;i=c;} heap[i]=x;pos[x]=i; }
    static void insert(int v){ if(pos[v]>=0)return; heap[hn]=v;pos[v]=hn;hn++;up(hn-1); }
    static int removeMax(){ int x=heap[0]; pos[x]=-1; hn--; if(hn>0){heap[0]=heap[hn];pos[heap[0]]=0;down(0);} return x; }
    static void bump(int v){ if((act[v]+=inc)>1e100){ for(int i=0;i<nv;i++)act[i]*=1e-100; inc*=1e-100; } if(pos[v]>=0)up(pos[v]); }

    static void watch(int lit, Clause c){ if(wn[lit]==ws[lit].length) ws[lit]=Arrays.copyOf(ws[lit], Math.max(4,wn[lit]*2)); ws[lit][wn[lit]++]=c; }
    static void enqueue(int lit, Clause r){ val[lit]=1; val[lit^1]=-1; int v=lit>>1; level[v]=dl; reason[v]=r; trail[tn++]=lit; }

    static Clause propagate(){
        while(qhead<tn){
            int p=trail[qhead++]; int f=p^1;
            Clause[] w=ws[f]; int n=wn[f]; int i=0,j=0;
            while(i<n){
                Clause c=w[i++];
                if(c.del) continue;
                int[] l=c.l;
                if(l[0]==f){ l[0]=l[1]; l[1]=f; }
                int first=l[0];
                if(val[first]==1){ w[j++]=c; continue; }
                boolean found=false;
                for(int k=2;k<l.length;k++){
                    if(val[l[k]]!=-1){ l[1]=l[k]; l[k]=f; watch(l[1],c); found=true; break; }
                }
                if(found) continue;
                w[j++]=c;
                if(val[first]==-1){
                    while(i<n) w[j++]=w[i++];
                    wn[f]=j; qhead=tn; return c;
                }
                enqueue(first,c);
            }
            wn[f]=j;
        }
        return null;
    }

    static void cancel(int lv){
        if(dl<=lv) return;
        for(int i=tn-1;i>=lim[lv];i--){ int lit=trail[i]; int v=lit>>1; val[lit]=0; val[lit^1]=0; phase[v]=(lit&1)==0; reason[v]=null; insert(v); }
        tn=lim[lv]; qhead=tn; dl=lv;
    }

    static int[] learnt = new int[0]; static int btlevel, learntLbd;
    static void analyze(Clause confl){
        int[] out=new int[16]; int on=1; int pathC=0; int p=-1; int idx=tn-1;
        do{
            int[] l=confl.l;
            for(int k=(p==-1?0:1);k<l.length;k++){
                int q=l[k]; int v=q>>1;
                if(!seen[v]&&level[v]>0){
                    bump(v); seen[v]=true;
                    if(level[v]>=dl) pathC++;
                    else { if(on==out.length) out=Arrays.copyOf(out,on*2); out[on++]=q; }
                }
            }
            while(!seen[trail[idx]>>1]) idx--;
            p=trail[idx]; idx--; confl=reason[p>>1]; seen[p>>1]=false; pathC--;
            if(pathC>0 && confl.l[0]!=p){ // ensure p at index 0
                int[] cl=confl.l; for(int k=1;k<cl.length;k++) if(cl[k]==p){cl[k]=cl[0];cl[0]=p;break;}
            }
        } while(pathC>0);
        out[0]=p^1;
        // clear seen for all but track
        int[] toClear=Arrays.copyOf(out,on);
        int j=1;
        for(int i=1;i<on;i++){
            int v=out[i]>>1; Clause r=reason[v];
            boolean keep=true;
            if(r!=null){
                keep=false;
                for(int k=0;k<r.l.length;k++){ int u=r.l[k]>>1; if(u!=v && !seen[u] && level[u]>0){keep=true;break;} }
            }
            if(keep) out[j++]=out[i];
        }
        for(int i=1;i<on;i++) seen[toClear[i]>>1]=false;
        on=j;
        learnt=Arrays.copyOf(out,on);
        if(on==1) btlevel=0;
        else {
            int mi=1; for(int i=2;i<on;i++) if(level[learnt[i]>>1]>level[learnt[mi]>>1]) mi=i;
            int t=learnt[1]; learnt[1]=learnt[mi]; learnt[mi]=t;
            btlevel=level[learnt[1]>>1];
        }
        stampN++; int lbd=0;
        for(int x: learnt){ int lv=level[x>>1]; if(stamp[lv]!=stampN){stamp[lv]=stampN;lbd++;} }
        learntLbd=lbd;
    }

    static void reduceDB(){
        ArrayList<Clause> cand=new ArrayList<>();
        for(Clause c: learnts) cand.add(c);
        cand.sort((a,b)-> a.lbd!=b.lbd ? Integer.compare(b.lbd,a.lbd) : Integer.compare(b.l.length,a.l.length));
        int rm=cand.size()/2; int removed=0;
        for(Clause c: cand){
            if(removed>=rm) break;
            if(c.lbd<=2||c.l.length<=2) continue;
            if(reason[c.l[0]>>1]==c && val[c.l[0]]==1) continue;
            c.del=true; removed++;
        }
        ArrayList<Clause> nl=new ArrayList<>();
        for(Clause c: learnts) if(!c.del) nl.add(c);
        learnts=nl;
        for(int lit=0;lit<2*nv;lit++){
            Clause[] w=ws[lit]; int j=0; for(int i=0;i<wn[lit];i++) if(!w[i].del) w[j++]=w[i];
            for(int i=j;i<wn[lit];i++) w[i]=null;
            wn[lit]=j;
        }
    }

    static long luby(long i){ // 1-based
        long k=1; while(((1L<<k)-1)<i) k++;
        while(true){ if(i==(1L<<k)-1) return 1L<<(k-1); i-=(1L<<(k-1))-1; k=1; while(((1L<<k)-1)<i) k++; }
    }

    public static void main(String[] args) throws IOException {
        StreamTokenizer st=new StreamTokenizer(new BufferedReader(new FileReader(args[0]),1<<16));
        st.resetSyntax(); st.wordChars(33,255); st.whitespaceChars(0,32);
        ArrayList<int[]> orig=new ArrayList<>();
        int hv=0; IntList cur=new IntList(); int maxv=0;
        while(st.nextToken()!=StreamTokenizer.TT_EOF){
            String s=st.sval;
            char ch=s.charAt(0);
            if(ch=='c'||ch=='p'||ch=='%'){
                boolean p=ch=='p';
                if(ch=='%') break;
                if(p){ st.nextToken(); st.nextToken(); hv=Integer.parseInt(st.sval); st.nextToken(); }
                else { // skip line: tokenizer is not line-aware; re-read file by lines instead
                    break;
                }
                continue;
            }
            break;
        }
        // simple robust line-based parse
        orig.clear();
        try(BufferedReader br=new BufferedReader(new FileReader(args[0]),1<<16)){
            String line;
            while((line=br.readLine())!=null){
                line=line.trim();
                if(line.isEmpty()) continue;
                char ch=line.charAt(0);
                if(ch=='c') continue;
                if(ch=='%') break;
                if(ch=='p'){ String[] t=line.split("\\s+"); hv=Integer.parseInt(t[2]); continue; }
                StringTokenizer tk=new StringTokenizer(line);
                while(tk.hasMoreTokens()){
                    int x=Integer.parseInt(tk.nextToken());
                    if(x==0){ orig.add(cur.toArray()); cur.n=0; }
                    else { cur.add(x); maxv=Math.max(maxv,Math.abs(x)); }
                }
            }
            if(cur.n>0) orig.add(cur.toArray());
        }
        nv=Math.max(hv,maxv);
        val=new byte[2*nv+2]; level=new int[nv]; reason=new Clause[nv]; trail=new int[nv+1];
        ws=new Clause[2*nv+2][]; wn=new int[2*nv+2]; for(int i=0;i<ws.length;i++) ws[i]=new Clause[0];
        act=new double[nv]; heap=new int[nv]; pos=new int[nv]; Arrays.fill(pos,-1);
        phase=new boolean[nv]; seen=new boolean[nv]; stamp=new int[nv+2];
        // occurrence-based initial activity
        boolean unsat=false;
        ArrayList<Clause> cls=new ArrayList<>();
        for(int[] c: orig){
            int[] t=new int[c.length]; int m=0; boolean taut=false;
            int[] lits=new int[c.length]; for(int i=0;i<c.length;i++) lits[i]=c[i]>0?2*(c[i]-1):2*(-c[i]-1)+1;
            Arrays.sort(lits);
            for(int i=0;i<lits.length;i++){
                if(i>0&&lits[i]==lits[i-1]) continue;
                if(i>0&&lits[i]==(lits[i-1]^1)) taut=true;
                t[m++]=lits[i];
            }
            if(taut) continue;
            t=Arrays.copyOf(t,m);
            for(int x: t) act[x>>1]+=1e-3;
            if(m==0){ unsat=true; break; }
            if(m==1){
                if(val[t[0]]==-1){unsat=true;break;}
                if(val[t[0]]==0) enqueue(t[0],null);
                continue;
            }
            Clause cl=new Clause(t); cls.add(cl);
        }
        if(unsat){ System.out.println("s UNSATISFIABLE"); System.exit(20); }
        for(Clause c: cls){ watch(c.l[0],c); watch(c.l[1],c); }
        for(int v=0;v<nv;v++) insert(v);
        if(propagate()!=null){ System.out.println("s UNSATISFIABLE"); System.exit(20); }

        long conflicts=0, restartN=1, sinceRestart=0, restartLim=100*luby(1);
        long nextReduce=4000; long reduceInc=600;
        while(true){
            Clause confl=propagate();
            if(confl!=null){
                conflicts++; sinceRestart++;
                if(dl==0){ System.out.println("s UNSATISFIABLE"); System.exit(20); }
                analyze(confl);
                cancel(btlevel);
                if(learnt.length==1) enqueue(learnt[0],null);
                else {
                    Clause c=new Clause(learnt); c.learnt=true; c.lbd=learntLbd;
                    learnts.add(c); watch(c.l[0],c); watch(c.l[1],c);
                    enqueue(c.l[0],c);
                }
                inc*=1/0.95;
            } else {
                if(sinceRestart>=restartLim){
                    sinceRestart=0; restartN++; restartLim=100*luby(restartN); cancel(0);
                }
                if(conflicts>=nextReduce){ nextReduce=conflicts+4000+reduceInc; reduceInc+=600; reduceDB(); }
                int v=-1;
                while(hn>0){ int x=removeMax(); if(val[2*x]==0){v=x;break;} }
                if(v<0) break;
                if(dl==lim.length) lim=Arrays.copyOf(lim,dl*2);
                lim[dl]=tn; dl++;
                enqueue(phase[v]?2*v:2*v+1,null);
            }
        }
        // verify
        for(int[] c: orig){
            boolean ok=false;
            for(int x: c){ int lit=x>0?2*(x-1):2*(-x-1)+1; if(val[lit]==1){ok=true;break;} }
            if(!ok && c.length>0){ System.err.println("internal error"); System.exit(1); }
        }
        StringBuilder sb=new StringBuilder("s SATISFIABLE\nv");
        int cnt=0;
        for(int v=0;v<nv;v++){
            String t=" "+(val[2*v]==1?(v+1):-(v+1));
            if(sb.length()-sb.lastIndexOf("\n")+t.length()>78) sb.append("\nv");
            sb.append(t);
        }
        sb.append(" 0");
        System.out.println(sb);
        System.out.flush();
        System.exit(10);
    }
    static final class IntList { int[] a=new int[8]; int n; void add(int x){ if(n==a.length)a=Arrays.copyOf(a,n*2); a[n++]=x; } int[] toArray(){ return Arrays.copyOf(a,n);} }
}
