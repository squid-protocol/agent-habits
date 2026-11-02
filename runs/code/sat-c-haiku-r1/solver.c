/*
 * solver.c - a SAT solver for DIMACS CNF formulas.
 *
 * The core is DPLL: unit propagation (two watched literals), decisions and
 * backtracking.  Backtracking is conflict-driven: each conflict yields a
 * first-UIP learnt clause, and the search backjumps to the clause's assertion
 * level.  VSIDS variable activities are kept in a binary heap.  The search
 * alternates between focused mode (LBD-based restarts, saved phases) and
 * stable mode (Luby restarts, target phases).  Learnt clauses are reduced by
 * LBD and activity.
 *
 * Usage: ./solver FILE
 *   SAT   : prints "s SATISFIABLE" and "v ..." lines ending in 0, exit 10
 *   UNSAT : prints "s UNSATISFIABLE", exit 20
 */

#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------------ */
/* Data structures                                                           */
/* ------------------------------------------------------------------------ */

/*
 * Literals: variable v (1..nvars) has positive literal 2v and negative
 * literal 2v+1, so the negation of l is l^1 and the variable is l>>1.
 */

typedef struct Clause {
    int size;
    int learnt;
    int deleted;
    int lbd;
    double act;
    int lits[];
} Clause;

typedef struct {
    Clause *c;
    int blocker; /* a literal of c; if it is true, c need not be inspected */
} Watcher;

typedef struct {
    Watcher *data;
    int size, cap;
} WatchList;

static int nvars;
static signed char *val;   /* per literal: 1 true, -1 false, 0 unassigned */
static int *level;         /* per variable: decision level of assignment */
static Clause **reason;    /* per variable: implying clause, NULL for decisions */
static int *trail;         /* assigned literals in assignment order */
static int trail_size, qhead;
static int *trail_lim;     /* trail_lim[i]: trail index where level i+1 starts */
static int dl;             /* current decision level */
static WatchList *watches; /* per literal: clauses watching that literal */

static Clause **learnts;
static int nlearnts, caplearnts;

static double *activity;   /* VSIDS activity per variable */
static double var_inc = 1.0;
static const double var_decay = 0.95;
static double cla_inc = 1.0;
static const double cla_decay = 0.999;
static signed char *polarity; /* saved phase: 1 = positive, 0 = negative */
static signed char *target;   /* phase of the largest conflict-free trail seen: 1, -1, or 0 = none */
static int best_trail;        /* largest trail size seen since the last restart */

static char *seen;
static int *to_clear, nto_clear;
static int *learnt_buf, learnt_size;
static int *lvl_stamp, stamp;

static int *heap, heap_size, *heap_pos;

static void oom(void) {
    fprintf(stderr, "c error: out of memory\n");
    exit(1);
}

static void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) oom();
    return p;
}

static void *xcalloc(size_t n, size_t s) {
    void *p = calloc(n ? n : 1, s ? s : 1);
    if (!p) oom();
    return p;
}

static void *xrealloc(void *p, size_t n) {
    void *q = realloc(p, n);
    if (!q) oom();
    return q;
}

/* ------------------------------------------------------------------------ */
/* VSIDS heap (max-heap on activity)                                         */
/* ------------------------------------------------------------------------ */

static void heap_up(int i) {
    int v = heap[i];
    while (i > 0) {
        int p = (i - 1) >> 1;
        if (activity[heap[p]] >= activity[v]) break;
        heap[i] = heap[p];
        heap_pos[heap[i]] = i;
        i = p;
    }
    heap[i] = v;
    heap_pos[v] = i;
}

static void heap_down(int i) {
    int v = heap[i];
    for (;;) {
        int c = 2 * i + 1;
        if (c >= heap_size) break;
        if (c + 1 < heap_size && activity[heap[c + 1]] > activity[heap[c]]) c++;
        if (activity[heap[c]] <= activity[v]) break;
        heap[i] = heap[c];
        heap_pos[heap[i]] = i;
        i = c;
    }
    heap[i] = v;
    heap_pos[v] = i;
}

