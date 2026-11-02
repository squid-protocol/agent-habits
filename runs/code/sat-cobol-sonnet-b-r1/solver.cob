IDENTIFICATION DIVISION.
PROGRAM-ID. SATSOLVER.
ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT CNF ASSIGN TO W-FN ORGANIZATION LINE SEQUENTIAL
        FILE STATUS W-FS.
DATA DIVISION.
FILE SECTION.
FD CNF RECORD IS VARYING IN SIZE FROM 1 TO 8192 DEPENDING ON W-RL.
01 REC.
    05 RB PIC X COMP-X OCCURS 8192.
WORKING-STORAGE SECTION.
78 MAXV VALUE 100000.
78 LOFF VALUE 100001.
78 MAXCL VALUE 800000.
78 POOLMAX VALUE 12000000.
01 W-FN PIC X(1024).
01 W-FS PIC XX.
01 W-RL PIC S9(9) COMP-5.
01 W-EOF PIC S9(9) COMP-5 VALUE 0.
01 W-I PIC S9(9) COMP-5.
01 W-J PIC S9(9) COMP-5.
01 W-K PIC S9(9) COMP-5.
01 W-NV PIC S9(9) COMP-5 VALUE 0.
01 W-NCL PIC S9(9) COMP-5 VALUE 0.
01 W-NC PIC S9(9) COMP-5 VALUE 0.
01 W-NORIG PIC S9(9) COMP-5 VALUE 0.
01 W-POOLN PIC S9(9) COMP-5 VALUE 0.
01 W-TOK PIC S9(9) COMP-5.
01 W-TOKF PIC S9(9) COMP-5.
01 W-NEG PIC S9(9) COMP-5.
01 W-CBN PIC S9(9) COMP-5 VALUE 0.
01 W-UNSAT PIC S9(9) COMP-5 VALUE 0.
01 W-STAMPC PIC S9(9) COMP-5 VALUE 0.
01 W-UNN PIC S9(9) COMP-5 VALUE 0.
01 W-L PIC S9(9) COMP-5.
01 W-V PIC S9(9) COMP-5.
01 W-Q PIC S9(9) COMP-5.
01 W-P PIC S9(9) COMP-5.
01 W-C PIC S9(9) COMP-5.
01 W-S PIC S9(9) COMP-5.
01 W-E PIC S9(9) COMP-5.
01 W-NODE PIC S9(9) COMP-5.
01 W-NX PIC S9(9) COMP-5.
01 W-PRV PIC S9(9) COMP-5.
01 W-OL PIC S9(9) COMP-5.
01 W-NL PIC S9(9) COMP-5.
01 W-OP PIC S9(9) COMP-5.
01 W-FND PIC S9(9) COMP-5.
01 W-F PIC S9(9) COMP-5.
01 W-ELIT PIC S9(9) COMP-5.
01 W-EREA PIC S9(9) COMP-5.
01 W-TRN PIC S9(9) COMP-5 VALUE 0.
01 W-QH PIC S9(9) COMP-5 VALUE 1.
01 W-DL PIC S9(9) COMP-5 VALUE 0.
01 W-CONFL PIC S9(9) COMP-5 VALUE 0.
01 W-HN PIC S9(9) COMP-5 VALUE 0.
01 W-HI PIC S9(9) COMP-5.
01 W-HV PIC S9(9) COMP-5.
01 W-HPAR PIC S9(9) COMP-5.
01 W-HC PIC S9(9) COMP-5.
01 W-ADN PIC S9(9) COMP-5.
01 W-RJ PIC S9(9) COMP-5.
01 W-NG PIC S9(9) COMP-5.
01 W-DONE PIC S9(9) COMP-5.
01 W-TOP PIC S9(9) COMP-5.
01 W-BV PIC S9(9) COMP-5.
01 W-HA COMP-2.
01 W-INC COMP-2 VALUE 1.0.
01 W-PATH PIC S9(9) COMP-5.
01 W-IDX PIC S9(9) COMP-5.
01 W-LN PIC S9(9) COMP-5.
01 W-K2 PIC S9(9) COMP-5.
01 W-RED PIC S9(9) COMP-5.
01 W-RC PIC S9(9) COMP-5.
01 W-BL PIC S9(9) COMP-5.
01 W-LBD PIC S9(9) COMP-5.
01 W-STP PIC S9(9) COMP-5 VALUE 0.
01 W-LV PIC S9(9) COMP-5.
01 W-BEST PIC S9(9) COMP-5.
01 W-TARGET PIC S9(9) COMP-5.
01 W-REMOVED PIC S9(9) COMP-5.
01 W-THR PIC S9(9) COMP-5.
01 W-NC2 PIC S9(9) COMP-5.
01 W-PN2 PIC S9(9) COMP-5.
01 W-LEN PIC S9(9) COMP-5.
01 W-NS PIC S9(9) COMP-5.
01 W-DEL PIC S9(9) COMP-5.
01 W-CAND PIC S9(9) COMP-5.
01 W-MAXL PIC S9(9) COMP-5 VALUE 6000.
01 W-CONFLICTS PIC S9(18) COMP-5 VALUE 0.
01 W-SINCE PIC S9(9) COMP-5 VALUE 0.
01 W-RLIM PIC S9(9) COMP-5 VALUE 100.
01 W-RN PIC S9(9) COMP-5 VALUE 0.
01 W-LSZ PIC S9(9) COMP-5.
01 W-LSEQ PIC S9(9) COMP-5.
01 W-LX PIC S9(9) COMP-5.
01 W-DV PIC S9(9) COMP-5.
01 W-RES PIC S9(9) COMP-5 VALUE 0.
01 W-NLEARNT PIC S9(9) COMP-5.
01 W-ED PIC -(6)9.
01 W-SP PIC S9(9) COMP-5.
01 W-PTR PIC S9(9) COMP-5.
01 W-OUT PIC X(100).
01 W-CB-T.
    05 W-CB PIC S9(9) COMP-5 OCCURS 100002.
