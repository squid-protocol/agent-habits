*> ------------------------------------------------------------------
*> solver.cob -- SAT solver for DIMACS CNF, written for GnuCOBOL 3.1.
*>
*> Core: DPLL search. Unit propagation uses two watched literals per
*> clause; the search branches on unassigned variables and backtracks.
*> Extensions: first-UIP conflict-driven clause learning (so a conflict
*> backjumps instead of only flipping the last decision) with local
*> clause minimisation; VSIDS-style variable activity in an integer
*> binary heap; target phases alternating with saved phases between
*> restarts; geometric restarts; LBD-based deletion of learned clauses
*> at restarts.
*>
*> Literal encoding: variable v >= 1 gives literal 2*v (positive) and
*> 2*v+1 (negative); the negation of literal x is x+1 if x is even,
*> x-1 if odd.  LV(x) is 1 if x is true, -1 if false, 0 if unassigned.
*>
*> Usage: solver FILE
*>   prints "s SATISFIABLE" + "v ... 0" and exits 10,
*>   or prints "s UNSATISFIABLE" and exits 20.
*> ------------------------------------------------------------------
IDENTIFICATION DIVISION.
PROGRAM-ID. SATSOLVE.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT CNF-FILE ASSIGN TO WS-FILENAME
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FSTAT.

DATA DIVISION.
FILE SECTION.
FD CNF-FILE.
01 CNF-REC PIC X(32768).

WORKING-STORAGE SECTION.
01 WS-FILENAME      PIC X(4096).
01 WS-FSTAT         PIC XX.
01 WS-EOF           PIC 9 VALUE 0.

*> ---- solver state ----
01 WS-CTRL.
   05 WS-NV         PIC S9(9) COMP-5 VALUE 0.
   05 WS-NC         PIC S9(9) COMP-5 VALUE 0.
   05 WS-CLTOP      PIC S9(9) COMP-5 VALUE 0.
   05 WS-TN         PIC S9(9) COMP-5 VALUE 0.
   05 WS-QH         PIC S9(9) COMP-5 VALUE 0.
   05 WS-LVL        PIC S9(9) COMP-5 VALUE 0.
   05 WS-NLEARN     PIC S9(9) COMP-5 VALUE 0.
   05 WS-LIMIT      PIC S9(9) COMP-5 VALUE 4000.
   05 WS-RLIM       PIC S9(9) COMP-5 VALUE 100.
   05 WS-CSRST      PIC S9(9) COMP-5 VALUE 0.
   05 WS-CONF       PIC S9(9) COMP-5 VALUE 0.
   05 WS-CONFL      PIC S9(9) COMP-5 VALUE 0.
   05 WS-STATUS     PIC S9(9) COMP-5 VALUE 0.
   05 WS-STAMP      PIC S9(9) COMP-5 VALUE 0.
   05 WS-HSZ        PIC S9(9) COMP-5 VALUE 0.
   05 WS-PATHC      PIC S9(9) COMP-5 VALUE 0.
   05 WS-LN         PIC S9(9) COMP-5 VALUE 0.
   05 WS-IDX        PIC S9(9) COMP-5 VALUE 0.
   05 WS-BL         PIC S9(9) COMP-5 VALUE 0.
   05 WS-LBD        PIC S9(9) COMP-5 VALUE 0.
   05 WS-HDRNV      PIC S9(9) COMP-5 VALUE 0.
   05 WS-HDRNC      PIC S9(9) COMP-5 VALUE 0.
   05 WS-INHDR      PIC S9(9) COMP-5 VALUE 0.
   05 WS-HCNT       PIC S9(9) COMP-5 VALUE 0.
   05 WS-CN         PIC S9(9) COMP-5 VALUE 0.
   05 WS-TAUT       PIC S9(9) COMP-5 VALUE 0.
   05 WS-DUP        PIC S9(9) COMP-5 VALUE 0.
   05 WS-PAK        PIC S9(9) COMP-5 VALUE 0.
   05 WS-CHK        PIC S9(9) COMP-5 VALUE 0.
   05 WS-T1         PIC S9(9) COMP-5 VALUE 0.
   05 WS-RC2        PIC S9(9) COMP-5 VALUE 0.
   05 WS-E2         PIC S9(9) COMP-5 VALUE 0.
   05 WS-W          PIC S9(9) COMP-5 VALUE 0.
   05 WS-Q3         PIC S9(9) COMP-5 VALUE 0.
   05 WS-RED        PIC S9(9) COMP-5 VALUE 0.
   05 WS-J2         PIC S9(9) COMP-5 VALUE 0.
   05 WS-TMODE      PIC S9(9) COMP-5 VALUE 1.
   05 WS-BESTN      PIC S9(9) COMP-5 VALUE 0.
   05 WS-TLEN       PIC S9(9) COMP-5 VALUE 0.
   05 WS-NCAND      PIC S9(9) COMP-5 VALUE 0.
   05 WS-HALF       PIC S9(9) COMP-5 VALUE 0.
   05 WS-THR        PIC S9(9) COMP-5 VALUE 0.
   05 WS-ACC        PIC S9(9) COMP-5 VALUE 0.
   05 WS-QT         PIC S9(9) COMP-5 VALUE 0.
   05 WS-LBX        PIC S9(9) COMP-5 VALUE 0.

