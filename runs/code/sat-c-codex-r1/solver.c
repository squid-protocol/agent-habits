#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef struct { int *a,n,cap; } Vec;
static void push(Vec *v,int x){if(v->n==v->cap){v->cap=v->cap?v->cap*2:8;v->a=realloc(v->a,(size_t)v->cap*sizeof(int));if(!v->a)exit(1);}v->a[v->n++]=x;}
static int nvar,ncl; static Vec *clauses,*watch; static signed char *val; static int *trail,tn,qhead,*level;
static int idx(int l){return 2*(abs(l)-1)+(l<0);}
static int litval(int l){return val[abs(l)]*(l<0?-1:1);}
static int enqueue(int l){int v=abs(l),x=l>0?1:-1;if(val[v])return val[v]==x;val[v]=x;trail[tn++]=l;return 1;}
static int propagate(void){while(qhead<tn){int p=trail[qhead++], fals=-p;Vec *w=&watch[idx(fals)];for(int i=0;i<w->n;){int ci=w->a[i];Vec *c=&clauses[ci];int wi=(c->a[0]==fals)?0:1, oi=wi^1, other=c->a[oi];if(litval(other)==1){i++;continue;}int k;for(k=2;k<c->n;k++)if(litval(c->a[k])!=-1)break;if(k<c->n){c->a[wi]=c->a[k];c->a[k]=fals;w->a[i]=w->a[--w->n];push(&watch[idx(c->a[wi])],ci);continue;}if(litval(other)==-1)return 0;if(!enqueue(other))return 0;i++;}}return 1;}
static int choose(void){int best=0,bs=-1;for(int v=1;v<=nvar;v++)if(!val[v]){int score=0;for(int c=0;c<ncl;c++){int open=0,sat=0;for(int j=0;j<clauses[c].n;j++){int z=litval(clauses[c].a[j]);if(z==1){sat=1;break;}if(z==0)open++;}if(!sat&&open)for(int j=0;j<clauses[c].n;j++)if(abs(clauses[c].a[j])==v){score+=100/open;break;}}if(score>bs){best=v;bs=score;}}return best;}
static int solve(void){if(!propagate())return 0;int v=choose();if(!v)return 1;int mark=tn,oldq=qhead;for(int s=1;s>=-1;s-=2){if(enqueue(s*v)&&solve())return 1;while(tn>mark)val[abs(trail[--tn])]=0;qhead=oldq;}return 0;}
int main(int argc,char **argv){if(argc!=2)return 1;FILE*f=fopen(argv[1],"r");if(!f)return 1;char line[65536];int h=0;while(fgets(line,sizeof line,f)){if(line[0]=='c'||line[0]=='\n')continue;if(line[0]=='p'){if(sscanf(line,"p cnf %d %d",&nvar,&ncl)!=2)return 1;h=1;break;}}if(!h)return 1;clauses=calloc(ncl+1,sizeof(Vec));watch=calloc(2*nvar,sizeof(Vec));val=calloc(nvar+1,1);level=calloc(nvar+1,sizeof(int));trail=malloc((size_t)(nvar+1)*sizeof(int));int lit,ci=0;Vec tmp={0};while(fscanf(f,"%d",&lit)==1){if(!lit){if(ci>=ncl)return 1;clauses[ci]=tmp;tmp=(Vec){0};if(clauses[ci].n==0){puts("s UNSATISFIABLE");return 20;}push(&watch[idx(clauses[ci].a[0])],ci);if(clauses[ci].n==1){if(!enqueue(clauses[ci].a[0])){puts("s UNSATISFIABLE");return 20;}}else push(&watch[idx(clauses[ci].a[1])],ci);ci++;}else push(&tmp,lit);}fclose(f);if(ci!=ncl)return 1;int sat=solve();if(!sat){puts("s UNSATISFIABLE");return 20;}puts("s SATISFIABLE");for(int v=1;v<=nvar;v++){if((v-1)%20==0){if(v>1)printf("\n");printf("v ");}printf("%d ",val[v]<0?-v:v);}printf("0\n");if(nvar==0)puts("v 0");return 10;}
