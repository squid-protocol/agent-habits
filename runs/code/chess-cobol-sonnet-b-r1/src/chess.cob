IDENTIFICATION DIVISION.
PROGRAM-ID. CBLCHESS.
ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT INF ASSIGN TO KEYBOARD ORGANIZATION LINE SEQUENTIAL.
DATA DIVISION.
FILE SECTION.
FD INF.
01 IN-REC PIC X(8000).
WORKING-STORAGE SECTION.
*> ---------------- board and game state ----------------
01 BDA.
   05 BD OCCURS 120 PIC S9(4) COMP-5.
01 STM       PIC S9(9) COMP-5 VALUE 1.
01 SIDX      PIC S9(9) COMP-5 VALUE 1.
01 SIDE10    PIC S9(9) COMP-5 VALUE 10.
01 EPSQ      PIC S9(9) COMP-5 VALUE 0.
01 HALF      PIC S9(9) COMP-5 VALUE 0.
01 HKEY      PIC S9(18) COMP-5 VALUE 0.
01 HC        PIC S9(9) COMP-5 VALUE 1.
01 KSA.
   05 KS OCCURS 2 PIC S9(9) COMP-5.
01 NPMA.
   05 NPM OCCURS 2 PIC S9(9) COMP-5.
01 CRA.
   05 CR OCCURS 4 PIC S9(9) COMP-5.
*> ---------------- undo stack ----------------
01 UNDOA.
   05 UF   OCCURS 4096 PIC S9(9) COMP-5.
   05 UT   OCCURS 4096 PIC S9(9) COMP-5.
   05 UPC  OCCURS 4096 PIC S9(9) COMP-5.
   05 UCAP OCCURS 4096 PIC S9(9) COMP-5.
   05 UPR   OCCURS 4096 PIC S9(9) COMP-5.
   05 UEP  OCCURS 4096 PIC S9(9) COMP-5.
   05 UH   OCCURS 4096 PIC S9(9) COMP-5.
   05 UKEY OCCURS 4096 PIC S9(18) COMP-5.
   05 UCR  OCCURS 4096.
      10 UCRK OCCURS 4 PIC S9(9) COMP-5.
*> ---------------- move lists ----------------
01 MOVEA.
   05 MF  OCCURS 26000 PIC S9(9) COMP-5.
   05 MT  OCCURS 26000 PIC S9(9) COMP-5.
   05 MP  OCCURS 26000 PIC S9(9) COMP-5.
   05 MSC OCCURS 26000 PIC S9(9) COMP-5.
*> ---------------- node arrays (indexed by ply) ----------------
01 NODEA.
   05 AL  OCCURS 100 PIC S9(9) COMP-5.
   05 BE  OCCURS 100 PIC S9(9) COMP-5.
   05 DP  OCCURS 100 PIC S9(9) COMP-5.
   05 MI  OCCURS 100 PIC S9(9) COMP-5.
   05 MN  OCCURS 100 PIC S9(9) COMP-5.
   05 BV  OCCURS 100 PIC S9(9) COMP-5.
   05 LG  OCCURS 100 PIC S9(9) COMP-5.
   05 IC  OCCURS 100 PIC S9(9) COMP-5.
   05 OA  OCCURS 100 PIC S9(9) COMP-5.
   05 BMF OCCURS 100 PIC S9(9) COMP-5.
   05 BMT OCCURS 100 PIC S9(9) COMP-5.
   05 BMP OCCURS 100 PIC S9(9) COMP-5.
   05 HF  OCCURS 100 PIC S9(9) COMP-5.
   05 HT  OCCURS 100 PIC S9(9) COMP-5.
   05 HP  OCCURS 100 PIC S9(9) COMP-5.
   05 BS  OCCURS 100 PIC S9(9) COMP-5.
   05 CFL OCCURS 100 PIC S9(9) COMP-5.
   05 QU  OCCURS 100 PIC S9(9) COMP-5.
   05 NN  OCCURS 100 PIC S9(9) COMP-5.
   05 K1F OCCURS 100 PIC S9(9) COMP-5.
   05 K1T OCCURS 100 PIC S9(9) COMP-5.
   05 K2F OCCURS 100 PIC S9(9) COMP-5.
   05 K2T OCCURS 100 PIC S9(9) COMP-5.
   05 PTOT OCCURS 100 PIC S9(18) COMP-5.
*> ---------------- constant tables ----------------
01 TABA.
   05 DIRV   OCCURS 16 PIC S9(9) COMP-5.
   05 DSTART OCCURS 6 PIC S9(9) COMP-5.
   05 DEND   OCCURS 6 PIC S9(9) COMP-5.
   05 SLID   OCCURS 6 PIC S9(9) COMP-5.
   05 CENT   OCCURS 120 PIC S9(9) COMP-5.
   05 FL     OCCURS 120 PIC S9(9) COMP-5.
   05 RK     OCCURS 120 PIC S9(9) COMP-5.
   05 MIR    OCCURS 120 PIC S9(9) COMP-5.
   05 PSTR   OCCURS 7.
      10 PST OCCURS 120 PIC S9(9) COMP-5.
   05 BVAL   OCCURS 6 PIC S9(9) COMP-5.
   05 MVVR   OCCURS 7.
      10 MVVC OCCURS 7 PIC S9(9) COMP-5.
   05 PBR    OCCURS 8 PIC S9(9) COMP-5.
01 ZTA.
   05 ZT OCCURS 1700 PIC S9(18) COMP-5.
01 HSA.
   05 HSS OCCURS 2.
      10 HSF OCCURS 120.
         15 HST OCCURS 120 PIC S9(9) COMP-5.
*> ---------------- transposition table ----------------
01 TTSIZE PIC S9(9) COMP-5 VALUE 262144.
01 TTA.
   05 TTE OCCURS 262144.
      10 TKEY PIC S9(18) COMP-5.
      10 TV   PIC S9(9) COMP-5.
      10 TD   PIC S9(9) COMP-5.
      10 TFL  PIC S9(9) COMP-5.
      10 TMF  PIC S9(9) COMP-5.
      10 TMT  PIC S9(9) COMP-5.
      10 TMP  PIC S9(9) COMP-5.
*> ---------------- scratch variables ----------------
01 MKF PIC S9(9) COMP-5.
01 MKT PIC S9(9) COMP-5.
01 MKP PIC S9(9) COMP-5.
01 MPC PIC S9(9) COMP-5.
01 MCAP PIC S9(9) COMP-5.
01 MA PIC S9(9) COMP-5.
01 MCA PIC S9(9) COMP-5.
01 NEWPC PIC S9(9) COMP-5.
01 ZI PIC S9(9) COMP-5.
01 SZ PIC S9(18) COMP-5 VALUE 123456789.
01 EPS2 PIC S9(9) COMP-5.
01 ILL PIC S9(9) COMP-5.
01 ATK-SQ PIC S9(9) COMP-5.
01 ATK-BY PIC S9(9) COMP-5.
01 ATK-RES PIC S9(9) COMP-5.
01 AB10 PIC S9(9) COMP-5.
01 ATS PIC S9(9) COMP-5.
01 AD PIC S9(9) COMP-5.
01 A2 PIC S9(9) COMP-5.
01 A3 PIC S9(9) COMP-5.
01 A4 PIC S9(9) COMP-5.
01 A5 PIC S9(9) COMP-5.
01 A6 PIC S9(9) COMP-5.
01 AV PIC S9(9) COMP-5.
01 GMODE PIC S9(9) COMP-5.
01 GN PIC S9(9) COMP-5.
01 GB PIC S9(9) COMP-5.
01 GS PIC S9(9) COMP-5.
01 GP PIC S9(9) COMP-5.
01 GQ PIC S9(9) COMP-5.
01 GA PIC S9(9) COMP-5.
01 GT PIC S9(9) COMP-5.
01 GV PIC S9(9) COMP-5.
01 GD PIC S9(9) COMP-5.
01 GSTOP PIC S9(9) COMP-5.
01 GX PIC S9(9) COMP-5.
01 GOFF PIC S9(9) COMP-5.
01 OLO PIC S9(9) COMP-5.
01 OHI PIC S9(9) COMP-5.
01 AF PIC S9(9) COMP-5.
01 ATT PIC S9(9) COMP-5.
01 APR PIC S9(9) COMP-5.
01 VA PIC S9(9) COMP-5.
01 RB PIC S9(9) COMP-5.
01 CRK PIC S9(9) COMP-5.
01 PRK PIC S9(9) COMP-5.
01 STR-ROW PIC S9(9) COMP-5.
01 ES PIC S9(9) COMP-5.
01 EPC PIC S9(9) COMP-5.
01 ET PIC S9(9) COMP-5.
01 ES2 PIC S9(9) COMP-5.
01 EV-S PIC S9(9) COMP-5.
01 EV-RES PIC S9(9) COMP-5.
01 EBW PIC S9(9) COMP-5.
01 EBB PIC S9(9) COMP-5.
01 EMW PIC S9(9) COMP-5.
01 EMB PIC S9(9) COMP-5.
01 ENDG PIC S9(9) COMP-5.
01 EDF PIC S9(9) COMP-5.
01 EDR PIC S9(9) COMP-5.
01 SP PIC S9(9) COMP-5 VALUE 1.
01 SRET PIC S9(9) COMP-5.
01 ARG-A PIC S9(9) COMP-5.
01 ARG-B PIC S9(9) COMP-5.
01 ARG-D PIC S9(9) COMP-5.
01 PRET PIC S9(18) COMP-5.
01 MX PIC S9(9) COMP-5.
01 CV PIC S9(9) COMP-5.
01 RED PIC S9(9) COMP-5.
01 TTI PIC S9(9) COMP-5.
01 TTQ PIC S9(18) COMP-5.
01 TTV2 PIC S9(9) COMP-5.
01 PBI PIC S9(9) COMP-5.
01 PBEST PIC S9(9) COMP-5.
01 PEND PIC S9(9) COMP-5.
01 PJ PIC S9(9) COMP-5.
01 PBS PIC S9(9) COMP-5.
01 PSW PIC S9(9) COMP-5.
01 REPF PIC S9(9) COMP-5.
01 REPJ PIC S9(9) COMP-5.
01 REPL PIC S9(9) COMP-5.
01 SJ PIC S9(9) COMP-5.
01 HV PIC S9(9) COMP-5.
01 MATE PIC S9(9) COMP-5 VALUE 30000.
01 MAXSP PIC S9(9) COMP-5 VALUE 60.
01 NODECNT PIC S9(18) COMP-5 VALUE 0.
01 CHKCNT PIC S9(9) COMP-5 VALUE 0.
01 STOPF PIC S9(9) COMP-5 VALUE 0.
01 QUITF PIC S9(9) COMP-5 VALUE 0.
01 STARTMS PIC S9(18) COMP-5 VALUE 0.
01 NOWMS PIC S9(18) COMP-5 VALUE 0.
01 ELAPS PIC S9(18) COMP-5 VALUE 0.
01 HARDLIM PIC S9(18) COMP-5 VALUE 0.
01 SOFTLIM PIC S9(18) COMP-5 VALUE 0.
01 MAXD PIC S9(9) COMP-5 VALUE 64.
01 IDD PIC S9(9) COMP-5.
01 INFIN PIC S9(9) COMP-5 VALUE 0.
01 TIMED PIC S9(9) COMP-5 VALUE 1.
01 RBF PIC S9(9) COMP-5.
01 RBT PIC S9(9) COMP-5.
01 RBP PIC S9(9) COMP-5.
01 RBV PIC S9(9) COMP-5.
01 TM.
   05 TMH PIC 99.
   05 TMM PIC 99.
   05 TMS PIC 99.
   05 TMC PIC 99.
