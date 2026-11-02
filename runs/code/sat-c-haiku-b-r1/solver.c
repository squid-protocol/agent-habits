/*
 * solver.c - a SAT solver for DIMACS CNF formulas.
 *
 * Core: DPLL search (decide, unit propagation with two watched literals,
 * chronological backtracking) extended with conflict-driven clause learning
 * (first-UIP learning, clause minimisation, non-chronological backjumping),
 * VSIDS variable selection, phase saving, Luby restarts and periodic removal
 * of weak learnt clauses.
 *
 * Usage: ./solver FILE
 *   prints "s SATISFIABLE" + "v ... 0" and exits 10, or "s UNSATISFIABLE"
 *   and exits 20.  Exits 1 on usage or input errors.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

/* Literals are encoded as 2*var + sign (sign 1 = negative), var = 0-based. */

typedef struct Clause {
    int size;
    int lbd;
    int learnt;
    int deleted;
    int lits[];
} Clause;

typedef struct {
    Clause *c;
    int blocker;   /* a literal of c; if it is true the clause needs no visit */
} Watch;

typedef struct {
    Watch *d;
    int n, cap;
} WList;

static int nvars;
static signed char *val;      /* per literal: 1 true, -1 false, 0 unassigned */
static int *level;            /* per variable: decision level of assignment */
static Clause **reason;       /* per variable: implying clause, NULL for decisions */
static int *phase;            /* per variable: last polarity (1 = positive) */
static int *trail, trail_n, qhead;
static int *trail_lim, dlevel;
static WList *watches;        /* per literal: clauses watching that literal */
static int *seen, *learnt_buf, learnt_n, *clr_buf;
static int *lbd_stamp, lbd_counter;
static double *act, var_inc = 1.0;
static int *heap, heap_n, *heap_pos;
static Clause **clauses;  static int nclauses, cap_clauses;
static Clause **learnts;  static int nlearnts, cap_learnts;
static int root_unsat;

static void die(const char *msg) {
    fprintf(stderr, "error: %s\n", msg);
    exit(1);
}

static void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) die("out of memory");
    return p;
}

static void *xcalloc(size_t n, size_t sz) {
    void *p = calloc(n ? n : 1, sz ? sz : 1);
    if (!p) die("out of memory");
    return p;
}

static void wl_push(WList *w, Clause *c, int blocker) {
    if (w->n == w->cap) {
        w->cap = w->cap ? 2 * w->cap : 4;
        w->d = realloc(w->d, (size_t)w->cap * sizeof(Watch));
        if (!w->d) die("out of memory");
    }
    w->d[w->n].c = c;
    w->d[w->n].blocker = blocker;
    w->n++;
}

static void push_clause(Clause ***arr, int *n, int *cap, Clause *c) {
    if (*n == *cap) {
        *cap = *cap ? 2 * *cap : 64;
        *arr = realloc(*arr, (size_t)*cap * sizeof(Clause *));
        if (!*arr) die("out of memory");
    }
    (*arr)[(*n)++] = c;
}

static Clause *new_clause(const int *lits, int n, int learnt) {
    Clause *c = xmalloc(sizeof(Clause) + (size_t)n * sizeof(int));
    c->size = n;
    c->lbd = n;
    c->learnt = learnt;
    c->deleted = 0;
    memcpy(c->lits, lits, (size_t)n * sizeof(int));
    return c;
}

static void attach(Clause *c) {
    wl_push(&watches[c->lits[0]], c, c->lits[1]);
    wl_push(&watches[c->lits[1]], c, c->lits[0]);
}

/* ---------- VSIDS heap (max-heap on activity) ---------- */

static void heap_up(int i) {
    int v = heap[i];
    while (i > 0) {
        int p = (i - 1) / 2;
        if (act[heap[p]] >= act[v]) break;
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
        int l = 2 * i + 1;
        if (l >= heap_n) break;
        int r = l + 1;
        int c = (r < heap_n && act[heap[r]] > act[heap[l]]) ? r : l;
        if (act[heap[c]] <= act[v]) break;
        heap[i] = heap[c];
        heap_pos[heap[i]] = i;
        i = c;
    }
    heap[i] = v;
    heap_pos[v] = i;
}

static void heap_insert(int v) {
    heap_pos[v] = heap_n;
    heap[heap_n++] = v;
    heap_up(heap_n - 1);
}

static int heap_pop(void) {
    int v = heap[0];
    heap_pos[v] = -1;
    heap_n--;
    if (heap_n > 0) {
        heap[0] = heap[heap_n];
        heap_pos[heap[0]] = 0;
        heap_down(0);
    }
    return v;
}

static void bump_var(int v) {
    act[v] += var_inc;
    if (act[v] > 1e100) {
        for (int i = 0; i < nvars; i++) act[i] *= 1e-100;
        var_inc *= 1e-100;
    }
    if (heap_pos[v] >= 0) heap_up(heap_pos[v]);
}

