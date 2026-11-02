#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef struct { int size, lbd, deleted; int lits[]; } Clause;
typedef struct { Clause *c; int blk; } Watch;
typedef struct { Watch *a; int n, cap; } WL;

static int nv;
static WL *watches;
static signed char *val;      /* per literal: 1 true, -1 false, 0 unassigned */
static int *level, *trail, *tlim, *phase;
static Clause **reason;
static int tn, qh, nlev;
static double *act, inc = 1.0;
static int *heap, *hpos, hn;
static char *seen;
static Clause **learnts; static int nl, capl;
static int *stamp, stampc;

#define VAR(l) ((l)>>1)
static void wpush(WL *w, Clause *c, int b){
    if(w->n==w->cap){ w->cap=w->cap?w->cap*2:4; w->a=realloc(w->a,w->cap*sizeof(Watch)); }
    w->a[w->n].c=c; w->a[w->n].blk=b; w->n++;
}
/* heap */
static void hup(int i){ int v=heap[i]; while(i>0){int p=(i-1)/2; if(act[heap[p]]>=act[v])break; heap[i]=heap[p]; hpos[heap[i]]=i; i=p;} heap[i]=v; hpos[v]=i; }
static void hdown(int i){ int v=heap[i]; for(;;){int c=2*i+1; if(c>=hn)break; if(c+1<hn&&act[heap[c+1]]>act[heap[c]])c++; if(act[heap[c]]<=act[v])break; heap[i]=heap[c]; hpos[heap[i]]=i; i=c;} heap[i]=v; hpos[v]=i; }
static void hins(int v){ if(hpos[v]>=0)return; heap[hn]=v; hpos[v]=hn; hn++; hup(hn-1); }
static int hpop(void){ int v=heap[0]; hpos[v]=-1; hn--; if(hn>0){heap[0]=heap[hn]; hpos[heap[0]]=0; hdown(0);} return v; }
static void bump(int v){ if((act[v]+=inc)>1e100){ for(int i=0;i<nv;i++)act[i]*=1e-100; inc*=1e-100; } if(hpos[v]>=0)hup(hpos[v]); }

static void enqueue(int l, Clause *r){ val[l]=1; val[l^1]=-1; level[VAR(l)]=nlev; reason[VAR(l)]=r; trail[tn++]=l; }

