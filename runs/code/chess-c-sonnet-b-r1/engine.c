#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <sys/select.h>

typedef uint64_t u64;
enum { P=1,N,B,R,Q,K };
#define TYPE(p) (((p)-1)%6+1)
#define COL(p) ((p)>6)
#define MATE 30000
#define INF 32000

typedef struct {
    int8_t b[64];
    int side, castle, ep, halfmove, fullmove;
    int ksq[2];
    u64 hash;
} State;

static u64 zp[13][64], zside, zcas[16], zep[9];
static const int cmask[64] = {
 13,15,15,15,12,15,15,14, 15,15,15,15,15,15,15,15, 15,15,15,15,15,15,15,15, 15,15,15,15,15,15,15,15,
 15,15,15,15,15,15,15,15, 15,15,15,15,15,15,15,15, 15,15,15,15,15,15,15,15, 7,15,15,15,3,15,15,11 };
static const int ndf[8]={1,2,2,1,-1,-2,-2,-1}, ndr[8]={2,1,-1,-2,-2,-1,1,2};
static const int kdf[8]={1,1,1,0,-1,-1,-1,0}, kdr[8]={1,0,-1,-1,-1,0,1,1};
static const int val[7]={0,100,320,330,500,900,0};

static u64 rng=88172645463325252ULL;
static u64 rnd(void){ rng^=rng<<13; rng^=rng>>7; rng^=rng<<17; return rng; }

static void init_hash(void){
    for(int i=0;i<13;i++)for(int j=0;j<64;j++)zp[i][j]=rnd();
    zside=rnd(); for(int i=0;i<16;i++)zcas[i]=rnd(); for(int i=0;i<9;i++)zep[i]=rnd();
}
static u64 calc_hash(const State*s){
    u64 h=0;
    for(int i=0;i<64;i++) if(s->b[i]) h^=zp[s->b[i]][i];
    if(s->side) h^=zside;
    h^=zcas[s->castle]; h^=zep[s->ep<0?8:s->ep&7];
    return h;
}

static int attacked(const State*s,int sq,int by){
    int f=sq&7,r=sq>>3, off=by?6:0;
    for(int i=0;i<8;i++){
        int nf=f+ndf[i],nr=r+ndr[i];
        if(nf>=0&&nf<8&&nr>=0&&nr<8&&s->b[nr*8+nf]==N+off) return 1;
        nf=f+kdf[i];nr=r+kdr[i];
        if(nf>=0&&nf<8&&nr>=0&&nr<8&&s->b[nr*8+nf]==K+off) return 1;
    }
    int pr=by?r+1:r-1;
    if(pr>=0&&pr<8){
        if(f>0&&s->b[pr*8+f-1]==P+off) return 1;
        if(f<7&&s->b[pr*8+f+1]==P+off) return 1;
    }
    for(int i=0;i<8;i++){
        int nf=f+kdf[i],nr=r+kdr[i];
        int diag=(kdf[i]&&kdr[i]);
        while(nf>=0&&nf<8&&nr>=0&&nr<8){
            int p=s->b[nr*8+nf];
            if(p){
                if(COL(p)==by){ int t=TYPE(p);
                    if(t==Q||(diag&&t==B)||(!diag&&t==R)) return 1; }
                break;
            }
            nf+=kdf[i];nr+=kdr[i];
        }
    }
    return 0;
}
static inline int in_check(const State*s,int c){ return attacked(s,s->ksq[c],!c); }

#define MV(f,t,p) ((f)|((t)<<6)|((p)<<12))
#define FROM(m) ((m)&63)
#define TO(m) (((m)>>6)&63)
#define PROMO(m) (((m)>>12)&7)