/* ---------- assignment, propagation, backtracking ---------- */

static void assign(int lit, Clause *r) {
    int v = lit >> 1;
    val[lit] = 1;
    val[lit ^ 1] = -1;
    level[v] = dlevel;
    reason[v] = r;
    trail[trail_n++] = lit;
}

/* Returns the conflicting clause, or NULL if propagation reached a fixpoint. */
static Clause *propagate(void) {
    while (qhead < trail_n) {
        int p = trail[qhead++];          /* literal that just became true */
        int falselit = p ^ 1;            /* its negation is now false */
        WList *ws = &watches[falselit];
        Watch *w = ws->d;
        int i = 0, j = 0, n = ws->n;
        Clause *confl = NULL;

        while (i < n) {
            Watch wi = w[i];
            if (val[wi.blocker] == 1) {
                w[j++] = w[i++];
                continue;
            }
            Clause *c = wi.c;
            int *L = c->lits;
            if (L[0] == falselit) {     /* make sure the false literal is L[1] */
                L[0] = L[1];
                L[1] = falselit;
            }
            i++;
            int first = L[0];
            if (first != wi.blocker && val[first] == 1) {
                w[j].c = c;
                w[j].blocker = first;
                j++;
                continue;
            }
            int found = 0;
            for (int k = 2; k < c->size; k++) {
                if (val[L[k]] != -1) {
                    L[1] = L[k];
                    L[k] = falselit;
                    wl_push(&watches[L[1]], c, first);
                    found = 1;
                    break;
                }
            }
            if (found) continue;        /* watch moved away from falselit */
            w[j].c = c;
            w[j].blocker = first;
            j++;
            if (val[first] == -1) {
                confl = c;
                while (i < n) w[j++] = w[i++];
                break;
            }
            assign(first, c);
        }
        ws->n = j;
        if (confl) {
            qhead = trail_n;
            return confl;
        }
    }
    return NULL;
}

static void backtrack(int lvl) {
    if (dlevel <= lvl) return;
    for (int i = trail_n - 1; i >= trail_lim[lvl]; i--) {
        int lit = trail[i], v = lit >> 1;
        val[lit] = 0;
        val[lit ^ 1] = 0;
        phase[v] = (lit & 1) ? 0 : 1;
        reason[v] = NULL;
        if (heap_pos[v] < 0) heap_insert(v);
    }
    trail_n = trail_lim[lvl];
    qhead = trail_n;
    dlevel = lvl;
}

/* ---------- conflict analysis (first UIP) ---------- */

static int compute_lbd(const int *lits, int n) {
    lbd_counter++;
    int cnt = 0;
    for (int i = 0; i < n; i++) {
        int lv = level[lits[i] >> 1];
        if (lbd_stamp[lv] != lbd_counter) {
            lbd_stamp[lv] = lbd_counter;
            cnt++;
        }
    }
    return cnt;
}

/* Fills learnt_buf (asserting literal first, second-highest level second). */
static int analyze(Clause *confl, int *out_bt) {
    int pathC = 0, p = -1, idx = trail_n - 1;
    learnt_n = 1;                        /* slot 0 is reserved for the UIP */
    do {
        for (int k = 0; k < confl->size; k++) {
            int q = confl->lits[k];
            if (q == p) continue;        /* the implied literal of a reason */
            int v = q >> 1;
            if (!seen[v] && level[v] > 0) {
                seen[v] = 1;
                bump_var(v);
                if (level[v] >= dlevel) pathC++;
                else learnt_buf[learnt_n++] = q;
            }
        }
        while (!seen[trail[idx] >> 1]) idx--;
        p = trail[idx--];
        confl = reason[p >> 1];
        seen[p >> 1] = 0;
        pathC--;
    } while (pathC > 0);
    learnt_buf[0] = p ^ 1;

    /* Local minimisation: drop a literal whose reason is covered by the clause. */
    int orig = learnt_n;
    for (int i = 1; i < orig; i++) clr_buf[i] = learnt_buf[i] >> 1;
    int j = 1;
    for (int i = 1; i < orig; i++) {
        int q = learnt_buf[i], v = q >> 1;
        Clause *r = reason[v];
        int redundant = 0;
        if (r) {
            redundant = 1;
            for (int k = 0; k < r->size; k++) {
                int xv = r->lits[k] >> 1;
                if (xv == v) continue;
                if (!seen[xv] && level[xv] > 0) {
                    redundant = 0;
                    break;
                }
            }
        }
        if (!redundant) learnt_buf[j++] = q;
    }
    learnt_n = j;
    for (int i = 1; i < orig; i++) seen[clr_buf[i]] = 0;

    int bt = 0;
    if (learnt_n > 1) {
        int mi = 1;
        for (int i = 2; i < learnt_n; i++)
            if (level[learnt_buf[i] >> 1] > level[learnt_buf[mi] >> 1]) mi = i;
        int tmp = learnt_buf[1];
        learnt_buf[1] = learnt_buf[mi];
        learnt_buf[mi] = tmp;
        bt = level[learnt_buf[1] >> 1];
    }
    *out_bt = bt;
    return learnt_n;
}

