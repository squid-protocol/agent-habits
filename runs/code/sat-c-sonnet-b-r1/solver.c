#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct Clause { int size, learnt, lbd, deleted; double act; int lits[]; } Clause;
typedef struct { Clause *c; int blk; } Watch;
typedef struct { Watch *a; int n, cap; } WL;

static int nv;
static WL *watches;
static signed char *val;      /* by literal */
static int *level, *trail, trail_n, qhead, *tlim, nlev;
static Clause **reason;
static double *act, var_inc = 1.0, cla_inc = 1.0;
static signed char *phase, *seen;
static int *heap, heap_n, *hpos;
static Clause **learnts; static int nlearnts, caplearnts;
static Clause **origs; static int norig, caporig;
static int *stamp, stampc;

#define VAR(l) ((l)>>1)
#define NEG(l) ((l)^1)

static void wpush(WL *w, Clause *c, int b){
  if(w->n==w->cap){ w->cap=w->cap?w->cap*2:4; w->a=realloc(w->a,w->cap*sizeof(Watch)); }
  w->a[w->n].c=c; w->a[w->n].blk=b; w->n++;
}
/* heap */
static void hup(int i){ int v=heap[i]; while(i>0){ int p=(i-1)/2; if(act[heap[p]]>=act[v])break; heap[i]=heap[p]; hpos[heap[i]]=i; i=p;} heap[i]=v; hpos[v]=i; }
static void hdown(int i){ int v=heap[i]; for(;;){ int c=2*i+1; if(c>=heap_n)break; if(c+1<heap_n&&act[heap[c+1]]>act[heap[c]])c++; if(act[heap[c]]<=act[v])break; heap[i]=heap[c]; hpos[heap[i]]=i; i=c;} heap[i]=v; hpos[v]=i; }
static void hins(int v){ if(hpos[v]>=0)return; heap[heap_n]=v; hpos[v]=heap_n; heap_n++; hup(heap_n-1); }
static int hpop(void){ int v=heap[0]; heap_n--; hpos[v]=-1; if(heap_n>0){ heap[0]=heap[heap_n]; hpos[heap[0]]=0; hdown(0);} return v; }
static void bump(int v){ if((act[v]+=var_inc)>1e100){ for(int i=1;i<=nv;i++)act[i]*=1e-100; var_inc*=1e-100;} if(hpos[v]>=0)hup(hpos[v]); }

static void enqueue(int l, Clause *r){ val[l]=1; val[NEG(l)]=-1; level[VAR(l)]=nlev; reason[VAR(l)]=r; trail[trail_n++]=l; }

static Clause *propagate(void){
  while(qhead<trail_n){
    int p=trail[qhead++], fl=NEG(p);
    WL *w=&watches[fl]; Watch *a=w->a; int i=0,j=0,n=w->n;
    while(i<n){
      Watch wt=a[i++];
      if(val[wt.blk]==1){ a[j++]=wt; continue; }
      Clause *c=wt.c; int *L=c->lits;
      if(L[0]==fl){ L[0]=L[1]; L[1]=fl; }
      int f=L[0];
      if(f!=wt.blk && val[f]==1){ wt.blk=f; a[j++]=wt; continue; }
      int found=0;
      for(int k=2;k<c->size;k++) if(val[L[k]]!=-1){
        L[1]=L[k]; L[k]=fl; wpush(&watches[L[1]],c,f); found=1; break; }
      if(found) continue;
      wt.blk=f; a[j++]=wt;
      if(val[f]==-1){
        while(i<n)a[j++]=a[i++];
        w->n=j; qhead=trail_n; return c;
      }
      enqueue(f,c);
    }
    w->n=j;
  }
  return NULL;
}

static void cancel(int lv){
  if(nlev<=lv)return;
  for(int i=trail_n-1;i>=tlim[lv];i--){ int l=trail[i],v=VAR(l); phase[v]=!(l&1); val[l]=val[NEG(l)]=0; reason[v]=NULL; hins(v); }
  trail_n=tlim[lv]; qhead=trail_n; nlev=lv;
}

static int *learnt_buf, *stk;
static Clause *newclause(int *lits,int n,int learnt){
  Clause *c=malloc(sizeof(Clause)+n*sizeof(int));
  c->size=n; c->learnt=learnt; c->lbd=0; c->deleted=0; c->act=0;
  memcpy(c->lits,lits,n*sizeof(int));
  wpush(&watches[c->lits[0]],c,c->lits[1]);
  wpush(&watches[c->lits[1]],c,c->lits[0]);
  return c;
}