01 PFD.
   05 PFD-FD  PIC S9(9) COMP-5 VALUE 0.
   05 PFD-EV  PIC S9(4) COMP-5 VALUE 1.
   05 PFD-REV PIC S9(4) COMP-5 VALUE 0.
01 NFDS PIC S9(18) COMP-5 VALUE 1.
01 PTMO PIC S9(9) COMP-5 VALUE 0.
01 PRC  PIC S9(9) COMP-5 VALUE 0.
01 NULLP PIC S9(18) COMP-5 VALUE 0.
*> ---------------- parsing / output ----------------
01 TKA.
   05 TK OCCURS 1000 PIC X(80).
01 NT PIC S9(9) COMP-5.
01 TP PIC S9(9) COMP-5.
01 LL PIC S9(9) COMP-5.
01 TI PIC S9(9) COMP-5.
01 CHR PIC X.
01 CHN PIC S9(9) COMP-5.
01 FR PIC S9(9) COMP-5.
01 FF PIC S9(9) COMP-5.
01 FS PIC S9(9) COMP-5.
01 PTYPE PIC S9(9) COMP-5.
01 FOUND PIC S9(9) COMP-5.
01 MVSTR PIC X(5).
01 MVLEN PIC S9(9) COMP-5.
01 MQ PIC S9(9) COMP-5.
01 MR PIC S9(9) COMP-5.
01 CW PIC S9(9) COMP-5.
01 CW2 PIC S9(9) COMP-5.
01 FILES PIC X(8) VALUE "abcdefgh".
01 NUMED PIC -(17)9.
01 NUMV PIC S9(18) COMP-5.
01 OUTLINE PIC X(400).
01 OP PIC S9(9) COMP-5.
01 PV1 PIC X(5).
01 WTIME PIC S9(18) COMP-5.
01 BTIME PIC S9(18) COMP-5.
01 WINC PIC S9(18) COMP-5.
01 BINC PIC S9(18) COMP-5.
01 MVTIME PIC S9(18) COMP-5.
01 MYT PIC S9(18) COMP-5.
01 MYI PIC S9(18) COMP-5.
01 PDEP PIC S9(9) COMP-5.
01 PTOTAL PIC S9(18) COMP-5.
01 LCG PIC S9(18) COMP-5.
01 II PIC S9(9) COMP-5.
01 JJ PIC S9(9) COMP-5.
01 KK PIC S9(9) COMP-5.
01 PCAP PIC S9(9) COMP-5.

PROCEDURE DIVISION.
MAIN-PARA.
    OPEN INPUT INF
    PERFORM INIT-TABLES
    PERFORM SET-START
    PERFORM UNTIL QUITF = 1
        READ INF
            AT END MOVE 1 TO QUITF
            NOT AT END PERFORM HANDLE-LINE
        END-READ
    END-PERFORM
    STOP RUN.

*> =====================================================
INIT-TABLES.
    MOVE -21 TO DIRV(1) MOVE -19 TO DIRV(2) MOVE -12 TO DIRV(3)
    MOVE -8 TO DIRV(4) MOVE 8 TO DIRV(5) MOVE 12 TO DIRV(6)
    MOVE 19 TO DIRV(7) MOVE 21 TO DIRV(8)
    MOVE -11 TO DIRV(9) MOVE -9 TO DIRV(10) MOVE 9 TO DIRV(11)
    MOVE 11 TO DIRV(12)
    MOVE -10 TO DIRV(13) MOVE -1 TO DIRV(14) MOVE 1 TO DIRV(15)
    MOVE 10 TO DIRV(16)
    MOVE 0 TO DSTART(1) MOVE 0 TO DEND(1) MOVE 0 TO SLID(1)
    MOVE 1 TO DSTART(2) MOVE 8 TO DEND(2) MOVE 0 TO SLID(2)
    MOVE 9 TO DSTART(3) MOVE 12 TO DEND(3) MOVE 1 TO SLID(3)
    MOVE 13 TO DSTART(4) MOVE 16 TO DEND(4) MOVE 1 TO SLID(4)
    MOVE 9 TO DSTART(5) MOVE 16 TO DEND(5) MOVE 1 TO SLID(5)
    MOVE 9 TO DSTART(6) MOVE 16 TO DEND(6) MOVE 0 TO SLID(6)
    MOVE 100 TO BVAL(1) MOVE 320 TO BVAL(2) MOVE 330 TO BVAL(3)
    MOVE 500 TO BVAL(4) MOVE 900 TO BVAL(5) MOVE 0 TO BVAL(6)
    MOVE 0 TO PBR(1) MOVE 0 TO PBR(2) MOVE 5 TO PBR(3)
    MOVE 12 TO PBR(4) MOVE 25 TO PBR(5) MOVE 45 TO PBR(6)
    MOVE 80 TO PBR(7) MOVE 0 TO PBR(8)
    PERFORM VARYING II FROM 1 BY 1 UNTIL II > 120
        MOVE 7 TO BD(II)
        MOVE 0 TO CENT(II) FL(II) RK(II) MIR(II)
    END-PERFORM
    PERFORM VARYING II FROM 1 BY 1 UNTIL II > 7
        PERFORM VARYING JJ FROM 1 BY 1 UNTIL JJ > 7
            COMPUTE MVVC(II JJ) = 10000 + 10 * II - JJ
        END-PERFORM
    END-PERFORM
    PERFORM VARYING FR FROM 0 BY 1 UNTIL FR > 7
        PERFORM VARYING FF FROM 0 BY 1 UNTIL FF > 7
            COMPUTE FS = 22 + FF + 10 * FR
            MOVE 0 TO BD(FS)
            MOVE FF TO FL(FS)
            MOVE FR TO RK(FS)
            COMPUTE MIR(FS) = 22 + FF + 10 * (7 - FR)
            MOVE FF TO II
            IF 7 - FF < II COMPUTE II = 7 - FF END-IF
            MOVE FR TO JJ
            IF 7 - FR < JJ COMPUTE JJ = 7 - FR END-IF
            COMPUTE CENT(FS) = II + JJ
            PERFORM INIT-PST
        END-PERFORM
    END-PERFORM
    MOVE 12345 TO LCG
    PERFORM VARYING II FROM 1 BY 1 UNTIL II > 1700
        COMPUTE LCG = LCG * 1103515245 + 12345
        DIVIDE LCG BY 2147483648 GIVING TTQ REMAINDER LCG
        COMPUTE ZT(II) = LCG / 8
        IF ZT(II) < 0 COMPUTE ZT(II) = 0 - ZT(II) END-IF
    END-PERFORM
    PERFORM CLEAR-HIST
    PERFORM CLEAR-TT
    PERFORM VARYING SP FROM 1 BY 1 UNTIL SP > 99
        MOVE 0 TO K1F(SP) K1T(SP) K2F(SP) K2T(SP) NN(SP)
    END-PERFORM
    MOVE 1 TO SP.

INIT-PST.
    *> white-oriented piece-square values for square FS (file FF, rank FR)
    COMPUTE PST(1 FS) = 100 + PBR(FR + 1)
    IF FR >= 1 AND FR <= 5
        IF FF = 3 OR FF = 4
            ADD 10 TO PST(1 FS)
        ELSE
            IF FF = 2 OR FF = 5 ADD 4 TO PST(1 FS) END-IF
        END-IF
    END-IF
    COMPUTE PST(2 FS) = 300 + 7 * CENT(FS)
    IF FR = 0 SUBTRACT 10 FROM PST(2 FS) END-IF
    COMPUTE PST(3 FS) = 330 + 4 * CENT(FS)
    COMPUTE PST(4 FS) = 500
    IF FR = 6 ADD 15 TO PST(4 FS) END-IF
    IF FF = 3 OR FF = 4 ADD 3 TO PST(4 FS) END-IF
    COMPUTE PST(5 FS) = 900 + 2 * CENT(FS)
    COMPUTE PST(6 FS) = 0 - 10 * FR
    IF FR = 0
        IF FF <= 2 OR FF >= 6 ADD 25 TO PST(6 FS) END-IF
    END-IF
    COMPUTE PST(7 FS) = 8 * CENT(FS).

