       IDENTIFICATION DIVISION.
       PROGRAM-ID. NOWMS.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 W-CD      PIC X(21).
       01 W-HH      PIC 99.
       01 W-MI      PIC 99.
       01 W-SS      PIC 99.
       01 W-CC      PIC 99.
       LINKAGE SECTION.
       01 LK-MS     PIC S9(9) COMP-5.
       PROCEDURE DIVISION USING LK-MS.
       NM-MAIN.
           MOVE FUNCTION CURRENT-DATE TO W-CD
           MOVE W-CD(9:2) TO W-HH
           MOVE W-CD(11:2) TO W-MI
           MOVE W-CD(13:2) TO W-SS
           MOVE W-CD(15:2) TO W-CC
           COMPUTE LK-MS = ((W-HH * 60 + W-MI) * 60 + W-SS) * 1000 + W-CC * 10
           GOBACK.
       END PROGRAM NOWMS.

       IDENTIFICATION DIVISION.
       PROGRAM-ID. ATTK.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "chs.cpy".
       01 A-K       PIC S9(4) COMP-5.
       01 A-T       PIC S9(4) COMP-5.
       01 A-D       PIC S9(4) COMP-5.
       LINKAGE SECTION.
       01 LK-SQ     PIC S9(4) COMP-5.
       01 LK-BY     PIC S9(4) COMP-5.
       01 LK-RES    PIC S9(4) COMP-5.
       PROCEDURE DIVISION USING LK-SQ LK-BY LK-RES.
       AT-MAIN.
           MOVE 0 TO LK-RES
           IF LK-BY = 0
               COMPUTE A-T = LK-SQ - 9
               IF B-PT(A-T) = 1 AND B-COL(A-T) = 0
                   MOVE 1 TO LK-RES
               END-IF
               COMPUTE A-T = LK-SQ - 11
               IF B-PT(A-T) = 1 AND B-COL(A-T) = 0
                   MOVE 1 TO LK-RES
               END-IF
           ELSE
               COMPUTE A-T = LK-SQ + 9
               IF B-PT(A-T) = 1 AND B-COL(A-T) = 1
                   MOVE 1 TO LK-RES
               END-IF
               COMPUTE A-T = LK-SQ + 11
               IF B-PT(A-T) = 1 AND B-COL(A-T) = 1
                   MOVE 1 TO LK-RES
               END-IF
           END-IF
           PERFORM VARYING A-K FROM 1 BY 1 UNTIL A-K > 8
               COMPUTE A-T = LK-SQ + B-NOFF(A-K)
               IF B-PT(A-T) = 2 AND B-COL(A-T) = LK-BY
                   MOVE 1 TO LK-RES
               END-IF
               COMPUTE A-T = LK-SQ + B-KOFF(A-K)
               IF B-PT(A-T) = 6 AND B-COL(A-T) = LK-BY
                   MOVE 1 TO LK-RES
               END-IF
           END-PERFORM
           PERFORM VARYING A-K FROM 1 BY 1 UNTIL A-K > 4
               MOVE B-KOFF(A-K) TO A-D
               COMPUTE A-T = LK-SQ + A-D
               PERFORM UNTIL B-PT(A-T) NOT = 0
                   COMPUTE A-T = A-T + A-D
               END-PERFORM
               IF B-COL(A-T) = LK-BY AND (B-PT(A-T) = 3 OR B-PT(A-T) = 5)
                   MOVE 1 TO LK-RES
               END-IF
           END-PERFORM
           PERFORM VARYING A-K FROM 5 BY 1 UNTIL A-K > 8
               MOVE B-KOFF(A-K) TO A-D
               COMPUTE A-T = LK-SQ + A-D
               PERFORM UNTIL B-PT(A-T) NOT = 0
                   COMPUTE A-T = A-T + A-D
               END-PERFORM
               IF B-COL(A-T) = LK-BY AND (B-PT(A-T) = 4 OR B-PT(A-T) = 5)
                   MOVE 1 TO LK-RES
               END-IF
           END-PERFORM
           GOBACK.
       END PROGRAM ATTK.

       IDENTIFICATION DIVISION.
       PROGRAM-ID. GENMV.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "chs.cpy".
       01 G-N       PIC S9(9) COMP-5.
       01 G-Q       PIC S9(4) COMP-5.
       01 G-R       PIC S9(4) COMP-5.
       01 G-F       PIC S9(4) COMP-5.
       01 G-S       PIC S9(4) COMP-5.
       01 G-T       PIC S9(4) COMP-5.
       01 G-T2      PIC S9(4) COMP-5.
       01 G-D       PIC S9(4) COMP-5.
       01 G-K       PIC S9(4) COMP-5.
       01 G-K1      PIC S9(4) COMP-5.
       01 G-K2      PIC S9(4) COMP-5.
       01 G-OPP     PIC S9(4) COMP-5.
       01 G-DIR     PIC S9(4) COMP-5.
       01 G-AF      PIC S9(4) COMP-5.
       01 G-AT      PIC S9(4) COMP-5.
       01 G-AP      PIC S9(4) COMP-5.
       01 G-A1      PIC S9(4) COMP-5.
       01 G-AR      PIC S9(4) COMP-5.
       LINKAGE SECTION.
       01 LK-BASE   PIC S9(9) COMP-5.
       01 LK-QONLY  PIC S9(4) COMP-5.
       01 LK-END    PIC S9(9) COMP-5.
       PROCEDURE DIVISION USING LK-BASE LK-QONLY LK-END.
       GM-MAIN.
           MOVE LK-BASE TO G-N
           MOVE LK-QONLY TO G-Q
           COMPUTE G-OPP = 1 - B-SIDE
           IF B-SIDE = 0
               MOVE 10 TO G-DIR
           ELSE
               MOVE -10 TO G-DIR
           END-IF
           PERFORM VARYING G-R FROM 0 BY 1 UNTIL G-R > 7
               PERFORM VARYING G-F FROM 0 BY 1 UNTIL G-F > 7
                   COMPUTE G-S = 22 + G-F + 10 * G-R
                   IF B-COL(G-S) = B-SIDE
                       PERFORM GEN-PIECE
                   END-IF
               END-PERFORM
           END-PERFORM
           MOVE G-N TO LK-END
           GOBACK.

       GEN-PIECE.
           EVALUATE B-PT(G-S)
               WHEN 1
                   PERFORM GEN-PAWN
               WHEN 2
                   PERFORM GEN-STEP
               WHEN 3
                   MOVE 1 TO G-K1
                   MOVE 4 TO G-K2
                   PERFORM GEN-SLIDE
               WHEN 4
                   MOVE 5 TO G-K1
                   MOVE 8 TO G-K2
                   PERFORM GEN-SLIDE
               WHEN 5
                   MOVE 1 TO G-K1
                   MOVE 8 TO G-K2
                   PERFORM GEN-SLIDE
               WHEN 6
                   PERFORM GEN-KING
           END-EVALUATE.

       GEN-STEP.
           PERFORM VARYING G-K FROM 1 BY 1 UNTIL G-K > 8
               COMPUTE G-T = G-S + B-NOFF(G-K)
               PERFORM TRY-STEP
           END-PERFORM.

       TRY-STEP.
           IF B-PT(G-T) = 0
               IF G-Q = 0
                   MOVE G-S TO G-AF
                   MOVE G-T TO G-AT
                   MOVE 0 TO G-AP
                   PERFORM ADD-MOVE
               END-IF
           ELSE
               IF B-COL(G-T) = G-OPP
                   MOVE G-S TO G-AF
                   MOVE G-T TO G-AT
                   MOVE 0 TO G-AP
                   PERFORM ADD-MOVE
               END-IF
           END-IF.

       GEN-SLIDE.
           PERFORM VARYING G-K FROM G-K1 BY 1 UNTIL G-K > G-K2
               MOVE B-KOFF(G-K) TO G-D
               COMPUTE G-T = G-S + G-D
               PERFORM UNTIL B-PT(G-T) NOT = 0
                   IF G-Q = 0
                       MOVE G-S TO G-AF
                       MOVE G-T TO G-AT
                       MOVE 0 TO G-AP
                       PERFORM ADD-MOVE
                   END-IF
                   COMPUTE G-T = G-T + G-D
               END-PERFORM
               IF B-COL(G-T) = G-OPP
                   MOVE G-S TO G-AF
                   MOVE G-T TO G-AT
                   MOVE 0 TO G-AP
                   PERFORM ADD-MOVE
               END-IF
           END-PERFORM.

       GEN-KING.
           PERFORM VARYING G-K FROM 1 BY 1 UNTIL G-K > 8
               COMPUTE G-T = G-S + B-KOFF(G-K)
               PERFORM TRY-STEP
           END-PERFORM
           IF G-Q = 0
               PERFORM GEN-CASTLE
           END-IF.

       GEN-CASTLE.
           IF B-SIDE = 0
               IF G-S = 26
                   IF B-CR(1) = 1 AND B-PT(27) = 0 AND B-PT(28) = 0
                      AND B-PT(29) = 4 AND B-COL(29) = 0
                       MOVE 26 TO G-A1
                       PERFORM CHK-ATT
                       IF G-AR = 0
                           MOVE 27 TO G-A1
                           PERFORM CHK-ATT
                       END-IF
                       IF G-AR = 0
                           MOVE 28 TO G-A1
                           PERFORM CHK-ATT
                       END-IF
                       IF G-AR = 0
                           MOVE 26 TO G-AF
                           MOVE 28 TO G-AT
                           MOVE 0 TO G-AP
                           PERFORM ADD-MOVE
                       END-IF
                   END-IF
                   IF B-CR(2) = 1 AND B-PT(25) = 0 AND B-PT(24) = 0
                      AND B-PT(23) = 0 AND B-PT(22) = 4 AND B-COL(22) = 0
                       MOVE 26 TO G-A1
                       PERFORM CHK-ATT
                       IF G-AR = 0
                           MOVE 25 TO G-A1
                           PERFORM CHK-ATT
                       END-IF
                       IF G-AR = 0
                           MOVE 24 TO G-A1
                           PERFORM CHK-ATT
                       END-IF
                       IF G-AR = 0
                           MOVE 26 TO G-AF
                           MOVE 24 TO G-AT
                           MOVE 0 TO G-AP
                           PERFORM ADD-MOVE
                       END-IF
                   END-IF
               END-IF
           ELSE
               IF G-S = 96
                   IF B-CR(3) = 1 AND B-PT(97) = 0 AND B-PT(98) = 0
                      AND B-PT(99) = 4 AND B-COL(99) = 1
                       MOVE 96 TO G-A1
                       PERFORM CHK-ATT
                       IF G-AR = 0
                           MOVE 97 TO G-A1
                           PERFORM CHK-ATT
                       END-IF
                       IF G-AR = 0
                           MOVE 98 TO G-A1
                           PERFORM CHK-ATT
                       END-IF
                       IF G-AR = 0
                           MOVE 96 TO G-AF
                           MOVE 98 TO G-AT
                           MOVE 0 TO G-AP
                           PERFORM ADD-MOVE
                       END-IF
                   END-IF
                   IF B-CR(4) = 1 AND B-PT(95) = 0 AND B-PT(94) = 0
                      AND B-PT(93) = 0 AND B-PT(92) = 4 AND B-COL(92) = 1
                       MOVE 96 TO G-A1
                       PERFORM CHK-ATT
                       IF G-AR = 0
                           MOVE 95 TO G-A1
                           PERFORM CHK-ATT
                       END-IF
                       IF G-AR = 0
                           MOVE 94 TO G-A1
                           PERFORM CHK-ATT
                       END-IF
                       IF G-AR = 0
                           MOVE 96 TO G-AF
                           MOVE 94 TO G-AT
                           MOVE 0 TO G-AP
                           PERFORM ADD-MOVE
                       END-IF
                   END-IF
               END-IF
           END-IF.

       CHK-ATT.
           CALL "ATTK" USING G-A1 G-OPP G-AR.

       GEN-PAWN.
           COMPUTE G-T = G-S + G-DIR
           IF B-PT(G-T) = 0
               IF (G-DIR = 10 AND G-T >= 92) OR (G-DIR = -10 AND G-T <= 29)
                   MOVE G-S TO G-AF
                   MOVE G-T TO G-AT
                   PERFORM ADD-PROMOS
               ELSE
                   IF G-Q = 0
                       MOVE G-S TO G-AF
                       MOVE G-T TO G-AT
                       MOVE 0 TO G-AP
                       PERFORM ADD-MOVE
                       IF (G-DIR = 10 AND G-S >= 32 AND G-S <= 39)
                          OR (G-DIR = -10 AND G-S >= 82 AND G-S <= 89)
                           COMPUTE G-T2 = G-T + G-DIR
                           IF B-PT(G-T2) = 0
                               MOVE G-T2 TO G-AT
                               MOVE 0 TO G-AP
                               PERFORM ADD-MOVE
                           END-IF
                       END-IF
                   END-IF
               END-IF
           END-IF
           PERFORM VARYING G-K FROM 1 BY 1 UNTIL G-K > 2
               IF G-K = 1
                   COMPUTE G-T = G-S + G-DIR - 1
               ELSE
                   COMPUTE G-T = G-S + G-DIR + 1
               END-IF
               IF B-COL(G-T) = G-OPP
                   MOVE G-S TO G-AF
                   MOVE G-T TO G-AT
                   IF (G-DIR = 10 AND G-T >= 92) OR (G-DIR = -10 AND G-T <= 29)
                       PERFORM ADD-PROMOS
                   ELSE
                       MOVE 0 TO G-AP
                       PERFORM ADD-MOVE
                   END-IF
               ELSE
                   IF B-EPS > 0 AND G-T = B-EPS AND B-PT(G-T) = 0
                       MOVE G-S TO G-AF
                       MOVE G-T TO G-AT
                       MOVE 0 TO G-AP
                       PERFORM ADD-MOVE
                   END-IF
               END-IF
           END-PERFORM.

       ADD-PROMOS.
           MOVE 5 TO G-AP
           PERFORM ADD-MOVE
           MOVE 4 TO G-AP
           PERFORM ADD-MOVE
           MOVE 3 TO G-AP
           PERFORM ADD-MOVE
           MOVE 2 TO G-AP
           PERFORM ADD-MOVE.

       ADD-MOVE.
           ADD 1 TO G-N
           MOVE G-AF TO M-FR(G-N)
           MOVE G-AT TO M-TO(G-N)
           MOVE G-AP TO M-PR(G-N)
           MOVE 0 TO M-SC(G-N).
       END PROGRAM GENMV.

       IDENTIFICATION DIVISION.
       PROGRAM-ID. MKMV.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "chs.cpy".
       01 K-F       PIC S9(4) COMP-5.
       01 K-T       PIC S9(4) COMP-5.
       01 K-P       PIC S9(4) COMP-5.
       01 K-M       PIC S9(4) COMP-5.
       01 K-C       PIC S9(4) COMP-5.
       01 K-I       PIC S9(4) COMP-5.
       01 K-X       PIC S9(4) COMP-5.
       LINKAGE SECTION.
       01 LK-MI     PIC S9(9) COMP-5.
       PROCEDURE DIVISION USING LK-MI.
       MK-MAIN.
           MOVE M-FR(LK-MI) TO K-F
           MOVE M-TO(LK-MI) TO K-T
           MOVE M-PR(LK-MI) TO K-P
           MOVE B-PT(K-F) TO K-M
           ADD 1 TO B-SP
           MOVE K-F TO B-UFR(B-SP)
           MOVE K-T TO B-UTO(B-SP)
           MOVE K-M TO B-UPT(B-SP)
           MOVE B-EPS TO B-UEP(B-SP)
           PERFORM VARYING K-I FROM 1 BY 1 UNTIL K-I > 4
               MOVE B-CR(K-I) TO B-UCR((B-SP - 1) * 4 + K-I)
           END-PERFORM
           MOVE K-T TO K-C
           COMPUTE K-X = K-T - K-F
           IF K-M = 1 AND B-EPS = K-T AND B-PT(K-T) = 0
               AND (K-X = 9 OR K-X = 11 OR K-X = -9 OR K-X = -11)
               IF B-SIDE = 0
                   COMPUTE K-C = K-T - 10
               ELSE
                   COMPUTE K-C = K-T + 10
               END-IF
           END-IF
           MOVE K-C TO B-UCS(B-SP)
           MOVE B-PT(K-C) TO B-UCT(B-SP)
           MOVE B-COL(K-C) TO B-UCC(B-SP)
           IF B-UCT(B-SP) > 0
               IF B-COL(K-C) = 0
                   SUBTRACT B-VAL(B-PT(K-C) + 1) FROM B-MAT
               ELSE
                   ADD B-VAL(B-PT(K-C) + 1) TO B-MAT
               END-IF
               MOVE 0 TO B-PT(K-C)
               MOVE 2 TO B-COL(K-C)
           END-IF
           IF K-P > 0
               MOVE K-P TO B-PT(K-T)
               IF B-SIDE = 0
                   ADD B-VAL(K-P + 1) TO B-MAT
                   SUBTRACT B-VAL(2) FROM B-MAT
               ELSE
                   SUBTRACT B-VAL(K-P + 1) FROM B-MAT
                   ADD B-VAL(2) TO B-MAT
               END-IF
           ELSE
               MOVE K-M TO B-PT(K-T)
           END-IF
           MOVE B-SIDE TO B-COL(K-T)
           MOVE 0 TO B-PT(K-F)
           MOVE 2 TO B-COL(K-F)
           IF K-M = 6
               IF K-X = 2 OR K-X = -2
                   IF K-X > 0
                       MOVE 4 TO B-PT(K-F + 1)
                       MOVE B-SIDE TO B-COL(K-F + 1)
                       MOVE 0 TO B-PT(K-F + 3)
                       MOVE 2 TO B-COL(K-F + 3)
                   ELSE
                       MOVE 4 TO B-PT(K-F - 1)
                       MOVE B-SIDE TO B-COL(K-F - 1)
                       MOVE 0 TO B-PT(K-F - 4)
                       MOVE 2 TO B-COL(K-F - 4)
                   END-IF
               END-IF
               MOVE K-T TO B-KSQ(B-SIDE + 1)
           END-IF
           IF K-F = 26 OR K-T = 26
               MOVE 0 TO B-CR(1)
               MOVE 0 TO B-CR(2)
           END-IF
           IF K-F = 29 OR K-T = 29
               MOVE 0 TO B-CR(1)
           END-IF
           IF K-F = 22 OR K-T = 22
               MOVE 0 TO B-CR(2)
           END-IF
           IF K-F = 96 OR K-T = 96
               MOVE 0 TO B-CR(3)
               MOVE 0 TO B-CR(4)
           END-IF
           IF K-F = 99 OR K-T = 99
               MOVE 0 TO B-CR(3)
           END-IF
           IF K-F = 92 OR K-T = 92
               MOVE 0 TO B-CR(4)
           END-IF
           IF K-M = 1 AND (K-X = 20 OR K-X = -20)
               COMPUTE B-EPS = (K-F + K-T) / 2
           ELSE
               MOVE 0 TO B-EPS
           END-IF
           IF B-SIDE = 0
               MOVE 1 TO B-SIDE
           ELSE
               MOVE 0 TO B-SIDE
           END-IF
           GOBACK.
       END PROGRAM MKMV.

       IDENTIFICATION DIVISION.
       PROGRAM-ID. UNMV.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "chs.cpy".
       01 U-F       PIC S9(4) COMP-5.
       01 U-T       PIC S9(4) COMP-5.
       01 U-P       PIC S9(4) COMP-5.
       01 U-M       PIC S9(4) COMP-5.
       01 U-C       PIC S9(4) COMP-5.
       01 U-I       PIC S9(4) COMP-5.
       01 U-X       PIC S9(4) COMP-5.
       LINKAGE SECTION.
       01 LK-MI     PIC S9(9) COMP-5.
       PROCEDURE DIVISION USING LK-MI.
       UM-MAIN.
           IF B-SIDE = 0
               MOVE 1 TO B-SIDE
           ELSE
               MOVE 0 TO B-SIDE
           END-IF
           MOVE M-FR(LK-MI) TO U-F
           MOVE M-TO(LK-MI) TO U-T
           MOVE M-PR(LK-MI) TO U-P
           MOVE B-UPT(B-SP) TO U-M
           COMPUTE U-X = U-T - U-F
           IF U-M = 6 AND (U-X = 2 OR U-X = -2)
               IF U-X > 0
                   MOVE 4 TO B-PT(U-F + 3)
                   MOVE B-SIDE TO B-COL(U-F + 3)
                   MOVE 0 TO B-PT(U-F + 1)
                   MOVE 2 TO B-COL(U-F + 1)
               ELSE
                   MOVE 4 TO B-PT(U-F - 4)
                   MOVE B-SIDE TO B-COL(U-F - 4)
                   MOVE 0 TO B-PT(U-F - 1)
                   MOVE 2 TO B-COL(U-F - 1)
               END-IF
           END-IF
           MOVE U-M TO B-PT(U-F)
           MOVE B-SIDE TO B-COL(U-F)
           MOVE 0 TO B-PT(U-T)
           MOVE 2 TO B-COL(U-T)
           IF U-P > 0
               IF B-SIDE = 0
                   SUBTRACT B-VAL(U-P + 1) FROM B-MAT
                   ADD B-VAL(2) TO B-MAT
               ELSE
                   ADD B-VAL(U-P + 1) TO B-MAT
                   SUBTRACT B-VAL(2) FROM B-MAT
               END-IF
           END-IF
           IF B-UCT(B-SP) > 0
               MOVE B-UCS(B-SP) TO U-C
               MOVE B-UCT(B-SP) TO B-PT(U-C)
               MOVE B-UCC(B-SP) TO B-COL(U-C)
               IF B-UCC(B-SP) = 0
                   ADD B-VAL(B-UCT(B-SP) + 1) TO B-MAT
               ELSE
                   SUBTRACT B-VAL(B-UCT(B-SP) + 1) FROM B-MAT
               END-IF
           END-IF
           IF U-M = 6
               MOVE U-F TO B-KSQ(B-SIDE + 1)
           END-IF
           PERFORM VARYING U-I FROM 1 BY 1 UNTIL U-I > 4
               MOVE B-UCR((B-SP - 1) * 4 + U-I) TO B-CR(U-I)
           END-PERFORM
           MOVE B-UEP(B-SP) TO B-EPS
           SUBTRACT 1 FROM B-SP
           GOBACK.
       END PROGRAM UNMV.