static int analyze(Clause *confl,int *out_n,int *lbd){
  int n=1, pathc=0, p=-1, idx=trail_n-1;
  do{
    if(confl->learnt){ if((confl->act+=cla_inc)>1e20){ for(int i=0;i<nlearnts;i++)learnts[i]->act*=1e-20; cla_inc*=1e-20; } }
    for(int k=(p==-1?0:1);k<confl->size;k++){
      int q=confl->lits[k], v=VAR(q);
      if(!seen[v]&&level[v]>0){
        seen[v]=1; bump(v);
        if(level[v]>=nlev)pathc++; else learnt_buf[n++]=q;
      }
    }
    while(!seen[VAR(trail[idx])])idx--;
    p=trail[idx--]; confl=reason[VAR(p)]; seen[VAR(p)]=0; pathc--;
    if(pathc>0 && confl->lits[0]!=p){ /* ensure p at index 0 */
      for(int k=1;k<confl->size;k++) if(confl->lits[k]==p){ confl->lits[k]=confl->lits[0]; confl->lits[0]=p; break; }
    }
  }while(pathc>0);
  learnt_buf[0]=NEG(p);
  /* minimize (local) */
  int m=1; memcpy(stk,learnt_buf,n*sizeof(int));
  for(int i=1;i<n;i++){
    int v=VAR(learnt_buf[i]); Clause *r=reason[v]; int keep=1;
    if(r){ keep=0; for(int k=0;k<r->size;k++){ int u=VAR(r->lits[k]); if(u==v)continue; if(!seen[u]&&level[u]>0){keep=1;break;} } }
    if(keep)learnt_buf[m++]=learnt_buf[i];
  }
  for(int i=1;i<n;i++)seen[VAR(stk[i])]=0;
  n=m;
  int bl=0;
  if(n>1){ int mi=1; for(int i=2;i<n;i++) if(level[VAR(learnt_buf[i])]>level[VAR(learnt_buf[mi])])mi=i;
    int t=learnt_buf[1]; learnt_buf[1]=learnt_buf[mi]; learnt_buf[mi]=t; bl=level[VAR(learnt_buf[1])]; }
  stampc++; int d=0;
  for(int i=0;i<n;i++){ int lv=level[VAR(learnt_buf[i])]; if(stamp[lv]!=stampc){stamp[lv]=stampc;d++;} }
  *lbd=d; *out_n=n; return bl;
}

static int cmpc(const void*a,const void*b){
  Clause *x=*(Clause**)a,*y=*(Clause**)b;
  if(x->lbd!=y->lbd)return y->lbd-x->lbd;
  return (x->act<y->act)?-1:(x->act>y->act);
}
static void reduce(void){
  qsort(learnts,nlearnts,sizeof(Clause*),cmpc);
  int lim=nlearnts/2, j=0;
  for(int i=0;i<nlearnts;i++){
    Clause *c=learnts[i];
    int locked=reason[VAR(c->lits[0])]==c && val[c->lits[0]]==1;
    if(i<lim && c->lbd>2 && c->size>2 && !locked) c->deleted=1; else learnts[j++]=c;
  }
  int old=nlearnts; nlearnts=j; (void)old;
  for(int l=0;l<2*nv+2;l++){ WL*w=&watches[l]; int k=0; for(int i=0;i<w->n;i++) if(!w->a[i].c->deleted) w->a[k++]=w->a[i]; w->n=k; }
  /* free deleted: we need list; recollect from sorted prefix */
}

static long luby(long i){ long k=1; while(((1L<<k)-1)<i+1)k++; /* find */
  for(;;){ if(i+1==(1L<<k)-1)return 1L<<(k-1); i-=(1L<<(k-1))-1; k=1; while(((1L<<k)-1)<i+1)k++; } }

