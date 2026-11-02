       IDENTIFICATION DIVISION.
       PROGRAM-ID. ENGINE.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "chs.cpy".
       01 LN        PIC X(4096).
       01 TKN.
          05 TK     PIC X(96) OCCURS 700.
       01 NTK       PIC S9(4) COMP-5.
       01 QUIT      PIC S9(4) COMP-5 VALUE 0.
       01 I1        PIC S9(9) COMP-5.
       01 I2        PIC S9(9) COMP-5.
       01 I3        PIC S9(9) COMP-5.
       01 WCH        PIC X.
       01 CUR       PIC X(96).
       01 CURLEN    PIC S9(4) COMP-5.
       01 FILES     PIC X(8) VALUE "abcdefgh".
       01 DIGS      PIC X(8) VALUE "12345678".
       01 PIECES    PIC X(12) VALUE "PNBRQKpnbrqk".
       01 PROMOCH   PIC X(4) VALUE "nbrq".
       01 FEN-PL    PIC X(90).
       01 FEN-SD    PIC X(90).
       01 FEN-CA    PIC X(90).
       01 FEN-EP    PIC X(90).
       01 W-SQ      PIC S9(4) COMP-5.
       01 W-F       PIC S9(4) COMP-5.
       01 W-R       PIC S9(4) COMP-5.
       01 W-Q       PIC S9(4) COMP-5.
       01 W-K       PIC S9(4) COMP-5.
       01 W-T       PIC S9(4) COMP-5.
       01 W-COL     PIC S9(4) COMP-5.
       01 W-FROM    PIC S9(4) COMP-5.
       01 W-TO      PIC S9(4) COMP-5.
       01 W-PRM     PIC S9(4) COMP-5.
       01 W-FOUND   PIC S9(4) COMP-5.
       01 W-STR     PIC X(8).
       01 W-SQS     PIC X(2).
       01 MSTART    PIC S9(4) COMP-5.
       01 GE        PIC S9(9) COMP-5.
       01 GB        PIC S9(9) COMP-5.
       01 GQ        PIC S9(4) COMP-5.
       01 GO-DEPTH  PIC S9(9) COMP-5.
       01 GO-MT     PIC S9(9) COMP-5.
       01 GO-WT     PIC S9(9) COMP-5.
       01 GO-BT     PIC S9(9) COMP-5.
       01 GO-WI     PIC S9(9) COMP-5.
       01 GO-BI     PIC S9(9) COMP-5.
       01 GO-PFT    PIC S9(9) COMP-5.
       01 LIM       PIC S9(9) COMP-5.
       01 MAXD      PIC S9(4) COMP-5.
       01 OWN       PIC S9(4) COMP-5.
       01 SQ        PIC S9(4) COMP-5.
       01 RES       PIC S9(4) COMP-5.
       01 SUB       PIC S9(18) COMP-5.
       01 TOTAL     PIC S9(18) COMP-5.
       01 ED        PIC Z(17)9.
       01 S-PLY     PIC S9(4) COMP-5.
       01 S-DEP     PIC S9(4) COMP-5.
       01 S-PLY1    PIC S9(4) COMP-5 VALUE 1.
       01 S-ALPHA   PIC S9(9) COMP-5.
       01 S-BETA    PIC S9(9) COMP-5.
       01 S-SC      PIC S9(9) COMP-5.
       01 FB-F      PIC S9(4) COMP-5.
       01 FB-T      PIC S9(4) COMP-5.
       01 FB-P      PIC S9(4) COMP-5.
       01 FB-SC     PIC S9(9) COMP-5.
       01 TMP-MS    PIC S9(9) COMP-5.
       01 TMP-EL    PIC S9(9) COMP-5.
       01 TMP-CNT   PIC S9(9) COMP-5.
       01 MODE-IO   PIC S9(4) COMP-5.
       01 IO-STATE  PIC S9(4) COMP-5.

       PROCEDURE DIVISION.
       MAIN-PARA.
           PERFORM INIT-TABLES
           PERFORM SET-STARTPOS
           PERFORM UNTIL QUIT = 1
               MOVE SPACES TO LN
               MOVE 1 TO MODE-IO
               CALL "INPIO" USING MODE-IO LN IO-STATE
               IF IO-STATE = 2
                   MOVE 1 TO QUIT
               ELSE
                   PERFORM TOKENIZE
                   IF NTK > 0
                       PERFORM DO-COMMAND
                   END-IF
                   CALL "fflush" USING BY VALUE 0
                   IF B-QUITREQ = 1
                       MOVE 1 TO QUIT
                   END-IF
               END-IF
           END-PERFORM
           STOP RUN.

       INIT-TABLES.
           MOVE 0 TO B-VAL(1)
           MOVE 100 TO B-VAL(2)
           MOVE 320 TO B-VAL(3)
           MOVE 330 TO B-VAL(4)
           MOVE 500 TO B-VAL(5)
           MOVE 900 TO B-VAL(6)
           MOVE 0 TO B-VAL(7)
           MOVE 0 TO B-VAL(8)
           MOVE 0 TO B-VAL(9)
           MOVE 0 TO B-VAL(10)
           MOVE -21 TO B-NOFF(1)
           MOVE -19 TO B-NOFF(2)
           MOVE -12 TO B-NOFF(3)
           MOVE -8 TO B-NOFF(4)
           MOVE 8 TO B-NOFF(5)
           MOVE 12 TO B-NOFF(6)
           MOVE 19 TO B-NOFF(7)
           MOVE 21 TO B-NOFF(8)
           MOVE -11 TO B-KOFF(1)
           MOVE -9 TO B-KOFF(2)
           MOVE 9 TO B-KOFF(3)
           MOVE 11 TO B-KOFF(4)
           MOVE -10 TO B-KOFF(5)
           MOVE -1 TO B-KOFF(6)
           MOVE 1 TO B-KOFF(7)
           MOVE 10 TO B-KOFF(8).

       CLEAR-BOARD.
           PERFORM VARYING W-SQ FROM 1 BY 1 UNTIL W-SQ > 120
               COMPUTE W-Q = W-SQ - 22
               MOVE 9 TO B-PT(W-SQ)
               IF W-Q >= 0 AND W-Q <= 77
                   COMPUTE W-R = W-Q / 10
                   COMPUTE W-F = W-Q - 10 * W-R
                   IF W-F < 8
                       MOVE 0 TO B-PT(W-SQ)
                   END-IF
               END-IF
               MOVE 2 TO B-COL(W-SQ)
           END-PERFORM
           MOVE 0 TO B-CR(1)
           MOVE 0 TO B-CR(2)
           MOVE 0 TO B-CR(3)
           MOVE 0 TO B-CR(4)
           MOVE 0 TO B-EPS
           MOVE 0 TO B-KSQ(1)
           MOVE 0 TO B-KSQ(2)
           MOVE 0 TO B-MAT
           MOVE 0 TO B-SP
           MOVE 0 TO B-SIDE.

       SET-STARTPOS.
           MOVE "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR" TO FEN-PL
           MOVE "w" TO FEN-SD
           MOVE "KQkq" TO FEN-CA
           MOVE "-" TO FEN-EP
           PERFORM SET-FEN.

       SET-FEN.
           PERFORM CLEAR-BOARD
           MOVE 7 TO W-R
           MOVE 0 TO W-F
           PERFORM VARYING I2 FROM 1 BY 1 UNTIL I2 > 90
               MOVE FEN-PL(I2:1) TO WCH
               EVALUATE TRUE
                   WHEN WCH = "/"
                       SUBTRACT 1 FROM W-R
                       MOVE 0 TO W-F
                   WHEN WCH = " "
                       CONTINUE
                   WHEN WCH >= "1" AND WCH <= "8"
                       COMPUTE W-F = W-F + FUNCTION NUMVAL(WCH)
                   WHEN OTHER
                       PERFORM VARYING W-K FROM 1 BY 1 UNTIL W-K > 12
                           IF PIECES(W-K:1) = WCH
                               IF W-K <= 6
                                   MOVE W-K TO W-T
                                   MOVE 0 TO W-COL
                               ELSE
                                   COMPUTE W-T = W-K - 6
                                   MOVE 1 TO W-COL
                               END-IF
                               COMPUTE W-SQ = 22 + W-F + 10 * W-R
                               MOVE W-T TO B-PT(W-SQ)
                               MOVE W-COL TO B-COL(W-SQ)
                               IF W-T = 6
                                   COMPUTE B-KSQ(W-COL + 1) = W-SQ
                               END-IF
                               ADD 1 TO W-F
                           END-IF
                       END-PERFORM
               END-EVALUATE
           END-PERFORM
           IF FEN-SD(1:1) = "b"
               MOVE 1 TO B-SIDE
           ELSE
               MOVE 0 TO B-SIDE
           END-IF
           MOVE 0 TO I3
           INSPECT FEN-CA TALLYING I3 FOR ALL "K"
           IF I3 > 0
               MOVE 1 TO B-CR(1)
           END-IF
           MOVE 0 TO I3
           INSPECT FEN-CA TALLYING I3 FOR ALL "Q"
           IF I3 > 0
               MOVE 1 TO B-CR(2)
           END-IF
           MOVE 0 TO I3
           INSPECT FEN-CA TALLYING I3 FOR ALL "k"
           IF I3 > 0
               MOVE 1 TO B-CR(3)
           END-IF
           MOVE 0 TO I3
           INSPECT FEN-CA TALLYING I3 FOR ALL "q"
           IF I3 > 0
               MOVE 1 TO B-CR(4)
           END-IF
           MOVE 0 TO B-EPS
           IF FEN-EP(1:1) NOT = "-" AND FEN-EP(1:1) NOT = " "
               MOVE FEN-EP(1:2) TO W-SQS
               PERFORM PARSE-SQS
               MOVE W-SQ TO B-EPS
           END-IF
           MOVE 0 TO B-MAT
           PERFORM VARYING W-SQ FROM 1 BY 1 UNTIL W-SQ > 120
               IF B-COL(W-SQ) = 0
                   ADD B-VAL(B-PT(W-SQ) + 1) TO B-MAT
               END-IF
               IF B-COL(W-SQ) = 1
                   SUBTRACT B-VAL(B-PT(W-SQ) + 1) FROM B-MAT
               END-IF
           END-PERFORM
           MOVE 0 TO B-SP.

       PARSE-SQS.
           MOVE 0 TO W-F
           MOVE 0 TO W-R
           PERFORM VARYING W-K FROM 1 BY 1 UNTIL W-K > 8
               IF FILES(W-K:1) = W-SQS(1:1)
                   COMPUTE W-F = W-K - 1
               END-IF
               IF DIGS(W-K:1) = W-SQS(2:1)
                   COMPUTE W-R = W-K - 1
               END-IF
           END-PERFORM
           COMPUTE W-SQ = 22 + W-F + 10 * W-R.

       SQ-TO-STR.
           COMPUTE W-Q = W-SQ - 22
           COMPUTE W-R = W-Q / 10
           COMPUTE W-F = W-Q - 10 * W-R
           MOVE FILES(W-F + 1:1) TO W-SQS(1:1)
           MOVE DIGS(W-R + 1:1) TO W-SQS(2:1).

       TOKENIZE.
           MOVE 0 TO NTK
           MOVE 1 TO I1
           PERFORM UNTIL I1 > 4096
               IF LN(I1:1) = SPACE OR LN(I1:1) = X"0D"
                   ADD 1 TO I1
               ELSE
                   MOVE SPACES TO CUR
                   MOVE 0 TO CURLEN
                   PERFORM UNTIL I1 > 4096 OR LN(I1:1) = SPACE OR LN(I1:1) = X"0D"
                       ADD 1 TO CURLEN
                       IF CURLEN <= 96
                           MOVE LN(I1:1) TO CUR(CURLEN:1)
                       END-IF
                       ADD 1 TO I1
                   END-PERFORM
                   IF NTK < 700
                       ADD 1 TO NTK
                       MOVE CUR TO TK(NTK)
                   END-IF
               END-IF
           END-PERFORM.

       DO-COMMAND.
           EVALUATE TK(1)
               WHEN "uci"
                   DISPLAY "id name COBOL-Chess 1.0"
                   DISPLAY "id author Claude"
                   DISPLAY "uciok"
               WHEN "isready"
                   DISPLAY "readyok"
               WHEN "ucinewgame"
                   PERFORM SET-STARTPOS
               WHEN "position"
                   PERFORM DO-POSITION
               WHEN "go"
                   PERFORM DO-GO
               WHEN "quit"
                   MOVE 1 TO QUIT
               WHEN OTHER
                   CONTINUE
           END-EVALUATE.

       DO-POSITION.
           COMPUTE MSTART = NTK + 1
           IF TK(2) = "startpos"
               PERFORM SET-STARTPOS
               PERFORM VARYING I1 FROM 3 BY 1 UNTIL I1 > NTK
                   IF TK(I1) = "moves"
                       COMPUTE MSTART = I1 + 1
                   END-IF
               END-PERFORM
           ELSE
               IF TK(2) = "fen"
                   MOVE TK(3) TO FEN-PL
                   MOVE TK(4) TO FEN-SD
                   MOVE TK(5) TO FEN-CA
                   MOVE TK(6) TO FEN-EP
                   PERFORM SET-FEN
                   PERFORM VARYING I1 FROM 7 BY 1 UNTIL I1 > NTK
                       IF TK(I1) = "moves"
                           COMPUTE MSTART = I1 + 1
                       END-IF
                   END-PERFORM
               END-IF
           END-IF
           PERFORM VARYING I1 FROM MSTART BY 1 UNTIL I1 > NTK
               MOVE TK(I1)(1:2) TO W-SQS
               PERFORM PARSE-SQS
               MOVE W-SQ TO W-FROM
               MOVE TK(I1)(3:2) TO W-SQS
               PERFORM PARSE-SQS
               MOVE W-SQ TO W-TO
               MOVE 0 TO W-PRM
               EVALUATE TK(I1)(5:1)
                   WHEN "q"
                       MOVE 5 TO W-PRM
                   WHEN "r"
                       MOVE 4 TO W-PRM
                   WHEN "b"
                       MOVE 3 TO W-PRM
                   WHEN "n"
                       MOVE 2 TO W-PRM
               END-EVALUATE
               PERFORM FIND-MAKE
           END-PERFORM.

       FIND-MAKE.
           MOVE 0 TO GB
           MOVE 0 TO GQ
           CALL "GENMV" USING GB GQ GE
           MOVE 0 TO W-FOUND
           COMPUTE I2 = 1
           PERFORM UNTIL I2 > GE OR W-FOUND = 1
               IF M-FR(I2) = W-FROM AND M-TO(I2) = W-TO AND M-PR(I2) = W-PRM
                   CALL "MKMV" USING I2
                   MOVE 1 TO W-FOUND
               END-IF
               ADD 1 TO I2
           END-PERFORM.

       DO-GO.
           MOVE 0 TO GO-DEPTH
           MOVE 0 TO GO-MT
           MOVE 0 TO GO-WT
           MOVE 0 TO GO-BT
           MOVE 0 TO GO-WI
           MOVE 0 TO GO-BI
           MOVE 0 TO GO-PFT
           MOVE 2 TO I1
           PERFORM UNTIL I1 > NTK
               EVALUATE TK(I1)
                   WHEN "depth"
                       COMPUTE GO-DEPTH = FUNCTION NUMVAL(TK(I1 + 1))
                       ADD 2 TO I1
                   WHEN "movetime"
                       COMPUTE GO-MT = FUNCTION NUMVAL(TK(I1 + 1))
                       ADD 2 TO I1
                   WHEN "wtime"
                       COMPUTE GO-WT = FUNCTION NUMVAL(TK(I1 + 1))
                       ADD 2 TO I1
                   WHEN "btime"
                       COMPUTE GO-BT = FUNCTION NUMVAL(TK(I1 + 1))
                       ADD 2 TO I1
                   WHEN "winc"
                       COMPUTE GO-WI = FUNCTION NUMVAL(TK(I1 + 1))
                       ADD 2 TO I1
                   WHEN "binc"
                       COMPUTE GO-BI = FUNCTION NUMVAL(TK(I1 + 1))
                       ADD 2 TO I1
                   WHEN "perft"
                       COMPUTE GO-PFT = FUNCTION NUMVAL(TK(I1 + 1))
                       ADD 2 TO I1
                   WHEN OTHER
                       ADD 1 TO I1
               END-EVALUATE
           END-PERFORM
           IF GO-PFT > 0
               PERFORM PERFT-ROOT
           ELSE
               PERFORM COMPUTE-LIMIT
               PERFORM SEARCH-ROOT
               PERFORM SHOW-BESTMOVE
           END-IF.

       COMPUTE-LIMIT.
           IF GO-DEPTH > 0
               MOVE GO-DEPTH TO MAXD
           ELSE
               MOVE 64 TO MAXD
           END-IF
           IF GO-MT > 0
               COMPUTE LIM = GO-MT - 30
           ELSE
               IF GO-WT > 0 OR GO-BT > 0
                   IF B-SIDE = 0
                       COMPUTE LIM = GO-WT / 30 + GO-WI / 2
                       IF LIM > GO-WT - 50
                           COMPUTE LIM = GO-WT - 50
                       END-IF
                   ELSE
                       COMPUTE LIM = GO-BT / 30 + GO-BI / 2
                       IF LIM > GO-BT - 50
                           COMPUTE LIM = GO-BT - 50
                       END-IF
                   END-IF
               ELSE
                   MOVE 999999999 TO LIM
               END-IF
           END-IF
           IF LIM < 10
               MOVE 10 TO LIM
           END-IF.

       SEARCH-ROOT.
           MOVE 0 TO B-ABRT
           MOVE 0 TO B-STOPREQ
           MOVE 0 TO B-NODES
           MOVE 0 TO B-CNT
           MOVE 0 TO FB-F
           MOVE 0 TO FB-T
           MOVE 0 TO FB-P
           MOVE 0 TO FB-SC
           CALL "NOWMS" USING B-T0
           MOVE LIM TO B-TLIM
           MOVE 1 TO S-DEP
           PERFORM UNTIL S-DEP > MAXD OR B-ABRT = 1
               MOVE S-DEP TO B-ITERD
               MOVE 0 TO B-BMF
               MOVE 0 TO B-BMT
               MOVE 0 TO B-BMP
               MOVE 0 TO S-PLY
               MOVE -100000 TO S-ALPHA
               MOVE 100000 TO S-BETA
               CALL "SRCH" USING S-PLY S-DEP S-ALPHA S-BETA S-SC
               IF B-ABRT = 0
                   MOVE B-BMF TO FB-F
                   MOVE B-BMT TO FB-T
                   MOVE B-BMP TO FB-P
                   MOVE S-SC TO FB-SC
               END-IF
               ADD 1 TO S-DEP
           END-PERFORM
           MOVE 0 TO B-ABRT.

       SHOW-BESTMOVE.
           IF FB-F = 0
               DISPLAY "bestmove 0000"
           ELSE
               MOVE FB-F TO W-SQ
               PERFORM SQ-TO-STR
               MOVE W-SQS TO W-STR(1:2)
               MOVE FB-T TO W-SQ
               PERFORM SQ-TO-STR
               MOVE W-SQS TO W-STR(3:2)
               MOVE SPACES TO W-STR(5:4)
               IF FB-P > 0
                   MOVE PROMOCH(FB-P - 1:1) TO W-STR(5:1)
               END-IF
               DISPLAY "bestmove " FUNCTION TRIM(W-STR)
           END-IF.

       PERFT-ROOT.
           MOVE 0 TO TOTAL
           MOVE 0 TO GB
           MOVE 0 TO GQ
           CALL "GENMV" USING GB GQ GE
           COMPUTE I2 = 1
           PERFORM UNTIL I2 > GE
               MOVE B-SIDE TO OWN
               CALL "MKMV" USING I2
               MOVE B-KSQ(OWN + 1) TO SQ
               CALL "ATTK" USING SQ B-SIDE RES
               IF RES = 0
                   COMPUTE S-DEP = GO-PFT - 1
                   CALL "PERFT" USING S-DEP S-PLY1 SUB
                   MOVE M-FR(I2) TO W-SQ
                   PERFORM SQ-TO-STR
                   MOVE W-SQS TO W-STR(1:2)
                   MOVE M-TO(I2) TO W-SQ
                   PERFORM SQ-TO-STR
                   MOVE W-SQS TO W-STR(3:2)
                   MOVE SPACES TO W-STR(5:4)
                   IF M-PR(I2) > 0
                       MOVE PROMOCH(M-PR(I2) - 1:1) TO W-STR(5:1)
                   END-IF
                   MOVE SUB TO ED
                   DISPLAY FUNCTION TRIM(W-STR) ": " FUNCTION TRIM(ED)
                   ADD SUB TO TOTAL
               END-IF
               CALL "UNMV" USING I2
               ADD 1 TO I2
           END-PERFORM
           MOVE TOTAL TO ED
           DISPLAY "Nodes searched: " FUNCTION TRIM(ED).
       END PROGRAM ENGINE.