CLEAR-HIST.
    PERFORM VARYING II FROM 1 BY 1 UNTIL II > 2
        PERFORM VARYING JJ FROM 1 BY 1 UNTIL JJ > 120
            PERFORM VARYING KK FROM 1 BY 1 UNTIL KK > 120
                MOVE 0 TO HST(II JJ KK)
            END-PERFORM
        END-PERFORM
    END-PERFORM.

HALVE-HIST.
    PERFORM VARYING II FROM 1 BY 1 UNTIL II > 2
        PERFORM VARYING JJ FROM 1 BY 1 UNTIL JJ > 120
            PERFORM VARYING KK FROM 1 BY 1 UNTIL KK > 120
                DIVIDE 2 INTO HST(II JJ KK)
            END-PERFORM
        END-PERFORM
    END-PERFORM.

CLEAR-TT.
    PERFORM VARYING II FROM 1 BY 1 UNTIL II > 262144
        MOVE 0 TO TKEY(II) TV(II) TD(II) TFL(II) TMF(II) TMT(II) TMP(II)
    END-PERFORM.

*> =====================================================
*> position set-up
SET-START.
    MOVE SPACES TO TK(990) TK(991) TK(992) TK(993) TK(994)
    MOVE "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR" TO TK(990)
    MOVE "w" TO TK(991)
    MOVE "KQkq" TO TK(992)
    MOVE "-" TO TK(993)
    MOVE "0" TO TK(994)
    MOVE 990 TO TI
    PERFORM LOAD-FEN.

*> FEN fields are TK(TI) .. TK(TI+4)
LOAD-FEN.
    PERFORM VARYING FR FROM 0 BY 1 UNTIL FR > 7
        PERFORM VARYING FF FROM 0 BY 1 UNTIL FF > 7
            COMPUTE FS = 22 + FF + 10 * FR
            MOVE 0 TO BD(FS)
        END-PERFORM
    END-PERFORM
    MOVE 7 TO FR
    MOVE 0 TO FF
    MOVE 0 TO NPM(1) NPM(2)
    MOVE 0 TO KS(1) KS(2)
    PERFORM VARYING JJ FROM 1 BY 1 UNTIL JJ > 80
        MOVE TK(TI)(JJ:1) TO CHR
        IF CHR = SPACE EXIT PERFORM END-IF
        EVALUATE TRUE
            WHEN CHR = "/"
                SUBTRACT 1 FROM FR
                MOVE 0 TO FF
            WHEN CHR >= "1" AND CHR <= "8"
                COMPUTE CHN = FUNCTION ORD(CHR) - 49
                ADD CHN TO FF
            WHEN OTHER
                PERFORM PIECE-FROM-CHAR
                COMPUTE FS = 22 + FF + 10 * FR
                MOVE PTYPE TO BD(FS)
                IF PTYPE = 6 MOVE FS TO KS(1) END-IF
                IF PTYPE = -6 MOVE FS TO KS(2) END-IF
                IF PTYPE > 1 AND PTYPE < 6 ADD 1 TO NPM(1) END-IF
                IF PTYPE < -1 AND PTYPE > -6 ADD 1 TO NPM(2) END-IF
                ADD 1 TO FF
        END-EVALUATE
    END-PERFORM
    COMPUTE II = TI + 1
    IF TK(II)(1:1) = "b"
        MOVE -1 TO STM
        MOVE 2 TO SIDX
        MOVE -10 TO SIDE10
    ELSE
        MOVE 1 TO STM
        MOVE 1 TO SIDX
        MOVE 10 TO SIDE10
    END-IF
    MOVE 0 TO CR(1) CR(2) CR(3) CR(4)
    COMPUTE II = TI + 2
    PERFORM VARYING JJ FROM 1 BY 1 UNTIL JJ > 4
        MOVE TK(II)(JJ:1) TO CHR
        EVALUATE CHR
            WHEN "K" MOVE 1 TO CR(1)
            WHEN "Q" MOVE 1 TO CR(2)
            WHEN "k" MOVE 1 TO CR(3)
            WHEN "q" MOVE 1 TO CR(4)
        END-EVALUATE
    END-PERFORM
    MOVE 0 TO EPSQ
    COMPUTE II = TI + 3
    IF TK(II)(1:1) >= "a" AND TK(II)(1:1) <= "h"
        COMPUTE FF = FUNCTION ORD(TK(II)(1:1)) - 98
        COMPUTE FR = FUNCTION ORD(TK(II)(2:1)) - 50
        COMPUTE EPSQ = 22 + FF + 10 * FR
    END-IF
    MOVE 0 TO HALF
    COMPUTE II = TI + 4
    IF TK(II)(1:1) >= "0" AND TK(II)(1:1) <= "9"
        COMPUTE HALF = FUNCTION NUMVAL(TK(II))
    END-IF
    MOVE 1 TO HC
    PERFORM COMPUTE-KEY.

PIECE-FROM-CHAR.
    MOVE 0 TO PTYPE
    EVALUATE CHR
        WHEN "P" MOVE 1 TO PTYPE
        WHEN "N" MOVE 2 TO PTYPE
        WHEN "B" MOVE 3 TO PTYPE
        WHEN "R" MOVE 4 TO PTYPE
        WHEN "Q" MOVE 5 TO PTYPE
        WHEN "K" MOVE 6 TO PTYPE
        WHEN "p" MOVE -1 TO PTYPE
        WHEN "n" MOVE -2 TO PTYPE
        WHEN "b" MOVE -3 TO PTYPE
        WHEN "r" MOVE -4 TO PTYPE
        WHEN "q" MOVE -5 TO PTYPE
        WHEN "k" MOVE -6 TO PTYPE
    END-EVALUATE.

COMPUTE-KEY.
    MOVE 0 TO HKEY
    PERFORM VARYING II FROM 22 BY 1 UNTIL II > 99
        IF BD(II) <> 0 AND BD(II) <> 7
            COMPUTE ZI = (BD(II) + 7) * 120 + II
            ADD ZT(ZI) TO HKEY
        END-IF
    END-PERFORM
    IF STM = -1 ADD SZ TO HKEY END-IF.

*> =====================================================
*> attack detection: is ATK-SQ attacked by side ATK-BY (+1/-1)
ATTACK.
    MOVE 0 TO ATK-RES
    IF ATK-BY = 1
        MOVE 10 TO AB10
        MOVE 2 TO A2 MOVE 3 TO A3 MOVE 4 TO A4 MOVE 5 TO A5 MOVE 6 TO A6
    ELSE
        MOVE -10 TO AB10
        MOVE -2 TO A2 MOVE -3 TO A3 MOVE -4 TO A4 MOVE -5 TO A5
        MOVE -6 TO A6
    END-IF
    COMPUTE ATS = ATK-SQ - AB10 - 1
    IF BD(ATS) = ATK-BY MOVE 1 TO ATK-RES EXIT PARAGRAPH END-IF
    COMPUTE ATS = ATK-SQ - AB10 + 1
    IF BD(ATS) = ATK-BY MOVE 1 TO ATK-RES EXIT PARAGRAPH END-IF
    PERFORM VARYING AD FROM 1 BY 1 UNTIL AD > 8
        COMPUTE ATS = ATK-SQ + DIRV(AD)
        IF BD(ATS) = A2 MOVE 1 TO ATK-RES EXIT PARAGRAPH END-IF
    END-PERFORM
    PERFORM VARYING AD FROM 9 BY 1 UNTIL AD > 16
        COMPUTE ATS = ATK-SQ + DIRV(AD)
        IF BD(ATS) = A6 MOVE 1 TO ATK-RES EXIT PARAGRAPH END-IF
    END-PERFORM
    PERFORM VARYING AD FROM 9 BY 1 UNTIL AD > 12
        MOVE ATK-SQ TO ATS
        PERFORM UNTIL 1 = 0
            ADD DIRV(AD) TO ATS
            MOVE BD(ATS) TO AV
            IF AV <> 0
                IF AV = A3 OR AV = A5
                    MOVE 1 TO ATK-RES
                    EXIT PARAGRAPH
                END-IF
                EXIT PERFORM
            END-IF
        END-PERFORM
    END-PERFORM
    PERFORM VARYING AD FROM 13 BY 1 UNTIL AD > 16
        MOVE ATK-SQ TO ATS
        PERFORM UNTIL 1 = 0
            ADD DIRV(AD) TO ATS
            MOVE BD(ATS) TO AV
            IF AV <> 0
                IF AV = A4 OR AV = A5
                    MOVE 1 TO ATK-RES
                    EXIT PARAGRAPH
                END-IF
                EXIT PERFORM
            END-IF
        END-PERFORM
    END-PERFORM.

*> after MAKE: did the side that just moved leave its king attacked?
ILLEGAL-CHK.
    COMPUTE ATK-SQ = KS(3 - SIDX)
    MOVE STM TO ATK-BY
    PERFORM ATTACK
    MOVE ATK-RES TO ILL.