static int gen(const State*s,int*mv,int caps){
    int n=0,c=s->side,off=c?6:0;
    for(int sq=0;sq<64;sq++){
        int p=s->b[sq];
        if(!p||COL(p)!=c) continue;
        int t=TYPE(p),f=sq&7,r=sq>>3;
        if(t==P){
            int dir=c?-1:1, r1=r+dir, prom=(r1==0||r1==7), start=c?6:1;
            int to=r1*8+f;
            if(!s->b[to]){
                if(prom){ for(int q=Q;q>=N;q--) mv[n++]=MV(sq,to,q); }
                else if(!caps){
                    mv[n++]=MV(sq,to,0);
                    if(r==start&&!s->b[to+dir*8]) mv[n++]=MV(sq,to+dir*8,0);
                }
            }
            for(int d=-1;d<=1;d+=2){
                int nf=f+d; if(nf<0||nf>7) continue;
                to=r1*8+nf; int tp=s->b[to];
                if((tp&&COL(tp)!=c)||(!tp&&to==s->ep)){
                    if(prom){ for(int q=Q;q>=N;q--) mv[n++]=MV(sq,to,q); }
                    else mv[n++]=MV(sq,to,0);
                }
            }
        } else if(t==N||t==K){
            for(int i=0;i<8;i++){
                int nf=f+(t==N?ndf[i]:kdf[i]),nr=r+(t==N?ndr[i]:kdr[i]);
                if(nf<0||nf>7||nr<0||nr>7) continue;
                int to=nr*8+nf,tp=s->b[to];
                if(tp&&COL(tp)==c) continue;
                if(caps&&!tp) continue;
                mv[n++]=MV(sq,to,0);
            }
            if(t==K&&!caps){
                int base=c?56:0;
                if(sq==base+4&&!attacked(s,sq,!c)){
                    if((s->castle&(c?4:1))&&!s->b[base+5]&&!s->b[base+6]&&s->b[base+7]==R+off
                       &&!attacked(s,base+5,!c)&&!attacked(s,base+6,!c)) mv[n++]=MV(sq,base+6,0);
                    if((s->castle&(c?8:2))&&!s->b[base+3]&&!s->b[base+2]&&!s->b[base+1]&&s->b[base]==R+off
                       &&!attacked(s,base+3,!c)&&!attacked(s,base+2,!c)) mv[n++]=MV(sq,base+2,0);
                }
            }
        } else {
            for(int i=0;i<8;i++){
                int diag=(kdf[i]&&kdr[i]);
                if(t==B&&!diag) continue;
                if(t==R&&diag) continue;
                int nf=f+kdf[i],nr=r+kdr[i];
                while(nf>=0&&nf<8&&nr>=0&&nr<8){
                    int to=nr*8+nf,tp=s->b[to];
                    if(tp){ if(COL(tp)!=c) mv[n++]=MV(sq,to,0); break; }
                    if(!caps) mv[n++]=MV(sq,to,0);
                    nf+=kdf[i];nr+=kdr[i];
                }
            }
        }
    }
    return n;
}

static inline void setp(State*s,int sq,int p){
    if(s->b[sq]) s->hash^=zp[(int)s->b[sq]][sq];
    s->b[sq]=p;
    if(p) s->hash^=zp[p][sq];
}
/* returns 0 if illegal (leaves s garbage) */
static int make(State*s,int m){
    int from=FROM(m),to=TO(m),pr=PROMO(m),c=s->side;
    int p=s->b[from],t=TYPE(p),cap=s->b[to];
    s->hash^=zep[s->ep<0?8:s->ep&7];
    int oldep=s->ep; s->ep=-1;
    s->halfmove++;
    if(cap||t==P) s->halfmove=0;
    setp(s,to,pr?pr+(c?6:0):p); setp(s,from,0);
    if(t==P){
        if(to==oldep&&!cap) setp(s,c?to+8:to-8,0);
        if(abs(to-from)==16) s->ep=(from+to)/2;
    }
    if(t==K){
        s->ksq[c]=to;
        if(to-from==2){ setp(s,to-1,s->b[to+1]); setp(s,to+1,0); }
        else if(from-to==2){ setp(s,to+1,s->b[to-2]); setp(s,to-2,0); }
    }
    s->hash^=zcas[s->castle];
    s->castle&=cmask[from]&cmask[to];
    s->hash^=zcas[s->castle];
    s->hash^=zep[s->ep<0?8:s->ep&7];
    s->side=!c; s->hash^=zside;
    if(c==1) s->fullmove++;
    return !in_check(s,c);
}