static void heap_insert(int v) {
    if (heap_pos[v] >= 0) return;
    heap[heap_size] = v;
    heap_pos[v] = heap_size;
    heap_size++;
    heap_up(heap_pos[v]);
}

static int heap_pop(void) {
    int top = heap[0];
    heap_size--;
    heap_pos[top] = -1;
    if (heap_size > 0) {
        heap[0] = heap[heap_size];
        heap_pos[heap[0]] = 0;
        heap_down(0);
    }
    return top;
}

static void bump_var(int v) {
    if ((activity[v] += var_inc) > 1e100) {
        for (int i = 1; i <= nvars; i++) activity[i] *= 1e-100;
        var_inc *= 1e-100;
    }
    if (heap_pos[v] >= 0) heap_up(heap_pos[v]);
}

static void bump_clause(Clause *c) {
    if ((c->act += cla_inc) > 1e20) {
        for (int i = 0; i < nlearnts; i++) learnts[i]->act *= 1e-20;
        cla_inc *= 1e-20;
    }
}

/* ------------------------------------------------------------------------ */
/* Clauses, watches, assignments                                             */
/* ------------------------------------------------------------------------ */

static Clause *new_clause(const int *lits, int n, int learnt) {
    Clause *c = xmalloc(sizeof(Clause) + (size_t)n * sizeof(int));
    c->size = n;
    c->learnt = learnt;
    c->deleted = 0;
    c->lbd = 0;
    c->act = 0.0;
    memcpy(c->lits, lits, (size_t)n * sizeof(int));
    return c;
}

static void watch_push(int lit, Clause *c, int blocker) {
    WatchList *w = &watches[lit];
    if (w->size == w->cap) {
        w->cap = w->cap ? 2 * w->cap : 4;
        w->data = xrealloc(w->data, (size_t)w->cap * sizeof(Watcher));
    }
    w->data[w->size].c = c;
    w->data[w->size].blocker = blocker;
    w->size++;
}

static inline void assign(int lit, Clause *from) {
    int v = lit >> 1;
    val[lit] = 1;
    val[lit ^ 1] = -1;
    level[v] = dl;
    reason[v] = from;
    trail[trail_size++] = lit;
}

static void backtrack(int lvl) {
    if (dl <= lvl) return;
    for (int i = trail_size - 1; i >= trail_lim[lvl]; i--) {
        int lit = trail[i];
        int v = lit >> 1;
        polarity[v] = !(lit & 1);
        val[lit] = 0;
        val[lit ^ 1] = 0;
        reason[v] = NULL;
        heap_insert(v);
    }
    trail_size = trail_lim[lvl];
    qhead = trail_size;
    dl = lvl;
}

/*
 * Unit propagation over the trail starting at qhead.  Returns the conflicting
 * clause, or NULL if propagation reached a fixpoint.
 */
static Clause *propagate(void) {
    Clause *confl = NULL;
    while (qhead < trail_size) {
        int p = trail[qhead++];
        int fl = p ^ 1; /* literal that just became false */
        WatchList *ws = &watches[fl];
        Watcher *i = ws->data, *j = ws->data, *end = ws->data + ws->size;
        while (i < end) {
            if (val[i->blocker] == 1) {
                *j++ = *i++;
                continue;
            }
            Clause *c = i->c;
            int *lits = c->lits;
            if (lits[0] == fl) {
                lits[0] = lits[1];
                lits[1] = fl;
            }
            i++;
            int first = lits[0];
            if (val[first] == 1) {
                /* clause already satisfied by its other watch */
                j->c = c;
                j->blocker = first;
                j++;
                continue;
            }
            int found = 0;
            for (int k = 2; k < c->size; k++) {
                if (val[lits[k]] != -1) {
                    lits[1] = lits[k];
                    lits[k] = fl;
                    watch_push(lits[1], c, first);
                    found = 1;
                    break;
                }
            }
            if (found) continue;
            /* clause is unit or conflicting under the current assignment */
            j->c = c;
            j->blocker = first;
            j++;
            if (val[first] == -1) {
                confl = c;
                qhead = trail_size;
                while (i < end) *j++ = *i++; /* keep the remaining watchers */
            } else {
                assign(first, c);
            }
        }
        ws->size = (int)(j - ws->data);
        if (confl) break;
    }
    return confl;
}