*> =====================================================
*> make / unmake. input MKF MKT MKP (promotion type 0 or 2..5)
MAKE.
    MOVE BD(MKF) TO MPC
    MOVE BD(MKT) TO MCAP
    MOVE MKF TO UF(HC)
    MOVE MKT TO UT(HC)
    MOVE MPC TO UPC(HC)
    MOVE MCAP TO UCAP(HC)
    MOVE MKP TO UPR(HC)
    MOVE EPSQ TO UEP(HC)
    MOVE HALF TO UH(HC)
    MOVE HKEY TO UKEY(HC)
    MOVE CR(1) TO UCRK(HC 1)
    MOVE CR(2) TO UCRK(HC 2)
    MOVE CR(3) TO UCRK(HC 3)
    MOVE CR(4) TO UCRK(HC 4)
    ADD 1 TO HC
    IF MPC < 0 COMPUTE MA = 0 - MPC ELSE MOVE MPC TO MA END-IF
    COMPUTE ZI = (MPC + 7) * 120 + MKF
    SUBTRACT ZT(ZI) FROM HKEY
    ADD 1 TO HALF
    IF MCAP <> 0
        COMPUTE ZI = (MCAP + 7) * 120 + MKT
        SUBTRACT ZT(ZI) FROM HKEY
        MOVE 0 TO HALF
        IF MCAP < 0 COMPUTE MCA = 0 - MCAP ELSE MOVE MCAP TO MCA END-IF
        IF MCA > 1 AND MCA < 6
            COMPUTE EPS2 = 3 - SIDX
            SUBTRACT 1 FROM NPM(EPS2)
        END-IF
    END-IF
    MOVE MPC TO NEWPC
    MOVE 0 TO BD(MKF)
    IF MKP <> 0
        COMPUTE NEWPC = MKP * STM
        ADD 1 TO NPM(SIDX)
    END-IF
    MOVE NEWPC TO BD(MKT)
    COMPUTE ZI = (NEWPC + 7) * 120 + MKT
    ADD ZT(ZI) TO HKEY
    IF MA = 1
        MOVE 0 TO HALF
        IF MKT = EPSQ AND MCAP = 0
            COMPUTE EPS2 = MKT - SIDE10
            COMPUTE ZI = (BD(EPS2) + 7) * 120 + EPS2
            SUBTRACT ZT(ZI) FROM HKEY
            MOVE 0 TO BD(EPS2)
        END-IF
        MOVE 0 TO EPSQ
        COMPUTE EPS2 = MKT - MKF
        IF EPS2 = 20 OR EPS2 = -20
            COMPUTE EPSQ = (MKF + MKT) / 2
        END-IF
    ELSE
        MOVE 0 TO EPSQ
        IF MA = 6
            MOVE MKT TO KS(SIDX)
            COMPUTE EPS2 = MKT - MKF
            IF EPS2 = 2
                COMPUTE ZI = MKT + 1
                COMPUTE GX = (BD(ZI) + 7) * 120 + ZI
                SUBTRACT ZT(GX) FROM HKEY
                COMPUTE ZI = MKT - 1
                COMPUTE GX = (BD(MKT + 1) + 7) * 120 + ZI
                ADD ZT(GX) TO HKEY
                MOVE BD(MKT + 1) TO BD(MKT - 1)
                MOVE 0 TO BD(MKT + 1)
            END-IF
            IF EPS2 = -2
                COMPUTE ZI = MKT - 2
                COMPUTE GX = (BD(ZI) + 7) * 120 + ZI
                SUBTRACT ZT(GX) FROM HKEY
                COMPUTE ZI = MKT + 1
                COMPUTE GX = (BD(MKT - 2) + 7) * 120 + ZI
                ADD ZT(GX) TO HKEY
                MOVE BD(MKT - 2) TO BD(MKT + 1)
                MOVE 0 TO BD(MKT - 2)
            END-IF
        END-IF
    END-IF
    *> castling rights
    IF MKF = 26 MOVE 0 TO CR(1) CR(2) END-IF
    IF MKF = 96 MOVE 0 TO CR(3) CR(4) END-IF
    IF MKF = 29 OR MKT = 29 MOVE 0 TO CR(1) END-IF
    IF MKF = 22 OR MKT = 22 MOVE 0 TO CR(2) END-IF
    IF MKF = 99 OR MKT = 99 MOVE 0 TO CR(3) END-IF
    IF MKF = 92 OR MKT = 92 MOVE 0 TO CR(4) END-IF
    IF STM = 1 ADD SZ TO HKEY ELSE SUBTRACT SZ FROM HKEY END-IF
    COMPUTE STM = 0 - STM
    COMPUTE SIDX = 3 - SIDX
    COMPUTE SIDE10 = 0 - SIDE10.

UNMAKE.
    SUBTRACT 1 FROM HC
    COMPUTE STM = 0 - STM
    COMPUTE SIDX = 3 - SIDX
    COMPUTE SIDE10 = 0 - SIDE10
    MOVE UF(HC) TO MKF
    MOVE UT(HC) TO MKT
    MOVE UPC(HC) TO MPC
    MOVE UCAP(HC) TO MCAP
    MOVE UPR(HC) TO MKP
    MOVE MPC TO BD(MKF)
    MOVE MCAP TO BD(MKT)
    IF MPC < 0 COMPUTE MA = 0 - MPC ELSE MOVE MPC TO MA END-IF
    IF MCAP <> 0
        IF MCAP < 0 COMPUTE MCA = 0 - MCAP ELSE MOVE MCAP TO MCA END-IF
        IF MCA > 1 AND MCA < 6
            COMPUTE EPS2 = 3 - SIDX
            ADD 1 TO NPM(EPS2)
        END-IF
    END-IF
    IF MKP <> 0 SUBTRACT 1 FROM NPM(SIDX) END-IF
    IF MA = 1
        IF MKT = UEP(HC) AND MCAP = 0
            COMPUTE EPS2 = MKT - SIDE10
            COMPUTE BD(EPS2) = 0 - MPC
        END-IF
    END-IF
    IF MA = 6
        MOVE MKF TO KS(SIDX)
        COMPUTE EPS2 = MKT - MKF
        IF EPS2 = 2
            MOVE BD(MKT - 1) TO BD(MKT + 1)
            MOVE 0 TO BD(MKT - 1)
        END-IF
        IF EPS2 = -2
            MOVE BD(MKT + 1) TO BD(MKT - 2)
            MOVE 0 TO BD(MKT + 1)
        END-IF
    END-IF
    MOVE UEP(HC) TO EPSQ
    MOVE UH(HC) TO HALF
    MOVE UKEY(HC) TO HKEY
    MOVE UCRK(HC 1) TO CR(1)
    MOVE UCRK(HC 2) TO CR(2)
    MOVE UCRK(HC 3) TO CR(3)
    MOVE UCRK(HC 4) TO CR(4).

NULLMAKE.
    MOVE 0 TO UF(HC)
    MOVE EPSQ TO UEP(HC)
    MOVE HALF TO UH(HC)
    MOVE HKEY TO UKEY(HC)
    ADD 1 TO HC
    MOVE 0 TO EPSQ
    MOVE 0 TO HALF
    IF STM = 1 ADD SZ TO HKEY ELSE SUBTRACT SZ FROM HKEY END-IF
    COMPUTE STM = 0 - STM
    COMPUTE SIDX = 3 - SIDX
    COMPUTE SIDE10 = 0 - SIDE10.

NULLUNMAKE.
    SUBTRACT 1 FROM HC
    COMPUTE STM = 0 - STM
    COMPUTE SIDX = 3 - SIDX
    COMPUTE SIDE10 = 0 - SIDE10
    MOVE UEP(HC) TO EPSQ
    MOVE UH(HC) TO HALF
    MOVE UKEY(HC) TO HKEY.

*> =====================================================
*> move generation for ply SP; GMODE 0 = all, 1 = captures/promotions
GEN.
    MOVE 0 TO GN
    COMPUTE GB = SP * 256
    MOVE GB TO BS(SP)
    IF STM = 1
        MOVE -6 TO OLO MOVE -1 TO OHI
        MOVE 92 TO PRK
    ELSE
        MOVE 1 TO OLO MOVE 6 TO OHI
        MOVE 29 TO PRK
    END-IF
    PERFORM VARYING GS FROM 22 BY 1 UNTIL GS > 99
        MOVE BD(GS) TO GP
        IF GP <> 0 AND GP <> 7
            COMPUTE GQ = GP * STM
            IF GQ > 0
                MOVE GQ TO GA
                IF GA = 1
                    PERFORM GEN-PAWN
                ELSE
                    PERFORM GEN-PIECE
                END-IF
            END-IF
        END-IF
    END-PERFORM
    IF GMODE = 0
        PERFORM GEN-CASTLE
    END-IF
    MOVE GN TO MN(SP).

GEN-PIECE.
    PERFORM VARYING GD FROM DSTART(GA) BY 1 UNTIL GD > DEND(GA)
        MOVE GS TO GT
        MOVE 0 TO GSTOP
        PERFORM UNTIL GSTOP = 1
            ADD DIRV(GD) TO GT
            MOVE BD(GT) TO GV
            IF GV = 0
                IF GMODE = 0
                    MOVE GS TO AF
                    MOVE GT TO ATT
                    MOVE 0 TO APR
                    PERFORM ADDQ
                END-IF
            ELSE
                IF GV >= OLO AND GV <= OHI
                    MOVE GS TO AF
                    MOVE GT TO ATT
                    MOVE 0 TO APR
                    PERFORM ADDC
                END-IF
                MOVE 1 TO GSTOP
            END-IF
            IF SLID(GA) = 0 MOVE 1 TO GSTOP END-IF
        END-PERFORM
    END-PERFORM.