01 W-UN-T.
    05 W-UN PIC S9(9) COMP-5 OCCURS 100002.
01 W-MARK-T.
    05 W-MARK PIC S9(9) COMP-5 OCCURS 200003.
01 W-VAL-T.
    05 W-VAL PIC S9(4) COMP-5 OCCURS 200003.
01 W-WHD-T.
    05 W-WHD PIC S9(9) COMP-5 OCCURS 200003.
01 W-LVL-T.
    05 W-LVL PIC S9(9) COMP-5 OCCURS 100002.
01 W-REAS-T.
    05 W-REAS PIC S9(9) COMP-5 OCCURS 100002.
01 W-SEEN-T.
    05 W-SEEN PIC S9(4) COMP-5 OCCURS 100002.
01 W-PHS-T.
    05 W-PHS PIC S9(4) COMP-5 OCCURS 100002.
01 W-HPOS-T.
    05 W-HPOS PIC S9(9) COMP-5 OCCURS 100002.
01 W-HP-T.
    05 W-HP PIC S9(9) COMP-5 OCCURS 100002.
01 W-ACT-T.
    05 W-ACT COMP-2 OCCURS 100002.
01 W-TRL-T.
    05 W-TRL PIC S9(9) COMP-5 OCCURS 100002.
01 W-TLIM-T.
    05 W-TLIM PIC S9(9) COMP-5 OCCURS 100003.
01 W-LRN-T.
    05 W-LRN PIC S9(9) COMP-5 OCCURS 100002.
01 W-LCP-T.
    05 W-LCP PIC S9(9) COMP-5 OCCURS 100002.
01 W-STPA-T.
    05 W-STPA PIC S9(9) COMP-5 OCCURS 100003.
01 W-HIST-T.
    05 W-HIST PIC S9(9) COMP-5 OCCURS 1002.
01 W-CST-T.
    05 W-CST PIC S9(9) COMP-5 OCCURS 800002.
01 W-CLEN-T.
    05 W-CLEN PIC S9(9) COMP-5 OCCURS 800002.
01 W-CLBD-T.
    05 W-CLBD PIC S9(9) COMP-5 OCCURS 800002.
01 W-NXT-T.
    05 W-NXT PIC S9(9) COMP-5 OCCURS 1600006.
01 W-NDC-T.
    05 W-NDC PIC S9(9) COMP-5 OCCURS 1600006.
01 W-NDK-T.
    05 W-NDK PIC S9(9) COMP-5 OCCURS 1600006.
01 W-PAR-T.
    05 W-PAR PIC S9(9) COMP-5 OCCURS 100002.
01 W-LITS-T.
    05 W-LITS PIC S9(9) COMP-5 OCCURS 12000002.

PROCEDURE DIVISION.
MAIN-PARA.
    ACCEPT W-FN FROM COMMAND-LINE
    MOVE FUNCTION TRIM(W-FN) TO W-FN
    PERFORM LOAD-FILE
    IF W-UNSAT = 1
        PERFORM DO-UNSAT
    END-IF
    PERFORM INIT-SOLVE
    IF W-UNSAT = 1
        PERFORM DO-UNSAT
    END-IF
    PERFORM SOLVE-LOOP
    STOP RUN.

DO-UNSAT.
    DISPLAY "s UNSATISFIABLE"
    MOVE 20 TO RETURN-CODE
    STOP RUN.

LOAD-FILE.
    OPEN INPUT CNF
    IF W-FS NOT = "00"
        DISPLAY "s UNKNOWN"
        MOVE 1 TO RETURN-CODE
        STOP RUN
    END-IF
    PERFORM UNTIL W-EOF = 1
        READ CNF
            AT END MOVE 1 TO W-EOF
            NOT AT END PERFORM PARSE-LINE
        END-READ
    END-PERFORM
    CLOSE CNF
    MOVE W-NC TO W-NORIG.