*> ---- scratch registers ----
01 WS-WORK.
   05 WS-X          PIC S9(9) COMP-5 VALUE 0.
   05 WS-NG         PIC S9(9) COMP-5 VALUE 0.
   05 WS-NL         PIC S9(9) COMP-5 VALUE 0.
   05 WS-Q          PIC S9(9) COMP-5 VALUE 0.
   05 WS-R          PIC S9(9) COMP-5 VALUE 0.
   05 WS-V          PIC S9(9) COMP-5 VALUE 0.
   05 WS-BV         PIC S9(9) COMP-5 VALUE 0.
   05 WS-AV         PIC S9(9) COMP-5 VALUE 0.
   05 WS-P          PIC S9(9) COMP-5 VALUE 0.
   05 WS-F          PIC S9(9) COMP-5 VALUE 0.
   05 WS-O          PIC S9(9) COMP-5 VALUE 0.
   05 WS-C          PIC S9(9) COMP-5 VALUE 0.
   05 WS-S          PIC S9(9) COMP-5 VALUE 0.
   05 WS-E          PIC S9(9) COMP-5 VALUE 0.
   05 WS-K          PIC S9(9) COMP-5 VALUE 0.
   05 WS-KL         PIC S9(9) COMP-5 VALUE 0.
   05 WS-FOUND      PIC S9(9) COMP-5 VALUE 0.
   05 WS-CUR        PIC S9(9) COMP-5 VALUE 0.
   05 WS-PREV       PIC S9(9) COMP-5 VALUE 0.
   05 WS-NXT        PIC S9(9) COMP-5 VALUE 0.
   05 WS-TMPL       PIC S9(9) COMP-5 VALUE 0.
   05 WS-N1         PIC S9(9) COMP-5 VALUE 0.
   05 WS-N2         PIC S9(9) COMP-5 VALUE 0.
   05 WS-AL         PIC S9(9) COMP-5 VALUE 0.
   05 WS-AR         PIC S9(9) COMP-5 VALUE 0.
   05 WS-RC         PIC S9(9) COMP-5 VALUE 0.
   05 WS-SKIPF      PIC S9(9) COMP-5 VALUE 0.
   05 WS-Q2         PIC S9(9) COMP-5 VALUE 0.
   05 WS-IA         PIC S9(9) COMP-5 VALUE 0.
   05 WS-IB         PIC S9(9) COMP-5 VALUE 0.
   05 WS-IC         PIC S9(9) COMP-5 VALUE 0.
   05 WS-IP         PIC S9(9) COMP-5 VALUE 0.
   05 WS-I          PIC S9(9) COMP-5 VALUE 0.
   05 WS-XV         PIC S9(9) COMP-5 VALUE 0.
   05 WS-PA         PIC S9(9) COMP-5 VALUE 0.
   05 WS-CH         PIC S9(9) COMP-5 VALUE 0.
   05 WS-DONE       PIC S9(9) COMP-5 VALUE 0.
   05 WS-HV         PIC S9(9) COMP-5 VALUE 0.
   05 WS-LIM        PIC S9(9) COMP-5 VALUE 0.
   05 WS-NEWNC      PIC S9(9) COMP-5 VALUE 0.
   05 WS-NEWTOP     PIC S9(9) COMP-5 VALUE 0.
   05 WS-NEWST      PIC S9(9) COMP-5 VALUE 0.
   05 WS-NEWLRN     PIC S9(9) COMP-5 VALUE 0.
   05 WS-KEEP       PIC S9(9) COMP-5 VALUE 0.
   05 WS-BEST       PIC S9(9) COMP-5 VALUE 0.
   05 WS-LVX        PIC S9(9) COMP-5 VALUE 0.
   05 WS-LI         PIC S9(9) COMP-5 VALUE 0.
   05 WS-VV         PIC S9(9) COMP-5 VALUE 0.
   05 WS-TK         PIC S9(9) COMP-5 VALUE 0.
   05 WS-TKV        PIC S9(9) COMP-5 VALUE 0.
   05 WS-TKNEG      PIC S9(9) COMP-5 VALUE 0.
   05 WS-TKIN       PIC S9(9) COMP-5 VALUE 0.
   05 WS-LEN        PIC S9(9) COMP-5 VALUE 0.
   05 WS-FP         PIC S9(9) COMP-5 VALUE 0.
   05 WS-IP2        PIC S9(9) COMP-5 VALUE 0.
   05 WS-SV         PIC S9(9) COMP-5 VALUE 0.
   05 WS-OP         PIC S9(9) COMP-5 VALUE 0.
   05 WS-HOLD       PIC S9(9) COMP-5 VALUE 0.
   05 WS-J-HOLD     PIC S9(9) COMP-5 VALUE 0.

01 WS-DIG.
   05 WS-DIGX       PIC X.
   05 WS-DIGN REDEFINES WS-DIGX PIC 9.
01 WS-CH-X          PIC X.
01 WS-ED            PIC -(9)9.
01 WS-TXT           PIC X(16).
01 WS-OUT           PIC X(200).
01 WS-INC           PIC S9(9) COMP-5 VALUE 1000.

*> ---- tables (indices 1-based; MAXV = 200000 variables) ----
*> per-literal tables (literal index 2..400001)
01 T-LIT.
   05 LV OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 WHEAD OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 NEGT OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 VOF OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 LSIGN OCCURS 400002 TIMES PIC S9(9) COMP-5.
*> watch nodes (node c = slot 0 of clause c, node c+400001 = slot 1)
01 T-WATCH.
   05 WNX OCCURS 800002 TIMES PIC S9(9) COMP-5.
   05 WCL OCCURS 800002 TIMES PIC S9(9) COMP-5.
*> per-variable tables (variable 1..200000)
01 T-VAR.
   05 VLEV OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 VREA OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 VSAV OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 SEEN OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 HPOS OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 HEAP OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 HPAR OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 ACT OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 TRAIL OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 DLIM OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 LVST OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 LKEEP OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 LBDH OCCURS 1002 TIMES PIC S9(9) COMP-5.
   05 TGT OCCURS 200002 TIMES PIC S9(9) COMP-5.
*> clauses 1..400001
01 T-CLS.
   05 CST OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 CEN OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 CLN OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 CLRN OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 CLBD OCCURS 400002 TIMES PIC S9(9) COMP-5.
   05 CLUSE OCCURS 400002 TIMES PIC S9(9) COMP-5.
01 T-CL.
   05 CL OCCURS 8000002 TIMES PIC S9(9) COMP-5.
01 T-CUR.
   05 CUR OCCURS 200002 TIMES PIC S9(9) COMP-5.
   05 LRN OCCURS 200002 TIMES PIC S9(9) COMP-5.

PROCEDURE DIVISION.