GEN-PAWN.
    MOVE GS TO AF
    COMPUTE GT = GS + SIDE10
    IF BD(GT) = 0
        MOVE GT TO ATT
        IF (STM = 1 AND GT >= 92) OR (STM = -1 AND GT <= 29)
            PERFORM ADD-PROMOS-Q
        ELSE
            IF GMODE = 0
                MOVE 0 TO APR
                PERFORM ADDQ
                IF (STM = 1 AND GS >= 32 AND GS <= 39)
                   OR (STM = -1 AND GS >= 82 AND GS <= 89)
                    COMPUTE GX = GT + SIDE10
                    IF BD(GX) = 0
                        MOVE GX TO ATT
                        MOVE 0 TO APR
                        PERFORM ADDQ
                    END-IF
                END-IF
            END-IF
        END-IF
    END-IF
    PERFORM VARYING GOFF FROM -1 BY 2 UNTIL GOFF > 1
        COMPUTE GT = GS + SIDE10 + GOFF
        MOVE BD(GT) TO GV
        IF GV >= OLO AND GV <= OHI
            MOVE GT TO ATT
            IF (STM = 1 AND GT >= 92) OR (STM = -1 AND GT <= 29)
                PERFORM ADD-PROMOS-C
            ELSE
                MOVE 0 TO APR
                PERFORM ADDC
            END-IF
        ELSE
            IF GT = EPSQ
                MOVE GT TO ATT
                MOVE 0 TO APR
                ADD 1 TO GN
                COMPUTE GX = GB + GN
                MOVE AF TO MF(GX)
                MOVE ATT TO MT(GX)
                MOVE 0 TO MP(GX)
                MOVE 10009 TO MSC(GX)
            END-IF
        END-IF
    END-PERFORM.

ADD-PROMOS-Q.
    PERFORM VARYING APR FROM 5 BY -1 UNTIL APR < 2
        ADD 1 TO GN
        COMPUTE GX = GB + GN
        MOVE AF TO MF(GX)
        MOVE ATT TO MT(GX)
        MOVE APR TO MP(GX)
        IF APR = 5 MOVE 9500 TO MSC(GX) ELSE MOVE 0 TO MSC(GX) END-IF
    END-PERFORM.

ADD-PROMOS-C.
    PERFORM VARYING APR FROM 5 BY -1 UNTIL APR < 2
        ADD 1 TO GN
        COMPUTE GX = GB + GN
        MOVE AF TO MF(GX)
        MOVE ATT TO MT(GX)
        MOVE APR TO MP(GX)
        IF GV < 0 COMPUTE VA = 0 - GV ELSE MOVE GV TO VA END-IF
        MOVE MVVC(VA 1) TO MSC(GX)
        IF APR = 5 ADD 9000 TO MSC(GX) ELSE SUBTRACT 5000 FROM MSC(GX) END-IF
    END-PERFORM.

ADDQ.
    ADD 1 TO GN
    COMPUTE GX = GB + GN
    MOVE AF TO MF(GX)
    MOVE ATT TO MT(GX)
    MOVE APR TO MP(GX)
    MOVE HST(SIDX AF ATT) TO MSC(GX).

ADDC.
    ADD 1 TO GN
    COMPUTE GX = GB + GN
    MOVE AF TO MF(GX)
    MOVE ATT TO MT(GX)
    MOVE APR TO MP(GX)
    IF GV < 0 COMPUTE VA = 0 - GV ELSE MOVE GV TO VA END-IF
    MOVE MVVC(VA GA) TO MSC(GX).

GEN-CASTLE.
    IF STM = 1
        MOVE 26 TO RB
        MOVE 1 TO CRK
    ELSE
        MOVE 96 TO RB
        MOVE 3 TO CRK
    END-IF
    IF CR(CRK) = 1
        COMPUTE GX = RB + 3
        IF BD(RB + 1) = 0 AND BD(RB + 2) = 0 AND BD(GX) = 4 * STM
            PERFORM CASTLE-ATTK-K
        END-IF
    END-IF
    COMPUTE GX = CRK + 1
    IF CR(GX) = 1
        COMPUTE GX = RB - 4
        IF BD(RB - 1) = 0 AND BD(RB - 2) = 0 AND BD(RB - 3) = 0
           AND BD(GX) = 4 * STM
            PERFORM CASTLE-ATTK-Q
        END-IF
    END-IF.

CASTLE-ATTK-K.
    COMPUTE ATK-BY = 0 - STM
    MOVE RB TO ATK-SQ
    PERFORM ATTACK
    IF ATK-RES = 0
        COMPUTE ATK-SQ = RB + 1
        PERFORM ATTACK
    END-IF
    IF ATK-RES = 0
        COMPUTE ATK-SQ = RB + 2
        PERFORM ATTACK
    END-IF
    IF ATK-RES = 0
        MOVE RB TO AF
        COMPUTE ATT = RB + 2
        ADD 1 TO GN
        COMPUTE GX = GB + GN
        MOVE AF TO MF(GX)
        MOVE ATT TO MT(GX)
        MOVE 0 TO MP(GX)
        MOVE 100 TO MSC(GX)
    END-IF.

CASTLE-ATTK-Q.
    COMPUTE ATK-BY = 0 - STM
    MOVE RB TO ATK-SQ
    PERFORM ATTACK
    IF ATK-RES = 0
        COMPUTE ATK-SQ = RB - 1
        PERFORM ATTACK
    END-IF
    IF ATK-RES = 0
        COMPUTE ATK-SQ = RB - 2
        PERFORM ATTACK
    END-IF
    IF ATK-RES = 0
        MOVE RB TO AF
        COMPUTE ATT = RB - 2
        ADD 1 TO GN
        COMPUTE GX = GB + GN
        MOVE AF TO MF(GX)
        MOVE ATT TO MT(GX)
        MOVE 0 TO MP(GX)
        MOVE 100 TO MSC(GX)
    END-IF.

*> =====================================================
*> static evaluation from the side to move's point of view
EVAL.
    MOVE 0 TO EV-S EBW EBB EMW EMB
    IF NPM(1) + NPM(2) <= 3 MOVE 1 TO ENDG ELSE MOVE 0 TO ENDG END-IF
    PERFORM VARYING ES FROM 22 BY 1 UNTIL ES > 99
        MOVE BD(ES) TO EPC
        IF EPC > 0 AND EPC < 7
            MOVE EPC TO ET
            IF ET = 3 ADD 1 TO EBW END-IF
            IF ET < 6 ADD BVAL(ET) TO EMW END-IF
            IF ET = 6 AND ENDG = 1 MOVE 7 TO ET END-IF
            ADD PST(ET ES) TO EV-S
        ELSE
            IF EPC < 0
                COMPUTE ET = 0 - EPC
                MOVE MIR(ES) TO ES2
                IF ET = 3 ADD 1 TO EBB END-IF
                IF ET < 6 ADD BVAL(ET) TO EMB END-IF
                IF ET = 6 AND ENDG = 1 MOVE 7 TO ET END-IF
                SUBTRACT PST(ET ES2) FROM EV-S
            END-IF
        END-IF
    END-PERFORM
    IF EBW >= 2 ADD 30 TO EV-S END-IF
    IF EBB >= 2 SUBTRACT 30 FROM EV-S END-IF
    IF ENDG = 1
        IF EMW - EMB >= 250
            COMPUTE EV-S = EV-S + 10 * (6 - CENT(KS(2)))
            PERFORM KDIST
            COMPUTE EV-S = EV-S + 4 * (14 - EDF - EDR)
        END-IF
        IF EMB - EMW >= 250
            COMPUTE EV-S = EV-S - 10 * (6 - CENT(KS(1)))
            PERFORM KDIST
            COMPUTE EV-S = EV-S - 4 * (14 - EDF - EDR)
        END-IF
    END-IF
    IF STM = 1
        COMPUTE EV-RES = EV-S + 10
    ELSE
        COMPUTE EV-RES = 10 - EV-S
    END-IF.

KDIST.
    COMPUTE EDF = FL(KS(1)) - FL(KS(2))
    IF EDF < 0 COMPUTE EDF = 0 - EDF END-IF
    COMPUTE EDR = RK(KS(1)) - RK(KS(2))
    IF EDR < 0 COMPUTE EDR = 0 - EDR END-IF.

FLUSH-OUT.
    CALL "fflush" USING BY VALUE NULLP.

*> =====================================================
*> time and input polling
GET-MS.
    ACCEPT TM FROM TIME
    COMPUTE NOWMS = ((TMH * 60 + TMM) * 60 + TMS) * 1000 + TMC * 10.

TICK.
    ADD 1 TO NODECNT
    ADD 1 TO CHKCNT
    IF CHKCNT >= 1024
        MOVE 0 TO CHKCNT
        PERFORM CHECK-STOP
    END-IF.

CHECK-STOP.
    IF TIMED = 1
        PERFORM GET-MS
        COMPUTE ELAPS = NOWMS - STARTMS
        IF ELAPS < 0 ADD 86400000 TO ELAPS END-IF
        IF ELAPS >= HARDLIM MOVE 1 TO STOPF END-IF
    END-IF
    MOVE 0 TO PFD-REV
    CALL "poll" USING PFD BY VALUE NFDS BY VALUE PTMO RETURNING PRC
    IF PRC > 0
        READ INF
            AT END
                MOVE 1 TO QUITF
                MOVE 1 TO STOPF
            NOT AT END
                PERFORM SEARCH-CMD
        END-READ
    END-IF.

SEARCH-CMD.
    IF IN-REC(1:4) = "stop"
        MOVE 1 TO STOPF
    END-IF
    IF IN-REC(1:4) = "quit"
        MOVE 1 TO STOPF
        MOVE 1 TO QUITF
    END-IF
    IF IN-REC(1:7) = "isready"
        DISPLAY "readyok"
        PERFORM FLUSH-OUT
    END-IF.

