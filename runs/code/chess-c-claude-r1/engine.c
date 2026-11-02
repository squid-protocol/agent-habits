#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <poll.h>
#include <unistd.h>

typedef unsigned long long U64;
typedef int Move;
typedef struct { signed char b[128]; int side, castle, ep, half, ksq[2]; U64 hash; } Pos;

#define MV(f,t,p,fl) ((f)|((t)<<8)|((p)<<16)|((fl)<<20))
#define FROM(m) ((m)&255)
#define TO(m) (((m)>>8)&255)
#define PROMO(m) (((m)>>16)&15)
#define FLAG(m) ((m)>>20)
#define F_EP 1
#define F_CASTLE 2
#define MATE 30000
#define MAXPLY 128

static U64 Zp[16][128], Zc[16], Zs, Ze[8];
static int cmask[128];
static const int kn[8]={33,31,18,14,-33,-31,-18,-14};
static const int kg[8]={1,-1,16,-16,15,-15,17,-17};
static const int bd[4]={15,-15,17,-17};
static const int rd[4]={1,-1,16,-16};
static const int pval[7]={0,100,320,330,500,900,0};

static U64 rng=88172645463325252ULL;
static U64 rnd(void){rng^=rng<<13;rng^=rng>>7;rng^=rng<<17;return rng;}

static void init_tables(void){
  for(int i=0;i<16;i++)for(int j=0;j<128;j++)Zp[i][j]=rnd();
  for(int i=0;i<16;i++)Zc[i]=rnd();
  Zs=rnd();for(int i=0;i<8;i++)Ze[i]=rnd();
  for(int i=0;i<128;i++)cmask[i]=15;
  cmask[0]=~2&15;cmask[4]=~3&15;cmask[7]=~1&15;
  cmask[0x70]=~8&15;cmask[0x74]=~12&15;cmask[0x77]=~4&15;
}

static U64 hash_calc(Pos*p){
  U64 h=0;
  for(int s=0;s<128;s++){if(s&0x88)continue;if(p->b[s])h^=Zp[(int)p->b[s]][s];}
  h^=Zc[p->castle];
  if(p->ep>=0)h^=Ze[p->ep&7];
  if(p->side)h^=Zs;
  return h;
}

static int attacked(const Pos*p,int sq,int by){
  const signed char*b=p->b;
  int base=by*8;
  if(by==0){
    int s=sq-15;if(!(s&0x88)&&b[s]==1)return 1;
    s=sq-17;if(!(s&0x88)&&b[s]==1)return 1;
  }else{
    int s=sq+15;if(!(s&0x88)&&b[s]==9)return 1;
    s=sq+17;if(!(s&0x88)&&b[s]==9)return 1;
  }
  for(int i=0;i<8;i++){
    int s=sq+kn[i];if(!(s&0x88)&&b[s]==base+2)return 1;
    s=sq+kg[i];if(!(s&0x88)&&b[s]==base+6)return 1;
  }
  for(int i=0;i<4;i++){
    int s=sq+bd[i];
    while(!(s&0x88)){if(b[s]){if(b[s]==base+3||b[s]==base+5)return 1;break;}s+=bd[i];}
    s=sq+rd[i];
    while(!(s&0x88)){if(b[s]){if(b[s]==base+4||b[s]==base+5)return 1;break;}s+=rd[i];}
  }
  return 0;
}

static int incheck(const Pos*p){return attacked(p,p->ksq[p->side],p->side^1);}