/* ------------------------------------------------------------------------ */
/* Conflict analysis (first UIP)                                             */
/* ------------------------------------------------------------------------ */

/*
 * Derives a learnt clause from the conflict.  The result is left in
 * learnt_buf[0..learnt_size); learnt_buf[0] is the asserting literal.
 * Sets *out_bt to the backjump level and *out_lbd to the clause's LBD.
 */
static void analyze(Clause *confl, int *out_bt, int *out_lbd) {
    int pathC = 0, idx = trail_size - 1;
    int p = -1;
    learnt_size = 1; /* slot 0 is reserved for the UIP literal */
    nto_clear = 0;
    do {
        if (confl->learnt) bump_clause(confl);
        for (int k = 0; k < confl->size; k++) {
            int q = confl->lits[k];
            int v = q >> 1;
            if (seen[v] || level[v] == 0) continue;
            seen[v] = 1;
            to_clear[nto_clear++] = v;
            bump_var(v);
            if (level[v] >= dl)
                pathC++;
            else
                learnt_buf[learnt_size++] = q;
        }
        while (!seen[trail[idx] >> 1]) idx--;
        p = trail[idx];
        idx--;
        confl = reason[p >> 1];
        pathC--;
    } while (pathC > 0);
    learnt_buf[0] = p ^ 1;

    /* Local minimisation: drop a literal implied by the other learnt literals. */
    int j = 1;
    for (int i = 1; i < learnt_size; i++) {
        int q = learnt_buf[i];
        int v = q >> 1;
        Clause *r = reason[v];
        int keep = 1;
        if (r) {
            keep = 0;
            for (int k = 0; k < r->size; k++) {
                int u = r->lits[k] >> 1;
                if (u != v && !seen[u] && level[u] > 0) {
                    keep = 1;
                    break;
                }
            }
        }
        if (keep) learnt_buf[j++] = q;
    }
    learnt_size = j;

    for (int i = 0; i < nto_clear; i++) seen[to_clear[i]] = 0;

    int bt = 0;
    if (learnt_size > 1) {
        int mi = 1;
        for (int i = 2; i < learnt_size; i++)
            if (level[learnt_buf[i] >> 1] > level[learnt_buf[mi] >> 1]) mi = i;
        int tmp = learnt_buf[1];
        learnt_buf[1] = learnt_buf[mi];
        learnt_buf[mi] = tmp;
        bt = level[learnt_buf[1] >> 1];
    }

    stamp++;
    int lbd = 0;
    for (int i = 0; i < learnt_size; i++) {
        int L = level[learnt_buf[i] >> 1];
        if (lvl_stamp[L] != stamp) {
            lvl_stamp[L] = stamp;
            lbd++;
        }
    }
    *out_bt = bt;
    *out_lbd = lbd;
}

/* ------------------------------------------------------------------------ */
/* Clause database reduction                                                 */
/* ------------------------------------------------------------------------ */

static int cmp_learnt(const void *a, const void *b) {
    const Clause *x = *(Clause *const *)a;
    const Clause *y = *(Clause *const *)b;
    if (x->lbd != y->lbd) return x->lbd < y->lbd ? -1 : 1;
    if (x->act != y->act) return x->act > y->act ? -1 : 1;
    return 0;
}

static int is_locked(const Clause *c) {
    int l = c->lits[0];
    return val[l] == 1 && reason[l >> 1] == c;
}