*> =====================================================
*> repetition check: REPF = 1 if the current position occurred before
REPCHK.
    MOVE 0 TO REPF
    COMPUTE REPL = HC - HALF
    IF REPL < 1 MOVE 1 TO REPL END-IF
    COMPUTE REPJ = HC - 2
    PERFORM UNTIL REPJ < REPL
        IF UKEY(REPJ) = HKEY
            MOVE 1 TO REPF
            EXIT PERFORM
        END-IF
        SUBTRACT 2 FROM REPJ
    END-PERFORM.

*> =====================================================
*> pick best-scored move into slot MI(SP)
PICK-MOVE.
    ADD BS(SP) MI(SP) GIVING PBI
    ADD BS(SP) MN(SP) GIVING PEND
    MOVE PBI TO PBEST
    MOVE MSC(PBI) TO PBS
    COMPUTE PJ = PBI + 1
    PERFORM UNTIL PJ > PEND
        IF MSC(PJ) > PBS
            MOVE MSC(PJ) TO PBS
            MOVE PJ TO PBEST
        END-IF
        ADD 1 TO PJ
    END-PERFORM
    IF PBEST <> PBI
        MOVE MF(PBI) TO PSW MOVE MF(PBEST) TO MF(PBI) MOVE PSW TO MF(PBEST)
        MOVE MT(PBI) TO PSW MOVE MT(PBEST) TO MT(PBI) MOVE PSW TO MT(PBEST)
        MOVE MP(PBI) TO PSW MOVE MP(PBEST) TO MP(PBI) MOVE PSW TO MP(PBEST)
        MOVE MSC(PBI) TO PSW MOVE MSC(PBEST) TO MSC(PBI)
        MOVE PSW TO MSC(PBEST)
    END-IF.

*> bump hash move and killers for ply SP
SCORE-MOVES.
    ADD BS(SP) MN(SP) GIVING PEND
    COMPUTE PJ = BS(SP) + 1
    PERFORM UNTIL PJ > PEND
        IF MF(PJ) = HF(SP) AND MT(PJ) = HT(SP) AND MP(PJ) = HP(SP)
            MOVE 2000000 TO MSC(PJ)
        ELSE
            IF MSC(PJ) < 8000
                IF MF(PJ) = K1F(SP) AND MT(PJ) = K1T(SP)
                    MOVE 9000 TO MSC(PJ)
                ELSE
                    IF MF(PJ) = K2F(SP) AND MT(PJ) = K2T(SP)
                        MOVE 8900 TO MSC(PJ)
                    END-IF
                END-IF
            END-IF
        END-IF
        ADD 1 TO PJ
    END-PERFORM.

*> =====================================================
*> quiescence search; uses AL(SP), BE(SP); result in SRET
QSEARCH.
    PERFORM EVAL
    IF SP >= MAXSP MOVE EV-RES TO SRET EXIT PARAGRAPH END-IF
    MOVE EV-RES TO BV(SP)
    IF EV-RES >= BE(SP) MOVE EV-RES TO SRET EXIT PARAGRAPH END-IF
    IF EV-RES > AL(SP) MOVE EV-RES TO AL(SP) END-IF
    MOVE 1 TO GMODE
    PERFORM GEN
    MOVE 1 TO MI(SP)
    MOVE 0 TO CFL(SP)
    PERFORM UNTIL MI(SP) > MN(SP) OR CFL(SP) = 1
        PERFORM PICK-MOVE
        ADD BS(SP) MI(SP) GIVING MX
        MOVE MF(MX) TO MKF
        MOVE MT(MX) TO MKT
        MOVE MP(MX) TO MKP
        PERFORM MAKE
        PERFORM ILLEGAL-CHK
        IF ILL = 1
            PERFORM UNMAKE
        ELSE
            PERFORM TICK
            COMPUTE ARG-A = 0 - BE(SP)
            COMPUTE ARG-B = 0 - AL(SP)
            ADD 1 TO SP
            MOVE ARG-A TO AL(SP)
            MOVE ARG-B TO BE(SP)
            PERFORM QSEARCH
            SUBTRACT 1 FROM SP
            PERFORM UNMAKE
            IF STOPF = 1
                MOVE 0 TO SRET
                EXIT PARAGRAPH
            END-IF
            COMPUTE CV = 0 - SRET
            IF CV > BV(SP)
                MOVE CV TO BV(SP)
                IF CV > AL(SP) MOVE CV TO AL(SP) END-IF
                IF CV >= BE(SP) MOVE 1 TO CFL(SP) END-IF
            END-IF
        END-IF
        ADD 1 TO MI(SP)
    END-PERFORM
    MOVE BV(SP) TO SRET.

*> =====================================================
*> main search; inputs SP, ARG-A, ARG-B, ARG-D; result in SRET
SRCH-NODE.
    PERFORM TICK
    IF STOPF = 1 MOVE 0 TO SRET EXIT PARAGRAPH END-IF
    MOVE ARG-A TO AL(SP)
    MOVE ARG-B TO BE(SP)
    MOVE ARG-D TO DP(SP)
    IF SP > 1
        IF HALF >= 100 MOVE 0 TO SRET EXIT PARAGRAPH END-IF
        PERFORM REPCHK
        IF REPF = 1 MOVE 0 TO SRET EXIT PARAGRAPH END-IF
    END-IF
    IF SP >= MAXSP
        PERFORM EVAL
        MOVE EV-RES TO SRET
        EXIT PARAGRAPH
    END-IF
    MOVE KS(SIDX) TO ATK-SQ
    COMPUTE ATK-BY = 0 - STM
    PERFORM ATTACK
    MOVE ATK-RES TO IC(SP)
    IF IC(SP) = 1 ADD 1 TO DP(SP) END-IF
    IF DP(SP) <= 0
        PERFORM QSEARCH
        EXIT PARAGRAPH
    END-IF
    *> transposition table probe
    MOVE 0 TO HF(SP) HT(SP) HP(SP)
    DIVIDE HKEY BY TTSIZE GIVING TTQ REMAINDER TTI
    ADD 1 TO TTI
    IF TKEY(TTI) = HKEY
        MOVE TMF(TTI) TO HF(SP)
        MOVE TMT(TTI) TO HT(SP)
        MOVE TMP(TTI) TO HP(SP)
        IF SP > 1 AND TD(TTI) >= DP(SP)
            MOVE TV(TTI) TO TTV2
            IF TTV2 > 29000 SUBTRACT SP FROM TTV2 END-IF
            IF TTV2 < -29000 ADD SP TO TTV2 END-IF
            IF TFL(TTI) = 0
                MOVE TTV2 TO SRET
                EXIT PARAGRAPH
            END-IF
            IF TFL(TTI) = 1 AND TTV2 >= BE(SP)
                MOVE TTV2 TO SRET
                EXIT PARAGRAPH
            END-IF
            IF TFL(TTI) = 2 AND TTV2 <= AL(SP)
                MOVE TTV2 TO SRET
                EXIT PARAGRAPH
            END-IF
        END-IF
    END-IF
    *> null move pruning
    IF SP > 1 AND IC(SP) = 0 AND DP(SP) >= 3 AND NN(SP) = 0
       AND NPM(SIDX) > 0 AND BE(SP) < 29000
        PERFORM EVAL
        IF EV-RES >= BE(SP)
            PERFORM NULLMAKE
            MOVE 2 TO RED
            IF DP(SP) >= 6 MOVE 3 TO RED END-IF
            COMPUTE ARG-A = 1 - BE(SP)
            COMPUTE ARG-B = 0 - BE(SP)
            COMPUTE ARG-D = DP(SP) - 1 - RED
            ADD 1 TO SP
            MOVE 1 TO NN(SP)
            PERFORM SRCH-NODE
            SUBTRACT 1 FROM SP
            PERFORM NULLUNMAKE
            IF STOPF = 1 MOVE 0 TO SRET EXIT PARAGRAPH END-IF
            COMPUTE CV = 0 - SRET
            IF CV >= BE(SP)
                IF CV > 29000 MOVE BE(SP) TO CV END-IF
                MOVE CV TO SRET
                EXIT PARAGRAPH
            END-IF
        END-IF
    END-IF
    MOVE 0 TO GMODE
    PERFORM GEN
    PERFORM SCORE-MOVES
    MOVE 0 TO LG(SP)
    COMPUTE BV(SP) = 0 - 31000
    MOVE AL(SP) TO OA(SP)
    MOVE 0 TO BMF(SP) BMT(SP) BMP(SP)
    MOVE 1 TO MI(SP)
    MOVE 0 TO CFL(SP)
    PERFORM UNTIL MI(SP) > MN(SP) OR CFL(SP) = 1
        PERFORM PICK-MOVE
        ADD BS(SP) MI(SP) GIVING MX
        MOVE MF(MX) TO MKF
        MOVE MT(MX) TO MKT
        MOVE MP(MX) TO MKP
        IF BD(MKT) = 0 AND MKP = 0
            MOVE 1 TO QU(SP)
        ELSE
            MOVE 0 TO QU(SP)
        END-IF
        PERFORM MAKE
        PERFORM ILLEGAL-CHK
        IF ILL = 1
            PERFORM UNMAKE
        ELSE
            ADD 1 TO LG(SP)
            MOVE 0 TO RED
            IF LG(SP) > 3 AND DP(SP) >= 3 AND IC(SP) = 0
               AND QU(SP) = 1 AND MSC(MX) < 8000
                MOVE 1 TO RED
                IF LG(SP) > 8 AND DP(SP) >= 5 MOVE 2 TO RED END-IF
            END-IF
            ADD 1 TO SP
            MOVE 0 TO NN(SP)
            IF LG(SP - 1) = 1
                COMPUTE ARG-A = 0 - BE(SP - 1)
                COMPUTE ARG-B = 0 - AL(SP - 1)
                COMPUTE ARG-D = DP(SP - 1) - 1
                PERFORM SRCH-NODE
                COMPUTE CV = 0 - SRET
            ELSE
                COMPUTE ARG-A = 0 - AL(SP - 1) - 1
                COMPUTE ARG-B = 0 - AL(SP - 1)
                COMPUTE ARG-D = DP(SP - 1) - 1 - RED
                PERFORM SRCH-NODE
                COMPUTE CV = 0 - SRET
                IF CV > AL(SP - 1) AND STOPF = 0
                    COMPUTE ARG-A = 0 - BE(SP - 1)
                    COMPUTE ARG-B = 0 - AL(SP - 1)
                    COMPUTE ARG-D = DP(SP - 1) - 1
                    PERFORM SRCH-NODE
                    COMPUTE CV = 0 - SRET
                END-IF
            END-IF
            SUBTRACT 1 FROM SP
            PERFORM UNMAKE
            IF STOPF = 1
                MOVE 0 TO SRET
                EXIT PARAGRAPH
            END-IF
            IF CV > BV(SP)
                MOVE CV TO BV(SP)
                ADD BS(SP) MI(SP) GIVING MX
                MOVE MF(MX) TO BMF(SP)
                MOVE MT(MX) TO BMT(SP)
                MOVE MP(MX) TO BMP(SP)
                IF CV > AL(SP) MOVE CV TO AL(SP) END-IF
                IF CV >= BE(SP)
                    MOVE 1 TO CFL(SP)
                    IF QU(SP) = 1
                        PERFORM UPDATE-QUIET
                    END-IF
                END-IF
            END-IF
        END-IF
        ADD 1 TO MI(SP)
    END-PERFORM
    IF LG(SP) = 0
        IF IC(SP) = 1
            COMPUTE SRET = SP - MATE
        ELSE
            MOVE 0 TO SRET
        END-IF
        EXIT PARAGRAPH
    END-IF
    *> store in the transposition table
    DIVIDE HKEY BY TTSIZE GIVING TTQ REMAINDER TTI
    ADD 1 TO TTI
    IF BV(SP) <= OA(SP)
        MOVE 2 TO TFL(TTI)
    ELSE
        IF BV(SP) >= BE(SP) MOVE 1 TO TFL(TTI) ELSE MOVE 0 TO TFL(TTI) END-IF
    END-IF
    MOVE BV(SP) TO TTV2
    IF TTV2 > 29000 ADD SP TO TTV2 END-IF
    IF TTV2 < -29000 SUBTRACT SP FROM TTV2 END-IF
    MOVE TTV2 TO TV(TTI)
    MOVE HKEY TO TKEY(TTI)
    MOVE DP(SP) TO TD(TTI)
    MOVE BMF(SP) TO TMF(TTI)
    MOVE BMT(SP) TO TMT(TTI)
    MOVE BMP(SP) TO TMP(TTI)
    MOVE BV(SP) TO SRET.