static void make(Pos*p,Move m){
  int from=FROM(m),to=TO(m),pr=PROMO(m),fl=FLAG(m),us=p->side;
  int pc=p->b[from],cap=p->b[to];
  U64 h=p->hash;
  if(p->ep>=0)h^=Ze[p->ep&7];
  p->ep=-1;
  if(cap)h^=Zp[cap][to];
  h^=Zp[pc][from];p->b[from]=0;
  if(fl==F_EP){int cs=to+(us?16:-16);h^=Zp[(int)p->b[cs]][cs];p->b[cs]=0;}
  if(pr)pc=us*8+pr;
  p->b[to]=pc;h^=Zp[pc][to];
  if((pc&7)==1&&(to-from==32||from-to==32)){p->ep=(from+to)/2;h^=Ze[p->ep&7];}
  if(fl==F_CASTLE){
    int rf,rt;
    if(to>from){rf=to+1;rt=to-1;}else{rf=to-2;rt=to+1;}
    int r=p->b[rf];h^=Zp[r][rf]^Zp[r][rt];p->b[rt]=r;p->b[rf]=0;
  }
  h^=Zc[p->castle];
  p->castle&=cmask[from]&cmask[to];
  h^=Zc[p->castle];
  if((pc&7)==6)p->ksq[us]=to;
  if((p->b[to]&7)==1||cap||fl==F_EP)p->half=0;else p->half++;
  p->side^=1;h^=Zs;
  p->hash=h;
}

static int addm(Move*l,int n,Move m){l[n]=m;return n+1;}

static int gen(const Pos*p,Move*l,int caps){
  int n=0,us=p->side;
  const signed char*b=p->b;
  for(int sq=0;sq<128;sq++){
    if(sq&0x88){sq+=7;continue;}
    int pc=b[sq];
    if(!pc||(pc>>3)!=us)continue;
    int t=pc&7;
    if(t==1){
      int dir=us?-16:16,sr=us?6:1,pr=us?0:7;
      int to=sq+dir;
      if(!(to&0x88)&&!b[to]){
        if((to>>4)==pr){for(int q=5;q>=2;q--)n=addm(l,n,MV(sq,to,q,0));}
        else if(!caps){
          n=addm(l,n,MV(sq,to,0,0));
          if((sq>>4)==sr&&!b[to+dir])n=addm(l,n,MV(sq,to+dir,0,0));
        }
      }
      for(int k=-1;k<=1;k+=2){
        to=sq+dir+k;if(to&0x88)continue;
        if(b[to]&&(b[to]>>3)!=us){
          if((to>>4)==pr){for(int q=5;q>=2;q--)n=addm(l,n,MV(sq,to,q,0));}
          else n=addm(l,n,MV(sq,to,0,0));
        }else if(to==p->ep)n=addm(l,n,MV(sq,to,0,F_EP));
      }
    }else if(t==2||t==6){
      const int*o=t==2?kn:kg;
      for(int i=0;i<8;i++){
        int to=sq+o[i];if(to&0x88)continue;
        if(!b[to]){if(!caps)n=addm(l,n,MV(sq,to,0,0));}
        else if((b[to]>>3)!=us)n=addm(l,n,MV(sq,to,0,0));
      }
    }else{
      for(int d=0;d<8;d++){
        int dd;
        if(d<4){if(t==4)continue;dd=bd[d];}
        else{if(t==3)continue;dd=rd[d-4];}
        int to=sq+dd;
        while(!(to&0x88)){
          if(!b[to]){if(!caps)n=addm(l,n,MV(sq,to,0,0));}
          else{if((b[to]>>3)!=us)n=addm(l,n,MV(sq,to,0,0));break;}
          to+=dd;
        }
      }
    }
  }
  if(!caps){
    if(us==0&&p->b[4]==6){
      if((p->castle&1)&&!b[5]&&!b[6]&&b[7]==4&&!attacked(p,4,1)&&!attacked(p,5,1)&&!attacked(p,6,1))n=addm(l,n,MV(4,6,0,F_CASTLE));
      if((p->castle&2)&&!b[3]&&!b[2]&&!b[1]&&b[0]==4&&!attacked(p,4,1)&&!attacked(p,3,1)&&!attacked(p,2,1))n=addm(l,n,MV(4,2,0,F_CASTLE));
    }else if(us==1&&p->b[0x74]==14){
      if((p->castle&4)&&!b[0x75]&&!b[0x76]&&b[0x77]==12&&!attacked(p,0x74,0)&&!attacked(p,0x75,0)&&!attacked(p,0x76,0))n=addm(l,n,MV(0x74,0x76,0,F_CASTLE));
      if((p->castle&8)&&!b[0x73]&&!b[0x72]&&!b[0x71]&&b[0x70]==12&&!attacked(p,0x74,0)&&!attacked(p,0x73,0)&&!attacked(p,0x72,0))n=addm(l,n,MV(0x74,0x72,0,F_CASTLE));
    }
  }
  return n;
}