int main(int argc,char**argv){
  if(argc<2){fprintf(stderr,"usage\n");return 1;}
  FILE*f=fopen(argv[1],"rb"); if(!f){perror("open");return 1;}
  fseek(f,0,SEEK_END); long sz=ftell(f); fseek(f,0,SEEK_SET);
  char*buf=malloc(sz+1); sz=fread(buf,1,sz,f); buf[sz]=0; fclose(f);
  int hv=0; long cap=1024,tot=0; int *all=malloc(cap*sizeof(int));
  char*p=buf;
  while(*p){
    while(*p==' '||*p=='\t'||*p=='\n'||*p=='\r')p++;
    if(!*p)break;
    if(*p=='c'||*p=='%'){ if(*p=='%')break; while(*p&&*p!='\n')p++; continue; }
    if(*p=='p'){ char*q=p; while(*q&&*q!='\n')q++; char t[16]; int nc; if(sscanf(p,"p %15s %d %d",t,&hv,&nc)<2)hv=0; p=q; continue; }
    char*e; long x=strtol(p,&e,10); if(e==p){p++;continue;} p=e;
    if(tot==cap){cap*=2;all=realloc(all,cap*sizeof(int));}
    all[tot++]=(int)x;
  }
  nv=hv; for(long i=0;i<tot;i++){int a=abs(all[i]); if(a>nv)nv=a;}
  int N=nv+1;
  watches=calloc(2*N+2,sizeof(WL)); val=calloc(2*N+2,1);
  level=calloc(N,sizeof(int)); trail=malloc(N*sizeof(int)); tlim=malloc((N+2)*sizeof(int));
  reason=calloc(N,sizeof(Clause*)); act=calloc(N,sizeof(double)); phase=calloc(N,1); seen=calloc(N,1);
  heap=malloc(N*sizeof(int)); hpos=malloc(N*sizeof(int)); learnt_buf=malloc((N+1)*sizeof(int)); stk=malloc((N+1)*sizeof(int));
  stamp=calloc(N+2,sizeof(int));
  for(int i=0;i<N;i++)hpos[i]=-1;
  for(int v=1;v<=nv;v++)hins(v);
  int unsat=0;
  /* load clauses */
  int *cl=malloc((N+1)*sizeof(int)); signed char *mark=calloc(2*N+2,1);
  long i=0;
  while(i<tot){
    int n=0,taut=0;
    while(i<tot&&all[i]!=0){ int x=all[i++]; int l=2*abs(x)+(x<0);
      if(mark[NEG(l)])taut=1; if(!mark[l]){mark[l]=1;cl[n++]=l;} }
    i++;
    for(int k=0;k<n;k++)mark[cl[k]]=0;
    if(taut)continue;
    if(n==0){unsat=1;break;}
    if(n==1){ if(val[cl[0]]==-1){unsat=1;break;} if(val[cl[0]]==0)enqueue(cl[0],NULL); continue; }
    Clause*c=newclause(cl,n,0);
    if(norig==caporig){caporig=caporig?caporig*2:1024;origs=realloc(origs,caporig*sizeof(Clause*));}
    origs[norig++]=c;
  }
  if(!unsat && propagate())unsat=1;
  if(unsat){ puts("s UNSATISFIABLE"); return 20; }
  long conflicts=0, restart_i=0, next_restart=100*luby(0), since=0, max_learnts=nv/3+5000>norig/3?nv/3+5000:norig/3;
  if(max_learnts<5000)max_learnts=5000;
  long reduce_at=max_learnts;
  srand(12345);
  for(;;){
    Clause*confl=propagate();
    if(confl){
      conflicts++; since++;
      if(nlev==0){ puts("s UNSATISFIABLE"); return 20; }
      int n,lbd; int bl=analyze(confl,&n,&lbd);
      cancel(bl);
      if(n==1) enqueue(learnt_buf[0],NULL);
      else{
        Clause*c=newclause(learnt_buf,n,1); c->lbd=lbd; c->act=cla_inc;
        if(nlearnts==caplearnts){caplearnts=caplearnts?caplearnts*2:1024;learnts=realloc(learnts,caplearnts*sizeof(Clause*));}
        learnts[nlearnts++]=c;
        enqueue(learnt_buf[0],c);
      }
      var_inc/=0.95; cla_inc/=0.999;
    } else {
      if(since>=next_restart){ since=0; restart_i++; next_restart=100*luby(restart_i); cancel(0); }
      if(conflicts>=reduce_at){
        /* mark and free deleted */
        Clause **old=malloc(nlearnts*sizeof(Clause*)); int on=nlearnts; memcpy(old,learnts,on*sizeof(Clause*));
        reduce();
        for(int k=0;k<on;k++) if(old[k]->deleted) free(old[k]);
        free(old);
        reduce_at=conflicts+max_learnts/2+ conflicts/10;
      }
      int v=0;
      while(heap_n>0){ int u=hpop(); if(val[2*u]==0){v=u;break;} }
      if(!v)break;
      tlim[nlev++]=trail_n;
      enqueue(2*v+(phase[v]?0:1),NULL);
    }
  }
  /* verify */
  for(int k=0;k<norig;k++){ Clause*c=origs[k]; int ok=0; for(int j=0;j<c->size;j++) if(val[c->lits[j]]==1){ok=1;break;} if(!ok){fprintf(stderr,"internal error\n");return 1;} }
  puts("s SATISFIABLE");
  int col=0; printf("v");
  for(int v=1;v<=nv;v++){ printf(" %d",val[2*v]==1?v:-v); if(++col%15==0)printf("\nv"); }
  printf(" 0\n");
  return 10;
}