static Clause *propagate(void){
    while(qh<tn){
        int p=trail[qh++], fl=p^1; WL *w=&watches[fl];
        int i=0,j=0;
        while(i<w->n){
            Watch x=w->a[i++];
            if(val[x.blk]>0){ w->a[j++]=x; continue; }
            Clause *c=x.c;
            if(c->deleted) continue;
            if(c->lits[0]==fl){ c->lits[0]=c->lits[1]; c->lits[1]=fl; }
            int f=c->lits[0];
            if(f!=x.blk && val[f]>0){ x.blk=f; w->a[j++]=x; continue; }
            int found=0;
            for(int k=2;k<c->size;k++) if(val[c->lits[k]]>=0){
                c->lits[1]=c->lits[k]; c->lits[k]=fl; wpush(&watches[c->lits[1]],c,f); found=1; break; }
            if(found) continue;
            x.blk=f; w->a[j++]=x;
            if(val[f]<0){
                while(i<w->n) w->a[j++]=w->a[i++];
                w->n=j; qh=tn; return c;
            }
            enqueue(f,c);
        }
        w->n=j;
    }
    return NULL;
}
static void backtrack(int lv){
    if(nlev<=lv) return;
    for(int i=tn-1;i>=tlim[lv];i--){ int l=trail[i], v=VAR(l); phase[v]=(l&1); val[l]=val[l^1]=0; reason[v]=NULL; hins(v); }
    tn=tlim[lv]; qh=tn; nlev=lv;
}
static Clause *newclause(int *lits,int n,int lbd){
    Clause *c=malloc(sizeof(Clause)+n*sizeof(int)); c->size=n; c->lbd=lbd; c->deleted=0;
    memcpy(c->lits,lits,n*sizeof(int)); return c;
}
static int *learnt; 
static int analyze(Clause *confl,int *outn,int *lbd){
    int n=1, pathc=0, p=-1, idx=tn-1;
    learnt[0]=0;
    do{
        for(int k=(p<0?0:1);k<confl->size;k++){
            int q=confl->lits[k], v=VAR(q);
            if(!seen[v] && level[v]>0){
                seen[v]=1; bump(v);
                if(level[v]>=nlev) pathc++; else learnt[n++]=q;
            }
        }
        while(!seen[VAR(trail[idx--])]);
        p=trail[idx+1]; confl=reason[VAR(p)]; seen[VAR(p)]=0; pathc--;
        if(pathc>0 && confl->lits[0]!=p){ /* ensure p at index 0 */
            for(int k=1;k<confl->size;k++) if(confl->lits[k]==p){ confl->lits[k]=confl->lits[0]; confl->lits[0]=p; break; }
        }
    }while(pathc>0);
    learnt[0]=p^1;
    /* minimize */
    static int *saved=NULL; if(!saved) saved=malloc((nv+1)*sizeof(int));
    memcpy(saved,learnt,n*sizeof(int));
    int j=1;
    for(int i=1;i<n;i++){
        Clause *r=reason[VAR(learnt[i])]; int keep=1;
        if(r){ keep=0; for(int k=0;k<r->size;k++){ int v=VAR(r->lits[k]); if(v==VAR(learnt[i]))continue; if(!seen[v]&&level[v]>0){keep=1;break;} } }
        if(keep) learnt[j++]=learnt[i];
    }
    for(int i=1;i<n;i++) seen[VAR(saved[i])]=0;
    n=j;
    int bt=0;
    if(n>1){ int mi=1; for(int i=2;i<n;i++) if(level[VAR(learnt[i])]>level[VAR(learnt[mi])]) mi=i;
        int t=learnt[1]; learnt[1]=learnt[mi]; learnt[mi]=t; bt=level[VAR(learnt[1])]; }
    stampc++; int d=0;
    for(int i=0;i<n;i++){ int lv=level[VAR(learnt[i])]; if(stamp[lv]!=stampc){stamp[lv]=stampc;d++;} }
    *lbd=d; *outn=n; return bt;
}
static int cmpc(const void *a,const void *b){
    const Clause *x=*(Clause*const*)a,*y=*(Clause*const*)b;
    if(x->lbd!=y->lbd) return y->lbd-x->lbd;
    return y->size-x->size;
}
static void reduce(void){
    qsort(learnts,nl,sizeof(Clause*),cmpc);
    int lim=nl/2, j=0;
    for(int i=0;i<nl;i++){
        Clause *c=learnts[i];
        int locked=(val[c->lits[0]]>0 && reason[VAR(c->lits[0])]==c);
        if(i<lim && c->lbd>2 && !locked) c->deleted=1; else learnts[j++]=c;
    }
    /* clean watches */
    for(int l=0;l<2*nv;l++){ WL *w=&watches[l]; int k=0;
        for(int i=0;i<w->n;i++) if(!w->a[i].c->deleted) w->a[k++]=w->a[i]; w->n=k; }
    /* free deleted: they are in the first part; rebuild by scanning old list is lost, so track */
    nl=j;
}
static double luby(int i){
    int size=1, seq=0; while(size<i+1){seq++; size=2*size+1;}
    int x=i; while(size-1!=x){ size=(size-1)>>1; seq--; x%=size; }
    double r=1; while(seq-->0) r*=2; return r;
}