static int legal(const Pos*p,Move m,Pos*out){
  *out=*p;make(out,m);
  return !attacked(out,out->ksq[p->side],p->side^1);
}

static void mstr(Move m,char*s){
  s[0]='a'+(FROM(m)&7);s[1]='1'+(FROM(m)>>4);
  s[2]='a'+(TO(m)&7);s[3]='1'+(TO(m)>>4);
  int pr=PROMO(m);
  if(pr){s[4]="?pnbrq"[pr];s[5]=0;}else s[4]=0;
}

/* ---------- eval ---------- */
static int iabs(int x){return x<0?-x:x;}
static int cdist(int sq){int f=sq&7,r=sq>>4;int a=iabs(2*f-7),c=iabs(2*r-7);return a>c?a:c;}

static int eval(const Pos*p){
  int sc[2]={0,0},npm[2]={0,0},pawns[2]={0,0},bishops[2]={0,0};
  int ks[2]={0,0};
  int pf[2][8]={{0}};
  for(int sq=0;sq<128;sq++){
    if(sq&0x88){sq+=7;continue;}
    int pc=p->b[sq];if(!pc)continue;
    int c=pc>>3,t=pc&7;
    int f=sq&7,r=sq>>4,rr=c?7-r:r,cd=cdist(sq);
    int v=0;
    switch(t){
      case 1:v=100+(rr-1)*6+((f==3||f==4)?(rr<5?10:0):((f==2||f==5)?(rr<5?4:0):0));
        if(rr>=5)v+=(rr-4)*12;
        pawns[c]++;pf[c][f]++;break;
      case 2:v=320+(7-cd)*5;npm[c]+=320;break;
      case 3:v=330+(7-cd)*2;npm[c]+=330;bishops[c]++;break;
      case 4:v=500+(rr==6?15:0);npm[c]+=500;break;
      case 5:v=900+(7-cd);npm[c]+=900;break;
      case 6:ks[c]=sq;continue;
    }
    sc[c]+=v;
  }
  if(!pawns[0]&&!pawns[1]&&npm[0]<=330&&npm[1]<=330)return 0;
  if(bishops[0]>=2)sc[0]+=30;
  if(bishops[1]>=2)sc[1]+=30;
  int ph=npm[0]+npm[1];if(ph>5000)ph=5000;
  for(int c=0;c<2;c++){
    int sq=ks[c],cd=cdist(sq),r=sq>>4,rr=c?7-r:r;
    int mg=cd*4-rr*15;
    int eg=(7-cd)*8;
    sc[c]+=(mg*ph+eg*(5000-ph))/5000;
  }
  int s=sc[0]-sc[1];
  /* mop-up */
  for(int c=0;c<2;c++){
    int w=c^1;
    if((sc[c]-sc[w])>300&&npm[w]==0){
      int d=iabs((ks[0]&7)-(ks[1]&7))+iabs((ks[0]>>4)-(ks[1]>>4));
      int bonus=cdist(ks[w])*8+(14-d)*4;
      s+=c==0?bonus:-bonus;
    }
  }
  s+=p->side?-10:10;
  return p->side?-s:s;
}