static void reduce_db(void) {
    qsort(learnts, (size_t)nlearnts, sizeof(Clause *), cmp_learnt);
    Clause **dead = xmalloc((size_t)nlearnts * sizeof(Clause *));
    int ndead = 0, j = 0;
    for (int i = 0; i < nlearnts; i++) {
        Clause *c = learnts[i];
        if (i >= nlearnts / 2 && c->lbd > 2 && !is_locked(c)) {
            c->deleted = 1;
            dead[ndead++] = c;
        } else {
            learnts[j++] = c;
        }
    }
    nlearnts = j;
    if (ndead == 0) {
        free(dead);
        return;
    }
    for (int l = 0; l < 2 * (nvars + 1); l++) {
        WatchList *w = &watches[l];
        int k = 0;
        for (int i = 0; i < w->size; i++)
            if (!w->data[i].c->deleted) w->data[k++] = w->data[i];
        w->size = k;
    }
    for (int i = 0; i < ndead; i++) free(dead[i]);
    free(dead);
}

/* ------------------------------------------------------------------------ */
/* Search                                                                    */
/* ------------------------------------------------------------------------ */

/* The x-th term (0-based) of the Luby sequence 1,1,2,1,1,2,4,1,1,2,... */
static long luby(long x) {
    long size = 1;
    int seq = 0;
    while (size < x + 1) {
        seq++;
        size = 2 * size + 1;
    }
    while (size - 1 != x) {
        size = (size - 1) >> 1;
        seq--;
        x = x % size;
    }
    return 1L << seq;
}

static int pick_branch(void) {
    while (heap_size > 0) {
        int v = heap_pop();
        if (val[2 * v] == 0) return v;
    }
    return 0;
}

/*
 * Returns 1 if satisfiable (full assignment in val), 0 if unsatisfiable.
 *
 * The search alternates between two modes of growing length, measured in
 * conflicts.  Focused mode restarts when the recent average LBD of learnt
 * clauses is well above the long-term average and uses saved phases.  Stable
 * mode restarts on the Luby schedule and decides with target phases (the
 * assignment of the longest conflict-free trail seen).
 */
static int search(void) {
    const long luby_base = 512;
    const long focus_min_gap = 50;
    long luby_idx = 0;
    long luby_limit = luby_base * luby(luby_idx);
    long conf_since_restart = 0;
    long max_learnts = 4000;
    double ema_fast = 0.0, ema_slow = 0.0;
    long nconf = 0;
    int stable = 0;
    long mode_len = 1000, mode_left = mode_len;

    if (propagate()) return 0;

    for (;;) {
        Clause *confl = propagate();
        if (confl) {
            conf_since_restart++;
            if (dl == 0) return 0;

            if (stable && trail_size > best_trail) {
                /* remember the phases of this conflict-free prefix of the trail */
                best_trail = trail_size;
                for (int i = 0; i < trail_size; i++)
                    target[trail[i] >> 1] = (trail[i] & 1) ? -1 : 1;
            }

            int bt, lbd;
            analyze(confl, &bt, &lbd);
            backtrack(bt);
            if (learnt_size == 1) {
                assign(learnt_buf[0], NULL);
            } else {
                Clause *c = new_clause(learnt_buf, learnt_size, 1);
                c->lbd = lbd;
                if (nlearnts == caplearnts) {
                    caplearnts = caplearnts ? 2 * caplearnts : 1024;
                    learnts = xrealloc(learnts, (size_t)caplearnts * sizeof(Clause *));
                }
                learnts[nlearnts++] = c;
                watch_push(c->lits[0], c, c->lits[1]);
                watch_push(c->lits[1], c, c->lits[0]);
                bump_clause(c);
                assign(c->lits[0], c);
            }
            var_inc /= var_decay;
            cla_inc /= cla_decay;

            /* LBD moving averages (plain averages during warm-up) */
            nconf++;
            double a_fast = 1.0 / (nconf < 32 ? (double)nconf : 32.0);
            double a_slow = 1.0 / (nconf < 4096 ? (double)nconf : 4096.0);
            ema_fast += (lbd - ema_fast) * a_fast;
            ema_slow += (lbd - ema_slow) * a_slow;

            if (--mode_left == 0) {
                stable = !stable;
                if (stable) mode_len *= 2;
                mode_left = mode_len;
                backtrack(0);
                conf_since_restart = 0;
                best_trail = 0;
                continue;
            }

            int restart;
            if (stable)
                restart = conf_since_restart >= luby_limit;
            else
                restart = conf_since_restart >= focus_min_gap && ema_fast > 1.25 * ema_slow;
            if (restart) {
                backtrack(0);
                conf_since_restart = 0;
                best_trail = 0;
                if (stable) {
                    luby_idx++;
                    luby_limit = luby_base * luby(luby_idx);
                }
            }
        } else {
            if (nlearnts >= max_learnts) {
                reduce_db();
                max_learnts += max_learnts / 10 + 300;
            }
            int v = pick_branch();
            if (v == 0) return 1;
            trail_lim[dl++] = trail_size;
            int pos;
            if (stable && target[v] != 0)
                pos = target[v] > 0;
            else
                pos = polarity[v];
            int lit = pos ? 2 * v : 2 * v + 1;
            assign(lit, NULL);
        }
    }
}