/* ---------- eval ---------- */
static const int pst[7][64]={{0},
{0,0,0,0,0,0,0,0, 50,50,50,50,50,50,50,50, 10,10,20,30,30,20,10,10, 5,5,10,25,25,10,5,5,
 0,0,0,20,20,0,0,0, 5,-5,-10,0,0,-10,-5,5, 5,10,10,-20,-20,10,10,5, 0,0,0,0,0,0,0,0},
{-50,-40,-30,-30,-30,-30,-40,-50, -40,-20,0,0,0,0,-20,-40, -30,0,10,15,15,10,0,-30, -30,5,15,20,20,15,5,-30,
 -30,0,15,20,20,15,0,-30, -30,5,10,15,15,10,5,-30, -40,-20,0,5,5,0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50},
{-20,-10,-10,-10,-10,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,10,10,5,0,-10, -10,5,5,10,10,5,5,-10,
 -10,0,10,10,10,10,0,-10, -10,10,10,10,10,10,10,-10, -10,5,0,0,0,0,5,-10, -20,-10,-10,-10,-10,-10,-10,-20},
{0,0,0,0,0,0,0,0, 5,10,10,10,10,10,10,5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5,
 -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, 0,0,0,5,5,0,0,0},
{-20,-10,-10,-5,-5,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,5,5,5,0,-10, -5,0,5,5,5,5,0,-5,
 0,0,5,5,5,5,0,-5, -10,5,5,5,5,5,0,-10, -10,0,5,0,0,0,0,-10, -20,-10,-10,-5,-5,-10,-10,-20},
{-30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30,
 -20,-30,-30,-40,-40,-30,-30,-20, -10,-20,-20,-20,-20,-20,-20,-10, 20,20,0,0,0,0,20,20, 20,30,10,0,0,10,30,20}};
static const int kend[64]={-50,-40,-30,-20,-20,-30,-40,-50, -30,-20,-10,0,0,-10,-20,-30, -30,-10,20,30,30,20,-10,-30,
 -30,-10,30,40,40,30,-10,-30, -30,-10,30,40,40,30,-10,-30, -30,-10,20,30,30,20,-10,-30, -30,-30,0,0,0,0,-30,-30, -50,-30,-30,-30,-30,-30,-30,-50};

static int eval(const State*s){
    int sc[2]={0,0},npm=0,bish[2]={0,0},kmid[2]={0,0},kend_[2]={0,0};
    for(int sq=0;sq<64;sq++){
        int p=s->b[sq]; if(!p) continue;
        int c=COL(p),t=TYPE(p),i=c?sq:sq^56;
        if(t==K){ kmid[c]=pst[K][i]; kend_[c]=kend[i]; continue; }
        sc[c]+=val[t]+pst[t][i];
        if(t!=P) npm+=val[t];
        if(t==B) bish[c]++;
        if(t==P){ /* passed pawn bonus */
            int f=sq&7,r=sq>>3,pass=1;
            for(int q=0;q<64&&pass;q++){
                int o=s->b[q]; if(o!=P+(c?0:6)) continue;
                int qr=q>>3,qf=q&7;
                if(abs(qf-f)<=1&&(c?qr<r:qr>r)) pass=0;
            }
            if(pass){ int adv=c?7-r:r; sc[c]+=adv*adv*3; }
        }
    }
    int ph=npm>6000?6000:npm;
    for(int c=0;c<2;c++){
        sc[c]+=(kmid[c]*ph+kend_[c]*(6000-ph))/6000;
        if(bish[c]>=2) sc[c]+=30;
    }
    int e=sc[0]-sc[1];
    return (s->side?-e:e)+8;
}