int main(int argc,char **argv){
    if(argc<2){fprintf(stderr,"usage: solver FILE\n");return 2;}
    FILE *f=fopen(argv[1],"rb"); if(!f){perror("open");return 2;}
    fseek(f,0,SEEK_END); long sz=ftell(f); fseek(f,0,SEEK_SET);
    char *buf=malloc(sz+1); sz=fread(buf,1,sz,f); buf[sz]=0; fclose(f);
    int hv=0; long cap=1024, m=0; int *all=malloc(cap*sizeof(int));
    char *p=buf, *end=buf+sz;
    while(p<end){
        while(p<end && (*p==' '||*p=='\t'||*p=='\r'||*p=='\n')) p++;
        if(p>=end)break;
        if(*p=='c'||*p=='%'){ if(*p=='%')break; while(p<end&&*p!='\n')p++; continue; }
        if(*p=='p'){ int a=0,b=0; sscanf(p,"p cnf %d %d",&a,&b); hv=a; while(p<end&&*p!='\n')p++; continue; }
        char *e; long x=strtol(p,&e,10); if(e==p){p++;continue;} p=e;
        if(m==cap){cap*=2; all=realloc(all,cap*sizeof(int));}
        all[m++]=(int)x;
    }
    nv=hv; for(long i=0;i<m;i++){ int a=abs(all[i]); if(a>nv)nv=a; }
    int N=nv+1;
    watches=calloc(2*N,sizeof(WL)); val=calloc(2*N,1);
    level=calloc(N,sizeof(int)); trail=malloc(N*sizeof(int)); tlim=malloc((N+1)*sizeof(int));
    phase=calloc(N,sizeof(int)); reason=calloc(N,sizeof(Clause*)); act=calloc(N,sizeof(double));
    heap=malloc(N*sizeof(int)); hpos=malloc(N*sizeof(int)); seen=calloc(N,1);
    stamp=calloc(N+2,sizeof(int)); learnt=malloc((N+1)*sizeof(int));
    for(int i=0;i<N;i++){hpos[i]=-1;phase[i]=1;}
    for(int v=0;v<nv;v++) hins(v);
    int unsat=0;
    int *tmp=malloc((nv+2)*sizeof(int));
    Clause **orig=NULL; long no=0, ocap=0;
    for(long i=0;i<m && !unsat;){
        int n=0, taut=0;
        while(i<m && all[i]!=0){
            int x=all[i++]; int l=2*(abs(x)-1)+(x<0);
            for(int k=0;k<n;k++){ if(tmp[k]==l) goto dup; if(tmp[k]==(l^1)) taut=1; }
            tmp[n++]=l; dup:;
        }
        i++;
        if(taut) continue;
        if(n==0){unsat=1;break;}
        if(n==1){ if(val[tmp[0]]<0){unsat=1;break;} if(val[tmp[0]]==0) enqueue(tmp[0],NULL); continue; }
        Clause *c=newclause(tmp,n,0);
        if(no==ocap){ocap=ocap?ocap*2:1024; orig=realloc(orig,ocap*sizeof(Clause*));}
        orig[no++]=c;
        wpush(&watches[c->lits[0]],c,c->lits[1]); wpush(&watches[c->lits[1]],c,c->lits[0]);
    }
    if(!unsat && propagate()) unsat=1;
    if(unsat){ puts("s UNSATISFIABLE"); return 20; }
    long conflicts=0; int restarts=0; long limit=64*(long)luby(0); long cc=0;
    long maxl=nv/3+4000; capl=1024; learnts=malloc(capl*sizeof(Clause*));
    for(;;){
        Clause *c=propagate();
        if(c){
            conflicts++; cc++;
            if(nlev==0){ puts("s UNSATISFIABLE"); return 20; }
            int n,lbd; int bt=analyze(c,&n,&lbd);
            backtrack(bt);
            if(n==1){ enqueue(learnt[0],NULL); }
            else{
                Clause *lc=newclause(learnt,n,lbd);
                if(nl==capl){capl*=2; learnts=realloc(learnts,capl*sizeof(Clause*));}
                learnts[nl++]=lc;
                wpush(&watches[lc->lits[0]],lc,lc->lits[1]); wpush(&watches[lc->lits[1]],lc,lc->lits[0]);
                enqueue(learnt[0],lc);
            }
            inc*=1/0.95;
        } else {
            if(cc>=limit){ cc=0; restarts++; limit=64*(long)luby(restarts); backtrack(0); }
            if(nl>=maxl){ 
                /* collect deleted for freeing: mark then free after cleaning */
                Clause **old=malloc(nl*sizeof(Clause*)); int on=nl; memcpy(old,learnts,nl*sizeof(Clause*));
                reduce();
                for(int i=0;i<on;i++) if(old[i]->deleted) free(old[i]);
                free(old); maxl+=maxl/10+300;
            }
            int v=-1;
            while(hn>0){ int x=hpop(); if(val[2*x]==0){v=x;break;} }
            if(v<0) break;
            tlim[nlev]=tn; nlev++;
            enqueue(2*v+phase[v],NULL);
        }
    }
    /* phase: phase[v]=1 initially means true; saved as (l&1) i.e. 1 = negative. handled below */
    for(long i=0;i<no;i++){ Clause *c=orig[i]; int ok=0; for(int k=0;k<c->size;k++) if(val[c->lits[k]]>0){ok=1;break;} if(!ok){fprintf(stderr,"internal error\n");return 3;} }
    puts("s SATISFIABLE");
    int col=0; printf("v");
    for(int v=0;v<nv;v++){ int x=val[2*v]>0?v+1:-(v+1); col+=printf(" %d",x); if(col>60){printf("\nv");col=0;} }
    printf(" 0\n");
    return 10;
}