PARSE-LINE.
    MOVE 1 TO W-I
    PERFORM UNTIL W-I > W-RL OR (RB(W-I) NOT = 32
            AND RB(W-I) NOT = 9 AND RB(W-I) NOT = 13)
        ADD 1 TO W-I
    END-PERFORM
    IF W-I > W-RL
        EXIT PARAGRAPH
    END-IF
    IF RB(W-I) = 99
        EXIT PARAGRAPH
    END-IF
    IF RB(W-I) = 37
        MOVE 1 TO W-EOF
        EXIT PARAGRAPH
    END-IF
    IF RB(W-I) = 112
        ADD 1 TO W-I
        PERFORM NEXT-INT
        IF W-TOKF = 1
            MOVE W-TOK TO W-NV
        END-IF
        PERFORM NEXT-INT
        IF W-TOKF = 1
            MOVE W-TOK TO W-NCL
        END-IF
        IF W-NV > MAXV
            DISPLAY "s UNKNOWN"
            MOVE 1 TO RETURN-CODE
            STOP RUN
        END-IF
        EXIT PARAGRAPH
    END-IF
    PERFORM NEXT-INT
    PERFORM UNTIL W-TOKF = 0
        IF W-TOK = 0
            PERFORM FINISH-CLAUSE
        ELSE
            ADD 1 TO W-CBN
            MOVE W-TOK TO W-CB(W-CBN)
            IF W-TOK < 0
                MOVE 0 TO W-NG
                SUBTRACT W-TOK FROM W-NG
                MOVE W-NG TO W-V
            ELSE
                MOVE W-TOK TO W-V
            END-IF
            IF W-V > MAXV OR W-CBN > 100000
                DISPLAY "s UNKNOWN"
                MOVE 1 TO RETURN-CODE
                STOP RUN
            END-IF
            IF W-V > W-NV
                MOVE W-V TO W-NV
            END-IF
        END-IF
        PERFORM NEXT-INT
    END-PERFORM.

NEXT-INT.
    MOVE 0 TO W-TOKF
    PERFORM UNTIL W-I > W-RL OR RB(W-I) = 45
            OR (RB(W-I) >= 48 AND RB(W-I) <= 57)
        ADD 1 TO W-I
    END-PERFORM
    IF W-I > W-RL
        EXIT PARAGRAPH
    END-IF
    MOVE 0 TO W-NEG
    IF RB(W-I) = 45
        MOVE 1 TO W-NEG
        ADD 1 TO W-I
    END-IF
    MOVE 0 TO W-TOK
    PERFORM UNTIL W-I > W-RL OR RB(W-I) < 48 OR RB(W-I) > 57
        COMPUTE W-TOK = W-TOK * 10 + RB(W-I) - 48
        ADD 1 TO W-I
    END-PERFORM
    IF W-NEG = 1
        MOVE 0 TO W-NG
        SUBTRACT W-TOK FROM W-NG
        MOVE W-NG TO W-TOK
    END-IF
    MOVE 1 TO W-TOKF.

FINISH-CLAUSE.
    ADD 1 TO W-STAMPC
    MOVE 0 TO W-K
    MOVE 0 TO W-DONE
    PERFORM VARYING W-J FROM 1 BY 1 UNTIL W-J > W-CBN
        MOVE W-CB(W-J) TO W-L
        IF W-MARK(LOFF - W-L) = W-STAMPC
            MOVE 1 TO W-DONE
        ELSE
            IF W-MARK(LOFF + W-L) NOT = W-STAMPC
                MOVE W-STAMPC TO W-MARK(LOFF + W-L)
                ADD 1 TO W-K
                MOVE W-L TO W-CB(W-K)
            END-IF
        END-IF
    END-PERFORM
    MOVE 0 TO W-CBN
    IF W-DONE = 1
        EXIT PARAGRAPH
    END-IF
    IF W-K = 0
        MOVE 1 TO W-UNSAT
        EXIT PARAGRAPH
    END-IF
    IF W-K = 1
        ADD 1 TO W-UNN
        MOVE W-CB(1) TO W-UN(W-UNN)
        EXIT PARAGRAPH
    END-IF
    IF W-NC >= MAXCL - 10 OR W-POOLN + W-K > POOLMAX - 200000
        DISPLAY "s UNKNOWN"
        MOVE 1 TO RETURN-CODE
        STOP RUN
    END-IF
    ADD 1 TO W-NC
    COMPUTE W-CST(W-NC) = W-POOLN + 1
    MOVE W-K TO W-CLEN(W-NC)
    MOVE 0 TO W-CLBD(W-NC)
    PERFORM VARYING W-J FROM 1 BY 1 UNTIL W-J > W-K
        ADD 1 TO W-POOLN
        MOVE W-CB(W-J) TO W-LITS(W-POOLN)
    END-PERFORM
    MOVE W-NC TO W-C
    PERFORM ATTACH.