/* ---------- search ---------- */
typedef struct { u64 key; int16_t score; int16_t move_lo; int8_t depth, flag; int16_t move_hi; } TTE;
#define TTBITS 21
static TTE *tt;
static u64 hist[2048]; static int hply;
static int killers[128][2], history[2][64][64];
static u64 nodes; static int stopped, allow_stop;
static double t_start, t_limit; static int infinite_mode;
static int rootbest;

static double now(void){ struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts); return ts.tv_sec*1000.0+ts.tv_nsec/1e6; }

static char inbuf[1<<16]; static int inlen;
static int fill_input(int block){
    if(inlen>=(int)sizeof(inbuf)-1) return 1;
    if(!block){
        fd_set fs; FD_ZERO(&fs); FD_SET(0,&fs); struct timeval tv={0,0};
        if(select(1,&fs,NULL,NULL,&tv)<=0) return 1;
    }
    int r=read(0,inbuf+inlen,sizeof(inbuf)-1-inlen);
    if(r<=0) return 0;
    inlen+=r; return 1;
}
static void poll_input(void){
    if(!fill_input(0)) { stopped=1; return; }
    inbuf[inlen]=0;
    if(strstr(inbuf,"stop")||strstr(inbuf,"quit")) stopped=1;
}
static void check_time(void){
    if(!allow_stop) return;
    if(!infinite_mode&&now()-t_start>=t_limit) stopped=1;
    poll_input();
}

static int qsearch(State*s,int alpha,int beta,int ply){
    if((++nodes&2047)==0) check_time();
    if(stopped) return 0;
    int stand=eval(s);
    if(ply>=100) return stand;
    if(stand>=beta) return stand;
    if(stand>alpha) alpha=stand;
    int mv[256],sc[256],n=gen(s,mv,1);
    for(int i=0;i<n;i++){
        int m=mv[i],cap=s->b[TO(m)];
        int v=cap?TYPE(cap):(TYPE(s->b[FROM(m)])==P?1:0);
        sc[i]=v*10-TYPE(s->b[FROM(m)])+(PROMO(m)?50:0);
    }
    for(int i=0;i<n;i++){
        int b=i; for(int j=i+1;j<n;j++) if(sc[j]>sc[b]) b=j;
        int t=mv[i];mv[i]=mv[b];mv[b]=t; t=sc[i];sc[i]=sc[b];sc[b]=t;
        State c=*s; if(!make(&c,mv[i])) continue;
        int v=-qsearch(&c,-beta,-alpha,ply+1);
        if(stopped) return 0;
        if(v>=beta) return v;
        if(v>alpha) alpha=v;
    }
    return alpha;
}

