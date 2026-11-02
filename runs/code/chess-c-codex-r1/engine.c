#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <sys/select.h>

typedef struct { int from,to,promo,flags; } Move;
enum { EP=1, CASTLE=2 };
typedef struct { char b[128]; int side,castle,ep,half,full; } Pos;
static const int val[7]={0,100,320,330,500,900,20000};
static const int knight[8]={33,31,18,14,-14,-18,-31,-33};
static const int kingd[8]={1,-1,16,-16,15,17,-15,-17};
static const int bishopd[4]={15,17,-15,-17}, rookd[4]={1,-1,16,-16};
static int sqfile(int s){return s&7;} static int sqrank(int s){return s>>4;}
static int valid(int s){return !(s&0x88);}
static int color(char p){return !p?0:(isupper((unsigned char)p)?1:(islower((unsigned char)p)?-1:0));}
static int typ(char p){switch(tolower((unsigned char)p)){case 'p':return 1;case 'n':return 2;case 'b':return 3;case 'r':return 4;case 'q':return 5;case 'k':return 6;}return 0;}
static void init(Pos *p){memset(p,0,sizeof(*p)); const char *r="rnbqkbnr";for(int f=0;f<8;f++){p->b[f]=toupper(r[f]);p->b[16+f]='P';p->b[96+f]='p';p->b[112+f]=r[f];}p->side=1;p->castle=15;p->ep=-1;p->full=1;}
static int attacked(Pos *p,int s,int by){int r=sqrank(s),f=sqfile(s); int a;
 if(by==1){a=s-15;if(valid(a)&&p->b[a]=='P')return 1;a=s-17;if(valid(a)&&p->b[a]=='P')return 1;}else{a=s+15;if(valid(a)&&p->b[a]=='p')return 1;a=s+17;if(valid(a)&&p->b[a]=='p')return 1;}
 for(int i=0;i<8;i++){a=s+knight[i];if(valid(a)&&color(p->b[a])==by&&typ(p->b[a])==2)return 1;}
 for(int i=0;i<8;i++){a=s+kingd[i];if(valid(a)&&color(p->b[a])==by&&typ(p->b[a])==6)return 1;}
 const int *ds;for(int z=0;z<2;z++){ds=z?rookd:bishopd;int n=z?4:4;for(int i=0;i<n;i++){a=s+ds[i];while(valid(a)){char c=p->b[a];if(c){if(color(c)==by&&(typ(c)==5||typ(c)==(z?4:3)))return 1;break;}a+=ds[i];}}}
 (void)r;(void)f;return 0;}