static void learn(void) {
    if (learnt_n == 1) {
        assign(learnt_buf[0], NULL);     /* unit: backjumped to level 0 */
        return;
    }
    Clause *c = new_clause(learnt_buf, learnt_n, 1);
    c->lbd = compute_lbd(learnt_buf, learnt_n);
    push_clause(&learnts, &nlearnts, &cap_learnts, c);
    attach(c);
    assign(c->lits[0], c);
}

/* ---------- learnt clause database reduction (only at level 0) ---------- */

static int cmp_worst_first(const void *a, const void *b) {
    const Clause *x = *(Clause *const *)a, *y = *(Clause *const *)b;
    if (x->lbd != y->lbd) return y->lbd - x->lbd;
    return y->size - x->size;
}

static void reduce_db(void) {
    for (int i = 0; i < trail_n; i++) reason[trail[i] >> 1] = NULL;
    qsort(learnts, (size_t)nlearnts, sizeof *learnts, cmp_worst_first);
    int limit = nlearnts / 2;
    for (int i = 0; i < limit; i++) {
        Clause *c = learnts[i];
        if (c->lbd > 2 && c->size > 2) c->deleted = 1;
    }
    for (int l = 0; l < 2 * nvars; l++) watches[l].n = 0;
    int j = 0;
    for (int i = 0; i < nlearnts; i++) {
        Clause *c = learnts[i];
        if (c->deleted) {
            free(c);
        } else {
            learnts[j++] = c;
            attach(c);
        }
    }
    nlearnts = j;
    for (int i = 0; i < nclauses; i++) attach(clauses[i]);
}

/* ---------- search ---------- */

static long luby(long i) {           /* 1, 1, 2, 1, 1, 2, 4, ... (i >= 1) */
    long k = 1;
    while (((long)1 << k) - 1 < i) k++;
    for (;;) {
        if (i == ((long)1 << k) - 1) return (long)1 << (k - 1);
        i -= ((long)1 << (k - 1)) - 1;
        k = 1;
        while (((long)1 << k) - 1 < i) k++;
    }
}

/* Returns 1 if satisfiable (val holds a full model), 0 if unsatisfiable. */
static int solve(void) {
    if (root_unsat) return 0;
    if (propagate()) return 0;

    long conflicts = 0, next_reduce = 2000, reduce_inc = 300;
    long restart_idx = 1, since_restart = 0;
    long restart_limit = 100 * luby(restart_idx);

    for (;;) {
        Clause *confl = propagate();
        if (confl) {
            conflicts++;
            since_restart++;
            if (dlevel == 0) return 0;
            int bt;
            analyze(confl, &bt);
            backtrack(bt);
            learn();
            var_inc *= 1.0 / 0.95;
            if (var_inc > 1e100) {
                for (int i = 0; i < nvars; i++) act[i] *= 1e-100;
                var_inc *= 1e-100;
            }
        } else {
            if (since_restart >= restart_limit) {
                backtrack(0);
                since_restart = 0;
                restart_idx++;
                restart_limit = 100 * luby(restart_idx);
                if (conflicts >= next_reduce) {
                    reduce_db();
                    reduce_inc += 300;
                    next_reduce = conflicts + reduce_inc;
                }
                continue;
            }
            int v = -1;
            while (heap_n > 0) {
                int u = heap_pop();
                if (val[2 * u] == 0) {
                    v = u;
                    break;
                }
            }
            if (v < 0) return 1;     /* every variable assigned, no conflict */
            trail_lim[dlevel++] = trail_n;
            assign(phase[v] ? 2 * v : 2 * v + 1, NULL);
        }
    }
}

/* ---------- input ---------- */

static int *flat;                    /* DIMACS literals, each clause ends with 0 */
static size_t flat_n, flat_cap;
static long hdr_vars;

static void push_flat(long x) {
    if (flat_n == flat_cap) {
        flat_cap = flat_cap ? 2 * flat_cap : 1 << 16;
        flat = realloc(flat, flat_cap * sizeof(int));
        if (!flat) die("out of memory");
    }
    flat[flat_n++] = (int)x;
}