static int search(State*s,int depth,int alpha,int beta,int ply,int nullok){
    int chk=in_check(s,s->side);
    if(chk) depth++;
    if(depth<=0) return qsearch(s,alpha,beta,ply);
    if((++nodes&2047)==0) check_time();
    if(stopped) return 0;
    if(ply>0){
        if(s->halfmove>=100) return 0;
        for(int i=hply-3;i>=0&&i>=hply-1-s->halfmove;i-=2) if(hist[i]==s->hash) return 0;
    }
    if(ply>=120) return eval(s);
    int pv=(beta-alpha>1);
    TTE*e=&tt[s->hash&((1ULL<<TTBITS)-1)];
    int ttmove=0;
    if(e->key==s->hash){
        ttmove=(uint16_t)e->move_lo|((int)e->move_hi<<16);
        if(e->depth>=depth&&ply>0&&!pv){
            int v=e->score;
            if(v>MATE-200) v-=ply; else if(v<-MATE+200) v+=ply;
            if(e->flag==0) return v;
            if(e->flag==1&&v>=beta) return v;
            if(e->flag==2&&v<=alpha) return v;
        }
    }
    if(!chk&&!pv&&nullok&&depth>=3&&beta<MATE-200){
        int np=0; for(int i=0;i<64;i++){int p=s->b[i]; if(p&&COL(p)==s->side&&TYPE(p)>P&&TYPE(p)<K) np++;}
        if(np&&eval(s)>=beta){
            State c=*s; c.hash^=zep[c.ep<0?8:c.ep&7]; c.ep=-1; c.hash^=zep[8];
            c.side=!c.side; c.hash^=zside; c.halfmove++;
            hist[hply++]=c.hash;
            int v=-search(&c,depth-3,-beta,-beta+1,ply+1,0);
            hply--;
            if(stopped) return 0;
            if(v>=beta) return beta;
        }
    }
    int mv[256],sc[256],n=gen(s,mv,0);
    for(int i=0;i<n;i++){
        int m=mv[i],cap=s->b[TO(m)];
        if(m==ttmove) sc[i]=1000000;
        else if(cap||(TYPE(s->b[FROM(m)])==P&&TO(m)==s->ep)) sc[i]=100000+(cap?TYPE(cap):1)*10-TYPE(s->b[FROM(m)]);
        else if(PROMO(m)) sc[i]=90000+PROMO(m);
        else if(m==killers[ply][0]) sc[i]=80000;
        else if(m==killers[ply][1]) sc[i]=79000;
        else sc[i]=history[s->side][FROM(m)][TO(m)];
    }
    int best=-INF,bestm=0,legal=0,oa=alpha;
    for(int i=0;i<n;i++){
        int b=i; for(int j=i+1;j<n;j++) if(sc[j]>sc[b]) b=j;
        int t=mv[i];mv[i]=mv[b];mv[b]=t; t=sc[i];sc[i]=sc[b];sc[b]=t;
        int m=mv[i];
        State c=*s; if(!make(&c,m)) continue;
        legal++;
        int quiet=!s->b[TO(m)]&&!PROMO(m)&&!(TYPE(s->b[FROM(m)])==P&&TO(m)==s->ep);
        hist[hply++]=c.hash;
        int v;
        if(legal==1) v=-search(&c,depth-1,-beta,-alpha,ply+1,1);
        else {
            int red=0;
            if(depth>=3&&legal>4&&quiet&&!chk) red=legal>8?2:1;
            v=-search(&c,depth-1-red,-alpha-1,-alpha,ply+1,1);
            if(v>alpha&&!stopped) v=-search(&c,depth-1,-beta,-alpha,ply+1,1);
        }
        hply--;
        if(stopped) return 0;
        if(v>best){ best=v; bestm=m; if(ply==0) rootbest=m; }
        if(v>alpha){ alpha=v;
            if(alpha>=beta){
                if(quiet){
                    if(killers[ply][0]!=m){ killers[ply][1]=killers[ply][0]; killers[ply][0]=m; }
                    history[s->side][FROM(m)][TO(m)]+=depth*depth;
                    if(history[s->side][FROM(m)][TO(m)]>70000) memset(history,0,sizeof history);
                }
                break;
            }
        }
    }
    if(!legal) return chk?-MATE+ply:0;
    int flag=best>=beta?1:(best>oa?0:2);
    int sv=best; if(sv>MATE-200) sv+=ply; else if(sv<-MATE+200) sv-=ply;
    e->key=s->hash; e->score=sv; e->depth=depth; e->flag=flag;
    e->move_lo=(int16_t)(bestm&0xffff); e->move_hi=(int16_t)(bestm>>16);
    return best;
}

static void move_str(int m,char*o){
    o[0]='a'+(FROM(m)&7);o[1]='1'+(FROM(m)>>3);o[2]='a'+(TO(m)&7);o[3]='1'+(TO(m)>>3);
    int p=PROMO(m); o[4]=p?" pnbrqk"[p]:0; o[5]=0; if(!p)o[4]=0;
}

static State root;

