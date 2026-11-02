use std::{env, fs, process};

#[derive(Clone)]
struct Clause { lits: Vec<usize>, watch: [usize; 2], learnt: bool }

struct Solver {
    n: usize, clauses: Vec<Clause>, watches: Vec<Vec<usize>>,
    val: Vec<i8>, level: Vec<usize>, reason: Vec<Option<usize>>, trail: Vec<usize>, limits: Vec<usize>, qhead: usize,
    activity: Vec<f64>, increment: f64,
}

impl Solver {
    fn new(n: usize) -> Self { Self { n, clauses: Vec::new(), watches: vec![Vec::new(); n*2], val: vec![0;n], level: vec![0;n], reason: vec![None;n], trail: Vec::new(), limits: Vec::new(), qhead: 0, activity: vec![0.0;n], increment: 1.0 } }
    fn add_clause(&mut self, lits: Vec<usize>, learnt: bool) -> usize {
        let id=self.clauses.len();
        let w0=0; let w1=if lits.len()>1 {1} else {0};
        self.clauses.push(Clause{lits,watch:[w0,w1],learnt});
        self.watches[self.clauses[id].lits[w0]].push(id);
        if w1!=w0 { let l=self.clauses[id].lits[w1]; self.watches[l].push(id); }
        id
    }
    fn value_lit(&self,l:usize)->i8 { let v=self.val[l/2]; if l%2==0 {v} else {-v} }
    fn enqueue(&mut self,l:usize, why:Option<usize>)->bool {
        let v=l/2; let wanted=if l%2==0 {1} else {-1};
        if self.val[v]!=0 {return self.val[v]==wanted;}
        self.val[v]=wanted; self.level[v]=self.limits.len(); self.reason[v]=why; self.trail.push(l); true
    }
    fn propagate(&mut self)->Option<usize> {
        while self.qhead<self.trail.len() {
            let assigned=self.trail[self.qhead]; self.qhead+=1; let false_lit=assigned^1;
            let mut i=0;
            while i<self.watches[false_lit].len() {
                let cid=self.watches[false_lit][i];
                let (wi,oi)={let c=&self.clauses[cid]; if c.lits[c.watch[0]]==false_lit {(0,1)} else {(1,0)}};
                let other=self.clauses[cid].lits[self.clauses[cid].watch[oi]];
                if self.value_lit(other)==1 {i+=1;continue;}
                let mut replacement=None;
                { let c=&self.clauses[cid]; for k in 0..c.lits.len() { if k!=c.watch[0] && k!=c.watch[1] && self.value_lit(c.lits[k])!=-1 {replacement=Some(k);break;} } }
                if let Some(k)=replacement {
                    let newlit=self.clauses[cid].lits[k]; self.clauses[cid].watch[wi]=k;
                    self.watches[false_lit].swap_remove(i); self.watches[newlit].push(cid);
                } else {
                    if self.value_lit(other)==-1 {return Some(cid);}
                    if !self.enqueue(other,Some(cid)) {return Some(cid);}
                    i+=1;
                }
            }
        }
        None
    }
    fn backtrack(&mut self, target:usize) {
        if self.limits.len()<=target{return;}
        let cut=self.limits[target];
        for &l in self.trail[cut..].iter().rev() {let v=l/2; self.val[v]=0;self.reason[v]=None;self.level[v]=0;}
        self.trail.truncate(cut); self.qhead=self.qhead.min(cut); self.limits.truncate(target);
    }
    fn analyze(&mut self, conflict:usize)->(Vec<usize>,usize) {
        let current=self.limits.len(); let mut learnt=vec![usize::MAX]; let mut seen=vec![false;self.n]; let mut path=0; let mut idx=self.trail.len(); let mut cid=conflict; let mut p=usize::MAX;
        loop {
            let lits=self.clauses[cid].lits.clone();
            for q in lits { let v=q/2; if q==p || seen[v] || self.level[v]==0 {continue;} seen[v]=true; self.activity[v]+=self.increment; if self.level[v]==current {path+=1;} else {learnt.push(q);} }
            while idx>0 {idx-=1; let q=self.trail[idx]; if seen[q/2] {p=q;break;}}
            let v=p/2; seen[v]=false; path-=1;
            if path==0 {break;}
            cid=self.reason[v].expect("non-UIP decision before UIP");
        }
        learnt[0]=p^1;
        let mut back=0; let mut best=1;
        for i in 1..learnt.len() {let lv=self.level[learnt[i]/2]; if lv>back {back=lv;best=i;}}
        if learnt.len()>1 {learnt.swap(1,best);}
        self.increment*=1.05; if self.increment>1e100 {for a in &mut self.activity {*a*=1e-100;} self.increment*=1e-100;}
        (learnt,back)
    }
    fn choose(&self)->Option<usize> { let mut best=None; let mut score=f64::NEG_INFINITY; for v in 0..self.n {if self.val[v]==0 && self.activity[v]>=score {score=self.activity[v];best=Some(v);}} best }
    fn solve(&mut self)->bool {
        loop {
            if let Some(conflict)=self.propagate() {
                if self.limits.is_empty(){return false;}
                let (learnt,back)=self.analyze(conflict); self.backtrack(back);
                let id=self.add_clause(learnt.clone(),true);
                if !self.enqueue(learnt[0],Some(id)){return false;}
            } else if let Some(v)=self.choose() {
                self.limits.push(self.trail.len()); self.enqueue(2*v,None);
            } else {return true;}
        }
    }
}

