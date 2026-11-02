//! DIMACS CNF parser.
//!
//! Comment lines start with `c`, the header is `p cnf <vars> <clauses>`, and clauses are
//! sequences of non-zero integers terminated by `0` (a clause may span several lines).
//! A line starting with `%` (SATLIB convention) ends the formula.

pub struct Cnf {
    /// Number of variables: the larger of the header count and the largest variable used.
    pub num_vars: usize,
    /// Clauses in DIMACS literal notation.
    pub clauses: Vec<Vec<i32>>,
}

pub fn parse(data: &[u8]) -> Cnf {
    let mut header_vars = 0usize;
    let mut max_var = 0usize;
    let mut clauses: Vec<Vec<i32>> = Vec::new();
    let mut current: Vec<i32> = Vec::new();

    for raw in data.split(|&b| b == b'\n') {
        let line = trim(raw);
        match line.first() {
            None | Some(b'c') => continue,
            Some(b'%') => break,
            Some(b'p') => {
                let mut toks = line.split(|b| b.is_ascii_whitespace()).filter(|t| !t.is_empty());
                toks.next(); // "p"
                toks.next(); // "cnf"
                if let Some(n) = toks.next().and_then(parse_int) {
                    header_vars = n.max(0) as usize;
                }
            }
            Some(_) => {
                for tok in line.split(|b| b.is_ascii_whitespace()).filter(|t| !t.is_empty()) {
                    let Some(x) = parse_int(tok) else { continue };
                    if x == 0 {
                        clauses.push(std::mem::take(&mut current));
                    } else {
                        max_var = max_var.max(x.unsigned_abs() as usize);
                        current.push(x);
                    }
                }
            }
        }
    }
    if !current.is_empty() {
        clauses.push(current);
    }
    Cnf { num_vars: header_vars.max(max_var), clauses }
}

fn trim(s: &[u8]) -> &[u8] {
    let start = s.iter().position(|b| !b.is_ascii_whitespace()).unwrap_or(s.len());
    let end = s.iter().rposition(|b| !b.is_ascii_whitespace()).map_or(start, |p| p + 1);
    &s[start..end]
}

fn parse_int(tok: &[u8]) -> Option<i32> {
    std::str::from_utf8(tok).ok()?.parse::<i32>().ok()
}