static void do_search(int maxdepth){
    nodes=0; stopped=0; allow_stop=0; memset(killers,0,sizeof killers);
    memset(history,0,sizeof history);
    int mv[256],n=gen(&root,mv,0),legal[256],nl=0;
    for(int i=0;i<n;i++){ State c=root; if(make(&c,mv[i])) legal[nl++]=mv[i]; }
    int best=nl?legal[0]:0;
    for(int d=1;d<=maxdepth&&nl;d++){
        allow_stop=d>1; rootbest=0;
        int v=search(&root,d,-INF,INF,0,0);
        if(stopped) { break; }
        if(rootbest) best=rootbest;
        char ms[8]; move_str(best,ms);
        printf("info depth %d score %s %d nodes %llu time %d pv %s\n",d,
            abs(v)>MATE-200?"mate":"cp",
            abs(v)>MATE-200?((v>0?MATE-v+1:-(MATE+v))/(v>0?2:2)):v,
            (unsigned long long)nodes,(int)(now()-t_start),ms);
        fflush(stdout);
        if(!infinite_mode&&v>MATE-200&&MATE-v<=d) break;
        if(!infinite_mode&&now()-t_start>t_limit*0.6) break;
    }
    char ms[8]; if(nl) move_str(best,ms); else strcpy(ms,"0000");
    printf("bestmove %s\n",ms); fflush(stdout);
}

static u64 perft(State*s,int d){
    if(d==0) return 1;
    int mv[256],n=gen(s,mv,0); u64 t=0;
    for(int i=0;i<n;i++){ State c=*s; if(!make(&c,mv[i])) continue; t+=d==1?1:perft(&c,d-1); }
    return t;
}

static void set_fen(State*s,const char*fen){
    memset(s,0,sizeof *s); s->ep=-1;
    int r=7,f=0; const char*p=fen;
    for(;*p&&*p!=' ';p++){
        if(*p=='/'){r--;f=0;}
        else if(*p>='1'&&*p<='8') f+=*p-'0';
        else {
            const char*k=strchr("PNBRQKpnbrqk",*p); int pc=k?(int)(k-"PNBRQKpnbrqk")+1:0;
            if(pc&&f<8&&r>=0){ s->b[r*8+f]=pc; if(pc==K)s->ksq[0]=r*8+f; if(pc==12)s->ksq[1]=r*8+f; }
            f++;
        }
    }
    while(*p==' ')p++;
    s->side=(*p=='b'); while(*p&&*p!=' ')p++; while(*p==' ')p++;
    for(;*p&&*p!=' ';p++){ if(*p=='K')s->castle|=1; if(*p=='Q')s->castle|=2; if(*p=='k')s->castle|=4; if(*p=='q')s->castle|=8; }
    while(*p==' ')p++;
    if(*p&&*p!='-'&&p[1]) s->ep=(p[1]-'1')*8+(p[0]-'a');
    while(*p&&*p!=' ')p++;
    s->halfmove=atoi(p); while(*p==' ')p++; while(*p&&*p!=' ')p++;
    s->fullmove=atoi(p); if(s->fullmove<1)s->fullmove=1;
    s->hash=calc_hash(s);
}

static void do_position(char*line){
    char*p=line+8; while(*p==' ')p++;
    if(!strncmp(p,"startpos",8)){ set_fen(&root,"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"); p+=8; }
    else if(!strncmp(p,"fen",3)){
        p+=3; while(*p==' ')p++;
        char fen[200]; int i=0; char*mvp=strstr(p," moves");
        while(*p&&p!=mvp&&i<199) fen[i++]=*p++;
        fen[i]=0; set_fen(&root,fen);
    } else return;
    hply=0; hist[hply++]=root.hash;
    char*m=strstr(p,"moves"); if(!m) return;
    m+=5;
    char*tok=strtok(m," \t\r\n");
    while(tok){
        int mv[256],n=gen(&root,mv,0);
        for(int i=0;i<n;i++){
            char ms[8]; move_str(mv[i],ms);
            if(!strcmp(ms,tok)){
                State c=root; if(make(&c,mv[i])){ root=c; hist[hply++]=root.hash; }
                break;
            }
        }
        tok=strtok(NULL," \t\r\n");
    }
}