*> ==================================================================
*> Main
*> ==================================================================
MAIN-PARA.
    ACCEPT WS-FILENAME FROM ARGUMENT-VALUE
    PERFORM INIT-TABLES
    OPEN INPUT CNF-FILE
    IF WS-FSTAT NOT = "00"
        DISPLAY "c cannot open input file" UPON SYSERR
        MOVE 1 TO RETURN-CODE
        STOP RUN
    END-IF
    PERFORM READ-ALL-LINES
    CLOSE CNF-FILE
    IF WS-STATUS = 0
        PERFORM INIT-HEAP
        PERFORM SOLVE
    END-IF
    IF WS-STATUS = 1
        PERFORM PRINT-SAT
        MOVE 10 TO RETURN-CODE
    ELSE
        DISPLAY "s UNSATISFIABLE"
        MOVE 20 TO RETURN-CODE
    END-IF
    STOP RUN.

*> Literal tables: literal 2v = positive v, 2v+1 = negative v.
INIT-TABLES.
    PERFORM VARYING WS-IC FROM 1 BY 1 UNTIL WS-IC > 400002
        MOVE 0 TO LV(WS-IC)
        MOVE 0 TO WHEAD(WS-IC)
        MOVE 0 TO NEGT(WS-IC)
        MOVE 0 TO VOF(WS-IC)
        MOVE 0 TO LSIGN(WS-IC)
    END-PERFORM
    MOVE 2 TO WS-LI
    PERFORM VARYING WS-V FROM 1 BY 1 UNTIL WS-V > 200000
        MOVE WS-LI TO WS-T1
        ADD 1 TO WS-T1
        MOVE WS-T1 TO NEGT(WS-LI)
        MOVE WS-LI TO NEGT(WS-T1)
        MOVE 1 TO LSIGN(WS-LI)
        MOVE 0 TO LSIGN(WS-T1)
        MOVE WS-V TO VOF(WS-LI)
        MOVE WS-V TO VOF(WS-T1)
        ADD 2 TO WS-LI
    END-PERFORM
    *> parent table of the binary heap: parent(i) = i / 2
    MOVE 1 TO WS-PAK
    MOVE 2 TO WS-CHK
    PERFORM UNTIL WS-CHK > 200001
        MOVE WS-PAK TO HPAR(WS-CHK)
        ADD 1 TO WS-CHK
        MOVE WS-PAK TO HPAR(WS-CHK)
        ADD 1 TO WS-CHK
        ADD 1 TO WS-PAK
    END-PERFORM
    PERFORM VARYING WS-IC FROM 1 BY 1 UNTIL WS-IC > 200002
        MOVE 0 TO VLEV(WS-IC)
        MOVE 0 TO VREA(WS-IC)
        MOVE 0 TO VSAV(WS-IC)
        MOVE 0 TO SEEN(WS-IC)
        MOVE 0 TO HPOS(WS-IC)
        MOVE 0 TO LVST(WS-IC)
        MOVE 0 TO ACT(WS-IC)
        MOVE 0 TO LKEEP(WS-IC)
    END-PERFORM.

*> ==================================================================
*> Parsing
*> ==================================================================
READ-ALL-LINES.
    MOVE 0 TO WS-EOF
    PERFORM UNTIL WS-EOF = 1
        READ CNF-FILE
            AT END
                MOVE 1 TO WS-EOF
            NOT AT END
                PERFORM PROCESS-LINE
        END-READ
    END-PERFORM
    IF WS-CN > 0
        PERFORM END-CLAUSE
    END-IF.

PROCESS-LINE.
    MOVE FUNCTION LENGTH(FUNCTION TRIM(CNF-REC TRAILING)) TO WS-LEN
    MOVE 1 TO WS-FP
    PERFORM UNTIL WS-FP > WS-LEN OR CNF-REC(WS-FP:1) NOT = SPACE
        ADD 1 TO WS-FP
    END-PERFORM
    IF WS-FP <= WS-LEN
        MOVE CNF-REC(WS-FP:1) TO WS-CH-X
        EVALUATE TRUE
            WHEN WS-CH-X = "c"
                CONTINUE
            WHEN WS-CH-X = "%"
                MOVE 1 TO WS-EOF
            WHEN WS-CH-X = "p"
                MOVE 1 TO WS-INHDR
                MOVE 0 TO WS-HCNT
                PERFORM SCAN-TOKENS
                MOVE 0 TO WS-INHDR
            WHEN OTHER
                PERFORM SCAN-TOKENS
        END-EVALUATE
    END-IF.

SCAN-TOKENS.
    MOVE 0 TO WS-TKIN
    MOVE 0 TO WS-TKV
    MOVE 0 TO WS-TKNEG
    PERFORM VARYING WS-IP FROM 1 BY 1 UNTIL WS-IP > WS-LEN
        MOVE CNF-REC(WS-IP:1) TO WS-CH-X
        IF WS-CH-X >= "0" AND WS-CH-X <= "9"
            MOVE WS-CH-X TO WS-DIGX
            COMPUTE WS-TKV = WS-TKV * 10 + WS-DIGN
            MOVE 1 TO WS-TKIN
        ELSE
            IF WS-TKIN = 1
                PERFORM EMIT-TOKEN
                MOVE 0 TO WS-TKIN
                MOVE 0 TO WS-TKV
            END-IF
            IF WS-CH-X = "-"
                MOVE 1 TO WS-TKNEG
            ELSE
                MOVE 0 TO WS-TKNEG
            END-IF
        END-IF
    END-PERFORM
    IF WS-TKIN = 1
        PERFORM EMIT-TOKEN
    END-IF.

EMIT-TOKEN.
    IF WS-TKNEG = 1
        COMPUTE WS-TK = 0 - WS-TKV
    ELSE
        MOVE WS-TKV TO WS-TK
    END-IF
    IF WS-INHDR = 1
        IF WS-HCNT = 0
            MOVE WS-TKV TO WS-HDRNV
            IF WS-TKV > WS-NV
                MOVE WS-TKV TO WS-NV
            END-IF
        ELSE
            MOVE WS-TKV TO WS-HDRNC
        END-IF
        ADD 1 TO WS-HCNT
    ELSE
        IF WS-TK = 0
            PERFORM END-CLAUSE
        ELSE
            PERFORM ADD-LIT
        END-IF
    END-IF.