ATTACH.
    MOVE W-CST(W-C) TO W-S
    MOVE W-LITS(W-S) TO W-L
    MOVE W-C TO W-NODE
    ADD W-C TO W-NODE
    MOVE W-C TO W-NDC(W-NODE)
    MOVE 0 TO W-NDK(W-NODE)
    MOVE W-WHD(LOFF + W-L) TO W-NXT(W-NODE)
    MOVE W-NODE TO W-WHD(LOFF + W-L)
    MOVE W-LITS(W-S + 1) TO W-L
    ADD 1 TO W-NODE
    MOVE W-C TO W-NDC(W-NODE)
    MOVE 1 TO W-NDK(W-NODE)
    MOVE W-WHD(LOFF + W-L) TO W-NXT(W-NODE)
    MOVE W-NODE TO W-WHD(LOFF + W-L).

INIT-SOLVE.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > W-NV
        COMPUTE W-PAR(W-I) = W-I / 2
    END-PERFORM
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > W-NV
        MOVE W-I TO W-HP(W-I)
        MOVE W-I TO W-HPOS(W-I)
        MOVE 0 TO W-PHS(W-I)
    END-PERFORM
    MOVE W-NV TO W-HN
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > W-UNN
        MOVE W-UN(W-I) TO W-L
        IF W-VAL(LOFF + W-L) = -1
            MOVE 1 TO W-UNSAT
            EXIT PARAGRAPH
        END-IF
        IF W-VAL(LOFF + W-L) = 0
            MOVE W-L TO W-ELIT
            MOVE 0 TO W-EREA
            PERFORM ENQUEUE
        END-IF
    END-PERFORM
    PERFORM PROPAGATE
    IF W-CONFL NOT = 0
        MOVE 1 TO W-UNSAT
    END-IF.

ENQUEUE.
    IF W-ELIT < 0
        MOVE 0 TO W-NG
        SUBTRACT W-ELIT FROM W-NG
        MOVE W-NG TO W-V
        MOVE 0 TO W-PHS(W-V)
    ELSE
        MOVE W-ELIT TO W-V
        MOVE 1 TO W-PHS(W-V)
    END-IF
    MOVE 1 TO W-VAL(LOFF + W-ELIT)
    MOVE -1 TO W-VAL(LOFF - W-ELIT)
    MOVE W-DL TO W-LVL(W-V)
    MOVE W-EREA TO W-REAS(W-V)
    ADD 1 TO W-TRN
    MOVE W-ELIT TO W-TRL(W-TRN).

PROPAGATE.
    PERFORM UNTIL W-QH > W-TRN OR W-CONFL NOT = 0
        MOVE W-TRL(W-QH) TO W-P
        ADD 1 TO W-QH
        MOVE 0 TO W-NG
        SUBTRACT W-P FROM W-NG
        MOVE W-NG TO W-F
        MOVE W-WHD(LOFF + W-F) TO W-NODE
        MOVE 0 TO W-PRV
        PERFORM UNTIL W-NODE = 0 OR W-CONFL NOT = 0
            MOVE W-NXT(W-NODE) TO W-NX
            MOVE W-NDC(W-NODE) TO W-C
            MOVE W-NDK(W-NODE) TO W-K
            MOVE W-CST(W-C) TO W-S
            MOVE W-LITS(W-S + 1 - W-K) TO W-OL
            IF W-VAL(LOFF + W-OL) = 1
                MOVE W-NODE TO W-PRV
            ELSE
                MOVE W-S TO W-E
                ADD W-CLEN(W-C) TO W-E
                SUBTRACT 1 FROM W-E
                MOVE 0 TO W-FND
                MOVE W-S TO W-J
                ADD 2 TO W-J
                PERFORM UNTIL W-J > W-E OR W-FND = 1
                    IF W-VAL(LOFF + W-LITS(W-J)) NOT = -1
                        MOVE 1 TO W-FND
                    ELSE
                        ADD 1 TO W-J
                    END-IF
                END-PERFORM
                IF W-FND = 1
                    MOVE W-LITS(W-J) TO W-NL
                    MOVE W-LITS(W-S + W-K) TO W-LITS(W-J)
                    MOVE W-NL TO W-LITS(W-S + W-K)
                    IF W-PRV = 0
                        MOVE W-NX TO W-WHD(LOFF + W-F)
                    ELSE
                        MOVE W-NX TO W-NXT(W-PRV)
                    END-IF
                    MOVE W-WHD(LOFF + W-NL) TO W-NXT(W-NODE)
                    MOVE W-NODE TO W-WHD(LOFF + W-NL)
                ELSE
                    MOVE W-NODE TO W-PRV
                    IF W-VAL(LOFF + W-OL) = -1
                        MOVE W-C TO W-CONFL
                    ELSE
                        MOVE W-OL TO W-ELIT
                        MOVE W-C TO W-EREA
                        PERFORM ENQUEUE
                    END-IF
                END-IF
            END-IF
            MOVE W-NX TO W-NODE
        END-PERFORM
    END-PERFORM.