static int skip_ws(FILE *f) {
    int c;
    do c = getc(f);
    while (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v');
    return c;
}

static void skip_line(FILE *f) {
    int c;
    do c = getc(f);
    while (c != '\n' && c != EOF);
}

static void parse(FILE *f) {
    int open = 0;
    for (;;) {
        int c = skip_ws(f);
        if (c == EOF) break;
        if (c == 'c') {
            skip_line(f);
            continue;
        }
        if (c == 'p') {
            long nv, nc;
            if (fscanf(f, " cnf %ld %ld", &nv, &nc) != 2) die("bad 'p cnf' header");
            if (nv < 0 || nv > INT_MAX / 4) die("bad variable count");
            hdr_vars = nv;
            skip_line(f);
            continue;
        }
        if (c == '%') break;             /* SATLIB end marker */
        ungetc(c, f);
        long x;
        if (fscanf(f, "%ld", &x) != 1) die("unexpected token in input");
        if (x == LONG_MIN || x > INT_MAX / 4 || x < -(INT_MAX / 4)) die("literal out of range");
        if (x == 0) {
            push_flat(0);
            open = 0;
        } else {
            push_flat(x);
            open = 1;
        }
    }
    if (open) push_flat(0);          /* tolerate a missing final 0 */
}

static int cmp_int(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}

static int *cbuf;
static int cbuf_cap;

/* Adds one clause given as DIMACS literals (n of them). */
static void add_input_clause(const int *d, int n) {
    if (n + 1 > cbuf_cap) {
        cbuf_cap = n + 16;
        cbuf = realloc(cbuf, (size_t)cbuf_cap * sizeof(int));
        if (!cbuf) die("out of memory");
    }
    for (int i = 0; i < n; i++) {
        int x = d[i];
        int v = (x < 0 ? -x : x) - 1;
        cbuf[i] = 2 * v + (x < 0 ? 1 : 0);
    }
    qsort(cbuf, (size_t)n, sizeof(int), cmp_int);

    int m = 0;
    for (int i = 0; i < n; i++) {
        if (m > 0 && cbuf[m - 1] == cbuf[i]) continue;   /* duplicate literal */
        if (m > 0 && (cbuf[m - 1] ^ 1) == cbuf[i]) return; /* tautology */
        cbuf[m++] = cbuf[i];
    }
    if (m == 0) {
        root_unsat = 1;
        return;
    }
    if (m == 1) {
        int lit = cbuf[0];
        if (val[lit] == -1) root_unsat = 1;
        else if (val[lit] == 0) assign(lit, NULL);
        return;
    }
    Clause *c = new_clause(cbuf, m, 0);
    push_clause(&clauses, &nclauses, &cap_clauses, c);
    attach(c);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s FILE\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        fprintf(stderr, "error: cannot open %s\n", argv[1]);
        return 1;
    }
    parse(f);
    fclose(f);

    int maxvar = 0;
    for (size_t i = 0; i < flat_n; i++) {
        int x = flat[i] < 0 ? -flat[i] : flat[i];
        if (x > maxvar) maxvar = x;
    }
    nvars = (int)hdr_vars > maxvar ? (int)hdr_vars : maxvar;

    val = xcalloc(2 * (size_t)nvars + 2, sizeof(signed char));
    level = xcalloc((size_t)nvars + 1, sizeof(int));
    reason = xcalloc((size_t)nvars + 1, sizeof(Clause *));
    phase = xcalloc((size_t)nvars + 1, sizeof(int));
    trail = xcalloc((size_t)nvars + 1, sizeof(int));
    trail_lim = xcalloc((size_t)nvars + 1, sizeof(int));
    watches = xcalloc(2 * (size_t)nvars + 2, sizeof(WList));
    seen = xcalloc((size_t)nvars + 1, sizeof(int));
    learnt_buf = xcalloc((size_t)nvars + 1, sizeof(int));
    clr_buf = xcalloc((size_t)nvars + 1, sizeof(int));
    lbd_stamp = xcalloc((size_t)nvars + 2, sizeof(int));
    act = xcalloc((size_t)nvars + 1, sizeof(double));
    heap = xcalloc((size_t)nvars + 1, sizeof(int));
    heap_pos = xcalloc((size_t)nvars + 1, sizeof(int));
    for (int v = 0; v < nvars; v++) {
        heap_pos[v] = -1;
        heap_insert(v);
    }

    size_t start = 0;
    for (size_t i = 0; i < flat_n; i++) {
        if (flat[i] == 0) {
            add_input_clause(flat + start, (int)(i - start));
            start = i + 1;
        }
    }

    int sat = solve();
    if (sat) {
        printf("s SATISFIABLE\n");
        int col = 0;
        printf("v");
        for (int v = 0; v < nvars; v++) {
            int x = val[2 * v] == 1 ? v + 1 : -(v + 1);
            if (col == 20) {
                printf("\nv");
                col = 0;
            }
            printf(" %d", x);
            col++;
        }
        printf(" 0\n");
        fflush(stdout);
        return 10;
    }
    printf("s UNSATISFIABLE\n");
    fflush(stdout);
    return 20;
}