*> Add literal WS-TK to the clause under construction, dropping
*> duplicates and flagging tautologies.
ADD-LIT.
    IF WS-TK > 0
        MOVE WS-TK TO WS-VV
        MOVE WS-TK TO WS-LI
        ADD WS-TK TO WS-LI
    ELSE
        COMPUTE WS-VV = 0 - WS-TK
        MOVE WS-VV TO WS-LI
        ADD WS-VV TO WS-LI
        ADD 1 TO WS-LI
    END-IF
    IF WS-VV > WS-NV
        MOVE WS-VV TO WS-NV
    END-IF
    MOVE NEGT(WS-LI) TO WS-NL
    MOVE 0 TO WS-DUP
    PERFORM VARYING WS-IA FROM 1 BY 1 UNTIL WS-IA > WS-CN
        IF CUR(WS-IA) = WS-LI
            MOVE 1 TO WS-DUP
        END-IF
        IF CUR(WS-IA) = WS-NL
            MOVE 1 TO WS-TAUT
        END-IF
    END-PERFORM
    IF WS-DUP = 0
        ADD 1 TO WS-CN
        MOVE WS-LI TO CUR(WS-CN)
    END-IF.

*> Finish the clause under construction: empty -> UNSAT, unit ->
*> assign at level 0, otherwise store it in the clause arena.
END-CLAUSE.
    IF WS-TAUT = 0
        EVALUATE TRUE
            WHEN WS-CN = 0
                MOVE 2 TO WS-STATUS
            WHEN WS-CN = 1
                MOVE CUR(1) TO WS-LI
                IF LV(WS-LI) = -1
                    MOVE 2 TO WS-STATUS
                END-IF
                IF LV(WS-LI) = 0
                    MOVE WS-LI TO WS-AL
                    MOVE 0 TO WS-AR
                    PERFORM ASSIGN-LIT
                END-IF
            WHEN OTHER
                ADD 1 TO WS-NC
                MOVE WS-NC TO WS-C
                COMPUTE CST(WS-C) = WS-CLTOP + 1
                MOVE WS-CN TO CLN(WS-C)
                MOVE CST(WS-C) TO CEN(WS-C)
                ADD WS-CN TO CEN(WS-C)
                SUBTRACT 1 FROM CEN(WS-C)
                MOVE 0 TO CLRN(WS-C)
                MOVE 0 TO CLBD(WS-C)
                MOVE 0 TO CLUSE(WS-C)
                PERFORM VARYING WS-IA FROM 1 BY 1 UNTIL WS-IA > WS-CN
                    MOVE CUR(WS-IA) TO CL(WS-CLTOP + WS-IA)
                END-PERFORM
                ADD WS-CN TO WS-CLTOP
        END-EVALUATE
    END-IF
    MOVE 0 TO WS-CN
    MOVE 0 TO WS-TAUT.

*> Make literal WS-AL true at level WS-LVL with reason clause WS-AR
*> (0 = decision or level-0 fact).
ASSIGN-LIT.
    MOVE 1 TO LV(WS-AL)
    MOVE NEGT(WS-AL) TO WS-NG
    MOVE -1 TO LV(WS-NG)
    MOVE VOF(WS-AL) TO WS-AV
    MOVE WS-LVL TO VLEV(WS-AV)
    MOVE WS-AR TO VREA(WS-AV)
    ADD 1 TO WS-TN
    MOVE WS-AL TO TRAIL(WS-TN).

*> ==================================================================
*> Watched-literal structures
*> ==================================================================
*> Clause c has watch nodes c and c+400001, linked into the list
*> WHEAD(literal) of the literal each one watches. The two watched
*> literals of a clause are CL(CST(c)) and CL(CST(c)+1).
BUILD-WATCHES.
    PERFORM VARYING WS-IC FROM 2 BY 1 UNTIL WS-IC > 2 * WS-NV + 1
        MOVE 0 TO WHEAD(WS-IC)
    END-PERFORM
    PERFORM VARYING WS-C FROM 1 BY 1 UNTIL WS-C > WS-NC
        MOVE CST(WS-C) TO WS-S
        MOVE CEN(WS-C) TO WS-E
        *> Move non-false literals to the front so the watches are valid.
        MOVE WS-S TO WS-K
        PERFORM VARYING WS-IA FROM WS-S BY 1 UNTIL WS-IA > WS-E
            IF LV(CL(WS-IA)) NOT = -1
                MOVE CL(WS-K) TO WS-TMPL
                MOVE CL(WS-IA) TO CL(WS-K)
                MOVE WS-TMPL TO CL(WS-IA)
                ADD 1 TO WS-K
            END-IF
        END-PERFORM
        PERFORM LINK-CLAUSE-WATCHES
    END-PERFORM.

*> Link both watch nodes of clause WS-C (watching CL(CST) and CL(CST+1)).
LINK-CLAUSE-WATCHES.
    MOVE CST(WS-C) TO WS-S
    MOVE WS-C TO WS-N1
    MOVE WS-C TO WS-N2
    ADD 400001 TO WS-N2
    MOVE WS-C TO WCL(WS-N1)
    MOVE WS-C TO WCL(WS-N2)
    MOVE WHEAD(CL(WS-S)) TO WNX(WS-N1)
    MOVE WS-N1 TO WHEAD(CL(WS-S))
    MOVE WHEAD(CL(WS-S + 1)) TO WNX(WS-N2)
    MOVE WS-N2 TO WHEAD(CL(WS-S + 1)).

*> ==================================================================
*> Unit propagation (two watched literals)
*> ==================================================================
*> Processes the trail from WS-QH. Sets WS-CONFL to a conflicting
*> clause index, or leaves it 0.
PROPAGATE.
    MOVE 0 TO WS-CONFL
    PERFORM UNTIL WS-QH >= WS-TN OR WS-CONFL NOT = 0
        ADD 1 TO WS-QH
        MOVE TRAIL(WS-QH) TO WS-P
        MOVE NEGT(WS-P) TO WS-F
        PERFORM VISIT-WATCHES
    END-PERFORM.