UPDATE-QUIET.
    IF NOT (BMF(SP) = K1F(SP) AND BMT(SP) = K1T(SP))
        MOVE K1F(SP) TO K2F(SP)
        MOVE K1T(SP) TO K2T(SP)
        MOVE BMF(SP) TO K1F(SP)
        MOVE BMT(SP) TO K1T(SP)
    END-IF
    COMPUTE HV = DP(SP) * DP(SP)
    ADD HV TO HST(SIDX BMF(SP) BMT(SP))
    IF HST(SIDX BMF(SP) BMT(SP)) > 7000
        PERFORM HALVE-HIST
    END-IF.

*> =====================================================
*> perft: inputs SP, ARG-D; result PRET
PERFT.
    IF ARG-D = 0
        MOVE 1 TO PRET
        EXIT PARAGRAPH
    END-IF
    MOVE ARG-D TO DP(SP)
    MOVE 0 TO GMODE
    PERFORM GEN
    MOVE 0 TO PTOT(SP)
    MOVE 1 TO MI(SP)
    PERFORM UNTIL MI(SP) > MN(SP)
        ADD BS(SP) MI(SP) GIVING MX
        MOVE MF(MX) TO MKF
        MOVE MT(MX) TO MKT
        MOVE MP(MX) TO MKP
        PERFORM MAKE
        PERFORM ILLEGAL-CHK
        IF ILL = 0
            IF DP(SP) = 1
                ADD 1 TO PTOT(SP)
            ELSE
                COMPUTE ARG-D = DP(SP) - 1
                ADD 1 TO SP
                PERFORM PERFT
                SUBTRACT 1 FROM SP
                ADD PRET TO PTOT(SP)
            END-IF
        END-IF
        PERFORM UNMAKE
        ADD 1 TO MI(SP)
    END-PERFORM
    MOVE PTOT(SP) TO PRET.

DO-PERFT.
    MOVE 1 TO SP
    MOVE 0 TO GMODE
    PERFORM GEN
    MOVE 0 TO PTOTAL
    MOVE 1 TO MI(1)
    PERFORM UNTIL MI(1) > MN(1)
        ADD BS(1) MI(1) GIVING MX
        MOVE MF(MX) TO MKF
        MOVE MT(MX) TO MKT
        MOVE MP(MX) TO MKP
        PERFORM MAKE
        PERFORM ILLEGAL-CHK
        IF ILL = 0
            IF PDEP <= 1
                MOVE 1 TO PRET
            ELSE
                COMPUTE ARG-D = PDEP - 1
                MOVE 2 TO SP
                PERFORM PERFT
                MOVE 1 TO SP
            END-IF
            ADD PRET TO PTOTAL
            ADD BS(1) MI(1) GIVING MX
            MOVE MF(MX) TO MKF
            MOVE MT(MX) TO MKT
            MOVE MP(MX) TO MKP
            PERFORM UNMAKE
            PERFORM MOVE-STR
            MOVE PRET TO NUMV
            PERFORM FMT-NUM
            DISPLAY MVSTR(1:MVLEN) ": " FUNCTION TRIM(NUMED)
        ELSE
            PERFORM UNMAKE
        END-IF
        ADD 1 TO MI(1)
    END-PERFORM
    MOVE PTOTAL TO NUMV
    PERFORM FMT-NUM
    DISPLAY "Nodes searched: " FUNCTION TRIM(NUMED).

*> =====================================================
*> output helpers
FMT-NUM.
    MOVE NUMV TO NUMED.

*> MKF MKT MKP -> MVSTR, MVLEN
MOVE-STR.
    MOVE SPACES TO MVSTR
    COMPUTE FS = MKF - 22
    DIVIDE FS BY 10 GIVING MQ REMAINDER MR
    ADD 1 TO MR
    MOVE FILES(MR:1) TO MVSTR(1:1)
    ADD 1 TO MQ
    MOVE MQ TO CW
    MOVE CW TO NUMED
    MOVE FUNCTION TRIM(NUMED) TO MVSTR(2:1)
    COMPUTE FS = MKT - 22
    DIVIDE FS BY 10 GIVING MQ REMAINDER MR
    ADD 1 TO MR
    MOVE FILES(MR:1) TO MVSTR(3:1)
    ADD 1 TO MQ
    MOVE MQ TO CW
    MOVE CW TO NUMED
    MOVE FUNCTION TRIM(NUMED) TO MVSTR(4:1)
    MOVE 4 TO MVLEN
    IF MKP <> 0
        MOVE 5 TO MVLEN
        EVALUATE MKP
            WHEN 5 MOVE "q" TO MVSTR(5:1)
            WHEN 4 MOVE "r" TO MVSTR(5:1)
            WHEN 3 MOVE "b" TO MVSTR(5:1)
            WHEN 2 MOVE "n" TO MVSTR(5:1)
        END-EVALUATE
    END-IF.

*> =====================================================
*> UCI command handling
HANDLE-LINE.
    MOVE 1 TO TP
    MOVE 0 TO NT
    COMPUTE LL = FUNCTION LENGTH(FUNCTION TRIM(IN-REC TRAILING))
    IF IN-REC = SPACES MOVE 0 TO LL END-IF
    PERFORM UNTIL TP > LL OR NT >= 980
        ADD 1 TO NT
        MOVE SPACES TO TK(NT)
        UNSTRING IN-REC DELIMITED BY ALL SPACE INTO TK(NT) WITH POINTER TP
        IF TK(NT) = SPACES SUBTRACT 1 FROM NT END-IF
    END-PERFORM
    IF NT = 0 EXIT PARAGRAPH END-IF
    MOVE SPACES TO TK(NT + 1) TK(NT + 2) TK(NT + 3) TK(NT + 4)
    EVALUATE TK(1)
        WHEN "uci"
            DISPLAY "id name CobolChess 1.0"
            DISPLAY "id author Claude"
            DISPLAY "uciok"
        WHEN "isready"
            DISPLAY "readyok"
        WHEN "ucinewgame"
            PERFORM CLEAR-TT
            PERFORM CLEAR-HIST
            PERFORM SET-START
        WHEN "position"
            PERFORM DO-POSITION
        WHEN "go"
            PERFORM DO-GO
        WHEN "quit"
            MOVE 1 TO QUITF
        WHEN "stop"
            CONTINUE
    END-EVALUATE
    PERFORM FLUSH-OUT.