/* ---------- input ---------- */
static char ibuf[1<<16];static int ilen=0,ieof=0;
static void fill(int block){
  if(ieof||ilen>=(int)sizeof(ibuf)-1)return;
  struct pollfd pf={0,POLLIN,0};
  int r=poll(&pf,1,block?-1:0);
  if(r>0){
    int n=read(0,ibuf+ilen,sizeof(ibuf)-1-ilen);
    if(n<=0)ieof=1;else ilen+=n;
  }
}
static int getl(char*out,int max){
  for(;;){
    for(int i=0;i<ilen;i++)if(ibuf[i]=='\n'){
      int n=i<max-1?i:max-1;memcpy(out,ibuf,n);out[n]=0;
      if(n>0&&out[n-1]=='\r')out[n-1]=0;
      memmove(ibuf,ibuf+i+1,ilen-i-1);ilen-=i+1;return 1;
    }
    if(ieof)return 0;
    fill(1);
  }
}

/* ---------- search ---------- */
typedef struct{U64 key;short score;Move move;signed char depth;unsigned char flag;}TT;
#define TTN (1<<20)
static TT*tt;
static U64 rephash[2048];static int rep_n=0;
static Move killers[MAXPLY][2];
static int history[16][128];
static long long nodes;
static int stopflag,quitflag,timed;
static double tstart,hardlim;
static Move rootbest;
static int maxdepth_limit;

static double now(void){struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);return ts.tv_sec*1000.0+ts.tv_nsec/1e6;}

static void checkstop(void){
  fill(0);
  if(ieof){stopflag=1;quitflag=1;return;}
  for(int i=0;i<ilen;){
    int j=i;while(j<ilen&&ibuf[j]!='\n')j++;
    if(j-i>=4&&!strncmp(ibuf+i,"stop",4))stopflag=1;
    if(j-i>=4&&!strncmp(ibuf+i,"quit",4)){stopflag=1;quitflag=1;}
    i=j+1;
  }
  if(timed&&now()-tstart>=hardlim)stopflag=1;
}

static int mscore(const Pos*p,Move m,Move ttm,int ply){
  if(m==ttm)return 10000000;
  int from=FROM(m),to=TO(m);
  int vic=p->b[to]&7,att=p->b[from]&7;
  if(FLAG(m)==F_EP)vic=1;
  int s=0;
  if(vic)s=100000+vic*10-att;
  if(PROMO(m))s+=90000+PROMO(m);
  if(s)return s;
  if(ply<MAXPLY){if(m==killers[ply][0])return 80000;if(m==killers[ply][1])return 79000;}
  return history[(int)p->b[from]][to];
}

static int qsearch(Pos*p,int alpha,int beta,int ply){
  nodes++;if((nodes&2047)==0)checkstop();
  if(stopflag)return 0;
  int stand=eval(p);
  if(ply>=MAXPLY-1)return stand;
  if(stand>=beta)return stand;
  if(stand>alpha)alpha=stand;
  Move l[256];int sc[256];
  int n=gen(p,l,1);
  for(int i=0;i<n;i++)sc[i]=mscore(p,l[i],0,MAXPLY);
  for(int i=0;i<n;i++){
    int bi=i;for(int j=i+1;j<n;j++)if(sc[j]>sc[bi])bi=j;
    int ts=sc[i];sc[i]=sc[bi];sc[bi]=ts;Move tm=l[i];l[i]=l[bi];l[bi]=tm;
    Pos np;if(!legal(p,l[i],&np))continue;
    int s=-qsearch(&np,-beta,-alpha,ply+1);
    if(stopflag)return 0;
    if(s>stand){stand=s;if(s>alpha){alpha=s;if(s>=beta)return s;}}
  }
  return stand;
}