*> Visit the watches of the literal WS-F that just became false.
VISIT-WATCHES.
    MOVE WHEAD(WS-F) TO WS-CUR
    MOVE 0 TO WS-PREV
    PERFORM UNTIL WS-CUR = 0 OR WS-CONFL NOT = 0
        MOVE WCL(WS-CUR) TO WS-C
        MOVE WNX(WS-CUR) TO WS-NXT
        MOVE CST(WS-C) TO WS-S
        IF CL(WS-S) = WS-F
            MOVE CL(WS-S) TO WS-TMPL
            MOVE CL(WS-S + 1) TO CL(WS-S)
            MOVE WS-TMPL TO CL(WS-S + 1)
        END-IF
        *> now CL(WS-S + 1) = WS-F
        MOVE CL(WS-S) TO WS-O
        IF LV(WS-O) = 1
            MOVE WS-CUR TO WS-PREV
        ELSE
            MOVE CEN(WS-C) TO WS-E
            MOVE 0 TO WS-FOUND
            MOVE WS-S TO WS-K
            ADD 2 TO WS-K
            PERFORM UNTIL WS-K > WS-E OR WS-FOUND = 1
                IF LV(CL(WS-K)) NOT = -1
                    MOVE 1 TO WS-FOUND
                ELSE
                    ADD 1 TO WS-K
                END-IF
            END-PERFORM
            IF WS-FOUND = 1
                *> move the watch from WS-F to CL(WS-K)
                MOVE CL(WS-K) TO WS-KL
                MOVE WS-F TO CL(WS-K)
                MOVE WS-KL TO CL(WS-S + 1)
                IF WS-PREV = 0
                    MOVE WS-NXT TO WHEAD(WS-F)
                ELSE
                    MOVE WS-NXT TO WNX(WS-PREV)
                END-IF
                MOVE WHEAD(WS-KL) TO WNX(WS-CUR)
                MOVE WS-CUR TO WHEAD(WS-KL)
            ELSE
                IF LV(WS-O) = -1
                    MOVE WS-C TO WS-CONFL
                ELSE
                    MOVE WS-O TO WS-AL
                    MOVE WS-C TO WS-AR
                    PERFORM ASSIGN-LIT
                END-IF
                MOVE WS-CUR TO WS-PREV
            END-IF
        END-IF
        MOVE WS-NXT TO WS-CUR
    END-PERFORM.

*> ==================================================================
*> Variable activity heap (max-heap on ACT, integer scores)
*> ==================================================================
INIT-HEAP.
    MOVE 0 TO WS-HSZ
    PERFORM VARYING WS-V FROM 1 BY 1 UNTIL WS-V > WS-NV
        MOVE WS-V TO WS-HV
        PERFORM HEAP-INSERT
    END-PERFORM.

*> Insert WS-HV (not already in heap).
HEAP-INSERT.
    ADD 1 TO WS-HSZ
    MOVE WS-HSZ TO WS-I
    MOVE WS-HV TO HEAP(WS-I)
    PERFORM SIFT-UP.

*> Element at HEAP(WS-I) moves up; sets HPOS for it.
SIFT-UP.
    MOVE HEAP(WS-I) TO WS-XV
    MOVE 0 TO WS-DONE
    PERFORM UNTIL WS-DONE = 1 OR WS-I <= 1
        MOVE HPAR(WS-I) TO WS-PA
        IF ACT(HEAP(WS-PA)) >= ACT(WS-XV)
            MOVE 1 TO WS-DONE
        ELSE
            MOVE HEAP(WS-PA) TO HEAP(WS-I)
            MOVE WS-I TO HPOS(HEAP(WS-I))
            MOVE WS-PA TO WS-I
        END-IF
    END-PERFORM
    MOVE WS-XV TO HEAP(WS-I)
    MOVE WS-I TO HPOS(WS-XV).

*> Element at HEAP(WS-I) moves down.
SIFT-DOWN.
    MOVE HEAP(WS-I) TO WS-XV
    MOVE 0 TO WS-DONE
    PERFORM UNTIL WS-DONE = 1
        MOVE WS-I TO WS-CH
        ADD WS-I TO WS-CH
        IF WS-CH > WS-HSZ
            MOVE 1 TO WS-DONE
        ELSE
            IF WS-CH < WS-HSZ
                IF ACT(HEAP(WS-CH + 1)) > ACT(HEAP(WS-CH))
                    ADD 1 TO WS-CH
                END-IF
            END-IF
            IF ACT(HEAP(WS-CH)) <= ACT(WS-XV)
                MOVE 1 TO WS-DONE
            ELSE
                MOVE HEAP(WS-CH) TO HEAP(WS-I)
                MOVE WS-I TO HPOS(HEAP(WS-I))
                MOVE WS-CH TO WS-I
            END-IF
        END-IF
    END-PERFORM
    MOVE WS-XV TO HEAP(WS-I)
    MOVE WS-I TO HPOS(WS-XV).

*> Remove the top variable into WS-V.
HEAP-POP.
    MOVE HEAP(1) TO WS-V
    MOVE 0 TO HPOS(WS-V)
    MOVE HEAP(WS-HSZ) TO WS-XV
    SUBTRACT 1 FROM WS-HSZ
    IF WS-HSZ > 0
        MOVE WS-XV TO HEAP(1)
        MOVE 1 TO HPOS(WS-XV)
        MOVE 1 TO WS-I
        PERFORM SIFT-DOWN
    END-IF.

*> Increase activity of WS-BV by the current increment.
BUMP-VAR.
    ADD WS-INC TO ACT(WS-BV)
    IF HPOS(WS-BV) > 0
        MOVE HPOS(WS-BV) TO WS-I
        PERFORM SIFT-UP
    END-IF.

*> Per conflict: grow the increment; rescale all scores when it gets large.
DECAY-ACTIVITY.
    COMPUTE WS-INC = WS-INC + WS-INC / 19
    IF WS-INC > 20000000
        PERFORM VARYING WS-IC FROM 1 BY 1 UNTIL WS-IC > WS-NV
            COMPUTE ACT(WS-IC) = ACT(WS-IC) / 1000
        END-PERFORM
        COMPUTE WS-INC = WS-INC / 1000
    END-IF.

