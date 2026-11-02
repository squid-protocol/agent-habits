       IDENTIFICATION DIVISION.
       PROGRAM-ID. SOLVER.
      *> SAT solver for DIMACS CNF, written for GnuCOBOL 3.1.
      *>
      *> Search is DPLL: unit propagation over two watched literals,
      *> decisions and backtracking. It is extended with first-UIP clause
      *> learning (conflict-driven backjumping), VSIDS-style variable
      *> activity, phase saving, Luby restarts and reduction of the
      *> learnt-clause database.
      *>
      *> Literals are signed integers (DIMACS numbering). The table index of
      *> literal L is L + LITOFF, so negative literals index below LITOFF.
      *> Exit codes: 10 SATISFIABLE, 20 UNSATISFIABLE, 1 error.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT CNF-FILE ASSIGN TO WS-FNAME
               ORGANIZATION IS RECORD SEQUENTIAL
               FILE STATUS IS WS-FS.

       DATA DIVISION.
       FILE SECTION.
       FD  CNF-FILE.
       01  CNF-REC                 PIC X(4096).

       WORKING-STORAGE SECTION.
       01  WS-FNAME                PIC X(1024).
       01  WS-FS                   PIC XX.
       01  WS-EOF                  PIC 9 COMP-5 VALUE 0.
       01  WS-LINE                 PIC X(200).
       01  CH-W                    PIC X.
       01  WS-PTR                  PIC 9(9) COMP-5.
       01  NUM-ED                  PIC -(8)9.
       01  DIGIT-BUF.
           05 DIGIT-X              PIC X.
       01  DIGIT-RED REDEFINES DIGIT-BUF.
           05 DIGIT-N              PIC 9.

      *> Capacities. MAXV variables, MAXCL clause slots, MAXLIT literal slots.
       01  G-LIMITS.
           05 LITOFF                  PIC S9(9) COMP-5 VALUE 200001.
           05 MAXV                 PIC S9(9) COMP-5 VALUE 200000.
           05 MAXCL                PIC S9(9) COMP-5 VALUE 1000000.
           05 MAXLIT               PIC S9(9) COMP-5 VALUE 10000000.

       01  SCALARS.
           05 NV                   PIC S9(9) COMP-5 VALUE 0.
           05 NORIG                PIC S9(9) COMP-5 VALUE 0.
           05 NCL                  PIC S9(9) COMP-5 VALUE 0.
           05 LTOP                 PIC S9(9) COMP-5 VALUE 0.
           05 NLRN                 PIC S9(9) COMP-5 VALUE 0.
           05 LLIM                 PIC S9(9) COMP-5 VALUE 4000.
           05 DL                   PIC S9(9) COMP-5 VALUE 0.
           05 TRTOP                PIC S9(9) COMP-5 VALUE 0.
           05 QHEAD                PIC S9(9) COMP-5 VALUE 1.
           05 CONFL                PIC S9(9) COMP-5 VALUE 0.
           05 PATHC                PIC S9(9) COMP-5 VALUE 0.
           05 P                    PIC S9(9) COMP-5 VALUE 0.
           05 IDX                  PIC S9(9) COMP-5 VALUE 0.
           05 IDX2                 PIC S9(9) COMP-5 VALUE 0.
           05 CC                   PIC S9(9) COMP-5 VALUE 0.
           05 SS                   PIC S9(9) COMP-5 VALUE 0.
           05 LN                   PIC S9(9) COMP-5 VALUE 0.
           05 K                    PIC S9(9) COMP-5 VALUE 0.
           05 Q                    PIC S9(9) COMP-5 VALUE 0.
           05 Q2                   PIC S9(9) COMP-5 VALUE 0.
           05 VV                   PIC S9(9) COMP-5 VALUE 0.
           05 VV2                  PIC S9(9) COMP-5 VALUE 0.
           05 SG                   PIC S9(9) COMP-5 VALUE 0.
           05 FOUND                PIC S9(9) COMP-5 VALUE 0.
           05 ND                   PIC S9(9) COMP-5 VALUE 0.
           05 PV                   PIC S9(9) COMP-5 VALUE 0.
           05 NXT                  PIC S9(9) COMP-5 VALUE 0.
           05 OTH                  PIC S9(9) COMP-5 VALUE 0.
           05 FL                   PIC S9(9) COMP-5 VALUE 0.
           05 NEWL                 PIC S9(9) COMP-5 VALUE 0.
           05 TMP                  PIC S9(9) COMP-5 VALUE 0.
           05 I                    PIC S9(9) COMP-5 VALUE 0.
           05 J                    PIC S9(9) COMP-5 VALUE 0.
           05 V                    PIC S9(9) COMP-5 VALUE 0.
           05 CIX                  PIC S9(9) COMP-5 VALUE 0.
           05 LBN                  PIC S9(9) COMP-5 VALUE 0.
           05 LOUTN                PIC S9(9) COMP-5 VALUE 0.
           05 BTL                  PIC S9(9) COMP-5 VALUE 0.
           05 LBD                  PIC S9(9) COMP-5 VALUE 0.
           05 LVV                  PIC S9(9) COMP-5 VALUE 0.
           05 STAMP                PIC S9(9) COMP-5 VALUE 0.
           05 MI                   PIC S9(9) COMP-5 VALUE 0.
           05 CONFLICTS            PIC S9(9) COMP-5 VALUE 0.
           05 NEXT-RESTART         PIC S9(9) COMP-5 VALUE 100.
           05 LUBY-I               PIC S9(9) COMP-5 VALUE 1.
           05 LVAL                 PIC S9(9) COMP-5 VALUE 1.
           05 LI                   PIC S9(9) COMP-5 VALUE 0.
           05 LP2                  PIC S9(9) COMP-5 VALUE 0.
           05 LDONE                PIC S9(9) COMP-5 VALUE 0.
           05 CTN                  PIC S9(9) COMP-5 VALUE 0.
           05 CSER                 PIC S9(9) COMP-5 VALUE 1.
           05 TAUT                 PIC S9(9) COMP-5 VALUE 0.
           05 ERRF                 PIC S9(9) COMP-5 VALUE 0.
           05 UNSATF               PIC S9(9) COMP-5 VALUE 0.
           05 STOPREAD             PIC S9(9) COMP-5 VALUE 0.
           05 SATF                 PIC S9(9) COMP-5 VALUE 0.
           05 SOLVED               PIC S9(9) COMP-5 VALUE 0.
           05 BADF                 PIC S9(9) COMP-5 VALUE 0.
           05 BESTV                PIC S9(9) COMP-5 VALUE 0.
           05 CPOS                  PIC S9(9) COMP-5 VALUE 0.
           05 LSTART               PIC S9(9) COMP-5 VALUE 1.
           05 LMODE                PIC S9(9) COMP-5 VALUE 0.
           05 INNUM                PIC S9(9) COMP-5 VALUE 0.
           05 HAVEDIG              PIC S9(9) COMP-5 VALUE 0.
           05 NUMV                 PIC S9(9) COMP-5 VALUE 0.
           05 NEG                  PIC S9(9) COMP-5 VALUE 0.
           05 ENQ-LIT              PIC S9(9) COMP-5 VALUE 0.
           05 ENQ-RSN              PIC S9(9) COMP-5 VALUE 0.
           05 BT-LVL               PIC S9(9) COMP-5 VALUE 0.
           05 BT-START             PIC S9(9) COMP-5 VALUE 0.
           05 WA-LIT               PIC S9(9) COMP-5 VALUE 0.
           05 WA-NODE              PIC S9(9) COMP-5 VALUE 0.
           05 WA-IDX               PIC S9(9) COMP-5 VALUE 0.
           05 NEWN                 PIC S9(9) COMP-5 VALUE 0.
           05 DST                  PIC S9(9) COMP-5 VALUE 0.
           05 DSTS                 PIC S9(9) COMP-5 VALUE 0.
           05 CLLV                 PIC S9(9) COMP-5 VALUE 0.
           05 CLBV                 PIC S9(9) COMP-5 VALUE 0.
           05 NC                   PIC S9(9) COMP-5 VALUE 0.
           05 HALF                 PIC S9(9) COMP-5 VALUE 0.
           05 GAP                  PIC S9(9) COMP-5 VALUE 0.
           05 KT                   PIC S9(9) COMP-5 VALUE 0.
           05 CT                   PIC S9(9) COMP-5 VALUE 0.
           05 JG                   PIC S9(9) COMP-5 VALUE 0.
           05 MOVING               PIC S9(9) COMP-5 VALUE 0.
           05 I0                   PIC S9(9) COMP-5 VALUE 0.
           05 I1                   PIC S9(9) COMP-5 VALUE 0.
           05 VINC                 PIC S9(9) COMP-5 VALUE 1000.
           05 HSIZE                PIC S9(9) COMP-5 VALUE 0.
           05 HI                   PIC S9(9) COMP-5 VALUE 0.
           05 HC                   PIC S9(9) COMP-5 VALUE 0.
           05 HC2                  PIC S9(9) COMP-5 VALUE 0.
           05 HP                   PIC S9(9) COMP-5 VALUE 0.
           05 HV                   PIC S9(9) COMP-5 VALUE 0.
           05 HPV                  PIC S9(9) COMP-5 VALUE 0.
           05 HPV2                 PIC S9(9) COMP-5 VALUE 0.
           05 HTOP                 PIC S9(9) COMP-5 VALUE 0.
           05 TCN                  PIC S9(9) COMP-5 VALUE 0.
           05 TOP0                 PIC S9(9) COMP-5 VALUE 0.
           05 MSP                  PIC S9(9) COMP-5 VALUE 0.
           05 RED-OK               PIC S9(9) COMP-5 VALUE 0.

      *> Per-variable and per-literal tables (1-based).
       01  T-VAL.
           05 VAL                  PIC S9(4) COMP-5 OCCURS 400005 TIMES.
       01  T-WH.
           05 WH                   PIC S9(9) COMP-5 OCCURS 400005 TIMES.
       01  T-LEV.
           05 LEV                  PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-RSN.
           05 RSN                  PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-PHS.
           05 PHS                  PIC S9(4) COMP-5 OCCURS 200005 TIMES.
       01  T-SEEN.
           05 SEEN                 PIC S9(4) COMP-5 OCCURS 200005 TIMES.
       01  T-ACT.
           05 ACT                  PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-MKP.
           05 MKP                  PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-MKN.
           05 MKN                  PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-LSTP.
           05 LSTP                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-TRAIL.
           05 TRAIL                PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-DLIM.
           05 DLIM                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-CTMP.
           05 CTMP                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-LBUF.
           05 LBUF                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-LOUT.
           05 LOUT                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.

      *> Clause table: start in LP, length, LBD, learnt flag, deleted flag.
       01  T-CST.
           05 CST                  PIC S9(9) COMP-5 OCCURS 1000005 TIMES.
       01  T-CLN.
           05 CLN                  PIC S9(9) COMP-5 OCCURS 1000005 TIMES.
       01  T-CLB.
           05 CLB                  PIC S9(9) COMP-5 OCCURS 1000005 TIMES.
       01  T-CLL.
           05 CLL                  PIC S9(9) COMP-5 OCCURS 1000005 TIMES.
       01  T-CLD.
           05 CLD                  PIC S9(9) COMP-5 OCCURS 1000005 TIMES.
       01  T-CAND.
           05 CAND                 PIC S9(9) COMP-5 OCCURS 1000005 TIMES.
       01  T-HEAP.
           05 HEAP                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-HPOS.
           05 HPOS                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-PAR.
           05 PAR                  PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-MSTK.
           05 MSTK                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-TCLR.
           05 TCLR                 PIC S9(9) COMP-5 OCCURS 200005 TIMES.
       01  T-KEYV.
           05 KEYV                 PIC S9(9) COMP-5 OCCURS 1000005 TIMES.
       01  T-LP.
           05 LP                   PIC S9(9) COMP-5 OCCURS 10000005 TIMES.

      *> Watch nodes: node n belongs to clause (n+1)/2; each clause owns
      *> nodes 2c-1 and 2c, which sit in the watch lists of its two watches.
       01  T-WNC.
           05 WN-C                 PIC S9(9) COMP-5 OCCURS 2000005 TIMES.
       01  T-WNX.
           05 WN-NX                PIC S9(9) COMP-5 OCCURS 2000005 TIMES.

       PROCEDURE DIVISION.
       MAIN-CTL.
           ACCEPT WS-FNAME FROM ARGUMENT-VALUE
           OPEN INPUT CNF-FILE
           IF WS-FS NOT = "00"
               DISPLAY "c cannot open input file" UPON SYSERR
               MOVE 1 TO RETURN-CODE
               STOP RUN
           END-IF
           PERFORM INIT-TABLES
           PERFORM PARSE-FILE
           CLOSE CNF-FILE
           PERFORM INIT-HEAP
           IF ERRF = 1
               DISPLAY "c input error" UPON SYSERR
               MOVE 1 TO RETURN-CODE
               STOP RUN
           END-IF
           IF UNSATF = 0
               MOVE 1 TO QHEAD
               PERFORM PROPAGATE
               IF CONFL NOT = 0
                   MOVE 1 TO UNSATF
               END-IF
           END-IF
           IF UNSATF = 0
               PERFORM SEARCH-LOOP
           END-IF
           IF ERRF = 1
               DISPLAY "c capacity exceeded" UPON SYSERR
               MOVE 1 TO RETURN-CODE
               STOP RUN
           END-IF
           IF UNSATF = 1
               DISPLAY "s UNSATISFIABLE"
               MOVE 20 TO RETURN-CODE
           ELSE
               PERFORM VERIFY-MODEL
               IF BADF = 1
                   DISPLAY "c internal error: model check failed"
                       UPON SYSERR
                   MOVE 1 TO RETURN-CODE
                   STOP RUN
               END-IF
               PERFORM PRINT-MODEL
               MOVE 10 TO RETURN-CODE
           END-IF
           STOP RUN.

      *> ------------------------------------------------------------
      *> Initialisation
      *> ------------------------------------------------------------
       INIT-HEAP.
           MOVE NV TO HSIZE
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NV
               MOVE I TO HEAP(I)
               MOVE I TO HPOS(I)
           END-PERFORM
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NV + 1
               COMPUTE PAR(I) = I / 2
           END-PERFORM.

       INIT-TABLES.
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > 400005
               MOVE 0 TO VAL(I)
               MOVE 0 TO WH(I)
           END-PERFORM
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > 200005
               MOVE 0 TO LEV(I)
               MOVE 0 TO RSN(I)
               MOVE -1 TO PHS(I)
               MOVE 0 TO SEEN(I)
               MOVE 0 TO ACT(I)
               MOVE 0 TO MKP(I)
               MOVE 0 TO MKN(I)
               MOVE 0 TO LSTP(I)
           END-PERFORM.

      *> ------------------------------------------------------------
      *> DIMACS input
      *> ------------------------------------------------------------
       PARSE-FILE.
           MOVE 0 TO WS-EOF
           MOVE 1 TO LSTART
           MOVE 0 TO LMODE
           MOVE 0 TO INNUM
           PERFORM UNTIL WS-EOF = 1 OR STOPREAD = 1
               MOVE LOW-VALUES TO CNF-REC
               READ CNF-FILE
                   AT END
                       MOVE 1 TO WS-EOF
                   NOT AT END
                       PERFORM PARSE-BLOCK
               END-READ
           END-PERFORM
           PERFORM FINISH-NUM
           IF CTN > 0 AND ERRF = 0
               PERFORM END-CLAUSE
           END-IF.

      *> The input is read as raw blocks, so a clause may span any number
      *> of lines or blocks. Unused bytes of a short block are LOW-VALUE.
       PARSE-BLOCK.
           PERFORM VARYING CPOS FROM 1 BY 1
                   UNTIL CPOS > 4096 OR WS-EOF = 1 OR STOPREAD = 1
               MOVE CNF-REC(CPOS:1) TO CH-W
               PERFORM PARSE-CHAR
           END-PERFORM.

      *> LMODE: 0 clause line, 1 comment or ignored line, 2 header line.
       PARSE-CHAR.
           EVALUATE TRUE
               WHEN CH-W = LOW-VALUE
                   PERFORM FINISH-NUM
                   MOVE 1 TO WS-EOF
               WHEN CH-W = X"0A"
                   PERFORM FINISH-NUM
                   MOVE 1 TO LSTART
                   MOVE 0 TO LMODE
               WHEN LMODE = 1
                   CONTINUE
               WHEN LSTART = 1 AND (CH-W = SPACE OR CH-W = X"09"
                                    OR CH-W = X"0D")
                   CONTINUE
               WHEN LSTART = 1 AND CH-W = "c"
                   MOVE 0 TO LSTART
                   MOVE 1 TO LMODE
               WHEN LSTART = 1 AND CH-W = "p"
                   MOVE 0 TO LSTART
                   MOVE 2 TO LMODE
               WHEN LSTART = 1 AND CH-W = "%"
                   MOVE 1 TO STOPREAD
               WHEN CH-W >= "0" AND CH-W <= "9"
                   MOVE 0 TO LSTART
                   IF INNUM = 0
                       MOVE 1 TO INNUM
                       MOVE 0 TO NUMV
                       MOVE 0 TO NEG
                       MOVE 0 TO HAVEDIG
                   END-IF
                   MOVE CH-W TO DIGIT-X
                   COMPUTE NUMV = NUMV * 10 + DIGIT-N
                   MOVE 1 TO HAVEDIG
               WHEN CH-W = "-"
                   PERFORM FINISH-NUM
                   MOVE 0 TO LSTART
                   MOVE 1 TO INNUM
                   MOVE 0 TO NUMV
                   MOVE 1 TO NEG
                   MOVE 0 TO HAVEDIG
               WHEN OTHER
                   PERFORM FINISH-NUM
                   MOVE 0 TO LSTART
           END-EVALUATE.

      *> Completes the number being read, if any: a header value, a
      *> terminating 0 (end of clause) or a literal.
       FINISH-NUM.
           IF INNUM = 1
               MOVE 0 TO INNUM
               IF HAVEDIG = 1
                   IF NEG = 1
                       COMPUTE NUMV = 0 - NUMV
                   END-IF
                   IF LMODE = 2
                       IF NUMV > MAXV OR NUMV < 0
                           MOVE 1 TO ERRF
                           MOVE 1 TO STOPREAD
                       ELSE
                           MOVE NUMV TO NV
                       END-IF
                       MOVE 1 TO LMODE
                   ELSE
                       IF NUMV = 0
                           PERFORM END-CLAUSE
                       ELSE
                           PERFORM ADD-LIT
                       END-IF
                   END-IF
               END-IF
           END-IF.

       ADD-LIT.
           IF NUMV > 0
               MOVE NUMV TO VV
               MOVE 1 TO SG
           ELSE
               COMPUTE VV = 0 - NUMV
               MOVE 0 TO SG
           END-IF
           IF VV > MAXV
               MOVE 1 TO ERRF
               MOVE 1 TO STOPREAD
           ELSE
               IF VV > NV
                   MOVE VV TO NV
               END-IF
               IF TAUT = 0
                   IF SG = 1
                       IF MKN(VV) = CSER
                           MOVE 1 TO TAUT
                       ELSE
                           IF MKP(VV) NOT = CSER
                               MOVE CSER TO MKP(VV)
                               PERFORM PUSH-CTMP
                           END-IF
                       END-IF
                   ELSE
                       IF MKP(VV) = CSER
                           MOVE 1 TO TAUT
                       ELSE
                           IF MKN(VV) NOT = CSER
                               MOVE CSER TO MKN(VV)
                               PERFORM PUSH-CTMP
                           END-IF
                       END-IF
                   END-IF
               END-IF
           END-IF.

       PUSH-CTMP.
           ADD 1 TO CTN
           MOVE NUMV TO CTMP(CTN).

      *> Closes the current clause. Units are enqueued at level 0; longer
      *> clauses are stored with watches on their first two literals.
       END-CLAUSE.
           IF TAUT = 0
               EVALUATE TRUE
                   WHEN CTN = 0
                       MOVE 1 TO UNSATF
                   WHEN CTN = 1
                       MOVE CTMP(1) TO ENQ-LIT
                       COMPUTE IDX = ENQ-LIT + LITOFF
                       IF VAL(IDX) = -1
                           MOVE 1 TO UNSATF
                       ELSE
                           IF VAL(IDX) = 0
                               MOVE 0 TO ENQ-RSN
                               PERFORM ENQUEUE
                           END-IF
                       END-IF
                   WHEN OTHER
                       PERFORM STORE-CLAUSE
               END-EVALUATE
           END-IF
           ADD 1 TO CSER
           MOVE 0 TO CTN
           MOVE 0 TO TAUT
           IF UNSATF = 1
               MOVE 1 TO STOPREAD
           END-IF.

       STORE-CLAUSE.
           IF NCL + 2 >= MAXCL OR LTOP + CTN + 2 >= MAXLIT
               MOVE 1 TO ERRF
               MOVE 1 TO STOPREAD
           ELSE
               ADD 1 TO NCL
               COMPUTE SS = LTOP + 1
               MOVE SS TO CST(NCL)
               MOVE CTN TO CLN(NCL)
               MOVE 0 TO CLL(NCL)
               MOVE 0 TO CLB(NCL)
               MOVE 0 TO CLD(NCL)
               PERFORM VARYING K FROM 1 BY 1 UNTIL K > CTN
                   COMPUTE IDX = LTOP + K
                   MOVE CTMP(K) TO LP(IDX)
               END-PERFORM
               ADD CTN TO LTOP
               MOVE NCL TO NORIG
               COMPUTE ND = 2 * NCL - 1
               MOVE NCL TO WN-C(ND)
               MOVE LP(SS) TO WA-LIT
               MOVE ND TO WA-NODE
               PERFORM WATCH-ADD
               COMPUTE ND = 2 * NCL
               MOVE NCL TO WN-C(ND)
               MOVE LP(SS + 1) TO WA-LIT
               MOVE ND TO WA-NODE
               PERFORM WATCH-ADD
           END-IF.

      *> Pushes watch node WA-NODE onto the watch list of literal WA-LIT.
       WATCH-ADD.
           COMPUTE WA-IDX = WA-LIT + LITOFF
           MOVE WH(WA-IDX) TO WN-NX(WA-NODE)
           MOVE WA-NODE TO WH(WA-IDX).

      *> Assigns ENQ-LIT true at the current level with reason ENQ-RSN.
       ENQUEUE.
           MOVE ENQ-LIT TO VV
           IF VV < 0
               MOVE 0 TO VV
               SUBTRACT ENQ-LIT FROM VV
           END-IF
           MOVE 1 TO VAL(ENQ-LIT + LITOFF)
           MOVE -1 TO VAL(LITOFF - ENQ-LIT)
           MOVE DL TO LEV(VV)
           MOVE ENQ-RSN TO RSN(VV)
           ADD 1 TO TRTOP
           MOVE ENQ-LIT TO TRAIL(TRTOP).

       PROPAGATE.
           MOVE 0 TO CONFL
           PERFORM UNTIL QHEAD > TRTOP OR CONFL NOT = 0
               MOVE TRAIL(QHEAD) TO P
               ADD 1 TO QHEAD
               MOVE 0 TO FL
               SUBTRACT P FROM FL
               MOVE WH(FL + LITOFF) TO ND
               MOVE 0 TO PV
               PERFORM WALK-WATCH UNTIL ND = 0 OR CONFL NOT = 0
           END-PERFORM.

       WALK-WATCH.
           MOVE WN-C(ND) TO CC
           MOVE CST(CC) TO SS
           MOVE CLN(CC) TO LN
           IF LP(SS) = FL
               MOVE LP(SS + 1) TO TMP
               MOVE FL TO LP(SS + 1)
               MOVE TMP TO LP(SS)
           END-IF
           MOVE WN-NX(ND) TO NXT
           MOVE LP(SS) TO OTH
           IF VAL(OTH + LITOFF) = 1
               MOVE ND TO PV
               MOVE NXT TO ND
           ELSE
               MOVE 2 TO K
               MOVE 0 TO FOUND
               PERFORM FIND-REPL UNTIL FOUND = 1 OR K >= LN
               IF FOUND = 1
      *>           Swap the replacement into watch position 1.
                   MOVE LP(SS + K) TO TMP
                   MOVE FL TO LP(SS + K)
                   MOVE TMP TO LP(SS + 1)
      *>           Move node ND from the FL list to the TMP list.
                   IF PV = 0
                       MOVE NXT TO WH(FL + LITOFF)
                   ELSE
                       MOVE NXT TO WN-NX(PV)
                   END-IF
                   MOVE TMP TO WA-LIT
                   MOVE ND TO WA-NODE
                   PERFORM WATCH-ADD
                   MOVE NXT TO ND
               ELSE
                   MOVE ND TO PV
                   MOVE NXT TO ND
                   IF VAL(OTH + LITOFF) = -1
                       MOVE CC TO CONFL
                   ELSE
                       MOVE OTH TO ENQ-LIT
                       MOVE CC TO ENQ-RSN
                       PERFORM ENQUEUE
                   END-IF
               END-IF
           END-IF.

      *> Tests the literal at position SS+K as a replacement watch.
       FIND-REPL.
           MOVE LP(SS + K) TO Q
           IF VAL(Q + LITOFF) NOT = -1
               MOVE 1 TO FOUND
           ELSE
               ADD 1 TO K
           END-IF.

       ANALYZE.
           MOVE 0 TO PATHC
           MOVE 0 TO P
           MOVE 1 TO LBN
           MOVE TRTOP TO IDX
           MOVE CONFL TO CC
           PERFORM ANALYZE-CLAUSE
           IF PATHC = 0
               MOVE 1 TO ERRF
           END-IF
           PERFORM UNTIL PATHC = 0
               PERFORM FIND-SEEN-TRAIL
               MOVE TRAIL(IDX) TO P
               SUBTRACT 1 FROM IDX
               MOVE P TO VV
               IF VV < 0
                   MOVE 0 TO VV
                   SUBTRACT P FROM VV
               END-IF
               MOVE 0 TO SEEN(VV)
               SUBTRACT 1 FROM PATHC
               IF PATHC > 0
                   MOVE RSN(VV) TO CC
                   PERFORM ANALYZE-CLAUSE
               END-IF
           END-PERFORM
           MOVE 0 TO LBUF(1)
           SUBTRACT P FROM LBUF(1)

      *>   Drop literals implied by the others (recursive minimisation).
           MOVE 0 TO TCN
           MOVE 1 TO LOUTN
           MOVE LBUF(1) TO LOUT(1)
           PERFORM VARYING I FROM 2 BY 1 UNTIL I > LBN
               PERFORM LIT-REDUNDANT
               IF FOUND = 0
                   ADD 1 TO LOUTN
                   MOVE LBUF(I) TO LOUT(LOUTN)
               END-IF
           END-PERFORM
           PERFORM VARYING I FROM 2 BY 1 UNTIL I > LBN
               MOVE LBUF(I) TO VV
               IF VV < 0
                   MOVE 0 TO VV
                   SUBTRACT LBUF(I) FROM VV
               END-IF
               MOVE 0 TO SEEN(VV)
           END-PERFORM
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > TCN
               MOVE TCLR(I) TO VV
               MOVE 0 TO SEEN(VV)
           END-PERFORM
           MOVE 0 TO TCN

      *>   Second watch: literal with the highest level.
           IF LOUTN = 1
               MOVE 0 TO BTL
           ELSE
               MOVE 2 TO MI
               MOVE LOUT(2) TO VV
               IF VV < 0
                   MOVE 0 TO VV
                   SUBTRACT LOUT(2) FROM VV
               END-IF
               MOVE LEV(VV) TO LVV
               PERFORM VARYING I FROM 3 BY 1 UNTIL I > LOUTN
                   MOVE LOUT(I) TO VV
                   IF VV < 0
                       MOVE 0 TO VV
                       SUBTRACT LOUT(I) FROM VV
                   END-IF
                   IF LEV(VV) > LVV
                       MOVE LEV(VV) TO LVV
                       MOVE I TO MI
                   END-IF
               END-PERFORM
               MOVE LOUT(MI) TO TMP
               MOVE LOUT(2) TO LOUT(MI)
               MOVE TMP TO LOUT(2)
               MOVE LVV TO BTL
           END-IF

      *>   Literal block distance: number of distinct levels in the clause.
           ADD 1 TO STAMP
           MOVE 0 TO LBD
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > LOUTN
               MOVE LOUT(I) TO VV
               IF VV < 0
                   MOVE 0 TO VV
                   SUBTRACT LOUT(I) FROM VV
               END-IF
               MOVE LEV(VV) TO LVV
               ADD 1 TO LVV
               IF LSTP(LVV) NOT = STAMP
                   MOVE STAMP TO LSTP(LVV)
                   ADD 1 TO LBD
               END-IF
           END-PERFORM.

      *> Scans the trail backwards from IDX to the next seen variable.
       FIND-SEEN-TRAIL.
           MOVE 0 TO FOUND
           PERFORM UNTIL FOUND = 1
               MOVE TRAIL(IDX) TO VV
               IF VV < 0
                   MOVE 0 TO VV
                   SUBTRACT TRAIL(IDX) FROM VV
               END-IF
               IF SEEN(VV) = 1
                   MOVE 1 TO FOUND
               ELSE
                   SUBTRACT 1 FROM IDX
               END-IF
           END-PERFORM.

      *> Adds the literals of clause CC (except P) that are new to the analysis.
       ANALYZE-CLAUSE.
           MOVE CST(CC) TO SS
           MOVE CLN(CC) TO LN
           PERFORM VARYING K FROM 0 BY 1 UNTIL K >= LN
               MOVE LP(SS + K) TO Q
               IF Q NOT = P
                   MOVE Q TO VV
                   IF VV < 0
                       MOVE 0 TO VV
                       SUBTRACT Q FROM VV
                   END-IF
                   IF SEEN(VV) = 0 AND LEV(VV) > 0
                       MOVE 1 TO SEEN(VV)
                       PERFORM BUMP-VAR
                       IF LEV(VV) >= DL
                           ADD 1 TO PATHC
                       ELSE
                           ADD 1 TO LBN
                           MOVE Q TO LBUF(LBN)
                       END-IF
                   END-IF
               END-IF
           END-PERFORM.

      *> Activity bump: add the increment, then restore heap order.
       BUMP-VAR.
           ADD VINC TO ACT(VV)
           IF HPOS(VV) > 0
               MOVE HPOS(VV) TO HI
               PERFORM HEAP-UP
           END-IF
           IF ACT(VV) > 100000000
               PERFORM RESCALE-ACT
           END-IF.

      *> Divides all activities and the increment by 100 (order preserved).
       RESCALE-ACT.
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NV
               COMPUTE ACT(I) = ACT(I) / 100
           END-PERFORM
           COMPUTE VINC = VINC / 100.

      *> Decay: the increment grows by 1/0.95 per conflict (20/19).
       DECAY-ACT.
           COMPUTE VINC = VINC + VINC / 19.

      *> A literal is redundant when its reason clause only contains
      *> literals that are already in the learnt clause or at level 0.
      *> A literal of the learnt clause is redundant when every literal in
      *> its reason is in the clause, at level 0, or itself redundant
      *> (checked by walking reasons with an explicit stack). Variables
      *> proven redundant stay marked in SEEN and are listed in TCLR.
       LIT-REDUNDANT.
           MOVE LBUF(I) TO Q
           MOVE Q TO VV
           IF VV < 0
               MOVE 0 TO VV
               SUBTRACT Q FROM VV
           END-IF
           IF RSN(VV) = 0
               MOVE 0 TO FOUND
           ELSE
               MOVE TCN TO TOP0
               MOVE 1 TO MSP
               MOVE VV TO MSTK(1)
               MOVE 1 TO RED-OK
               PERFORM LR-POP UNTIL MSP = 0 OR RED-OK = 0
               IF RED-OK = 1
                   MOVE 1 TO FOUND
               ELSE
                   MOVE 0 TO FOUND
                   PERFORM VARYING J FROM TOP0 BY 1 UNTIL J >= TCN
                       MOVE TCLR(J + 1) TO VV2
                       MOVE 0 TO SEEN(VV2)
                   END-PERFORM
                   MOVE TOP0 TO TCN
               END-IF
           END-IF.

       LR-POP.
           MOVE MSTK(MSP) TO VV
           SUBTRACT 1 FROM MSP
           MOVE RSN(VV) TO CC
           MOVE CST(CC) TO SS
           MOVE CLN(CC) TO LN
           PERFORM VARYING K FROM 0 BY 1 UNTIL K >= LN OR RED-OK = 0
               PERFORM LR-LIT
           END-PERFORM.

       LR-LIT.
           MOVE LP(SS + K) TO Q2
           MOVE Q2 TO VV2
           IF VV2 < 0
               MOVE 0 TO VV2
               SUBTRACT Q2 FROM VV2
           END-IF
           IF VV2 NOT = VV
               IF SEEN(VV2) = 0 AND LEV(VV2) > 0
                   IF RSN(VV2) NOT = 0
                       MOVE 1 TO SEEN(VV2)
                       ADD 1 TO MSP
                       MOVE VV2 TO MSTK(MSP)
                       ADD 1 TO TCN
                       MOVE VV2 TO TCLR(TCN)
                   ELSE
                       MOVE 0 TO RED-OK
                   END-IF
               END-IF
           END-IF.


       BACKTRACK.
           IF DL > BT-LVL
               MOVE DLIM(BT-LVL + 1) TO BT-START
               PERFORM VARYING J FROM TRTOP BY -1 UNTIL J < BT-START
                   MOVE TRAIL(J) TO Q
                   MOVE Q TO VV
                   IF Q < 0
                       MOVE 0 TO VV
                       SUBTRACT Q FROM VV
                       MOVE -1 TO PHS(VV)
                   ELSE
                       MOVE 1 TO PHS(VV)
                   END-IF
                   MOVE 0 TO VAL(Q + LITOFF)
                   MOVE 0 TO VAL(LITOFF - Q)
                   PERFORM HEAP-INSERT
               END-PERFORM
               MOVE BT-START TO TRTOP
               SUBTRACT 1 FROM TRTOP
               MOVE TRTOP TO QHEAD
               ADD 1 TO QHEAD
               MOVE BT-LVL TO DL
           END-IF.

       LEARN.
           MOVE BTL TO BT-LVL
           PERFORM BACKTRACK
           IF LOUTN = 1
               MOVE LOUT(1) TO ENQ-LIT
               MOVE 0 TO ENQ-RSN
               PERFORM ENQUEUE
           ELSE
               PERFORM STORE-LEARNT
               IF ERRF = 0
                   MOVE LOUT(1) TO ENQ-LIT
                   MOVE NCL TO ENQ-RSN
                   PERFORM ENQUEUE
               END-IF
           END-IF.

       STORE-LEARNT.
           IF NCL + 2 >= MAXCL OR LTOP + LOUTN + 2 >= MAXLIT
               MOVE 1 TO ERRF
           ELSE
               ADD 1 TO NCL
               COMPUTE SS = LTOP + 1
               MOVE SS TO CST(NCL)
               MOVE LOUTN TO CLN(NCL)
               MOVE 1 TO CLL(NCL)
               MOVE LBD TO CLB(NCL)
               MOVE 0 TO CLD(NCL)
               PERFORM VARYING K FROM 1 BY 1 UNTIL K > LOUTN
                   COMPUTE IDX = LTOP + K
                   MOVE LOUT(K) TO LP(IDX)
               END-PERFORM
               ADD LOUTN TO LTOP
               ADD 1 TO NLRN
               COMPUTE ND = 2 * NCL - 1
               MOVE NCL TO WN-C(ND)
               MOVE LP(SS) TO WA-LIT
               MOVE ND TO WA-NODE
               PERFORM WATCH-ADD
               COMPUTE ND = 2 * NCL
               MOVE NCL TO WN-C(ND)
               MOVE LP(SS + 1) TO WA-LIT
               MOVE ND TO WA-NODE
               PERFORM WATCH-ADD
           END-IF.

      *> ------------------------------------------------------------
      *> Search driver
      *> ------------------------------------------------------------
       SEARCH-LOOP.
           PERFORM UNTIL SOLVED = 1
               PERFORM PROPAGATE
               IF CONFL NOT = 0
                   ADD 1 TO CONFLICTS
                   IF DL = 0
                       MOVE 1 TO UNSATF
                       MOVE 1 TO SOLVED
                   ELSE
                       PERFORM ANALYZE
                       IF ERRF = 1
                           MOVE 1 TO SOLVED
                       ELSE
                           PERFORM LEARN
                           IF ERRF = 1
                               MOVE 1 TO SOLVED
                           ELSE
                               PERFORM DECAY-ACT
                               IF CONFLICTS >= NEXT-RESTART
                                   OR NLRN >= LLIM
                                   OR LTOP + NV + 10 >= MAXLIT
                                   OR NCL + NV + 10 >= MAXCL
                                   PERFORM RESTART-PROC
                               END-IF
                           END-IF
                       END-IF
                   END-IF
               ELSE
                   PERFORM PICK-VAR
                   IF BESTV = 0
                       MOVE 1 TO SATF
                       MOVE 1 TO SOLVED
                   ELSE
                       ADD 1 TO DL
                       MOVE TRTOP TO DLIM(DL)
                       ADD 1 TO DLIM(DL)
                       IF PHS(BESTV) = 1
                           MOVE BESTV TO ENQ-LIT
                       ELSE
                           MOVE 0 TO ENQ-LIT
                           SUBTRACT BESTV FROM ENQ-LIT
                       END-IF
                       MOVE 0 TO ENQ-RSN
                       PERFORM ENQUEUE
                   END-IF
               END-IF
           END-PERFORM.

      *> Restart to level 0, simplify the database if needed, and advance
      *> the Luby schedule when the restart is due.
       RESTART-PROC.
           MOVE 0 TO BT-LVL
           PERFORM BACKTRACK
           PERFORM PROPAGATE
           IF CONFL NOT = 0
               MOVE 1 TO UNSATF
               MOVE 1 TO SOLVED
           ELSE
               IF NLRN >= LLIM OR LTOP + NV + 10 >= MAXLIT
                   OR NCL + NV + 10 >= MAXCL
                   PERFORM REDUCE-DB
               END-IF
               IF CONFLICTS >= NEXT-RESTART
                   ADD 1 TO LUBY-I
                   MOVE LUBY-I TO LI
                   PERFORM LUBY-CALC
                   COMPUTE NEXT-RESTART = CONFLICTS + 100 * LVAL
               END-IF
           END-IF.

      *> LVAL = luby(LI), the Luby sequence 1 1 2 1 1 2 4 ...
       LUBY-CALC.
           MOVE 1 TO LDONE
           PERFORM UNTIL LDONE = 0
               MOVE 2 TO LP2
               PERFORM UNTIL LP2 - 1 >= LI
                   COMPUTE LP2 = LP2 * 2
               END-PERFORM
               IF LP2 - 1 = LI
                   COMPUTE LVAL = LP2 / 2
                   MOVE 0 TO LDONE
               ELSE
                   COMPUTE LI = LI - LP2 / 2 + 1
               END-IF
           END-PERFORM.

      *> Picks the unassigned variable with the highest activity into BESTV.
       PICK-VAR.
           MOVE 0 TO BESTV
           MOVE 0 TO FOUND
           PERFORM UNTIL FOUND = 1 OR HSIZE = 0
               PERFORM HEAP-POP
               IF VAL(HTOP + LITOFF) = 0
                   MOVE HTOP TO BESTV
                   MOVE 1 TO FOUND
               END-IF
           END-PERFORM.

      *> Binary max-heap of variables ordered by ACT. Holds every unassigned
      *> variable (assigned ones are dropped lazily by PICK-VAR).
       HEAP-INSERT.
           IF HPOS(VV) = 0
               ADD 1 TO HSIZE
               MOVE VV TO HEAP(HSIZE)
               MOVE HSIZE TO HPOS(VV)
               MOVE HSIZE TO HI
               PERFORM HEAP-UP
           END-IF.

      *> Removes the top into HTOP.
       HEAP-POP.
           MOVE HEAP(1) TO HTOP
           MOVE 0 TO HPOS(HTOP)
           MOVE HEAP(HSIZE) TO HPV
           SUBTRACT 1 FROM HSIZE
           IF HSIZE > 0
               MOVE HPV TO HEAP(1)
               MOVE 1 TO HI
               PERFORM HEAP-DOWN
           END-IF.

      *> Moves the variable at position HI up while it beats its parent.
       HEAP-UP.
           MOVE HEAP(HI) TO HV
           MOVE 1 TO MOVING
           PERFORM UNTIL MOVING = 0
               IF HI <= 1
                   MOVE 0 TO MOVING
               ELSE
                   MOVE PAR(HI) TO HP
                   MOVE HEAP(HP) TO HPV
                   IF ACT(HPV) < ACT(HV)
                       MOVE HPV TO HEAP(HI)
                       MOVE HI TO HPOS(HPV)
                       MOVE HP TO HI
                   ELSE
                       MOVE 0 TO MOVING
                   END-IF
               END-IF
           END-PERFORM
           MOVE HV TO HEAP(HI)
           MOVE HI TO HPOS(HV).

      *> Moves the variable at position HI down past its larger children.
       HEAP-DOWN.
           MOVE HEAP(HI) TO HV
           MOVE 1 TO MOVING
           PERFORM UNTIL MOVING = 0
               MOVE HI TO HC
               ADD HI TO HC
               IF HC > HSIZE
                   MOVE 0 TO MOVING
               ELSE
                   MOVE HEAP(HC) TO HPV
                   IF HC < HSIZE
                       MOVE HC TO HC2
                       ADD 1 TO HC2
                       MOVE HEAP(HC2) TO HPV2
                       IF ACT(HPV) < ACT(HPV2)
                           MOVE HC2 TO HC
                           MOVE HPV2 TO HPV
                       END-IF
                   END-IF
                   IF ACT(HPV) > ACT(HV)
                       MOVE HPV TO HEAP(HI)
                       MOVE HI TO HPOS(HPV)
                       MOVE HC TO HI
                   ELSE
                       MOVE 0 TO MOVING
                   END-IF
               END-IF
           END-PERFORM
           MOVE HV TO HEAP(HI)
           MOVE HI TO HPOS(HV).

       REDUCE-DB.
           MOVE 0 TO NC
           PERFORM VARYING CIX FROM 1 BY 1 UNTIL CIX > NCL
               MOVE 0 TO CLD(CIX)
               IF CLL(CIX) = 1 AND CLB(CIX) > 2
                   ADD 1 TO NC
                   MOVE CIX TO CAND(NC)
                   IF CLN(CIX) > 999
                       COMPUTE KEYV(NC) = CLB(CIX) * 1000 + 999
                   ELSE
                       COMPUTE KEYV(NC) = CLB(CIX) * 1000 + CLN(CIX)
                   END-IF
               END-IF
           END-PERFORM
      *>   Shell sort ascending by KEYV (best candidates first).
           COMPUTE GAP = NC / 2
           PERFORM UNTIL GAP < 1
               PERFORM VARYING I FROM GAP BY 1 UNTIL I >= NC
                   COMPUTE IDX = I + 1
                   MOVE KEYV(IDX) TO KT
                   MOVE CAND(IDX) TO CT
                   MOVE IDX TO J
                   MOVE 1 TO MOVING
                   PERFORM UNTIL MOVING = 0
                       IF J <= GAP
                           MOVE 0 TO MOVING
                       ELSE
                           COMPUTE JG = J - GAP
                           IF KEYV(JG) > KT
                               MOVE KEYV(JG) TO KEYV(J)
                               MOVE CAND(JG) TO CAND(J)
                               SUBTRACT GAP FROM J
                           ELSE
                               MOVE 0 TO MOVING
                           END-IF
                       END-IF
                   END-PERFORM
                   MOVE KT TO KEYV(J)
                   MOVE CT TO CAND(J)
               END-PERFORM
               COMPUTE GAP = GAP / 2
           END-PERFORM
      *>   Mark the worse half for deletion.
           COMPUTE HALF = NC / 2
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NC
               IF I > HALF
                   MOVE CAND(I) TO CIX
                   MOVE 1 TO CLD(CIX)
               END-IF
           END-PERFORM
      *>   Compact in place (clauses keep their relative order, so the
      *>   original clauses stay first and keep their indices).
           MOVE 0 TO NEWN
           MOVE 0 TO DST
           MOVE 0 TO NLRN
           PERFORM VARYING CIX FROM 1 BY 1 UNTIL CIX > NCL
               IF CLD(CIX) = 0
                   MOVE CST(CIX) TO SS
                   MOVE CLN(CIX) TO LN
                   MOVE CLL(CIX) TO CLLV
                   MOVE CLB(CIX) TO CLBV
                   ADD 1 TO NEWN
                   COMPUTE DSTS = DST + 1
                   PERFORM VARYING K FROM 0 BY 1 UNTIL K >= LN
                       COMPUTE IDX = DSTS + K
                       COMPUTE IDX2 = SS + K
                       MOVE LP(IDX2) TO LP(IDX)
                   END-PERFORM
                   MOVE DSTS TO CST(NEWN)
                   MOVE LN TO CLN(NEWN)
                   MOVE CLLV TO CLL(NEWN)
                   MOVE CLBV TO CLB(NEWN)
                   MOVE 0 TO CLD(NEWN)
                   IF CLLV = 1
                       ADD 1 TO NLRN
                   END-IF
                   ADD LN TO DST
               END-IF
           END-PERFORM
           MOVE NEWN TO NCL
           MOVE DST TO LTOP
      *>   Reasons are not needed at level 0.
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > TRTOP
               MOVE TRAIL(I) TO Q
               IF Q < 0
                   COMPUTE VV = 0 - Q
               ELSE
                   MOVE Q TO VV
               END-IF
               MOVE 0 TO RSN(VV)
           END-PERFORM
           COMPUTE I0 = LITOFF - NV
           COMPUTE I1 = LITOFF + NV
           PERFORM VARYING I FROM I0 BY 1 UNTIL I > I1
               MOVE 0 TO WH(I)
           END-PERFORM
           PERFORM VARYING CIX FROM 1 BY 1 UNTIL CIX > NCL
               PERFORM REBUILD-CLAUSE
           END-PERFORM
           COMPUTE LLIM = NLRN + 4000.

      *> Puts non-false literals first, then watches the first two.
       REBUILD-CLAUSE.
           MOVE CST(CIX) TO SS
           MOVE CLN(CIX) TO LN
           MOVE SS TO I
           PERFORM VARYING K FROM 0 BY 1 UNTIL K >= LN
               COMPUTE IDX = SS + K
               MOVE LP(IDX) TO Q
               COMPUTE IDX2 = Q + LITOFF
               IF VAL(IDX2) NOT = -1
                   MOVE LP(I) TO TMP
                   MOVE Q TO LP(I)
                   MOVE TMP TO LP(IDX)
                   ADD 1 TO I
               END-IF
           END-PERFORM
           COMPUTE ND = 2 * CIX - 1
           MOVE CIX TO WN-C(ND)
           MOVE LP(SS) TO WA-LIT
           MOVE ND TO WA-NODE
           PERFORM WATCH-ADD
           COMPUTE ND = 2 * CIX
           MOVE CIX TO WN-C(ND)
           MOVE LP(SS + 1) TO WA-LIT
           MOVE ND TO WA-NODE
           PERFORM WATCH-ADD.

      *> ------------------------------------------------------------
      *> Output
      *> ------------------------------------------------------------
      *> Checks that every original clause has a true literal.
       VERIFY-MODEL.
           MOVE 0 TO BADF
           PERFORM VARYING CIX FROM 1 BY 1 UNTIL CIX > NORIG
               MOVE 0 TO FOUND
               MOVE CST(CIX) TO SS
               MOVE CLN(CIX) TO LN
               PERFORM VARYING K FROM 0 BY 1 UNTIL K >= LN OR FOUND = 1
                   COMPUTE IDX = LP(SS + K) + LITOFF
                   IF VAL(IDX) = 1
                       MOVE 1 TO FOUND
                   END-IF
               END-PERFORM
               IF FOUND = 0
                   MOVE 1 TO BADF
               END-IF
           END-PERFORM
           PERFORM VARYING V FROM 1 BY 1 UNTIL V > NV
               COMPUTE IDX = V + LITOFF
               IF VAL(IDX) = 0
                   MOVE 1 TO BADF
               END-IF
           END-PERFORM.

       PRINT-MODEL.
           DISPLAY "s SATISFIABLE"
           MOVE SPACES TO WS-LINE
           MOVE 1 TO WS-PTR
           STRING "v" DELIMITED BY SIZE INTO WS-LINE
               WITH POINTER WS-PTR
           PERFORM VARYING V FROM 1 BY 1 UNTIL V > NV
               COMPUTE IDX = V + LITOFF
               IF VAL(IDX) = 1
                   MOVE V TO NUM-ED
               ELSE
                   COMPUTE NUMV = 0 - V
                   MOVE NUMV TO NUM-ED
               END-IF
               IF WS-PTR > 70
                   DISPLAY WS-LINE(1:WS-PTR - 1)
                   MOVE SPACES TO WS-LINE
                   MOVE 1 TO WS-PTR
                   STRING "v" DELIMITED BY SIZE INTO WS-LINE
                       WITH POINTER WS-PTR
               END-IF
               STRING " " FUNCTION TRIM(NUM-ED) DELIMITED BY SIZE
                   INTO WS-LINE WITH POINTER WS-PTR
           END-PERFORM
           STRING " 0" DELIMITED BY SIZE INTO WS-LINE
               WITH POINTER WS-PTR
           DISPLAY WS-LINE(1:WS-PTR - 1).
