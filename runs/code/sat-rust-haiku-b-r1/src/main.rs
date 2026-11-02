//! `solver FILE`: decides a DIMACS CNF formula.
//!
//! Output follows the SAT competition convention: `s SATISFIABLE` with `v` lines (exit 10), or
//! `s UNSATISFIABLE` (exit 20). Any model is re-checked against the input before it is printed.

mod dimacs;
mod solver;

use std::io::{self, Write};
use std::process::exit;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 2 {
        eprintln!("usage: {} FILE", args.first().map_or("solver", |s| s.as_str()));
        exit(1);
    }
    let data = match std::fs::read(&args[1]) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("c error: cannot read {}: {}", args[1], e);
            exit(1);
        }
    };
    let cnf = dimacs::parse(&data);
    let n = cnf.num_vars;

    match solver::solve(n, &cnf.clauses) {
        Some(model) => {
            let satisfied = cnf.clauses.iter().all(|c| {
                c.iter().any(|&x| model[x.unsigned_abs() as usize - 1] == (x > 0))
            });
            if !satisfied {
                // Internal error: never report an unverified model as SATISFIABLE.
                eprintln!("c internal error: model does not satisfy the formula");
                exit(1);
            }
            let stdout = io::stdout();
            let mut out = io::BufWriter::new(stdout.lock());
            writeln!(out, "s SATISFIABLE").expect("write to stdout");
            let mut line = String::from("v");
            for (v, &value) in model.iter().enumerate() {
                let lit = if value { v as i64 + 1 } else { -(v as i64 + 1) };
                if line.len() > 72 {
                    writeln!(out, "{line}").expect("write to stdout");
                    line = String::from("v");
                }
                line.push(' ');
                line.push_str(&lit.to_string());
            }
            line.push_str(" 0");
            writeln!(out, "{line}").expect("write to stdout");
            out.flush().expect("flush stdout");
            exit(10);
        }
        None => {
            println!("s UNSATISFIABLE");
            exit(20);
        }
    }
}