*> ==================================================================
*> Backtracking
*> ==================================================================
*> Undo all assignments above level WS-BL.
BACKTRACK.
    MOVE DLIM(WS-BL + 1) TO WS-LIM
    PERFORM VARYING WS-IB FROM WS-TN BY -1 UNTIL WS-IB <= WS-LIM
        MOVE TRAIL(WS-IB) TO WS-P
        MOVE VOF(WS-P) TO WS-V
        MOVE NEGT(WS-P) TO WS-NG
        MOVE 0 TO LV(WS-P)
        MOVE 0 TO LV(WS-NG)
        MOVE LSIGN(WS-P) TO VSAV(WS-V)
        IF HPOS(WS-V) = 0
            MOVE WS-V TO WS-HV
            PERFORM HEAP-INSERT
        END-IF
    END-PERFORM
    MOVE WS-LIM TO WS-TN
    MOVE WS-LIM TO WS-QH
    MOVE WS-BL TO WS-LVL.

BACKTRACK-TO-ZERO.
    IF WS-LVL > 0
        MOVE 0 TO WS-BL
        PERFORM BACKTRACK
    END-IF.

*> ==================================================================
*> Decisions
*> ==================================================================
PICK-DECISION.
    MOVE 0 TO WS-FOUND
    PERFORM UNTIL WS-FOUND = 1 OR WS-HSZ = 0
        PERFORM HEAP-POP
        MOVE WS-V TO WS-AL
        ADD WS-V TO WS-AL
        IF LV(WS-AL) = 0
            MOVE 1 TO WS-FOUND
        END-IF
    END-PERFORM
    IF WS-FOUND = 0
        MOVE 1 TO WS-STATUS
    ELSE
        ADD 1 TO WS-LVL
        MOVE WS-TN TO DLIM(WS-LVL)
        IF WS-TMODE = 1
            IF TGT(WS-V) NOT = 1
                ADD 1 TO WS-AL
            END-IF
        ELSE
            IF VSAV(WS-V) NOT = 1
                ADD 1 TO WS-AL
            END-IF
        END-IF
        MOVE 0 TO WS-AR
        PERFORM ASSIGN-LIT
    END-IF.

*> ==================================================================
*> Conflict analysis (first UIP) with local clause minimisation
*> ==================================================================
*> Scan clause WS-RC. WS-SKIPF = 1 when it is a reason clause, in
*> which case position CST is the implied literal and is skipped.
PROCESS-CLAUSE.
    MOVE 1 TO CLUSE(WS-RC)
    MOVE CST(WS-RC) TO WS-S
    MOVE CEN(WS-RC) TO WS-E
    MOVE WS-S TO WS-IA
    IF WS-SKIPF = 1
        ADD 1 TO WS-IA
    END-IF
    PERFORM UNTIL WS-IA > WS-E
        MOVE CL(WS-IA) TO WS-Q2
        MOVE VOF(WS-Q2) TO WS-V
        IF SEEN(WS-V) = 0 AND VLEV(WS-V) > 0
            MOVE 1 TO SEEN(WS-V)
            MOVE WS-V TO WS-BV
            PERFORM BUMP-VAR
            IF VLEV(WS-V) >= WS-LVL
                ADD 1 TO WS-PATHC
            ELSE
                ADD 1 TO WS-LN
                MOVE WS-Q2 TO LRN(WS-LN)
            END-IF
        END-IF
        ADD 1 TO WS-IA
    END-PERFORM.

*> Walk the trail backwards to the next seen variable; it becomes WS-P
*> (true trail literal) with variable WS-V.
FIND-NEXT.
    MOVE TRAIL(WS-IDX) TO WS-P
    MOVE VOF(WS-P) TO WS-V
    PERFORM UNTIL SEEN(WS-V) = 1
        SUBTRACT 1 FROM WS-IDX
        MOVE TRAIL(WS-IDX) TO WS-P
        MOVE VOF(WS-P) TO WS-V
    END-PERFORM
    MOVE 0 TO SEEN(WS-V)
    SUBTRACT 1 FROM WS-PATHC
    SUBTRACT 1 FROM WS-IDX.

*> Builds the learned clause in LRN(1..WS-LN); LRN(1) is the asserting
*> literal (false now).
ANALYZE.
    MOVE 1 TO WS-LN
    MOVE 0 TO WS-PATHC
    MOVE WS-TN TO WS-IDX
    MOVE WS-CONFL TO WS-RC
    MOVE 0 TO WS-SKIPF
    PERFORM PROCESS-CLAUSE
    PERFORM FIND-NEXT
    PERFORM UNTIL WS-PATHC = 0
        MOVE VREA(WS-V) TO WS-RC
        MOVE 1 TO WS-SKIPF
        PERFORM PROCESS-CLAUSE
        PERFORM FIND-NEXT
    END-PERFORM
    MOVE NEGT(WS-P) TO LRN(1)
    PERFORM MINIMIZE.

*> Drop a learned literal q when its reason clause's other literals are
*> all either in the learned clause or at level 0. Clears SEEN flags.
MINIMIZE.
    PERFORM VARYING WS-IB FROM 2 BY 1 UNTIL WS-IB > WS-LN
        MOVE 1 TO LKEEP(WS-IB)
        MOVE LRN(WS-IB) TO WS-Q3
        MOVE VOF(WS-Q3) TO WS-V
        MOVE VREA(WS-V) TO WS-RC2
        IF WS-RC2 NOT = 0
            MOVE 1 TO WS-RED
            MOVE CST(WS-RC2) TO WS-IA
            ADD 1 TO WS-IA
            MOVE CEN(WS-RC2) TO WS-E2
            PERFORM UNTIL WS-IA > WS-E2 OR WS-RED = 0
                MOVE CL(WS-IA) TO WS-Q3
                MOVE VOF(WS-Q3) TO WS-W
                IF SEEN(WS-W) = 0 AND VLEV(WS-W) > 0
                    MOVE 0 TO WS-RED
                END-IF
                ADD 1 TO WS-IA
            END-PERFORM
            IF WS-RED = 1
                MOVE 0 TO LKEEP(WS-IB)
            END-IF
        END-IF
    END-PERFORM
    PERFORM VARYING WS-IB FROM 2 BY 1 UNTIL WS-IB > WS-LN
        MOVE LRN(WS-IB) TO WS-Q3
        MOVE VOF(WS-Q3) TO WS-V
        MOVE 0 TO SEEN(WS-V)
    END-PERFORM
    MOVE 1 TO WS-J2
    PERFORM VARYING WS-IB FROM 2 BY 1 UNTIL WS-IB > WS-LN
        IF LKEEP(WS-IB) = 1
            ADD 1 TO WS-J2
            MOVE LRN(WS-IB) TO LRN(WS-J2)
        END-IF
    END-PERFORM
    MOVE WS-J2 TO WS-LN.