/* ------------------------------------------------------------------------ */
/* DIMACS input                                                              */
/* ------------------------------------------------------------------------ */

typedef struct {
    int *lits;    /* all literals, each clause terminated by 0 */
    size_t n, cap;
    long nclauses;
    long header_vars;
    long maxvar;
} Formula;

static void formula_push(Formula *fm, int x) {
    if (fm->n == fm->cap) {
        fm->cap = fm->cap ? 2 * fm->cap : 4096;
        fm->lits = xrealloc(fm->lits, fm->cap * sizeof(int));
    }
    fm->lits[fm->n++] = x;
}

static void parse_dimacs(FILE *f, Formula *fm) {
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    int open_clause = 0; /* whether tokens of an unterminated clause were seen */
    while ((len = getline(&line, &cap, f)) != -1) {
        char *s = line;
        while (*s == ' ' || *s == '\t' || *s == '\r') s++;
        if (*s == '\0' || *s == '\n') continue;
        if (*s == 'c') continue;
        if (*s == '%') break; /* SATLIB end-of-formula marker */
        if (*s == 'p') {
            char fmt[16] = {0};
            long nv = 0, nc = 0;
            if (sscanf(s, "p %15s %ld %ld", fmt, &nv, &nc) != 3 || strcmp(fmt, "cnf") != 0) {
                fprintf(stderr, "c error: malformed header\n");
                exit(1);
            }
            fm->header_vars = nv;
            continue;
        }
        for (;;) {
            char *end;
            long x = strtol(s, &end, 10);
            if (end == s) break; /* no more numbers on this line */
            s = end;
            if (x > 1000000000L || x < -1000000000L) {
                fprintf(stderr, "c error: literal out of range\n");
                exit(1);
            }
            if (x == 0) {
                formula_push(fm, 0);
                fm->nclauses++;
                open_clause = 0;
            } else {
                long a = x < 0 ? -x : x;
                if (a > fm->maxvar) fm->maxvar = a;
                formula_push(fm, (int)x);
                open_clause = 1;
            }
        }
    }
    if (open_clause) { /* tolerate a missing final 0 */
        formula_push(fm, 0);
        fm->nclauses++;
    }
    free(line);
}

/* ------------------------------------------------------------------------ */
/* Main                                                                      */
/* ------------------------------------------------------------------------ */

static inline int enc(int x) { return x > 0 ? 2 * x : 2 * (-x) + 1; }

/*
 * Loads the formula into the solver.  Returns 0 if a contradiction is found
 * already (empty clause or conflicting units), 1 otherwise.
 */