BACKTRACK.
    IF W-DL <= W-BL
        EXIT PARAGRAPH
    END-IF
    MOVE W-TLIM(W-BL + 1) TO W-K
    PERFORM VARYING W-I FROM W-TRN BY -1 UNTIL W-I < W-K
        MOVE W-TRL(W-I) TO W-L
        MOVE 0 TO W-VAL(LOFF + W-L)
        MOVE 0 TO W-VAL(LOFF - W-L)
        IF W-L < 0
            MOVE 0 TO W-NG
            SUBTRACT W-L FROM W-NG
            MOVE W-NG TO W-V
        ELSE
            MOVE W-L TO W-V
        END-IF
        IF W-HPOS(W-V) = 0
            PERFORM HEAP-INSERT
        END-IF
    END-PERFORM
    MOVE W-K TO W-TRN
    SUBTRACT 1 FROM W-TRN
    MOVE W-K TO W-QH
    MOVE W-BL TO W-DL.

HEAP-INSERT.
    ADD 1 TO W-HN
    MOVE W-V TO W-HP(W-HN)
    MOVE W-HN TO W-HPOS(W-V)
    MOVE W-HN TO W-HI
    PERFORM HEAP-UP.

HEAP-UP.
    MOVE W-HP(W-HI) TO W-HV
    MOVE W-ACT(W-HV) TO W-HA
    MOVE 0 TO W-DONE
    PERFORM UNTIL W-HI <= 1 OR W-DONE = 1
        MOVE W-PAR(W-HI) TO W-HPAR
        MOVE W-HP(W-HPAR) TO W-HC
        IF W-ACT(W-HC) < W-HA
            MOVE W-HC TO W-HP(W-HI)
            MOVE W-HI TO W-HPOS(W-HC)
            MOVE W-HPAR TO W-HI
        ELSE
            MOVE 1 TO W-DONE
        END-IF
    END-PERFORM
    MOVE W-HV TO W-HP(W-HI)
    MOVE W-HI TO W-HPOS(W-HV).

HEAP-DOWN.
    MOVE W-HP(W-HI) TO W-HV
    MOVE W-ACT(W-HV) TO W-HA
    MOVE 0 TO W-DONE
    PERFORM UNTIL W-DONE = 1
        MOVE W-HI TO W-HPAR
        ADD W-HI TO W-HPAR
        IF W-HPAR > W-HN
            MOVE 1 TO W-DONE
        ELSE
            IF W-HPAR < W-HN
                IF W-ACT(W-HP(W-HPAR + 1)) > W-ACT(W-HP(W-HPAR))
                    ADD 1 TO W-HPAR
                END-IF
            END-IF
            MOVE W-HP(W-HPAR) TO W-HC
            IF W-ACT(W-HC) > W-HA
                MOVE W-HC TO W-HP(W-HI)
                MOVE W-HI TO W-HPOS(W-HC)
                MOVE W-HPAR TO W-HI
            ELSE
                MOVE 1 TO W-DONE
            END-IF
        END-IF
    END-PERFORM
    MOVE W-HV TO W-HP(W-HI)
    MOVE W-HI TO W-HPOS(W-HV).

HEAP-POP.
    MOVE W-HP(1) TO W-TOP
    MOVE 0 TO W-HPOS(W-TOP)
    MOVE W-HP(W-HN) TO W-HV
    SUBTRACT 1 FROM W-HN
    IF W-HN > 0
        MOVE W-HV TO W-HP(1)
        MOVE 1 TO W-HPOS(W-HV)
        MOVE 1 TO W-HI
        PERFORM HEAP-DOWN
    END-IF.

BUMP.
    ADD W-INC TO W-ACT(W-BV)
    IF W-ACT(W-BV) > 1.0E+100
        PERFORM VARYING W-RJ FROM 1 BY 1 UNTIL W-RJ > W-NV
            COMPUTE W-ACT(W-RJ) = W-ACT(W-RJ) * 1.0E-100
        END-PERFORM
        COMPUTE W-INC = W-INC * 1.0E-100
    END-IF
    IF W-HPOS(W-BV) > 0
        MOVE W-HPOS(W-BV) TO W-HI
        PERFORM HEAP-UP
    END-IF.