static int kingpos(Pos *p,int side){char k=side==1?'K':'k';for(int s=0;s<128;s++)if(valid(s)&&p->b[s]==k)return s;return -1;}
static void add(Move *m,int *n,int f,int t,int pr,int fl){m[*n]=(Move){f,t,pr,fl};(*n)++;}
static int pseudo(Pos *p,Move *m){int n=0,side=p->side;for(int s=0;s<128;s++){if(!valid(s)){s+=7;continue;}char c=p->b[s];if(color(c)!=side)continue;int t=typ(c),d=side==1?16:-16,x;
 if(t==1){x=s+d;if(valid(x)&&!p->b[x]){if(sqrank(x)==(side==1?7:0)){for(int q=2;q<=5;q++)add(m,&n,s,x,q,0);}else add(m,&n,s,x,0,0);int y=x+d;if(sqrank(s)==(side==1?1:6)&&!p->b[y])add(m,&n,s,y,0,0);}
 for(int k=-1;k<=1;k+=2){x=s+d+k;if(valid(x)&&color(p->b[x])==-side){if(sqrank(x)==(side==1?7:0)){for(int q=2;q<=5;q++)add(m,&n,s,x,q,0);}else add(m,&n,s,x,0,0);}else if(x==p->ep)add(m,&n,s,x,0,EP);}}
 else if(t==2||t==6){const int *ds=t==2?knight:kingd;int z=t==2?8:8;for(int i=0;i<z;i++){x=s+ds[i];if(valid(x)&&color(p->b[x])!=side)add(m,&n,s,x,0,0);}}
 else {for(int z=0;z<2;z++){if(t==3&&z==1)continue;if(t==4&&z==0)continue;const int *ds=z?rookd:bishopd;for(int i=0;i<4;i++){x=s+ds[i];while(valid(x)){if(color(p->b[x])==side)break;add(m,&n,s,x,0,0);if(p->b[x])break;x+=ds[i];}}}}
 if(t==6&&side==1&&s==4&&!attacked(p,4,-1)){if((p->castle&1)&&p->b[5]==0&&p->b[6]==0&&p->b[7]=='R'&&!attacked(p,5,-1)&&!attacked(p,6,-1))add(m,&n,4,6,0,CASTLE);if((p->castle&2)&&!p->b[1]&&!p->b[2]&&!p->b[3]&&p->b[0]=='R'&&!attacked(p,3,-1)&&!attacked(p,2,-1))add(m,&n,4,2,0,CASTLE);}
 if(t==6&&side==-1&&s==116&&!attacked(p,116,1)){if((p->castle&4)&&!p->b[117]&&!p->b[118]&&p->b[119]=='r'&&!attacked(p,117,1)&&!attacked(p,118,1))add(m,&n,116,118,0,CASTLE);if((p->castle&8)&&!p->b[113]&&!p->b[114]&&!p->b[115]&&p->b[112]=='r'&&!attacked(p,115,1)&&!attacked(p,114,1))add(m,&n,116,114,0,CASTLE);}
 }return n;}
typedef struct {char cap,epcap;int castle,ep,half,full;} Undo;
static Undo make(Pos *p,Move m){Undo u={p->b[m.to],0,p->castle,p->ep,p->half,p->full};char c=p->b[m.from];p->ep=-1;p->half++;if(typ(c)==1||u.cap)p->half=0;if(m.flags&EP){u.epcap=p->b[m.to+(p->side==1?-16:16)];p->b[m.to+(p->side==1?-16:16)]=0;}p->b[m.to]=m.promo?(char)(p->side==1?" PNBRQ"[m.promo]:" pnbrq"[m.promo]):c;p->b[m.from]=0;if(typ(c)==1&&abs(m.to-m.from)==32)p->ep=(m.to+m.from)/2;if(m.flags&CASTLE){if(m.to==6){p->b[5]=p->b[7];p->b[7]=0;}else if(m.to==2){p->b[3]=p->b[0];p->b[0]=0;}else if(m.to==118){p->b[117]=p->b[119];p->b[119]=0;}else{p->b[115]=p->b[112];p->b[112]=0;}}
 if(c=='K')p->castle&=~3;if(c=='k')p->castle&=~12;if(m.from==0||m.to==0)p->castle&=~2;if(m.from==7||m.to==7)p->castle&=~1;if(m.from==112||m.to==112)p->castle&=~8;if(m.from==119||m.to==119)p->castle&=~4;if(p->side==-1)p->full++;p->side=-p->side;return u;}