static void do_go(char*line){
    int depth=64,movetime=-1,wt=-1,bt=-1,wi=0,bi=0,mtg=30; infinite_mode=0;
    char*tok=strtok(line+2," \t\r\n");
    while(tok){
        if(!strcmp(tok,"perft")){
            int d=atoi(strtok(NULL," \t\r\n")?:"1"); if(d<1)d=1;
            int mv[256],n=gen(&root,mv,0); u64 tot=0;
            for(int i=0;i<n;i++){
                State c=root; if(!make(&c,mv[i])) continue;
                u64 k=d==1?1:perft(&c,d-1); char ms[8]; move_str(mv[i],ms);
                printf("%s: %llu\n",ms,(unsigned long long)k); tot+=k;
            }
            printf("\nNodes searched: %llu\n",(unsigned long long)tot); fflush(stdout); return;
        }
        char*a;
        if(!strcmp(tok,"depth")){ if((a=strtok(NULL," \t\r\n"))) depth=atoi(a); movetime=-2; }
        else if(!strcmp(tok,"movetime")){ if((a=strtok(NULL," \t\r\n"))) movetime=atoi(a); }
        else if(!strcmp(tok,"wtime")){ if((a=strtok(NULL," \t\r\n"))) wt=atoi(a); }
        else if(!strcmp(tok,"btime")){ if((a=strtok(NULL," \t\r\n"))) bt=atoi(a); }
        else if(!strcmp(tok,"winc")){ if((a=strtok(NULL," \t\r\n"))) wi=atoi(a); }
        else if(!strcmp(tok,"binc")){ if((a=strtok(NULL," \t\r\n"))) bi=atoi(a); }
        else if(!strcmp(tok,"movestogo")){ if((a=strtok(NULL," \t\r\n"))) mtg=atoi(a); if(mtg<1)mtg=1; }
        else if(!strcmp(tok,"infinite")) infinite_mode=1;
        tok=strtok(NULL," \t\r\n");
    }
    t_start=now();
    if(movetime>=0) t_limit=movetime>100?movetime-30:movetime*0.8;
    else if(movetime==-2) t_limit=1e9;
    else if(wt>=0||bt>=0){
        int rem=root.side?bt:wt, inc=root.side?bi:wi; if(rem<0)rem=0;
        t_limit=rem/(double)mtg+inc*0.75;
        if(t_limit>rem*0.5) t_limit=rem*0.5;
        t_limit-=20; if(t_limit<10) t_limit=10;
    } else if(!infinite_mode) t_limit=1e9; 
    if(movetime==-2&&!infinite_mode) t_limit=1e9;
    do_search(depth);
}

static int get_line(char*out,int sz){
    for(;;){
        char*nl=memchr(inbuf,'\n',inlen);
        if(nl){
            int l=nl-inbuf; if(l>=sz)l=sz-1;
            memcpy(out,inbuf,l); out[l]=0;
            int rest=inlen-(int)(nl-inbuf)-1; memmove(inbuf,nl+1,rest); inlen=rest;
            return 1;
        }
        if(!fill_input(1)) return 0;
    }
}

int main(void){
    init_hash();
    tt=calloc(1ULL<<TTBITS,sizeof(TTE));
    set_fen(&root,"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    hply=0; hist[hply++]=root.hash;
    char line[8192];
    while(get_line(line,sizeof line)){
        if(!strncmp(line,"uci",3)&&!line[3]){
            printf("id name SimpleC 1.0\nid author Claude\nuciok\n");
        } else if(!strncmp(line,"isready",7)) printf("readyok\n");
        else if(!strncmp(line,"ucinewgame",10)){ memset(tt,0,(1ULL<<TTBITS)*sizeof(TTE)); }
        else if(!strncmp(line,"position",8)) do_position(line);
        else if(!strncmp(line,"go",2)) do_go(line);
        else if(!strncmp(line,"quit",4)) break;
        fflush(stdout);
    }
    return 0;
}