ANALYZE.
    MOVE 0 TO W-PATH
    MOVE 0 TO W-P
    MOVE W-TRN TO W-IDX
    MOVE 1 TO W-LN
    MOVE W-CONFL TO W-C
    MOVE 0 TO W-ADN
    PERFORM UNTIL W-ADN = 1
        MOVE W-CST(W-C) TO W-S
        MOVE W-S TO W-E
        ADD W-CLEN(W-C) TO W-E
        SUBTRACT 1 FROM W-E
        PERFORM VARYING W-J FROM W-S BY 1 UNTIL W-J > W-E
            MOVE W-LITS(W-J) TO W-Q
            IF W-Q NOT = W-P
                IF W-Q < 0
                    MOVE 0 TO W-NG
                    SUBTRACT W-Q FROM W-NG
                    MOVE W-NG TO W-V
                ELSE
                    MOVE W-Q TO W-V
                END-IF
                IF W-SEEN(W-V) = 0 AND W-LVL(W-V) > 0
                    MOVE W-V TO W-BV
                    PERFORM BUMP
                    MOVE 1 TO W-SEEN(W-V)
                    IF W-LVL(W-V) >= W-DL
                        ADD 1 TO W-PATH
                    ELSE
                        ADD 1 TO W-LN
                        MOVE W-Q TO W-LRN(W-LN)
                    END-IF
                END-IF
            END-IF
        END-PERFORM
        MOVE W-TRL(W-IDX) TO W-P
        IF W-P < 0
            MOVE 0 TO W-NG
            SUBTRACT W-P FROM W-NG
            MOVE W-NG TO W-V
        ELSE
            MOVE W-P TO W-V
        END-IF
        PERFORM UNTIL W-SEEN(W-V) = 1
            SUBTRACT 1 FROM W-IDX
            MOVE W-TRL(W-IDX) TO W-P
            IF W-P < 0
                MOVE 0 TO W-NG
                SUBTRACT W-P FROM W-NG
                MOVE W-NG TO W-V
            ELSE
                MOVE W-P TO W-V
            END-IF
        END-PERFORM
        SUBTRACT 1 FROM W-IDX
        MOVE 0 TO W-SEEN(W-V)
        SUBTRACT 1 FROM W-PATH
        IF W-PATH = 0
            MOVE 1 TO W-ADN
        ELSE
            MOVE W-REAS(W-V) TO W-C
        END-IF
    END-PERFORM
    COMPUTE W-LRN(1) = 0 - W-P
    PERFORM VARYING W-I FROM 2 BY 1 UNTIL W-I > W-LN
        MOVE W-LRN(W-I) TO W-LCP(W-I)
    END-PERFORM
    MOVE W-LN TO W-LSZ
    MOVE 1 TO W-K2
    PERFORM VARYING W-I FROM 2 BY 1 UNTIL W-I > W-LSZ
        MOVE W-LCP(W-I) TO W-Q
        IF W-Q < 0
            MOVE 0 TO W-NG
            SUBTRACT W-Q FROM W-NG
            MOVE W-NG TO W-V
        ELSE
            MOVE W-Q TO W-V
        END-IF
        MOVE 1 TO W-DEL
        IF W-REAS(W-V) = 0
            MOVE 0 TO W-DEL
        ELSE
            MOVE W-REAS(W-V) TO W-RC
            MOVE W-CST(W-RC) TO W-S
            MOVE W-S TO W-E
            ADD W-CLEN(W-RC) TO W-E
            SUBTRACT 1 FROM W-E
            PERFORM VARYING W-J FROM W-S BY 1 UNTIL W-J > W-E
                MOVE W-LITS(W-J) TO W-L
                IF W-L < 0
                    MOVE 0 TO W-NG
                    SUBTRACT W-L FROM W-NG
                    MOVE W-NG TO W-L
                END-IF
                IF W-L NOT = W-V
                    IF W-SEEN(W-L) = 0 AND W-LVL(W-L) > 0
                        MOVE 0 TO W-DEL
                    END-IF
                END-IF
            END-PERFORM
        END-IF
        IF W-DEL = 0
            ADD 1 TO W-K2
            MOVE W-Q TO W-LRN(W-K2)
        END-IF
    END-PERFORM
    PERFORM VARYING W-I FROM 2 BY 1 UNTIL W-I > W-LSZ
        MOVE W-LCP(W-I) TO W-Q
        IF W-Q < 0
            MOVE 0 TO W-NG
            SUBTRACT W-Q FROM W-NG
            MOVE W-NG TO W-V
        ELSE
            MOVE W-Q TO W-V
        END-IF
        MOVE 0 TO W-SEEN(W-V)
    END-PERFORM
    MOVE W-K2 TO W-LN
    MOVE 0 TO W-BL
    IF W-LN > 1
        MOVE 2 TO W-BEST
        MOVE W-LRN(2) TO W-Q
        IF W-Q < 0
            MOVE 0 TO W-NG
            SUBTRACT W-Q FROM W-NG
            MOVE W-NG TO W-V
        ELSE
            MOVE W-Q TO W-V
        END-IF
        MOVE W-LVL(W-V) TO W-BL
        PERFORM VARYING W-I FROM 3 BY 1 UNTIL W-I > W-LN
            MOVE W-LRN(W-I) TO W-Q
            IF W-Q < 0
                MOVE 0 TO W-NG
                SUBTRACT W-Q FROM W-NG
                MOVE W-NG TO W-V
            ELSE
                MOVE W-Q TO W-V
            END-IF
            IF W-LVL(W-V) > W-BL
                MOVE W-LVL(W-V) TO W-BL
                MOVE W-I TO W-BEST
            END-IF
        END-PERFORM
        MOVE W-LRN(2) TO W-Q
        MOVE W-LRN(W-BEST) TO W-LRN(2)
        MOVE W-Q TO W-LRN(W-BEST)
    END-IF
    ADD 1 TO W-STP
    MOVE 0 TO W-LBD
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > W-LN
        MOVE W-LRN(W-I) TO W-Q
        IF W-Q < 0
            MOVE 0 TO W-NG
            SUBTRACT W-Q FROM W-NG
            MOVE W-NG TO W-V
        ELSE
            MOVE W-Q TO W-V
        END-IF
        MOVE W-LVL(W-V) TO W-LV
        IF W-STPA(W-LV + 1) NOT = W-STP
            MOVE W-STP TO W-STPA(W-LV + 1)
            ADD 1 TO W-LBD
        END-IF
    END-PERFORM
    IF W-LBD > 1000
        MOVE 1000 TO W-LBD
    END-IF.