static int load(const Formula *fm) {
    int *tmp = xmalloc((size_t)(fm->n + 1) * sizeof(int));
    int *mark = xcalloc((size_t)(2 * (nvars + 1)), sizeof(int));
    int ok = 1;
    int cid = 0;
    size_t s = 0;
    for (size_t i = 0; i < fm->n && ok; i++) {
        if (fm->lits[i] != 0) continue;
        /* clause occupies fm->lits[s..i) */
        cid++;
        int k = 0, taut = 0;
        for (size_t t = s; t < i; t++) {
            int l = enc(fm->lits[t]);
            if (mark[l ^ 1] == cid) {
                taut = 1;
                break;
            }
            if (mark[l] == cid) continue;
            mark[l] = cid;
            tmp[k++] = l;
        }
        s = i + 1;
        if (taut) continue;
        if (k == 0) {
            ok = 0;
        } else if (k == 1) {
            if (val[tmp[0]] == -1)
                ok = 0;
            else if (val[tmp[0]] == 0)
                assign(tmp[0], NULL);
        } else {
            Clause *c = new_clause(tmp, k, 0);
            watch_push(c->lits[0], c, c->lits[1]);
            watch_push(c->lits[1], c, c->lits[0]);
        }
    }
    free(tmp);
    free(mark);
    return ok;
}

static void print_model(void) {
    printf("s SATISFIABLE\n");
    printf("v");
    int col = 0;
    for (int v = 1; v <= nvars; v++) {
        printf(" %d", val[2 * v] == 1 ? v : -v);
        if (++col == 20 && v < nvars) {
            printf("\nv");
            col = 0;
        }
    }
    printf(" 0\n");
}

/* Independent check of the model against the input clauses. */
static int model_ok(const Formula *fm) {
    size_t s = 0;
    for (size_t i = 0; i < fm->n; i++) {
        if (fm->lits[i] != 0) continue;
        int sat = 0;
        for (size_t t = s; t < i && !sat; t++) {
            int x = fm->lits[t];
            if (x > 0 && val[2 * x] == 1) sat = 1;
            if (x < 0 && val[2 * (-x) + 1] == 1) sat = 1;
        }
        if (!sat) return 0;
        s = i + 1;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s FILE\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        fprintf(stderr, "c error: cannot open %s\n", argv[1]);
        return 1;
    }
    Formula fm = {0};
    parse_dimacs(f, &fm);
    fclose(f);

    nvars = (int)(fm.header_vars > fm.maxvar ? fm.header_vars : fm.maxvar);
    size_t nv1 = (size_t)nvars + 1;
    val = xcalloc(2 * nv1, sizeof(signed char));
    level = xcalloc(nv1, sizeof(int));
    reason = xcalloc(nv1, sizeof(Clause *));
    trail = xcalloc(nv1, sizeof(int));
    trail_lim = xcalloc(nv1, sizeof(int));
    watches = xcalloc(2 * nv1, sizeof(WatchList));
    activity = xcalloc(nv1, sizeof(double));
    polarity = xcalloc(nv1, sizeof(signed char));
    target = xcalloc(nv1, sizeof(signed char));
    seen = xcalloc(nv1, sizeof(char));
    to_clear = xcalloc(nv1, sizeof(int));
    learnt_buf = xcalloc(nv1, sizeof(int));
    lvl_stamp = xcalloc(nv1 + 1, sizeof(int));
    heap = xcalloc(nv1, sizeof(int));
    heap_pos = xcalloc(nv1, sizeof(int));
    for (size_t v = 0; v < nv1; v++) heap_pos[v] = -1;
    for (int v = nvars; v >= 1; v--) heap_insert(v);

    int sat;
    if (!load(&fm)) {
        sat = 0;
    } else {
        sat = search();
    }

    if (sat) {
        if (!model_ok(&fm)) {
            fprintf(stderr, "c internal error: model does not satisfy the formula\n");
            return 1;
        }
        print_model();
        fflush(stdout);
        return 10;
    }
    printf("s UNSATISFIABLE\n");
    fflush(stdout);
    return 20;
}