static int search(Pos*p,int depth,int alpha,int beta,int ply,int nullok){
  int chk=incheck(p);
  if(ply>0){
    if(p->half>=100)return 0;
    int lim=rep_n-1-p->half;if(lim<0)lim=0;
    for(int i=rep_n-3;i>=lim;i-=2)if(rephash[i]==p->hash)return 0;
  }
  if(chk)depth++;
  if(depth<=0||ply>=MAXPLY-1)return qsearch(p,alpha,beta,ply);
  nodes++;if((nodes&2047)==0)checkstop();
  if(stopflag)return 0;
  int orig=alpha;
  TT*e=&tt[p->hash&(TTN-1)];
  Move ttm=0;
  if(e->key==p->hash){
    ttm=e->move;
    if(ply>0&&e->depth>=depth){
      int s=e->score;
      if(s>MATE-200)s-=ply;else if(s<-MATE+200)s+=ply;
      if(e->flag==0)return s;
      if(e->flag==1&&s>=beta)return s;
      if(e->flag==2&&s<=alpha)return s;
    }
  }
  if(nullok&&!chk&&depth>=3&&beta<MATE-300){
    int us=p->side,np_=0;
    for(int sq=0;sq<128;sq++){if(sq&0x88){sq+=7;continue;}int pc=p->b[sq];if(pc&&(pc>>3)==us&&(pc&7)>1&&(pc&7)<6)np_=1;}
    if(np_&&eval(p)>=beta){
      Pos q=*p;
      if(q.ep>=0)q.hash^=Ze[q.ep&7];
      q.ep=-1;q.side^=1;q.hash^=Zs;q.half++;
      rephash[rep_n++]=q.hash;
      int s=-search(&q,depth-3,-beta,-beta+1,ply+1,0);
      rep_n--;
      if(stopflag)return 0;
      if(s>=beta)return s>MATE-300?beta:s;
    }
  }
  Move l[256];int sc[256];
  int n=gen(p,l,0);
  for(int i=0;i<n;i++)sc[i]=mscore(p,l[i],ttm,ply);
  int best=-MATE-1;Move bm=0;int moves=0;
  for(int i=0;i<n;i++){
    int bi=i;for(int j=i+1;j<n;j++)if(sc[j]>sc[bi])bi=j;
    int ts=sc[i];sc[i]=sc[bi];sc[bi]=ts;Move tm=l[i];l[i]=l[bi];l[bi]=tm;
    Move m=l[i];
    Pos np;if(!legal(p,m,&np))continue;
    moves++;
    int quiet=!p->b[TO(m)]&&!PROMO(m)&&FLAG(m)!=F_EP;
    rephash[rep_n++]=np.hash;
    int s;
    if(moves==1)s=-search(&np,depth-1,-beta,-alpha,ply+1,1);
    else{
      int red=0;
      if(moves>4&&depth>=3&&!chk&&quiet&&!incheck(&np))red=1;
      s=-search(&np,depth-1-red,-alpha-1,-alpha,ply+1,1);
      if(s>alpha&&red)s=-search(&np,depth-1,-alpha-1,-alpha,ply+1,1);
      if(s>alpha&&s<beta)s=-search(&np,depth-1,-beta,-alpha,ply+1,1);
    }
    rep_n--;
    if(stopflag)return 0;
    if(s>best){
      best=s;bm=m;if(ply==0)rootbest=m;
      if(s>alpha){
        alpha=s;
        if(s>=beta){
          if(quiet&&ply<MAXPLY){
            if(killers[ply][0]!=m){killers[ply][1]=killers[ply][0];killers[ply][0]=m;}
            history[(int)p->b[FROM(m)]][TO(m)]+=depth*depth;
            if(history[(int)p->b[FROM(m)]][TO(m)]>70000)memset(history,0,sizeof history);
          }
          break;
        }
      }
    }
  }
  if(!moves)return chk?-MATE+ply:0;
  int st=best;
  if(st>MATE-200)st+=ply;else if(st<-MATE+200)st-=ply;
  e->key=p->hash;e->score=st;e->move=bm;e->depth=depth;
  e->flag=best<=orig?2:(best>=beta?1:0);
  return best;
}

static Pos pos;