*> Handle one conflict at a positive level: learn, backjump, assert.
HANDLE-CONFLICT.
    ADD 1 TO WS-CONF
    ADD 1 TO WS-CSRST
    IF WS-LVL = 0
        MOVE 2 TO WS-STATUS
    ELSE
        *> Target phases: remember the longest conflict-free trail prefix
        *> since the last restart; decisions in target mode follow it.
        MOVE DLIM(WS-LVL) TO WS-TLEN
        IF WS-TLEN > WS-BESTN
            MOVE WS-TLEN TO WS-BESTN
            PERFORM VARYING WS-IB FROM 1 BY 1 UNTIL WS-IB > WS-TLEN
                MOVE VOF(TRAIL(WS-IB)) TO WS-V
                MOVE LSIGN(TRAIL(WS-IB)) TO TGT(WS-V)
            END-PERFORM
        END-IF
        PERFORM ANALYZE
        *> Put the literal with the highest level (after LRN(1)) in LRN(2).
        IF WS-LN = 1
            MOVE 0 TO WS-BL
        ELSE
            MOVE -1 TO WS-BEST
            MOVE 2 TO WS-J-HOLD
            PERFORM VARYING WS-IB FROM 2 BY 1 UNTIL WS-IB > WS-LN
                MOVE LRN(WS-IB) TO WS-Q3
                MOVE VOF(WS-Q3) TO WS-V
                IF VLEV(WS-V) > WS-BEST
                    MOVE VLEV(WS-V) TO WS-BEST
                    MOVE WS-IB TO WS-J-HOLD
                END-IF
            END-PERFORM
            MOVE LRN(2) TO WS-HOLD
            MOVE LRN(WS-J-HOLD) TO LRN(2)
            MOVE WS-HOLD TO LRN(WS-J-HOLD)
            MOVE WS-BEST TO WS-BL
        END-IF
        *> literal block distance (LBD): number of distinct levels
        ADD 1 TO WS-STAMP
        MOVE 0 TO WS-LBD
        PERFORM VARYING WS-IB FROM 1 BY 1 UNTIL WS-IB > WS-LN
            MOVE LRN(WS-IB) TO WS-Q3
            MOVE VOF(WS-Q3) TO WS-V
            MOVE VLEV(WS-V) TO WS-LVX
            ADD 1 TO WS-LVX
            IF LVST(WS-LVX) NOT = WS-STAMP
                MOVE WS-STAMP TO LVST(WS-LVX)
                ADD 1 TO WS-LBD
            END-IF
        END-PERFORM
        PERFORM BACKTRACK-TO-BL
        IF WS-LN = 1
            MOVE LRN(1) TO WS-AL
            MOVE 0 TO WS-AR
            PERFORM ASSIGN-LIT
        ELSE
            PERFORM STORE-LEARNT
            MOVE LRN(1) TO WS-AL
            MOVE WS-C TO WS-AR
            PERFORM ASSIGN-LIT
        END-IF
        PERFORM DECAY-ACTIVITY
    END-IF.

BACKTRACK-TO-BL.
    IF WS-LVL > WS-BL
        PERFORM BACKTRACK
    END-IF.

*> Append LRN(1..WS-LN) as a learned clause with watches on LRN(1), LRN(2).
STORE-LEARNT.
    ADD 1 TO WS-NC
    MOVE WS-NC TO WS-C
    COMPUTE CST(WS-C) = WS-CLTOP + 1
    MOVE WS-LN TO CLN(WS-C)
    MOVE CST(WS-C) TO CEN(WS-C)
    ADD WS-LN TO CEN(WS-C)
    SUBTRACT 1 FROM CEN(WS-C)
    MOVE 1 TO CLRN(WS-C)
    MOVE WS-LBD TO CLBD(WS-C)
    MOVE 0 TO CLUSE(WS-C)
    PERFORM VARYING WS-IB FROM 1 BY 1 UNTIL WS-IB > WS-LN
        MOVE LRN(WS-IB) TO CL(WS-CLTOP + WS-IB)
    END-PERFORM
    ADD WS-LN TO WS-CLTOP
    ADD 1 TO WS-NLEARN
    PERFORM LINK-CLAUSE-WATCHES.