static void unmake(Pos*p,Move m,Undo u){p->side=-p->side;if(p->side==-1)p->full--;char c=p->b[m.to];p->b[m.from]=m.promo?(p->side==1?'P':'p'):c;p->b[m.to]=u.cap;if(m.flags&EP)p->b[m.to+(p->side==1?-16:16)]=u.epcap;if(m.flags&CASTLE){if(m.to==6){p->b[7]=p->b[5];p->b[5]=0;}else if(m.to==2){p->b[0]=p->b[3];p->b[3]=0;}else if(m.to==118){p->b[119]=p->b[117];p->b[117]=0;}else{p->b[112]=p->b[115];p->b[115]=0;}}p->castle=u.castle;p->ep=u.ep;p->half=u.half;p->full=u.full;}
static int legal(Pos*p,Move*m,Move*out){int n=pseudo(p,m),k=0;for(int i=0;i<n;i++){Undo u=make(p,m[i]);int ks=kingpos(p,-p->side);int ok=ks>=0&&!attacked(p,ks,p->side);unmake(p,m[i],u);if(ok)out[k++]=m[i];}return k;}
static long long perft(Pos*p,int d){if(d==0)return 1;Move a[256],b[256];int n=legal(p,a,b);long long z=0;for(int i=0;i<n;i++){Undo u=make(p,b[i]);z+=perft(p,d-1);unmake(p,b[i],u);}return z;}
static long long nodes;static double deadline;static int stopped;
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static void pollstop(void){if(now()>deadline){stopped=1;return;}fd_set f;FD_ZERO(&f);FD_SET(0,&f);struct timeval tv={0,0};if(select(1,&f,NULL,NULL,&tv)>0){char s[256];if(fgets(s,sizeof s,stdin)){if(!strncmp(s,"stop",4)||!strncmp(s,"quit",4))stopped=1;}}}
static int eval(Pos*p){int s=0;for(int q=0;q<128;q++){if(!valid(q))continue;char c=p->b[q];int t=typ(c);if(t){int center=7-(abs(2*sqfile(q)-7)+abs(2*sqrank(q)-7))/2;int v=val[t]+(t==1?sqrank(q)*(color(c)==1?7:-7):center*(t==2||t==3?5:1));s+=color(c)*v;}}return p->side*s;}
static int qsearch(Pos*p,int a,int b,int ply){if((++nodes&2047)==0)pollstop();if(stopped)return 0;int check=attacked(p,kingpos(p,p->side),-p->side);int stand=eval(p);if(!check){if(stand>=b)return b;if(stand>a)a=stand;}Move ps[256],ms[256];int n=legal(p,ps,ms);if(!n&&check)return -30000+ply;for(int i=0;i<n;i++)if(check||p->b[ms[i].to]||ms[i].flags&EP||ms[i].promo){Undo u=make(p,ms[i]);int v=-qsearch(p,-b,-a,ply+1);unmake(p,ms[i],u);if(v>=b)return b;if(v>a)a=v;}return a;}
static int search(Pos*p,int d,int a,int b,int ply){if((++nodes&2047)==0)pollstop();if(stopped)return 0;if(d<=0)return qsearch(p,a,b,ply);Move ps[256],ms[256];int n=legal(p,ps,ms);if(!n){if(attacked(p,kingpos(p,p->side),-p->side))return -30000+ply;return 0;}for(int i=0;i<n;i++){for(int j=i+1;j<n;j++){int x=(p->b[ms[i].to]?val[typ(p->b[ms[i].to])]*10-val[typ(p->b[ms[i].from])]:0)+(ms[i].promo?900:0),y=(p->b[ms[j].to]?val[typ(p->b[ms[j].to])]*10-val[typ(p->b[ms[j].from])]:0)+(ms[j].promo?900:0);if(y>x){Move z=ms[i];ms[i]=ms[j];ms[j]=z;}}Undo u=make(p,ms[i]);int v=-search(p,d-1,-b,-a,ply+1);unmake(p,ms[i],u);if(stopped)return 0;if(v>=b)return b;if(v>a)a=v;}return a;}
static void parsefen(Pos*p,char *s){memset(p,0,sizeof(*p));p->ep=-1;p->full=1;int r=7,f=0;char *x=s;while(*x&&*x!=' '){if(*x=='/'){r--;f=0;}else if(isdigit((unsigned char)*x))f+=*x-'0';else if(f<8)p->b[r*16+f++]=*x;x++;}while(*x==' ')x++;p->side=*x=='b'?-1:1;while(*x&&*x!=' ')x++;while(*x==' ')x++;while(*x&&*x!=' '){if(*x=='K')p->castle|=1;if(*x=='Q')p->castle|=2;if(*x=='k')p->castle|=4;if(*x=='q')p->castle|=8;x++;}while(*x==' ')x++;if(*x&&x[0]!='-')p->ep=(x[1]-'1')*16+x[0]-'a';while(*x&&*x!=' ')x++;if(*x)p->half=atoi(x+1);while(*x&&*x!=' ')x++;if(*x)p->full=atoi(x+1);}
static int square(char*a){return (a[1]-'1')*16+a[0]-'a';}
static int parsemove(Pos*p,char*s,Move*out){Move a[256],b[256];int n=legal(p,a,b);for(int i=0;i<n;i++){char z[8];snprintf(z,sizeof z,"%c%c%c%c%s",'a'+sqfile(b[i].from),'1'+sqrank(b[i].from),'a'+sqfile(b[i].to),'1'+sqrank(b[i].to),b[i].promo?(b[i].promo==2?"n":b[i].promo==3?"b":b[i].promo==4?"r":"q"):"");if(!strncmp(s,z,strlen(z))){*out=b[i];return 1;}}return 0;}
int main(void){Pos p;init(&p);char line[4096];while(fgets(line,sizeof line,stdin)){if(!strncmp(line,"uci",3)){puts("id name Cobalt\nid author OpenAI\nuciok");fflush(stdout);}else if(!strncmp(line,"isready",7)){puts("readyok");fflush(stdout);}else if(!strncmp(line,"ucinewgame",10))init(&p);else if(!strncmp(line,"position ",9)){char *x=line+9;if(!strncmp(x,"startpos",8)){init(&p);x+=8;}else if(!strncmp(x,"fen ",4)){x+=4;char *m=strstr(x," moves ");if(m)*m=0;parsefen(&p,x);x=m?m+7:x+strlen(x);}while(!strncmp(x," moves ",7))x+=7;char *tok=strtok(x," \r\n");while(tok){Move m;if(parsemove(&p,tok,&m)){Undo u=make(&p,m);(void)u;}tok=strtok(NULL," \r\n");}}
 else if(!strncmp(line,"go perft ",9)){int d=atoi(line+9);Move a[256],b[256];int n=legal(&p,a,b);long long total=0;for(int i=0;i<n;i++){Undo u=make(&p,b[i]);long long c=perft(&p,d-1);unmake(&p,b[i],u);printf("%c%c%c%c%s: %lld\n",'a'+sqfile(b[i].from),'1'+sqrank(b[i].from),'a'+sqfile(b[i].to),'1'+sqrank(b[i].to),b[i].promo?(b[i].promo==2?"n":b[i].promo==3?"b":b[i].promo==4?"r":"q"):"",c);total+=c;}printf("Nodes searched: %lld\n",total);fflush(stdout);}
 else if(!strncmp(line,"go",2)){int depth=5,ms=1000;char *q=strstr(line,"depth ");if(q)depth=atoi(q+6);q=strstr(line,"movetime ");if(q)ms=atoi(q+9);else{char key[16];int t=0;snprintf(key,sizeof key,"%stime ",p.side==1?"w":"b");q=strstr(line,key);if(q){t=atoi(q+strlen(key));int inc=0;snprintf(key,sizeof key,"%sinc ",p.side==1?"w":"b");q=strstr(line,key);if(q)inc=atoi(q+strlen(key));ms=t/30+inc*3/4;if(ms<10)ms=10;}else ms=1500;}q=strstr(line,"perft ");if(q)continue;Move a[256],b[256],best={0};int n=legal(&p,a,b);if(n)best=b[0];deadline=now()+ms/1000.0;stopped=0;nodes=0;for(int d=1;d<=depth&&!stopped;d++){int ba=-32000;for(int i=0;i<n;i++){Undo u=make(&p,b[i]);int v=-search(&p,d-1,-32000,32000,1);unmake(&p,b[i],u);if(stopped)break;if(v>ba){ba=v;best=b[i];}}}printf("bestmove %c%c%c%c%s\n",n?'a'+sqfile(best.from):'0',n?'1'+sqrank(best.from):'0',n?'a'+sqfile(best.to):'0',n?'1'+sqrank(best.to):'0',best.promo?(best.promo==2?"n":best.promo==3?"b":best.promo==4?"r":"q"):"");fflush(stdout);}
 else if(!strncmp(line,"quit",4))break;}
 return 0;}
