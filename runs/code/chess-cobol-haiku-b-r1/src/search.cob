       IDENTIFICATION DIVISION.
       PROGRAM-ID. PERFT RECURSIVE.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "chs.cpy".
       LOCAL-STORAGE SECTION.
       01 P-BASE    PIC S9(9) COMP-5.
       01 P-END     PIC S9(9) COMP-5.
       01 P-I       PIC S9(9) COMP-5.
       01 P-OWN     PIC S9(4) COMP-5.
       01 P-SQ      PIC S9(4) COMP-5.
       01 P-RES     PIC S9(4) COMP-5.
       01 P-QO      PIC S9(4) COMP-5.
       01 P-D1      PIC S9(4) COMP-5.
       01 P-P1      PIC S9(4) COMP-5.
       01 P-SUB     PIC S9(18) COMP-5.
       01 P-TOT     PIC S9(18) COMP-5.
       LINKAGE SECTION.
       01 LK-DEP    PIC S9(4) COMP-5.
       01 LK-PLY    PIC S9(4) COMP-5.
       01 LK-TOT    PIC S9(18) COMP-5.
       PROCEDURE DIVISION USING LK-DEP LK-PLY LK-TOT.
       PF-MAIN.
           IF LK-DEP = 0
               MOVE 1 TO LK-TOT
               GOBACK
           END-IF
           COMPUTE P-BASE = LK-PLY * 256
           MOVE 0 TO P-QO
           CALL "GENMV" USING P-BASE P-QO P-END
           MOVE 0 TO P-TOT
           MOVE B-SIDE TO P-OWN
           COMPUTE P-I = P-BASE + 1
           PERFORM UNTIL P-I > P-END
               CALL "MKMV" USING P-I
               MOVE B-KSQ(P-OWN + 1) TO P-SQ
               CALL "ATTK" USING P-SQ B-SIDE P-RES
               IF P-RES = 0
                   IF LK-DEP = 1
                       ADD 1 TO P-TOT
                   ELSE
                       COMPUTE P-D1 = LK-DEP - 1
                       COMPUTE P-P1 = LK-PLY + 1
                       CALL "PERFT" USING P-D1 P-P1 P-SUB
                       ADD P-SUB TO P-TOT
                   END-IF
               END-IF
               CALL "UNMV" USING P-I
               ADD 1 TO P-I
           END-PERFORM
           MOVE P-TOT TO LK-TOT
           GOBACK.
       END PROGRAM PERFT.

       IDENTIFICATION DIVISION.
       PROGRAM-ID. SRCH RECURSIVE.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "chs.cpy".
       01 SR-LINE   PIC X(4096).
       LOCAL-STORAGE SECTION.
       01 L-BASE    PIC S9(9) COMP-5.
       01 L-END     PIC S9(9) COMP-5.
       01 L-I       PIC S9(9) COMP-5.
       01 L-J       PIC S9(9) COMP-5.
       01 L-BI      PIC S9(9) COMP-5.
       01 L-MAXS    PIC S9(9) COMP-5.
       01 L-SWF     PIC S9(4) COMP-5.
       01 L-SWT     PIC S9(4) COMP-5.
       01 L-SWP     PIC S9(4) COMP-5.
       01 L-SWS     PIC S9(9) COMP-5.
       01 L-OWN     PIC S9(4) COMP-5.
       01 L-OPP     PIC S9(4) COMP-5.
       01 L-SQ      PIC S9(4) COMP-5.
       01 L-INCHK   PIC S9(4) COMP-5.
       01 L-RES     PIC S9(4) COMP-5.
       01 L-QONLY   PIC S9(4) COMP-5.
       01 L-STAND   PIC S9(9) COMP-5.
       01 L-BEST    PIC S9(9) COMP-5.
       01 L-ALPHA   PIC S9(9) COMP-5.
       01 L-BETA    PIC S9(9) COMP-5.
       01 L-NA      PIC S9(9) COMP-5.
       01 L-NB      PIC S9(9) COMP-5.
       01 L-LEGAL   PIC S9(9) COMP-5.
       01 L-VAL     PIC S9(9) COMP-5.
       01 L-SCR     PIC S9(9) COMP-5.
       01 L-DEP     PIC S9(4) COMP-5.
       01 L-PLYN    PIC S9(4) COMP-5.
       01 L-CUT     PIC S9(4) COMP-5.
       01 L-VT      PIC S9(4) COMP-5.
       01 L-AT      PIC S9(4) COMP-5.
       01 L-NOW     PIC S9(9) COMP-5.
       01 L-EL      PIC S9(9) COMP-5.
       01 L-MODE    PIC S9(4) COMP-5.
       01 L-STATE   PIC S9(4) COMP-5.
       LINKAGE SECTION.
       01 LK-PLY    PIC S9(4) COMP-5.
       01 LK-DEP    PIC S9(4) COMP-5.
       01 LK-ALPHA  PIC S9(9) COMP-5.
       01 LK-BETA   PIC S9(9) COMP-5.
       01 LK-RES    PIC S9(9) COMP-5.
       PROCEDURE DIVISION USING LK-PLY LK-DEP LK-ALPHA LK-BETA LK-RES.
       SR-MAIN.
           ADD 1 TO B-NODES
           ADD 1 TO B-CNT
           IF B-CNT >= 32
               MOVE 0 TO B-CNT
               PERFORM CHECK-TIME
           END-IF
           IF B-ABRT = 1
               MOVE 0 TO LK-RES
               GOBACK
           END-IF
           MOVE LK-ALPHA TO L-ALPHA
           MOVE LK-BETA TO L-BETA
           MOVE B-SIDE TO L-OWN
           COMPUTE L-OPP = 1 - L-OWN
           MOVE B-KSQ(L-OWN + 1) TO L-SQ
           CALL "ATTK" USING L-SQ L-OPP L-INCHK
           IF LK-PLY >= 60
               PERFORM STAND-EVAL
               MOVE L-STAND TO LK-RES
               GOBACK
           END-IF
           IF LK-DEP <= 0
               IF L-INCHK = 0
                   PERFORM STAND-EVAL
                   IF L-STAND >= L-BETA
                       MOVE L-STAND TO LK-RES
                       GOBACK
                   END-IF
                   IF L-STAND > L-ALPHA
                       MOVE L-STAND TO L-ALPHA
                   END-IF
                   MOVE L-STAND TO L-BEST
                   MOVE 1 TO L-QONLY
               ELSE
                   MOVE -100000 TO L-BEST
                   MOVE 0 TO L-QONLY
               END-IF
           ELSE
               MOVE -100000 TO L-BEST
               MOVE 0 TO L-QONLY
           END-IF
           COMPUTE L-BASE = LK-PLY * 256
           CALL "GENMV" USING L-BASE L-QONLY L-END
           PERFORM SCORE-MOVES
           MOVE 0 TO L-LEGAL
           MOVE 0 TO L-CUT
           COMPUTE L-I = L-BASE + 1
           PERFORM UNTIL L-I > L-END OR L-CUT = 1 OR B-ABRT = 1
               PERFORM PICK-BEST
               CALL "MKMV" USING L-I
               MOVE B-KSQ(L-OWN + 1) TO L-SQ
               CALL "ATTK" USING L-SQ B-SIDE L-RES
               IF L-RES = 1
                   CALL "UNMV" USING L-I
               ELSE
                   ADD 1 TO L-LEGAL
                   COMPUTE L-DEP = LK-DEP - 1
                   COMPUTE L-PLYN = LK-PLY + 1
                   COMPUTE L-NA = 0 - L-BETA
                   COMPUTE L-NB = 0 - L-ALPHA
                   CALL "SRCH" USING L-PLYN L-DEP L-NA L-NB L-SCR
                   CALL "UNMV" USING L-I
                   COMPUTE L-VAL = 0 - L-SCR
                   IF B-ABRT = 0
                       IF L-VAL > L-BEST
                           MOVE L-VAL TO L-BEST
                           IF LK-PLY = 0
                               MOVE M-FR(L-I) TO B-BMF
                               MOVE M-TO(L-I) TO B-BMT
                               MOVE M-PR(L-I) TO B-BMP
                           END-IF
                           IF L-VAL > L-ALPHA
                               MOVE L-VAL TO L-ALPHA
                           END-IF
                           IF L-ALPHA >= L-BETA
                               MOVE 1 TO L-CUT
                           END-IF
                       END-IF
                   END-IF
               END-IF
               ADD 1 TO L-I
           END-PERFORM
           IF B-ABRT = 1
               MOVE 0 TO LK-RES
               GOBACK
           END-IF
           IF L-LEGAL = 0
               IF L-INCHK = 1
                   COMPUTE L-BEST = -30000 + LK-PLY
               ELSE
                   IF LK-DEP > 0
                       MOVE 0 TO L-BEST
                   END-IF
               END-IF
           END-IF
           MOVE L-BEST TO LK-RES
           GOBACK.

       STAND-EVAL.
           MOVE B-MAT TO L-STAND
           IF B-SIDE = 1
               COMPUTE L-STAND = 0 - B-MAT
           END-IF.

       SCORE-MOVES.
           PERFORM VARYING L-I FROM L-BASE BY 1 UNTIL L-I >= L-END
               COMPUTE L-J = L-I + 1
               MOVE 0 TO M-SC(L-J)
               IF B-PT(M-TO(L-J)) > 0
                   MOVE B-PT(M-TO(L-J)) TO L-VT
                   MOVE B-PT(M-FR(L-J)) TO L-AT
                   COMPUTE M-SC(L-J) = 10000 + L-VT * 10 - L-AT
               END-IF
               IF M-PR(L-J) > 0
                   COMPUTE M-SC(L-J) = M-SC(L-J) + 5000 + M-PR(L-J)
               END-IF
           END-PERFORM.

       PICK-BEST.
           MOVE L-I TO L-BI
           MOVE M-SC(L-I) TO L-MAXS
           COMPUTE L-J = L-I + 1
           PERFORM UNTIL L-J > L-END
               IF M-SC(L-J) > L-MAXS
                   MOVE M-SC(L-J) TO L-MAXS
                   MOVE L-J TO L-BI
               END-IF
               ADD 1 TO L-J
           END-PERFORM
           IF L-BI NOT = L-I
               MOVE M-FR(L-I) TO L-SWF
               MOVE M-FR(L-BI) TO M-FR(L-I)
               MOVE L-SWF TO M-FR(L-BI)
               MOVE M-TO(L-I) TO L-SWT
               MOVE M-TO(L-BI) TO M-TO(L-I)
               MOVE L-SWT TO M-TO(L-BI)
               MOVE M-PR(L-I) TO L-SWP
               MOVE M-PR(L-BI) TO M-PR(L-I)
               MOVE L-SWP TO M-PR(L-BI)
               MOVE M-SC(L-I) TO L-SWS
               MOVE M-SC(L-BI) TO M-SC(L-I)
               MOVE L-SWS TO M-SC(L-BI)
           END-IF.

       CHECK-TIME.
           CALL "NOWMS" USING L-NOW
           COMPUTE L-EL = L-NOW - B-T0
           IF L-EL < 0
               ADD 86400000 TO L-EL
           END-IF
           MOVE 2 TO L-MODE
           CALL "INPIO" USING L-MODE SR-LINE L-STATE
      *> End of input ends an unlimited search but lets a timed search run to its deadline.
           IF B-ITERD >= 2
               IF L-EL >= B-TLIM OR B-STOPREQ = 1
                   MOVE 1 TO B-ABRT
               END-IF
               IF B-QUITREQ = 1 AND B-TLIM >= 999999999
                   MOVE 1 TO B-ABRT
               END-IF
           END-IF.
       END PROGRAM SRCH.