LEARN.
    PERFORM ANALYZE
    PERFORM BACKTRACK
    IF W-LN = 1
        MOVE W-LRN(1) TO W-ELIT
        MOVE 0 TO W-EREA
        PERFORM ENQUEUE
    ELSE
        ADD 1 TO W-NC
        COMPUTE W-CST(W-NC) = W-POOLN + 1
        MOVE W-LN TO W-CLEN(W-NC)
        MOVE W-LBD TO W-CLBD(W-NC)
        PERFORM VARYING W-J FROM 1 BY 1 UNTIL W-J > W-LN
            ADD 1 TO W-POOLN
            MOVE W-LRN(W-J) TO W-LITS(W-POOLN)
        END-PERFORM
        MOVE W-NC TO W-C
        PERFORM ATTACH
        MOVE W-LRN(1) TO W-ELIT
        MOVE W-NC TO W-EREA
        PERFORM ENQUEUE
    END-IF
    COMPUTE W-INC = W-INC / 0.95.

REDUCE-DB.
    MOVE 0 TO W-BL
    PERFORM BACKTRACK
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 1000
        MOVE 0 TO W-HIST(W-I)
    END-PERFORM
    MOVE 0 TO W-CAND
    PERFORM VARYING W-C FROM W-NORIG BY 1 UNTIL W-C > W-NC
        IF W-C > W-NORIG
            IF W-CLBD(W-C) > 2 AND W-CLEN(W-C) > 2
                ADD 1 TO W-HIST(W-CLBD(W-C))
                ADD 1 TO W-CAND
            END-IF
        END-IF
    END-PERFORM
    COMPUTE W-TARGET = W-CAND / 2
    MOVE 0 TO W-REMOVED
    MOVE 1001 TO W-THR
    MOVE 0 TO W-DONE
    PERFORM VARYING W-I FROM 1000 BY -1 UNTIL W-I < 3 OR W-DONE = 1
        IF W-REMOVED + W-HIST(W-I) <= W-TARGET
            ADD W-HIST(W-I) TO W-REMOVED
            MOVE W-I TO W-THR
        ELSE
            MOVE 1 TO W-DONE
        END-IF
    END-PERFORM
    MOVE W-NORIG TO W-NC2
    IF W-NORIG > 0
        COMPUTE W-PN2 = W-CST(W-NORIG) + W-CLEN(W-NORIG) - 1
    ELSE
        MOVE 0 TO W-PN2
    END-IF
    PERFORM VARYING W-C FROM W-NORIG BY 1 UNTIL W-C > W-NC
        IF W-C > W-NORIG
            MOVE 0 TO W-DEL
            IF W-CLBD(W-C) > 2 AND W-CLEN(W-C) > 2
                IF W-CLBD(W-C) >= W-THR
                    MOVE 1 TO W-DEL
                ELSE
                    IF W-CLBD(W-C) = W-THR - 1 AND W-REMOVED < W-TARGET
                        MOVE 1 TO W-DEL
                        ADD 1 TO W-REMOVED
                    END-IF
                END-IF
            END-IF
            IF W-DEL = 0
                ADD 1 TO W-NC2
                MOVE W-CST(W-C) TO W-S
                MOVE W-CLEN(W-C) TO W-LEN
                MOVE W-CLBD(W-C) TO W-LBD
                COMPUTE W-NS = W-PN2 + 1
                PERFORM VARYING W-J FROM 0 BY 1 UNTIL W-J >= W-LEN
                    MOVE W-LITS(W-S + W-J) TO W-LITS(W-NS + W-J)
                END-PERFORM
                MOVE W-NS TO W-CST(W-NC2)
                MOVE W-LEN TO W-CLEN(W-NC2)
                MOVE W-LBD TO W-CLBD(W-NC2)
                ADD W-LEN TO W-PN2
            END-IF
        END-IF
    END-PERFORM
    MOVE W-NC2 TO W-NC
    MOVE W-PN2 TO W-POOLN
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > W-TRN
        MOVE W-TRL(W-I) TO W-L
        IF W-L < 0
            MOVE 0 TO W-NG
            SUBTRACT W-L FROM W-NG
            MOVE W-NG TO W-L
        END-IF
        MOVE 0 TO W-REAS(W-L)
    END-PERFORM
    MOVE 0 TO W-NG
    SUBTRACT W-NV FROM W-NG
    PERFORM VARYING W-L FROM W-NG BY 1 UNTIL W-L > W-NV
        MOVE 0 TO W-WHD(LOFF + W-L)
    END-PERFORM
    PERFORM VARYING W-C FROM 1 BY 1 UNTIL W-C > W-NC
        PERFORM ATTACH
    END-PERFORM
    COMPUTE W-MAXL = W-MAXL + 500.