static void think(double softms,int maxd){
  Pos root=pos;
  nodes=0;stopflag=0;
  memset(killers,0,sizeof killers);
  Move l[256];Pos t;int n=gen(&root,l,0),nl=0;Move first=0;
  for(int i=0;i<n;i++)if(legal(&root,l[i],&t)){nl++;if(!first)first=l[i];}
  Move best=first;
  if(nl==0){printf("bestmove 0000\n");fflush(stdout);return;}
  int base_rep=rep_n;
  for(int d=1;d<=maxd;d++){
    rootbest=0;
    int s=search(&root,d,-MATE-1,MATE+1,0,0);
    rep_n=base_rep;
    if(stopflag&&d>1)break;
    if(rootbest)best=rootbest;
    char ms[8];mstr(best,ms);
    double el=now()-tstart;
    if(s>MATE-200)printf("info depth %d score mate %d nodes %lld time %d pv %s\n",d,(MATE-s+1)/2,nodes,(int)el,ms);
    else if(s<-MATE+200)printf("info depth %d score mate %d nodes %lld time %d pv %s\n",d,-(MATE+s+1)/2,nodes,(int)el,ms);
    else printf("info depth %d score cp %d nodes %lld time %d pv %s\n",d,s,nodes,(int)el,ms);
    fflush(stdout);
    if(stopflag)break;
    if(nl==1&&timed)break;
    if(timed&&el>softms)break;
    if(s>MATE-200&&(MATE-s)<d)break;
    if(s<-MATE+200&&(MATE+s)<d)break;
  }
  char ms[8];mstr(best,ms);
  printf("bestmove %s\n",ms);fflush(stdout);
}

static U64 perft(Pos*p,int d){
  if(d==0)return 1;
  Move l[256];int n=gen(p,l,0);U64 c=0;
  for(int i=0;i<n;i++){Pos q;if(!legal(p,l[i],&q))continue;c+=d==1?1:perft(&q,d-1);}
  return c;
}

static void set_start(Pos*p);
static int set_fen(Pos*p,char*fen){
  memset(p,0,sizeof *p);p->ep=-1;
  char*s=fen;int r=7,f=0;
  while(*s&&*s!=' '){
    char c=*s++;
    if(c=='/'){r--;f=0;}
    else if(c>='1'&&c<='8')f+=c-'0';
    else{
      const char*pcs="pnbrqk";int col=0;
      if(c>='A'&&c<='Z'){col=0;c=c-'A'+'a';}else col=1;
      const char*q=strchr(pcs,c);if(!q||r<0||f>7)return 0;
      int sq=r*16+f;p->b[sq]=col*8+(int)(q-pcs)+1;
      if((q-pcs)==5)p->ksq[col]=sq;
      f++;
    }
  }
  while(*s==' ')s++;
  p->side=(*s=='b');if(*s)s++;
  while(*s==' ')s++;
  while(*s&&*s!=' '){
    if(*s=='K')p->castle|=1;if(*s=='Q')p->castle|=2;if(*s=='k')p->castle|=4;if(*s=='q')p->castle|=8;s++;
  }
  while(*s==' ')s++;
  if(*s&&*s!='-'&&s[1]){p->ep=(s[1]-'1')*16+(s[0]-'a');s+=2;}else if(*s)s++;
  while(*s==' ')s++;
  p->half=atoi(s);
  p->hash=hash_calc(p);
  return 1;
}
static void set_start(Pos*p){set_fen(p,"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");}

static int apply_move(Pos*p,const char*str){
  Move l[256];int n=gen(p,l,0);
  for(int i=0;i<n;i++){
    char s[8];mstr(l[i],s);
    if(!strcmp(s,str)){Pos q;if(!legal(p,l[i],&q))return 0;*p=q;return 1;}
  }
  return 0;
}