*> ==================================================================
*> Learned-clause deletion (only at level 0, after a restart).
*> Keeps original clauses, glue clauses (LBD <= 2) and clauses used
*> in conflict analysis since the last reduction.
*> ==================================================================
REDUCE.
    PERFORM VARYING WS-IC FROM 1 BY 1 UNTIL WS-IC > WS-TN
        MOVE VOF(TRAIL(WS-IC)) TO WS-V
        MOVE 0 TO VREA(WS-V)
    END-PERFORM
    *> histogram of LBD over non-glue learned clauses
    PERFORM VARYING WS-IC FROM 0 BY 1 UNTIL WS-IC > 1001
        MOVE 0 TO LBDH(WS-IC + 1)
    END-PERFORM
    MOVE 0 TO WS-NCAND
    PERFORM VARYING WS-C FROM 1 BY 1 UNTIL WS-C > WS-NC
        IF CLRN(WS-C) = 1 AND CLBD(WS-C) > 2
            MOVE CLBD(WS-C) TO WS-LBX
            IF WS-LBX > 1000
                MOVE 1000 TO WS-LBX
            END-IF
            ADD 1 TO LBDH(WS-LBX + 1)
            ADD 1 TO WS-NCAND
        END-IF
    END-PERFORM
    *> delete the worse half: LBD above threshold WS-THR, and part of WS-THR
    DIVIDE WS-NCAND BY 2 GIVING WS-HALF
    MOVE 0 TO WS-ACC
    MOVE 3 TO WS-THR
    PERFORM UNTIL WS-THR >= 1000 OR WS-ACC + LBDH(WS-THR + 1) >= WS-HALF
        ADD LBDH(WS-THR + 1) TO WS-ACC
        ADD 1 TO WS-THR
    END-PERFORM
    COMPUTE WS-QT = WS-HALF - WS-ACC
    MOVE 0 TO WS-NEWNC
    MOVE 0 TO WS-NEWTOP
    MOVE 0 TO WS-NEWLRN
    PERFORM VARYING WS-C FROM 1 BY 1 UNTIL WS-C > WS-NC
        MOVE 1 TO WS-KEEP
        IF CLRN(WS-C) = 1 AND CLBD(WS-C) > 2
            MOVE CLBD(WS-C) TO WS-LBX
            IF WS-LBX > 1000
                MOVE 1000 TO WS-LBX
            END-IF
            IF WS-LBX > WS-THR
                MOVE 0 TO WS-KEEP
            ELSE
                IF WS-LBX = WS-THR AND WS-QT > 0
                    MOVE 0 TO WS-KEEP
                    SUBTRACT 1 FROM WS-QT
                END-IF
            END-IF
        END-IF
        IF WS-KEEP = 1
            ADD 1 TO WS-NEWNC
            MOVE CST(WS-C) TO WS-S
            MOVE CEN(WS-C) TO WS-E
            MOVE WS-NEWTOP TO WS-NEWST
            ADD 1 TO WS-NEWST
            MOVE WS-S TO WS-IA
            MOVE WS-NEWST TO WS-K
            PERFORM UNTIL WS-IA > WS-E
                MOVE CL(WS-IA) TO CL(WS-K)
                ADD 1 TO WS-IA
                ADD 1 TO WS-K
            END-PERFORM
            MOVE WS-NEWST TO CST(WS-NEWNC)
            MOVE WS-NEWST TO CEN(WS-NEWNC)
            ADD CLN(WS-C) TO CEN(WS-NEWNC)
            SUBTRACT 1 FROM CEN(WS-NEWNC)
            MOVE CLN(WS-C) TO CLN(WS-NEWNC)
            MOVE CLRN(WS-C) TO CLRN(WS-NEWNC)
            MOVE CLBD(WS-C) TO CLBD(WS-NEWNC)
            MOVE 0 TO CLUSE(WS-NEWNC)
            IF CLRN(WS-NEWNC) = 1
                ADD 1 TO WS-NEWLRN
            END-IF
            ADD CLN(WS-NEWNC) TO WS-NEWTOP
        END-IF
    END-PERFORM
    MOVE WS-NEWNC TO WS-NC
    MOVE WS-NEWTOP TO WS-CLTOP
    MOVE WS-NEWLRN TO WS-NLEARN
    PERFORM BUILD-WATCHES
    ADD 2000 TO WS-NLEARN GIVING WS-LIMIT.

*> ==================================================================
*> Main search loop
*> ==================================================================
SOLVE.
    PERFORM BUILD-WATCHES
    PERFORM PROPAGATE
    IF WS-CONFL NOT = 0
        MOVE 2 TO WS-STATUS
    END-IF
    PERFORM UNTIL WS-STATUS NOT = 0
        PERFORM PROPAGATE
        IF WS-CONFL NOT = 0
            PERFORM HANDLE-CONFLICT
        ELSE
            IF WS-CSRST >= WS-RLIM OR WS-CLTOP > 6000000
                PERFORM BACKTRACK-TO-ZERO
                MOVE 0 TO WS-CSRST
                MOVE 0 TO WS-BESTN
                *> alternate between target-phase and saved-phase decisions
                IF WS-TMODE = 1
                    MOVE 0 TO WS-TMODE
                ELSE
                    MOVE 1 TO WS-TMODE
                END-IF
                COMPUTE WS-RLIM = WS-RLIM + WS-RLIM / 2
                IF WS-RLIM > 30000
                    MOVE 30000 TO WS-RLIM
                END-IF
                IF WS-NLEARN >= WS-LIMIT OR WS-CLTOP > 6000000
                    PERFORM REDUCE
                END-IF
            END-IF
            IF WS-STATUS = 0
                PERFORM PICK-DECISION
            END-IF
        END-IF
    END-PERFORM.

*> ==================================================================
*> Output
*> ==================================================================
PRINT-SAT.
    DISPLAY "s SATISFIABLE"
    MOVE SPACES TO WS-OUT
    MOVE 1 TO WS-OP
    STRING "v" DELIMITED BY SIZE INTO WS-OUT WITH POINTER WS-OP
    PERFORM VARYING WS-V FROM 1 BY 1 UNTIL WS-V > WS-NV
        MOVE WS-V TO WS-SV
        IF LV(2 * WS-V) NOT = 1
            COMPUTE WS-SV = 0 - WS-V
        END-IF
        IF WS-OP > 70
            DISPLAY WS-OUT(1:WS-OP - 1)
            MOVE SPACES TO WS-OUT
            MOVE 1 TO WS-OP
            STRING "v" DELIMITED BY SIZE INTO WS-OUT WITH POINTER WS-OP
        END-IF
        MOVE WS-SV TO WS-ED
        MOVE FUNCTION TRIM(WS-ED) TO WS-TXT
        STRING " " DELIMITED BY SIZE
               WS-TXT DELIMITED BY SPACE
               INTO WS-OUT WITH POINTER WS-OP
    END-PERFORM
    STRING " 0" DELIMITED BY SIZE INTO WS-OUT WITH POINTER WS-OP
    DISPLAY WS-OUT(1:WS-OP - 1).