fn parse(path:&str)->Result<(usize,Vec<Vec<usize>>),String>{
    let input=fs::read_to_string(path).map_err(|e|e.to_string())?; let mut n=None; let mut expected=None; let mut clauses=Vec::new(); let mut cur=Vec::new();
    for line in input.lines(){let s=line.trim();if s.is_empty()||s.starts_with('c'){continue;} if s.starts_with('p'){let x:Vec<_>=s.split_whitespace().collect();if x.len()!=4||x[1]!="cnf"{return Err("invalid DIMACS header".into());} n=Some(x[2].parse::<usize>().map_err(|_|"invalid variable count")?);expected=Some(x[3].parse::<usize>().map_err(|_|"invalid clause count")?);continue;} for t in s.split_whitespace(){let x:i64=t.parse().map_err(|_|format!("invalid literal: {t}"))?;if x==0{clauses.push(std::mem::take(&mut cur));}else{let v=x.unsigned_abs() as usize;if v==0||n.map_or(false,|nn|v>nn){return Err("literal out of range".into());}cur.push(if x>0{2*(v-1)}else{2*(v-1)+1});}} }
    let n=n.ok_or("missing header")?;if !cur.is_empty(){return Err("unterminated clause".into());}if Some(clauses.len())!=expected{return Err("clause count mismatch".into());}Ok((n,clauses))
}
fn main(){
    let args:Vec<String>=env::args().collect(); if args.len()!=2{eprintln!("usage: solver FILE");process::exit(1);}
    let (n, input)=match parse(&args[1]){Ok(x)=>x,Err(e)=>{eprintln!("{e}");process::exit(1)}};
    let mut s=Solver::new(n); let mut immediate=false;
    for c in input {let mut seen=vec![false;n*2];let mut lits=Vec::new();let mut taut=false;for l in c {if seen[l^1]{taut=true;break;}if !seen[l]{seen[l]=true;lits.push(l);}}if taut{continue;}if lits.is_empty(){immediate=true;break;}for &l in &lits{s.activity[l/2]+=1.0;}let id=s.add_clause(lits.clone(),false);if lits.len()==1&&!s.enqueue(lits[0],Some(id)){immediate=true;break;}}
    if !immediate && s.solve(){println!("s SATISFIABLE");let mut line=String::from("v");for v in 0..n {let x=if s.val[v]>=0{(v+1) as i64}else{-((v+1) as i64)};let part=format!(" {x}");if line.len()+part.len()>78{println!("{line}");line=String::from("v");}line.push_str(&part);}line.push_str(" 0");println!("{line}");process::exit(10);}else{println!("s UNSATISFIABLE");process::exit(20);}
}