DO-POSITION.
    MOVE 3 TO TI
    IF TK(2) = "startpos"
        PERFORM SET-START
        MOVE 3 TO TI
    ELSE
        IF TK(2) = "fen"
            MOVE 3 TO TI
            PERFORM LOAD-FEN
            MOVE 9 TO TI
        ELSE
            EXIT PARAGRAPH
        END-IF
    END-IF
    IF TK(TI) = "moves"
        ADD 1 TO TI
        PERFORM UNTIL TI > NT
            PERFORM APPLY-TOKEN-MOVE
            ADD 1 TO TI
        END-PERFORM
    END-IF.

*> apply move text TK(TI) if it is legal
APPLY-TOKEN-MOVE.
    COMPUTE FF = FUNCTION ORD(TK(TI)(1:1)) - 98
    COMPUTE FR = FUNCTION ORD(TK(TI)(2:1)) - 50
    COMPUTE MKF = 22 + FF + 10 * FR
    COMPUTE FF = FUNCTION ORD(TK(TI)(3:1)) - 98
    COMPUTE FR = FUNCTION ORD(TK(TI)(4:1)) - 50
    COMPUTE MKT = 22 + FF + 10 * FR
    MOVE 0 TO MKP
    MOVE TK(TI)(5:1) TO CHR
    EVALUATE CHR
        WHEN "q" MOVE 5 TO MKP
        WHEN "r" MOVE 4 TO MKP
        WHEN "b" MOVE 3 TO MKP
        WHEN "n" MOVE 2 TO MKP
    END-EVALUATE
    MOVE 1 TO SP
    MOVE 0 TO GMODE
    PERFORM GEN
    MOVE 0 TO FOUND
    MOVE MKF TO FS
    MOVE MKT TO CW
    MOVE MKP TO CW2
    PERFORM VARYING JJ FROM 1 BY 1 UNTIL JJ > MN(1) OR FOUND = 1
        COMPUTE GX = 256 + JJ
        IF MF(GX) = FS AND MT(GX) = CW AND MP(GX) = CW2
            MOVE 1 TO FOUND
        END-IF
    END-PERFORM
    MOVE 1 TO SP
    IF FOUND = 1
        MOVE FS TO MKF
        MOVE CW TO MKT
        MOVE CW2 TO MKP
        PERFORM MAKE
        PERFORM ILLEGAL-CHK
        IF ILL = 1 PERFORM UNMAKE END-IF
    END-IF.

DO-GO.
    MOVE 0 TO INFIN
    MOVE 1 TO TIMED
    MOVE 64 TO MAXD
    MOVE 0 TO WTIME BTIME WINC BINC MVTIME
    MOVE 0 TO PDEP
    PERFORM VARYING II FROM 2 BY 1 UNTIL II > NT
        EVALUATE TK(II)
            WHEN "perft"
                COMPUTE PDEP = FUNCTION NUMVAL(TK(II + 1))
            WHEN "depth"
                COMPUTE MAXD = FUNCTION NUMVAL(TK(II + 1))
                MOVE 2 TO TIMED
            WHEN "movetime"
                COMPUTE MVTIME = FUNCTION NUMVAL(TK(II + 1))
            WHEN "wtime"
                COMPUTE WTIME = FUNCTION NUMVAL(TK(II + 1))
            WHEN "btime"
                COMPUTE BTIME = FUNCTION NUMVAL(TK(II + 1))
            WHEN "winc"
                COMPUTE WINC = FUNCTION NUMVAL(TK(II + 1))
            WHEN "binc"
                COMPUTE BINC = FUNCTION NUMVAL(TK(II + 1))
            WHEN "infinite"
                MOVE 1 TO INFIN
        END-EVALUATE
    END-PERFORM
    IF TK(2) = "perft"
        PERFORM DO-PERFT
        EXIT PARAGRAPH
    END-IF
    PERFORM GET-MS
    MOVE NOWMS TO STARTMS
    *> time limits (milliseconds)
    MOVE 1000000000 TO HARDLIM SOFTLIM
    IF MVTIME > 0
        COMPUTE HARDLIM = MVTIME - 30
        IF HARDLIM < 5 MOVE 5 TO HARDLIM END-IF
        MOVE HARDLIM TO SOFTLIM
        MOVE 1 TO TIMED
    ELSE
        IF WTIME > 0 OR BTIME > 0
            IF STM = 1
                MOVE WTIME TO MYT
                MOVE WINC TO MYI
            ELSE
                MOVE BTIME TO MYT
                MOVE BINC TO MYI
            END-IF
            COMPUTE SOFTLIM = MYT / 30 + MYI * 3 / 4
            COMPUTE HARDLIM = SOFTLIM * 3
            IF HARDLIM > MYT / 2 COMPUTE HARDLIM = MYT / 2 END-IF
            IF HARDLIM < 5 MOVE 5 TO HARDLIM END-IF
            IF SOFTLIM > HARDLIM MOVE HARDLIM TO SOFTLIM END-IF
            MOVE 1 TO TIMED
        ELSE
            IF INFIN = 1
                MOVE 0 TO TIMED
            ELSE
                IF TIMED = 2
                    MOVE 0 TO TIMED
                ELSE
                    MOVE 1000 TO HARDLIM SOFTLIM
                END-IF
            END-IF
        END-IF
    END-IF
    IF MAXD > 60 MOVE 60 TO MAXD END-IF
    PERFORM ITERATE
    IF INFIN = 1 AND QUITF = 0
        PERFORM UNTIL STOPF = 1
            READ INF
                AT END MOVE 1 TO QUITF MOVE 1 TO STOPF
                NOT AT END PERFORM SEARCH-CMD
            END-READ
        END-PERFORM
    END-IF
    IF RBF = 0
        DISPLAY "bestmove 0000"
    ELSE
        MOVE RBF TO MKF
        MOVE RBT TO MKT
        MOVE RBP TO MKP
        PERFORM MOVE-STR
        DISPLAY "bestmove " MVSTR(1:MVLEN)
    END-IF.

ITERATE.
    MOVE 0 TO STOPF NODECNT CHKCNT RBF RBT RBP RBV
    MOVE 0 TO NN(1)
    PERFORM VARYING SP FROM 1 BY 1 UNTIL SP > 99
        MOVE 0 TO K1F(SP) K1T(SP) K2F(SP) K2T(SP)
    END-PERFORM
    MOVE 1 TO SP
    PERFORM VARYING IDD FROM 1 BY 1 UNTIL IDD > MAXD OR STOPF = 1
        MOVE 1 TO SP
        COMPUTE ARG-A = 0 - 31000
        MOVE 31000 TO ARG-B
        MOVE IDD TO ARG-D
        PERFORM SRCH-NODE
        MOVE 1 TO SP
        IF BMF(1) <> 0
            MOVE BMF(1) TO RBF
            MOVE BMT(1) TO RBT
            MOVE BMP(1) TO RBP
        END-IF
        IF STOPF = 0
            MOVE BV(1) TO RBV
            PERFORM PRINT-INFO
            IF LG(1) = 0 EXIT PERFORM END-IF
            IF RBV > 29000 EXIT PERFORM END-IF
            IF TIMED = 1
                PERFORM GET-MS
                COMPUTE ELAPS = NOWMS - STARTMS
                IF ELAPS < 0 ADD 86400000 TO ELAPS END-IF
                IF ELAPS * 10 > SOFTLIM * 5 EXIT PERFORM END-IF
                IF LG(1) = 1 AND IDD >= 4 EXIT PERFORM END-IF
            END-IF
        END-IF
    END-PERFORM.

PRINT-INFO.
    PERFORM GET-MS
    COMPUTE ELAPS = NOWMS - STARTMS
    IF ELAPS < 0 ADD 86400000 TO ELAPS END-IF
    MOVE SPACES TO OUTLINE
    MOVE 1 TO OP
    STRING "info depth " DELIMITED BY SIZE INTO OUTLINE WITH POINTER OP
    MOVE IDD TO NUMV
    PERFORM FMT-NUM
    STRING FUNCTION TRIM(NUMED) DELIMITED BY SIZE INTO OUTLINE WITH POINTER OP
    IF RBV > 29000
        COMPUTE NUMV = (MATE - RBV + 1) / 2
        STRING " score mate " DELIMITED BY SIZE INTO OUTLINE WITH POINTER OP
    ELSE
        IF RBV < -29000
            COMPUTE NUMV = 0 - (MATE + RBV + 1) / 2
            STRING " score mate " DELIMITED BY SIZE INTO OUTLINE
                WITH POINTER OP
        ELSE
            MOVE RBV TO NUMV
            STRING " score cp " DELIMITED BY SIZE INTO OUTLINE
                WITH POINTER OP
        END-IF
    END-IF
    PERFORM FMT-NUM
    STRING FUNCTION TRIM(NUMED) DELIMITED BY SIZE INTO OUTLINE WITH POINTER OP
    STRING " nodes " DELIMITED BY SIZE INTO OUTLINE WITH POINTER OP
    MOVE NODECNT TO NUMV
    PERFORM FMT-NUM
    STRING FUNCTION TRIM(NUMED) DELIMITED BY SIZE INTO OUTLINE WITH POINTER OP
    STRING " time " DELIMITED BY SIZE INTO OUTLINE WITH POINTER OP
    MOVE ELAPS TO NUMV
    PERFORM FMT-NUM
    STRING FUNCTION TRIM(NUMED) DELIMITED BY SIZE INTO OUTLINE WITH POINTER OP
    IF RBF <> 0
        MOVE RBF TO MKF
        MOVE RBT TO MKT
        MOVE RBP TO MKP
        PERFORM MOVE-STR
        STRING " pv " MVSTR(1:MVLEN) DELIMITED BY SIZE INTO OUTLINE
            WITH POINTER OP
    END-IF
    DISPLAY FUNCTION TRIM(OUTLINE TRAILING)
    PERFORM FLUSH-OUT.