LUBY.
    MOVE 1 TO W-LSZ
    MOVE 0 TO W-LSEQ
    PERFORM UNTIL W-LSZ >= W-RN + 1
        ADD 1 TO W-LSEQ
        COMPUTE W-LSZ = 2 * W-LSZ + 1
    END-PERFORM
    MOVE W-RN TO W-LX
    PERFORM UNTIL W-LSZ - 1 = W-LX
        COMPUTE W-LSZ = (W-LSZ - 1) / 2
        SUBTRACT 1 FROM W-LSEQ
        COMPUTE W-LX = FUNCTION MOD(W-LX, W-LSZ)
    END-PERFORM
    MOVE 1 TO W-RES
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > W-LSEQ
        COMPUTE W-RES = W-RES * 2
    END-PERFORM
    COMPUTE W-RLIM = 100 * W-RES.

SOLVE-LOOP.
    PERFORM LUBY
    PERFORM UNTIL 1 = 2
        PERFORM PROPAGATE
        IF W-CONFL NOT = 0
            ADD 1 TO W-CONFLICTS
            ADD 1 TO W-SINCE
            IF W-DL = 0
                PERFORM DO-UNSAT
            END-IF
            PERFORM LEARN
            MOVE 0 TO W-CONFL
        ELSE
            COMPUTE W-NLEARNT = W-NC - W-NORIG
            IF W-NLEARNT > W-MAXL OR W-POOLN > POOLMAX - 200000
                    OR W-NC > MAXCL - 10
                PERFORM REDUCE-DB
            END-IF
            IF W-SINCE >= W-RLIM
                MOVE 0 TO W-SINCE
                ADD 1 TO W-RN
                PERFORM LUBY
                MOVE 0 TO W-BL
                PERFORM BACKTRACK
            ELSE
                MOVE 0 TO W-DV
                PERFORM UNTIL W-DV NOT = 0 OR W-HN = 0
                    PERFORM HEAP-POP
                    IF W-VAL(LOFF + W-TOP) = 0
                        MOVE W-TOP TO W-DV
                    END-IF
                END-PERFORM
                IF W-DV = 0
                    PERFORM DO-SAT
                END-IF
                ADD 1 TO W-DL
                MOVE W-TRN TO W-TLIM(W-DL)
                ADD 1 TO W-TLIM(W-DL)
                IF W-PHS(W-DV) = 1
                    MOVE W-DV TO W-ELIT
                ELSE
                    MOVE 0 TO W-NG
                    SUBTRACT W-DV FROM W-NG
                    MOVE W-NG TO W-ELIT
                END-IF
                MOVE 0 TO W-EREA
                PERFORM ENQUEUE
            END-IF
        END-IF
    END-PERFORM.

DO-SAT.
    DISPLAY "s SATISFIABLE"
    MOVE SPACES TO W-OUT
    MOVE 1 TO W-PTR
    STRING "v" DELIMITED BY SIZE INTO W-OUT WITH POINTER W-PTR
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > W-NV
        IF W-VAL(LOFF + W-I) = 1
            MOVE W-I TO W-ED
        ELSE
            MOVE 0 TO W-NG
            SUBTRACT W-I FROM W-NG
            MOVE W-NG TO W-ED
        END-IF
        MOVE 0 TO W-SP
        INSPECT W-ED TALLYING W-SP FOR LEADING SPACES
        STRING " " W-ED(W-SP + 1:) DELIMITED BY SIZE
            INTO W-OUT WITH POINTER W-PTR
        IF W-PTR > 70
            DISPLAY W-OUT(1:W-PTR - 1)
            MOVE SPACES TO W-OUT
            MOVE 1 TO W-PTR
            STRING "v" DELIMITED BY SIZE INTO W-OUT WITH POINTER W-PTR
        END-IF
    END-PERFORM
    STRING " 0" DELIMITED BY SIZE INTO W-OUT WITH POINTER W-PTR
    DISPLAY W-OUT(1:W-PTR - 1)
    MOVE 10 TO RETURN-CODE
    STOP RUN.