int main(void){
  init_tables();
  tt=calloc(TTN,sizeof(TT));
  set_start(&pos);rep_n=0;rephash[rep_n++]=pos.hash;
  static char line[65536];
  while(getl(line,sizeof line)){
    char*sp;char*tok=strtok_r(line," \t",&sp);
    if(!tok)continue;
    if(!strcmp(tok,"uci")){
      printf("id name SimpleC 1.0\nid author Claude\nuciok\n");fflush(stdout);
    }else if(!strcmp(tok,"isready")){printf("readyok\n");fflush(stdout);}
    else if(!strcmp(tok,"ucinewgame")){
      memset(tt,0,TTN*sizeof(TT));memset(history,0,sizeof history);
      set_start(&pos);rep_n=0;rephash[rep_n++]=pos.hash;
    }else if(!strcmp(tok,"position")){
      tok=strtok_r(NULL," \t",&sp);if(!tok)continue;
      Pos np;
      if(!strcmp(tok,"startpos")){set_start(&np);tok=strtok_r(NULL," \t",&sp);}
      else if(!strcmp(tok,"fen")){
        char fen[256]="";
        while((tok=strtok_r(NULL," \t",&sp))&&strcmp(tok,"moves")){strcat(fen,tok);strcat(fen," ");}
        if(!set_fen(&np,fen))continue;
      }else continue;
      pos=np;rep_n=0;rephash[rep_n++]=pos.hash;
      if(tok&&!strcmp(tok,"moves")){
        while((tok=strtok_r(NULL," \t",&sp))){
          if(!apply_move(&pos,tok))break;
          if(rep_n<2000)rephash[rep_n++]=pos.hash;
        }
      }
    }else if(!strcmp(tok,"go")){
      int depth=0,mt=0,wt=0,bt=0,wi=0,bi=0,inf=0,perf=0,mtg=0;
      while((tok=strtok_r(NULL," \t",&sp))){
        char*a;
        if(!strcmp(tok,"perft")){a=strtok_r(NULL," \t",&sp);perf=a?atoi(a):1;}
        else if(!strcmp(tok,"depth")){a=strtok_r(NULL," \t",&sp);depth=a?atoi(a):0;}
        else if(!strcmp(tok,"movetime")){a=strtok_r(NULL," \t",&sp);mt=a?atoi(a):0;}
        else if(!strcmp(tok,"wtime")){a=strtok_r(NULL," \t",&sp);wt=a?atoi(a):0;}
        else if(!strcmp(tok,"btime")){a=strtok_r(NULL," \t",&sp);bt=a?atoi(a):0;}
        else if(!strcmp(tok,"winc")){a=strtok_r(NULL," \t",&sp);wi=a?atoi(a):0;}
        else if(!strcmp(tok,"binc")){a=strtok_r(NULL," \t",&sp);bi=a?atoi(a):0;}
        else if(!strcmp(tok,"movestogo")){a=strtok_r(NULL," \t",&sp);mtg=a?atoi(a):0;}
        else if(!strcmp(tok,"infinite"))inf=1;
      }
      if(perf){
        Move l[256];int n=gen(&pos,l,0);U64 tot=0;
        for(int i=0;i<n;i++){
          Pos q;if(!legal(&pos,l[i],&q))continue;
          U64 c=perf>1?perft(&q,perf-1):1;tot+=c;
          char s[8];mstr(l[i],s);printf("%s: %llu\n",s,c);
        }
        printf("\nNodes searched: %llu\n",tot);fflush(stdout);
        continue;
      }
      tstart=now();timed=0;double soft=1e9;int md=64;
      if(depth){md=depth;}
      else if(mt){timed=1;hardlim=mt-20;if(hardlim<5)hardlim=5;soft=hardlim*0.5;}
      else if(!inf&&(wt||bt||wi||bi)){
        int tm=pos.side?bt:wt,inc=pos.side?bi:wi;
        double alloc=tm/(mtg?mtg+1:30)+inc*0.75;
        hardlim=alloc*2.5;if(hardlim>tm/3.0)hardlim=tm/3.0;
        if(hardlim>tm-50)hardlim=tm-50;
        if(hardlim<5)hardlim=5;
        soft=alloc*0.5;if(soft>hardlim)soft=hardlim*0.5;
        timed=1;
      }
      think(soft,md);
      if(quitflag)break;
    }else if(!strcmp(tok,"quit"))break;
  }
  return 0;
}
