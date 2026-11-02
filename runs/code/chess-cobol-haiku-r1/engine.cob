>>SOURCE FORMAT FREE
*> ChessCOBOL - a UCI chess engine written in GnuCOBOL 3.1.
*>
*> Three programs live in this file:
*>   ENGINE   - UCI front end (main program): commands, time budget, output.
*>   INPUTIO  - buffered stdin reader; non-blocking poll for "stop"/"quit" during a search.
*>   CHESS    - board, move generation, make/unmake, alpha-beta + quiescence search, perft.
*>              Recursive: every search node is one CALL to CHESS.
*>
*> Board: 10x12 mailbox. Square index sq = 10*(rank+1) + file + 2 with rank 1..8 and
*> file 0..7 (a=0). a1 = 22, h1 = 29, a8 = 92, h8 = 99. Walls have piece code 13.
*> Piece codes: 1..6 = white P N B R Q K, 7..12 = black p n b r q k.

IDENTIFICATION DIVISION.
PROGRAM-ID. ENGINE.
DATA DIVISION.
WORKING-STORAGE SECTION.
01 LINE-IN        PIC X(8192).
01 IO-OP          PIC S9(9) COMP-5.
01 IO-RC          PIC S9(9) COMP-5.
01 CH-OP          PIC S9(9) COMP-5.
01 CH-A           PIC S9(9) COMP-5.
01 CH-B           PIC S9(9) COMP-5.
01 CH-C           PIC S9(9) COMP-5.
01 CH-D           PIC S9(9) COMP-5.
01 CH-STR         PIC X(2048).
01 CH-RES         PIC S9(9) COMP-5.
01 NTOK           PIC 9(4) COMP-5.
01 TOK-TBL.
   05 TOK         PIC X(80) OCCURS 600.
01 TMP-TOK        PIC X(80).
01 PTR            PIC 9(5) COMP-5.
01 TI             PIC 9(4) COMP-5.
01 WANT-QUIT      PIC 9 COMP-5 VALUE 0.
01 FEN-BUF        PIC X(2048).
01 FEN-PTR        PIC 9(5) COMP-5.
01 GO-DEPTH       PIC S9(9) COMP-5.
01 GO-MT          PIC S9(9) COMP-5.
01 GO-WT          PIC S9(9) COMP-5.
01 GO-BT          PIC S9(9) COMP-5.
01 GO-WI          PIC S9(9) COMP-5.
01 GO-BI          PIC S9(9) COMP-5.
01 GO-PERFT       PIC S9(9) COMP-5.
01 GO-SIDE        PIC S9(9) COMP-5.
01 GO-MAXD        PIC S9(9) COMP-5.
01 GO-LIMIT       PIC S9(9) COMP-5.
01 GO-MY          PIC S9(9) COMP-5.
01 GO-INC         PIC S9(9) COMP-5.
01 NUMED          PIC -(9)9.

PROCEDURE DIVISION.
MAIN-LOOP.
    PERFORM UNTIL WANT-QUIT = 1
        MOVE 1 TO IO-OP
        CALL "INPUTIO" USING IO-OP LINE-IN IO-RC
        IF IO-RC = 0
            MOVE 1 TO WANT-QUIT
        ELSE
            PERFORM TOKENIZE
            IF NTOK > 0
                PERFORM HANDLE-CMD
            END-IF
        END-IF
    END-PERFORM
    STOP RUN.

TOKENIZE.
    MOVE 0 TO NTOK
    MOVE 1 TO PTR
    PERFORM UNTIL PTR > 8192 OR NTOK >= 600
        MOVE SPACES TO TMP-TOK
        UNSTRING LINE-IN DELIMITED BY ALL SPACE
            INTO TMP-TOK WITH POINTER PTR
        IF TMP-TOK NOT = SPACES
            ADD 1 TO NTOK
            MOVE TMP-TOK TO TOK(NTOK)
        END-IF
    END-PERFORM.

HANDLE-CMD.
    EVALUATE TOK(1)
        WHEN "uci"
            DISPLAY "id name ChessCOBOL 1.0"
            DISPLAY "id author ChessCOBOL contributors"
            DISPLAY "uciok"
        WHEN "isready"
            DISPLAY "readyok"
        WHEN "ucinewgame"
            MOVE "startpos" TO CH-STR
            MOVE 1 TO CH-OP
            CALL "CHESS" USING CH-OP CH-A CH-B CH-C CH-D CH-STR CH-RES
        WHEN "position"
            PERFORM CMD-POSITION
        WHEN "go"
            PERFORM CMD-GO
        WHEN "quit"
            MOVE 1 TO WANT-QUIT
        WHEN OTHER
            CONTINUE
    END-EVALUATE.

CMD-POSITION.
    IF NTOK >= 2 AND TOK(2) = "fen"
        MOVE SPACES TO FEN-BUF
        MOVE 1 TO FEN-PTR
        MOVE 3 TO TI
        PERFORM UNTIL TI > NTOK OR TOK(TI) = "moves"
            STRING TOK(TI) DELIMITED BY SPACE
                   " " DELIMITED BY SIZE
                INTO FEN-BUF WITH POINTER FEN-PTR
            ADD 1 TO TI
        END-PERFORM
        MOVE FEN-BUF TO CH-STR
    ELSE
        MOVE "startpos" TO CH-STR
        MOVE 3 TO TI
    END-IF
    MOVE 1 TO CH-OP
    CALL "CHESS" USING CH-OP CH-A CH-B CH-C CH-D CH-STR CH-RES
    IF TI <= NTOK AND TOK(TI) = "moves"
        ADD 1 TO TI
    END-IF
    PERFORM UNTIL TI > NTOK
        MOVE TOK(TI) TO CH-STR
        MOVE 2 TO CH-OP
        CALL "CHESS" USING CH-OP CH-A CH-B CH-C CH-D CH-STR CH-RES
        ADD 1 TO TI
    END-PERFORM.

CMD-GO.
    MOVE 0 TO GO-DEPTH GO-MT GO-WT GO-BT GO-WI GO-BI GO-PERFT
    MOVE 2 TO TI
    PERFORM UNTIL TI > NTOK
        EVALUATE TOK(TI)
            WHEN "depth"
                ADD 1 TO TI
                COMPUTE GO-DEPTH = FUNCTION NUMVAL(TOK(TI))
            WHEN "movetime"
                ADD 1 TO TI
                COMPUTE GO-MT = FUNCTION NUMVAL(TOK(TI))
            WHEN "wtime"
                ADD 1 TO TI
                COMPUTE GO-WT = FUNCTION NUMVAL(TOK(TI))
            WHEN "btime"
                ADD 1 TO TI
                COMPUTE GO-BT = FUNCTION NUMVAL(TOK(TI))
            WHEN "winc"
                ADD 1 TO TI
                COMPUTE GO-WI = FUNCTION NUMVAL(TOK(TI))
            WHEN "binc"
                ADD 1 TO TI
                COMPUTE GO-BI = FUNCTION NUMVAL(TOK(TI))
            WHEN "perft"
                ADD 1 TO TI
                COMPUTE GO-PERFT = FUNCTION NUMVAL(TOK(TI))
            WHEN "movestogo"
                ADD 1 TO TI
            WHEN OTHER
                CONTINUE
        END-EVALUATE
        ADD 1 TO TI
    END-PERFORM
    IF GO-PERFT > 0
        MOVE 4 TO CH-OP
        MOVE GO-PERFT TO CH-A
        CALL "CHESS" USING CH-OP CH-A CH-B CH-C CH-D CH-STR CH-RES
    ELSE
        MOVE 8 TO CH-OP
        CALL "CHESS" USING CH-OP CH-A CH-B CH-C CH-D CH-STR CH-RES
        MOVE CH-RES TO GO-SIDE
        PERFORM COMPUTE-LIMIT
        IF GO-DEPTH > 0
            MOVE GO-DEPTH TO GO-MAXD
        ELSE
            MOVE 64 TO GO-MAXD
        END-IF
        MOVE 4 TO IO-OP
        CALL "INPUTIO" USING IO-OP LINE-IN IO-RC
        MOVE 3 TO CH-OP
        MOVE GO-MAXD TO CH-A
        MOVE GO-LIMIT TO CH-B
        CALL "CHESS" USING CH-OP CH-A CH-B CH-C CH-D CH-STR CH-RES
        DISPLAY "bestmove " FUNCTION TRIM(CH-STR)
        MOVE 3 TO IO-OP
        CALL "INPUTIO" USING IO-OP LINE-IN IO-RC
        IF IO-RC = 2
            MOVE 1 TO WANT-QUIT
        END-IF
    END-IF.

*> Time budget in milliseconds (0 = no time limit, search until depth or stop).
COMPUTE-LIMIT.
    MOVE 0 TO GO-LIMIT
    MOVE 0 TO GO-MY
    MOVE 0 TO GO-INC
    IF GO-MT > 0
        COMPUTE GO-LIMIT = GO-MT - GO-MT / 10 - 5
    ELSE
        IF GO-SIDE = 0 AND GO-WT > 0
            MOVE GO-WT TO GO-MY
            MOVE GO-WI TO GO-INC
        END-IF
        IF GO-SIDE = 1 AND GO-BT > 0
            MOVE GO-BT TO GO-MY
            MOVE GO-BI TO GO-INC
        END-IF
        IF GO-MY > 0
            COMPUTE GO-LIMIT = GO-MY / 30 + GO-INC * 3 / 4
            IF GO-LIMIT > GO-MY / 4
                COMPUTE GO-LIMIT = GO-MY / 4
            END-IF
        END-IF
    END-IF
    IF GO-LIMIT < 1 AND (GO-MT > 0 OR GO-MY > 0)
        MOVE 1 TO GO-LIMIT
    END-IF.

END PROGRAM ENGINE.

*> ============================================================
*> INPUTIO: buffered reader on stdin (raw read(2) so that poll(2) stays accurate).
*>   op 1 GET-LINE : next complete line into LK-LINE, LK-RC 1; LK-RC 0 at end of input.
*>   op 2 POLL     : non-blocking look at stdin; consumes "stop"/"quit" lines; LK-RC = state.
*>   op 3 STATE    : LK-RC = state (0 none, 1 stop, 2 quit).
*>   op 4 RESET    : clear state.
*> ============================================================
IDENTIFICATION DIVISION.
PROGRAM-ID. INPUTIO.
DATA DIVISION.
WORKING-STORAGE SECTION.
01 IBUF           PIC X(65536).
01 IBUF2          PIC X(65536).
01 ITMP           PIC X(4096).
01 IBLEN          PIC 9(6) COMP-5 VALUE 0.
01 IPOS           PIC 9(6) COMP-5 VALUE 1.
01 IEOF           PIC 9 COMP-5 VALUE 0.
01 IFD            PIC S9(9) COMP-5 VALUE 0.
01 ISZ            PIC S9(18) COMP-5 VALUE 4096.
01 IRD            PIC S9(18) COMP-5.
01 PFD.
   05 PFFD        PIC S9(9) COMP-5 VALUE 0.
   05 PFEV        PIC S9(4) COMP-5 VALUE 1.
   05 PFRE        PIC S9(4) COMP-5 VALUE 0.
01 PNFDS          PIC S9(18) COMP-5 VALUE 1.
01 PTMO           PIC S9(9) COMP-5 VALUE 0.
01 PRC            PIC S9(9) COMP-5.
01 QSTOP          PIC 9 COMP-5 VALUE 0.
01 KK             PIC 9(6) COMP-5.
01 EE             PIC 9(6) COMP-5.
01 LEFT-N         PIC 9(6) COMP-5.
01 LN             PIC 9(6) COMP-5.
01 SC-S           PIC 9(6) COMP-5.
01 SC-E           PIC 9(6) COMP-5.
01 SC-R           PIC 9(6) COMP-5.
01 SC-GO          PIC 9 COMP-5.
LINKAGE SECTION.
01 LK-OP          PIC S9(9) COMP-5.
01 LK-LINE        PIC X(8192).
01 LK-RC          PIC S9(9) COMP-5.
PROCEDURE DIVISION USING LK-OP LK-LINE LK-RC.
MAIN-IO.
    EVALUATE LK-OP
        WHEN 1
            PERFORM GET-LINE
        WHEN 2
            PERFORM POLL-CTRL
            MOVE QSTOP TO LK-RC
        WHEN 3
            MOVE QSTOP TO LK-RC
        WHEN 4
            MOVE 0 TO QSTOP
            MOVE 0 TO LK-RC
    END-EVALUATE
    GOBACK.

GET-LINE.
    MOVE 0 TO LK-RC
    PERFORM FIND-LF
    PERFORM UNTIL KK > 0 OR IEOF = 1
        PERFORM FILL-BUF
        PERFORM FIND-LF
    END-PERFORM
    IF KK > 0
        COMPUTE LN = KK - IPOS
        IF LN > 0 AND IBUF(KK - 1:1) = X"0D"
            SUBTRACT 1 FROM LN
        END-IF
        PERFORM EXTRACT-LINE
        COMPUTE IPOS = KK + 1
        MOVE 1 TO LK-RC
    ELSE
        IF IPOS <= IBLEN
            COMPUTE LN = IBLEN - IPOS + 1
            PERFORM EXTRACT-LINE
            COMPUTE IPOS = IBLEN + 1
            MOVE 1 TO LK-RC
        END-IF
    END-IF.

EXTRACT-LINE.
    MOVE SPACES TO LK-LINE
    IF LN > 8192
        MOVE 8192 TO LN
    END-IF
    IF LN > 0
        MOVE IBUF(IPOS:LN) TO LK-LINE(1:LN)
    END-IF.

*> Sets KK to the position of the first LF at or after IPOS (0 if none).
FIND-LF.
    MOVE 0 TO KK
    MOVE IPOS TO EE
    PERFORM UNTIL EE > IBLEN OR KK > 0
        IF IBUF(EE:1) = X"0A"
            MOVE EE TO KK
        END-IF
        ADD 1 TO EE
    END-PERFORM.

*> Blocking read of more input, after compacting unread bytes to the front.
FILL-BUF.
    IF IPOS > 1
        IF IPOS <= IBLEN
            COMPUTE LEFT-N = IBLEN - IPOS + 1
            MOVE IBUF(IPOS:LEFT-N) TO IBUF2(1:LEFT-N)
            MOVE IBUF2(1:LEFT-N) TO IBUF(1:LEFT-N)
            MOVE LEFT-N TO IBLEN
        ELSE
            MOVE 0 TO IBLEN
        END-IF
        MOVE 1 TO IPOS
    END-IF
    CALL "read" USING BY VALUE IFD BY REFERENCE ITMP BY VALUE ISZ
        RETURNING IRD
    IF IRD <= 0
        MOVE 1 TO IEOF
    ELSE
        MOVE ITMP(1:IRD) TO IBUF(IBLEN + 1:IRD)
        ADD IRD TO IBLEN
    END-IF.

POLL-CTRL.
    MOVE 0 TO PFRE
    CALL "poll" USING BY REFERENCE PFD BY VALUE PNFDS BY VALUE PTMO
        RETURNING PRC
    IF PRC > 0 AND PFRE NOT = 0 AND IEOF = 0
        PERFORM FILL-BUF
    END-IF
    PERFORM SCAN-CTRL.

*> Removes complete "stop"/"quit" lines from the buffer and records them in QSTOP.
SCAN-CTRL.
    MOVE IPOS TO SC-S
    MOVE 1 TO SC-GO
    PERFORM UNTIL SC-GO = 0
        MOVE 0 TO SC-E
        MOVE SC-S TO EE
        PERFORM UNTIL EE > IBLEN OR SC-E > 0
            IF IBUF(EE:1) = X"0A"
                MOVE EE TO SC-E
            END-IF
            ADD 1 TO EE
        END-PERFORM
        IF SC-E = 0
            MOVE 0 TO SC-GO
        ELSE
            IF SC-E - SC-S >= 4 AND SC-E - SC-S <= 5
                    AND IBUF(SC-S:4) = "stop"
                IF QSTOP = 0
                    MOVE 1 TO QSTOP
                END-IF
                PERFORM REMOVE-LINE
            ELSE
                IF SC-E - SC-S >= 4 AND SC-E - SC-S <= 5
                        AND IBUF(SC-S:4) = "quit"
                    MOVE 2 TO QSTOP
                    PERFORM REMOVE-LINE
                ELSE
                    COMPUTE SC-S = SC-E + 1
                END-IF
            END-IF
        END-IF
    END-PERFORM.

REMOVE-LINE.
    COMPUTE SC-R = IBLEN - SC-E
    IF SC-R > 0
        MOVE IBUF(SC-E + 1:SC-R) TO IBUF2(1:SC-R)
        MOVE IBUF2(1:SC-R) TO IBUF(SC-S:SC-R)
    END-IF
    COMPUTE IBLEN = IBLEN - (SC-E - SC-S + 1).

END PROGRAM INPUTIO.

*> ============================================================
*> CHESS: board, move generation, search and perft.
*> Operations (LK-OP):
*>   1 SETPOS  LK-STR = FEN or "startpos"
*>   2 APPLY   LK-STR = move in UCI notation (made on the board, no undo kept)
*>   3 SEARCH  LK-A = max depth, LK-B = time limit ms (0 none); best move -> LK-STR
*>   4 PERFT   LK-A = depth; prints divide output and node count
*>   5 NODE    alpha-beta node: LK-A ply, LK-B depth, LK-C alpha, LK-D beta -> LK-RES
*>   6 QS      quiescence node: LK-A ply, LK-C alpha, LK-D beta -> LK-RES
*>   7 PERFTNODE LK-A ply, LK-B depth -> LK-RES
*>   8 SIDE    side to move -> LK-RES (0 white, 1 black)
*> ============================================================
IDENTIFICATION DIVISION.
PROGRAM-ID. CHESS IS RECURSIVE.
DATA DIVISION.
WORKING-STORAGE SECTION.
*> ---- board and game state ----
01 PC-TBL.
   05 PC          PIC 99 COMP-5 OCCURS 120.
01 KSQ-TBL.
   05 KSQ         PIC S9(4) COMP-5 OCCURS 2.
01 SIDE           PIC S9(4) COMP-5 VALUE 0.
01 EPSQ           PIC S9(4) COMP-5 VALUE 0.
01 CR             PIC X(4) VALUE "1111".
01 INITD          PIC 9 COMP-5 VALUE 0.
01 KD-TBL.
   05 KD          PIC S9(4) COMP-5 OCCURS 8.
01 NK-TBL.
   05 NK          PIC S9(4) COMP-5 OCCURS 8.
01 VT-TBL.
   05 VT          PIC S9(9) COMP-5 OCCURS 6.
*> ---- undo stack (indexed by ply + 1) ----
01 UMOV-TBL.
   05 UMOV        PIC S9(4) COMP-5 OCCURS 128.
01 UCAP-TBL.
   05 UCAP        PIC S9(4) COMP-5 OCCURS 128.
01 UCSQ-TBL.
   05 UCSQ        PIC S9(4) COMP-5 OCCURS 128.
01 UEP-TBL.
   05 UEP         PIC S9(4) COMP-5 OCCURS 128.
01 UCR-TBL.
   05 UCR         PIC X(4) OCCURS 128.
*> ---- move lists: entries for ply p are at p*256 + 1 .. p*256 + count ----
01 MCNT-TBL.
   05 MCNT        PIC S9(9) COMP-5 OCCURS 128.
01 MFR-TBL.
   05 MFR         PIC S9(4) COMP-5 OCCURS 32768.
01 MTO-TBL.
   05 MTO         PIC S9(4) COMP-5 OCCURS 32768.
01 MPR-TBL.
   05 MPR         PIC S9(4) COMP-5 OCCURS 32768.
01 MSC-TBL.
   05 MSC         PIC S9(9) COMP-5 OCCURS 32768.
*> ---- search state ----
01 ITERDEP        PIC S9(9) COMP-5 VALUE 0.
01 STOPNOW        PIC 9 COMP-5 VALUE 0.
01 NODES          PIC S9(9) COMP-5 VALUE 0.
01 TLIMIT         PIC S9(9) COMP-5 VALUE 0.
01 START-MS       PIC S9(9) COMP-5 VALUE 0.
01 NOW-MS         PIC S9(9) COMP-5 VALUE 0.
01 DONE-DEPTH     PIC S9(9) COMP-5 VALUE 0.
01 RB-F           PIC S9(4) COMP-5 VALUE 0.
01 RB-T           PIC S9(4) COMP-5 VALUE 0.
01 RB-P           PIC S9(4) COMP-5 VALUE 0.
01 PREV-F         PIC S9(4) COMP-5 VALUE 0.
01 PREV-T         PIC S9(4) COMP-5 VALUE 0.
01 PREV-P         PIC S9(4) COMP-5 VALUE 0.
*> ---- constants ----
01 ZERO-V         PIC S9(9) COMP-5 VALUE 0.
01 ONE-V          PIC S9(9) COMP-5 VALUE 1.
01 OP-NODE        PIC S9(9) COMP-5 VALUE 5.
01 OP-QS          PIC S9(9) COMP-5 VALUE 6.
01 OP-PERFT       PIC S9(9) COMP-5 VALUE 7.
01 NEG-INF        PIC S9(9) COMP-5 VALUE -100000.
01 POS-INF        PIC S9(9) COMP-5 VALUE 100000.
01 MATE-V         PIC S9(9) COMP-5 VALUE 30000.
01 START-FEN      PIC X(80) VALUE
   "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".
01 FEN-WORK       PIC X(2048).
01 PIECE-LETTERS  PIC X(12) VALUE "PNBRQKpnbrqk".
01 FILES-S        PIC X(8) VALUE "abcdefgh".
01 RANKS-S        PIC X(8) VALUE "12345678".
01 PROMO-S        PIC X(6) VALUE "xxnbrq".
*> ---- generation scratch ----
01 GPLY           PIC S9(9) COMP-5 VALUE 0.
01 GCAP           PIC 9 COMP-5 VALUE 0.
01 GB             PIC S9(9) COMP-5 VALUE 0.
01 GN             PIC S9(9) COMP-5 VALUE 0.
01 GIX            PIC S9(9) COMP-5 VALUE 0.
01 GS             PIC S9(4) COMP-5 VALUE 0.
01 GT             PIC S9(4) COMP-5 VALUE 0.
01 GT2            PIC S9(4) COMP-5 VALUE 0.
01 GD             PIC S9(4) COMP-5 VALUE 0.
01 GK             PIC S9(4) COMP-5 VALUE 0.
01 GK1            PIC S9(4) COMP-5 VALUE 0.
01 GK2            PIC S9(4) COMP-5 VALUE 0.
01 GRAY           PIC 9 COMP-5 VALUE 0.
01 GTY            PIC S9(4) COMP-5 VALUE 0.
01 GOWN           PIC S9(4) COMP-5 VALUE 0.
01 GOPP           PIC S9(4) COMP-5 VALUE 0.
01 GVV            PIC S9(9) COMP-5 VALUE 0.
01 GPT            PIC S9(4) COMP-5 VALUE 0.
01 GOK            PIC 9 COMP-5 VALUE 0.
01 GC-1           PIC S9(4) COMP-5 VALUE 0.
01 GC-2           PIC S9(4) COMP-5 VALUE 0.
01 GC-3           PIC S9(4) COMP-5 VALUE 0.
01 GM-F           PIC S9(4) COMP-5 VALUE 0.
01 GM-T           PIC S9(4) COMP-5 VALUE 0.
01 GM-P           PIC S9(4) COMP-5 VALUE 0.
01 GM-S           PIC S9(9) COMP-5 VALUE 0.
*> ---- attack test scratch ----
01 ASQ            PIC S9(4) COMP-5 VALUE 0.
01 ABY            PIC S9(4) COMP-5 VALUE 0.
01 ABASE          PIC S9(4) COMP-5 VALUE 0.
01 ATG             PIC S9(4) COMP-5 VALUE 0.
01 AK             PIC S9(4) COMP-5 VALUE 0.
01 AATT           PIC 9 COMP-5 VALUE 0.
*> ---- evaluation / make scratch ----
01 EV             PIC S9(9) COMP-5 VALUE 0.
01 ES             PIC S9(4) COMP-5 VALUE 0.
01 ET             PIC S9(4) COMP-5 VALUE 0.
01 W-F            PIC S9(4) COMP-5 VALUE 0.
01 W-T            PIC S9(4) COMP-5 VALUE 0.
01 W-P            PIC S9(4) COMP-5 VALUE 0.
01 W-PLY          PIC S9(9) COMP-5 VALUE 0.
01 W-IX           PIC S9(9) COMP-5 VALUE 0.
01 W-PC           PIC S9(4) COMP-5 VALUE 0.
01 W-WD           PIC S9(4) COMP-5 VALUE 0.
01 W-CS           PIC S9(4) COMP-5 VALUE 0.
*> ---- move-to-text / parse scratch ----
01 SQ-IN          PIC S9(4) COMP-5 VALUE 0.
01 SQ-Q           PIC S9(4) COMP-5 VALUE 0.
01 SQ-REM         PIC S9(4) COMP-5 VALUE 0.
01 SQ-FILE        PIC S9(4) COMP-5 VALUE 0.
01 SQ-RANK        PIC S9(4) COMP-5 VALUE 0.
01 SQ-TXT         PIC XX.
01 MV-F           PIC S9(4) COMP-5 VALUE 0.
01 MV-T           PIC S9(4) COMP-5 VALUE 0.
01 MV-P           PIC S9(4) COMP-5 VALUE 0.
01 MV-TXT         PIC X(5).
01 PS-POS         PIC S9(4) COMP-5 VALUE 0.
01 PS-SQ          PIC S9(4) COMP-5 VALUE 0.
01 PS-RANK        PIC S9(4) COMP-5 VALUE 0.
01 PS-FILE        PIC S9(4) COMP-5 VALUE 0.
01 FP             PIC S9(9) COMP-5 VALUE 0.
01 FL             PIC S9(4) COMP-5 VALUE 0.
01 RK             PIC S9(4) COMP-5 VALUE 0.
01 FCH            PIC X.
01 PCODE          PIC S9(4) COMP-5 VALUE 0.
01 PK             PIC S9(4) COMP-5 VALUE 0.
01 SQ-X           PIC S9(4) COMP-5 VALUE 0.
01 CB-S           PIC S9(4) COMP-5 VALUE 0.
01 CB-T           PIC S9(4) COMP-5 VALUE 0.
01 CB-R           PIC S9(4) COMP-5 VALUE 0.
01 CB-C           PIC S9(4) COMP-5 VALUE 0.
01 ES-S           PIC S9(4) COMP-5 VALUE 0.
01 PB-K           PIC S9(9) COMP-5 VALUE 0.
01 PB-BEST        PIC S9(9) COMP-5 VALUE 0.
01 PB-SC          PIC S9(9) COMP-5 VALUE 0.
01 PB-IX          PIC S9(9) COMP-5 VALUE 0.
01 PB-IX2         PIC S9(9) COMP-5 VALUE 0.
01 TW-F           PIC S9(4) COMP-5 VALUE 0.
01 TW-T           PIC S9(4) COMP-5 VALUE 0.
01 TW-P           PIC S9(4) COMP-5 VALUE 0.
01 TW-S           PIC S9(9) COMP-5 VALUE 0.
01 BON-K          PIC S9(9) COMP-5 VALUE 0.
01 BON-IX         PIC S9(9) COMP-5 VALUE 0.
01 CT-OP          PIC S9(9) COMP-5 VALUE 0.
01 CT-RC          PIC S9(9) COMP-5 VALUE 0.
01 CT-Q           PIC S9(9) COMP-5 VALUE 0.
01 CT-R           PIC S9(9) COMP-5 VALUE 0.
01 CT-LINE        PIC X(8192).
01 CDT-X          PIC X(21).
01 T-ELAPSED      PIC S9(9) COMP-5 VALUE 0.
01 INFO-DEPTH     PIC -(9)9.
01 INFO-CP        PIC -(9)9.
01 INFO-NODES     PIC -(9)9.
01 INFO-TIME      PIC -(9)9.
01 INFO-NPS       PIC -(9)9.
01 MATE-N         PIC S9(9) COMP-5 VALUE 0.
01 NPS-W          PIC S9(18) COMP-5 VALUE 0.
01 CNT-ED         PIC -(9)9.
01 TOT-ED         PIC -(9)9.

LOCAL-STORAGE SECTION.
01 L-PLY          PIC S9(9) COMP-5.
01 L-DEP          PIC S9(9) COMP-5.
01 L-ALPHA        PIC S9(9) COMP-5.
01 L-BETA         PIC S9(9) COMP-5.
01 L-BEST         PIC S9(9) COMP-5.
01 L-SC           PIC S9(9) COMP-5.
01 L-RES          PIC S9(9) COMP-5.
01 L-LEG          PIC S9(9) COMP-5.
01 L-CNT          PIC S9(9) COMP-5.
01 L-I            PIC S9(9) COMP-5.
01 L-CHK          PIC S9(9) COMP-5.
01 L-ME           PIC S9(9) COMP-5.
01 L-MB           PIC S9(9) COMP-5.
01 L-IDX          PIC S9(9) COMP-5.
01 L-F            PIC S9(4) COMP-5.
01 L-T            PIC S9(4) COMP-5.
01 L-P            PIC S9(4) COMP-5.
01 L-CUT          PIC S9(9) COMP-5.
01 L-STOP         PIC S9(9) COMP-5.
01 L-OK           PIC S9(9) COMP-5.
01 L-NA           PIC S9(9) COMP-5.
01 L-NB           PIC S9(9) COMP-5.
01 L-NC           PIC S9(9) COMP-5.
01 L-ND           PIC S9(9) COMP-5.
01 L-TOT          PIC S9(9) COMP-5.
01 L-MAXD         PIC S9(9) COMP-5.
01 L-ITER         PIC S9(9) COMP-5.
01 L-FOUND        PIC S9(9) COMP-5.
01 L-SCORE        PIC S9(9) COMP-5.

LINKAGE SECTION.
01 LK-OP          PIC S9(9) COMP-5.
01 LK-A           PIC S9(9) COMP-5.
01 LK-B           PIC S9(9) COMP-5.
01 LK-C           PIC S9(9) COMP-5.
01 LK-D           PIC S9(9) COMP-5.
01 LK-STR         PIC X(2048).
01 LK-RES         PIC S9(9) COMP-5.

PROCEDURE DIVISION USING LK-OP LK-A LK-B LK-C LK-D LK-STR LK-RES.
MAIN-DISPATCH.
    IF INITD = 0
        PERFORM INIT-TABLES
    END-IF
    EVALUATE LK-OP
        WHEN 1
            PERFORM OP-SETPOS
        WHEN 2
            PERFORM OP-APPLY
        WHEN 3
            PERFORM SEARCH-TOP
        WHEN 4
            PERFORM PERFT-TOP
        WHEN 5
            PERFORM NODE-SEARCH
        WHEN 6
            PERFORM QS-SEARCH
        WHEN 7
            PERFORM PERFT-NODE
        WHEN 8
            MOVE SIDE TO LK-RES
    END-EVALUATE
    GOBACK.

*> ---------------- setup ----------------
INIT-TABLES.
    MOVE 10 TO KD(1)
    MOVE -10 TO KD(2)
    MOVE 1 TO KD(3)
    MOVE -1 TO KD(4)
    MOVE 11 TO KD(5)
    MOVE 9 TO KD(6)
    MOVE -9 TO KD(7)
    MOVE -11 TO KD(8)
    MOVE 21 TO NK(1)
    MOVE 19 TO NK(2)
    MOVE 12 TO NK(3)
    MOVE 8 TO NK(4)
    MOVE -8 TO NK(5)
    MOVE -12 TO NK(6)
    MOVE -19 TO NK(7)
    MOVE -21 TO NK(8)
    MOVE 100 TO VT(1)
    MOVE 320 TO VT(2)
    MOVE 330 TO VT(3)
    MOVE 500 TO VT(4)
    MOVE 900 TO VT(5)
    MOVE 0 TO VT(6)
    MOVE 1 TO INITD
    MOVE START-FEN TO FEN-WORK
    PERFORM SET-FEN.

OP-SETPOS.
    MOVE LK-STR TO FEN-WORK
    PERFORM SET-FEN
    MOVE 0 TO LK-RES.

OP-APPLY.
    MOVE LK-STR TO FEN-WORK
    MOVE 1 TO PS-POS
    PERFORM PARSE-SQ-ATG
    MOVE PS-SQ TO W-F
    MOVE 3 TO PS-POS
    PERFORM PARSE-SQ-ATG
    MOVE PS-SQ TO W-T
    PERFORM PARSE-PROMO
    MOVE 0 TO W-PLY
    PERFORM MAKE-MOVE
    MOVE 0 TO LK-RES.

*> Parses the square at FEN-WORK(PS-POS:2) into PS-SQ.
PARSE-SQ-ATG.
    COMPUTE PS-FILE = FUNCTION ORD(FEN-WORK(PS-POS:1)) - 98
    COMPUTE PS-RANK = FUNCTION ORD(FEN-WORK(PS-POS + 1:1)) - 49
    COMPUTE PS-SQ = 10 * (PS-RANK + 1) + PS-FILE + 2.

*> Promotion letter at FEN-WORK(5:1) into W-P.
PARSE-PROMO.
    MOVE 0 TO W-P
    EVALUATE FEN-WORK(5:1)
        WHEN "q" MOVE 5 TO W-P
        WHEN "r" MOVE 4 TO W-P
        WHEN "b" MOVE 3 TO W-P
        WHEN "n" MOVE 2 TO W-P
        WHEN OTHER CONTINUE
    END-EVALUATE.

CLEAR-BOARD.
    PERFORM VARYING CB-S FROM 1 BY 1 UNTIL CB-S > 120
        COMPUTE CB-T = CB-S - 1
        DIVIDE CB-T BY 10 GIVING CB-R REMAINDER CB-C
        IF CB-R < 2 OR CB-R > 9 OR CB-C < 1 OR CB-C > 8
            MOVE 13 TO PC(CB-S)
        ELSE
            MOVE 0 TO PC(CB-S)
        END-IF
    END-PERFORM.

*> Loads FEN-WORK ("startpos" or a FEN string) into the board.
SET-FEN.
    IF FEN-WORK(1:8) = "startpos"
        MOVE START-FEN TO FEN-WORK
    END-IF
    PERFORM CLEAR-BOARD
    MOVE 1 TO FP
    MOVE 8 TO RK
    MOVE 0 TO FL
    PERFORM UNTIL FP > 2048 OR FEN-WORK(FP:1) = SPACE
        MOVE FEN-WORK(FP:1) TO FCH
        EVALUATE TRUE
            WHEN FCH = "/"
                SUBTRACT 1 FROM RK
                MOVE 0 TO FL
            WHEN FCH >= "1" AND FCH <= "8"
                COMPUTE FL = FL + FUNCTION ORD(FCH) - 49
            WHEN OTHER
                PERFORM FIND-PIECE
                IF PCODE > 0
                    COMPUTE SQ-X = 10 * (RK + 1) + FL + 2
                    MOVE PCODE TO PC(SQ-X)
                END-IF
                ADD 1 TO FL
        END-EVALUATE
        ADD 1 TO FP
    END-PERFORM
    PERFORM SKIP-SPACES
    IF FEN-WORK(FP:1) = "b"
        MOVE 1 TO SIDE
    ELSE
        MOVE 0 TO SIDE
    END-IF
    ADD 1 TO FP
    PERFORM SKIP-SPACES
    MOVE "0000" TO CR
    PERFORM UNTIL FP > 2048 OR FEN-WORK(FP:1) = SPACE
        EVALUATE FEN-WORK(FP:1)
            WHEN "K" MOVE "1" TO CR(1:1)
            WHEN "Q" MOVE "1" TO CR(2:1)
            WHEN "k" MOVE "1" TO CR(3:1)
            WHEN "q" MOVE "1" TO CR(4:1)
            WHEN OTHER CONTINUE
        END-EVALUATE
        ADD 1 TO FP
    END-PERFORM
    PERFORM SKIP-SPACES
    IF FEN-WORK(FP:1) = "-"
        MOVE 0 TO EPSQ
    ELSE
        MOVE FP TO PS-POS
        PERFORM PARSE-SQ-ATG
        MOVE PS-SQ TO EPSQ
    END-IF
    MOVE 0 TO KSQ(1)
    MOVE 0 TO KSQ(2)
    PERFORM VARYING ES-S FROM 22 BY 1 UNTIL ES-S > 99
        IF PC(ES-S) = 6
            MOVE ES-S TO KSQ(1)
        END-IF
        IF PC(ES-S) = 12
            MOVE ES-S TO KSQ(2)
        END-IF
    END-PERFORM.

SKIP-SPACES.
    PERFORM UNTIL FP > 2048 OR FEN-WORK(FP:1) NOT = SPACE
        ADD 1 TO FP
    END-PERFORM.

FIND-PIECE.
    MOVE 0 TO PCODE
    PERFORM VARYING PK FROM 1 BY 1 UNTIL PK > 12 OR PCODE > 0
        IF PIECE-LETTERS(PK:1) = FCH
            MOVE PK TO PCODE
        END-IF
    END-PERFORM.

*> ---------------- square / move text ----------------
*> SQ-IN -> SQ-TXT (two characters).
SQ-TO-TXT.
    DIVIDE SQ-IN BY 10 GIVING SQ-Q REMAINDER SQ-REM
    COMPUTE SQ-FILE = SQ-REM - 2
    COMPUTE SQ-RANK = SQ-Q - 1
    MOVE FILES-S(SQ-FILE + 1:1) TO SQ-TXT(1:1)
    MOVE RANKS-S(SQ-RANK:1) TO SQ-TXT(2:1).

*> MV-F, MV-T, MV-P -> MV-TXT in UCI notation.
MOVE-TXT.
    MOVE SPACES TO MV-TXT
    MOVE MV-F TO SQ-IN
    PERFORM SQ-TO-TXT
    MOVE SQ-TXT TO MV-TXT(1:2)
    MOVE MV-T TO SQ-IN
    PERFORM SQ-TO-TXT
    MOVE SQ-TXT TO MV-TXT(3:2)
    IF MV-P > 0
        MOVE PROMO-S(MV-P + 1:1) TO MV-TXT(5:1)
    END-IF.

*> ---------------- attacks ----------------
*> Is square ASQ attacked by side ABY?  Result in AATT.
ATT-SQ.
    MOVE 0 TO AATT
    COMPUTE ABASE = ABY * 6
    IF ABY = 0
        IF PC(ASQ - 9) = 1 OR PC(ASQ - 11) = 1
            MOVE 1 TO AATT
        END-IF
    ELSE
        IF PC(ASQ + 9) = 7 OR PC(ASQ + 11) = 7
            MOVE 1 TO AATT
        END-IF
    END-IF
    PERFORM VARYING AK FROM 1 BY 1 UNTIL AK > 8 OR AATT = 1
        COMPUTE ATG = ASQ + NK(AK)
        IF PC(ATG) = ABASE + 2
            MOVE 1 TO AATT
        END-IF
    END-PERFORM
    PERFORM VARYING AK FROM 1 BY 1 UNTIL AK > 8 OR AATT = 1
        COMPUTE ATG = ASQ + KD(AK)
        IF PC(ATG) = ABASE + 6
            MOVE 1 TO AATT
        END-IF
    END-PERFORM
    PERFORM VARYING AK FROM 1 BY 1 UNTIL AK > 4 OR AATT = 1
        MOVE ASQ TO ATG
        ADD KD(AK) TO ATG
        PERFORM UNTIL PC(ATG) NOT = 0
            ADD KD(AK) TO ATG
        END-PERFORM
        IF PC(ATG) = ABASE + 4 OR PC(ATG) = ABASE + 5
            MOVE 1 TO AATT
        END-IF
    END-PERFORM
    PERFORM VARYING AK FROM 5 BY 1 UNTIL AK > 8 OR AATT = 1
        MOVE ASQ TO ATG
        ADD KD(AK) TO ATG
        PERFORM UNTIL PC(ATG) NOT = 0
            ADD KD(AK) TO ATG
        END-PERFORM
        IF PC(ATG) = ABASE + 3 OR PC(ATG) = ABASE + 5
            MOVE 1 TO AATT
        END-IF
    END-PERFORM.

*> ---------------- evaluation (side to move's view) ----------------
EVAL-POS.
    MOVE 0 TO EV
    PERFORM VARYING ES FROM 22 BY 1 UNTIL ES > 99
        IF PC(ES) >= 1 AND PC(ES) <= 6
            ADD VT(PC(ES)) TO EV
        END-IF
        IF PC(ES) >= 7 AND PC(ES) <= 12
            SUBTRACT VT(PC(ES) - 6) FROM EV
        END-IF
    END-PERFORM
    IF SIDE = 1
        COMPUTE EV = 0 - EV
    END-IF.

*> ---------------- make / unmake ----------------
*> Plays move W-F -> W-T (promotion W-P) at ply W-PLY, saving undo information.
MAKE-MOVE.
    COMPUTE W-IX = W-PLY + 1
    MOVE PC(W-F) TO W-PC
    MOVE W-PC TO UMOV(W-IX)
    MOVE PC(W-T) TO UCAP(W-IX)
    MOVE W-T TO UCSQ(W-IX)
    MOVE EPSQ TO UEP(W-IX)
    MOVE CR TO UCR(W-IX)
    COMPUTE W-WD = W-T - W-F
    IF (W-PC = 1 OR W-PC = 7) AND PC(W-T) = 0
            AND (W-WD = 9 OR W-WD = 11 OR W-WD = -9 OR W-WD = -11)
        COMPUTE W-CS = W-T - 10 + 20 * SIDE
        MOVE PC(W-CS) TO UCAP(W-IX)
        MOVE W-CS TO UCSQ(W-IX)
        MOVE 0 TO PC(W-CS)
    END-IF
    IF W-P > 0
        COMPUTE PC(W-T) = SIDE * 6 + W-P
    ELSE
        MOVE W-PC TO PC(W-T)
    END-IF
    MOVE 0 TO PC(W-F)
    IF W-PC = 6 OR W-PC = 12
        MOVE W-T TO KSQ(SIDE + 1)
        IF W-WD = 2
            MOVE PC(W-T + 1) TO PC(W-T - 1)
            MOVE 0 TO PC(W-T + 1)
        END-IF
        IF W-WD = -2
            MOVE PC(W-T - 2) TO PC(W-T + 1)
            MOVE 0 TO PC(W-T - 2)
        END-IF
    END-IF
    IF (W-PC = 1 OR W-PC = 7) AND (W-WD = 20 OR W-WD = -20)
        COMPUTE EPSQ = (W-F + W-T) / 2
    ELSE
        MOVE 0 TO EPSQ
    END-IF
    IF W-F = 26 OR W-T = 26
        MOVE "00" TO CR(1:2)
    END-IF
    IF W-F = 22 OR W-T = 22
        MOVE "0" TO CR(2:1)
    END-IF
    IF W-F = 29 OR W-T = 29
        MOVE "0" TO CR(1:1)
    END-IF
    IF W-F = 96 OR W-T = 96
        MOVE "00" TO CR(3:2)
    END-IF
    IF W-F = 92 OR W-T = 92
        MOVE "0" TO CR(4:1)
    END-IF
    IF W-F = 99 OR W-T = 99
        MOVE "0" TO CR(3:1)
    END-IF
    COMPUTE SIDE = 1 - SIDE.

*> Undoes the move W-F -> W-T played at ply W-PLY.
UNMAKE-MOVE.
    COMPUTE W-IX = W-PLY + 1
    COMPUTE SIDE = 1 - SIDE
    MOVE 0 TO PC(W-T)
    MOVE UMOV(W-IX) TO PC(W-F)
    MOVE UCAP(W-IX) TO PC(UCSQ(W-IX))
    MOVE UEP(W-IX) TO EPSQ
    MOVE UCR(W-IX) TO CR
    IF UMOV(W-IX) = 6 OR UMOV(W-IX) = 12
        MOVE W-F TO KSQ(SIDE + 1)
        COMPUTE W-WD = W-T - W-F
        IF W-WD = 2
            MOVE PC(W-T - 1) TO PC(W-T + 1)
            MOVE 0 TO PC(W-T - 1)
        END-IF
        IF W-WD = -2
            MOVE PC(W-T + 1) TO PC(W-T - 2)
            MOVE 0 TO PC(W-T + 1)
        END-IF
    END-IF.

*> ---------------- move generation ----------------
*> Adds move GM-F -> GM-T (promotion GM-P, score GM-S) to the list of ply GPLY.
ADD-MOVE.
    ADD 1 TO GN
    COMPUTE GIX = GB + GN
    MOVE GM-F TO MFR(GIX)
    MOVE GM-T TO MTO(GIX)
    MOVE GM-P TO MPR(GIX)
    MOVE GM-S TO MSC(GIX).

*> Generates pseudo-legal moves for side to move into list GPLY.
*> GCAP = 1: captures and promotions only.
GEN-MOVES.
    MOVE 0 TO GN
    COMPUTE GB = GPLY * 256
    IF SIDE = 0
        MOVE 0 TO GOWN
        MOVE 6 TO GOPP
    ELSE
        MOVE 6 TO GOWN
        MOVE 0 TO GOPP
    END-IF
    PERFORM VARYING GS FROM 22 BY 1 UNTIL GS > 99
        IF PC(GS) > GOWN AND PC(GS) <= GOWN + 6
            COMPUTE GTY = PC(GS) - GOWN
            EVALUATE GTY
                WHEN 1
                    PERFORM GEN-PAWN
                WHEN 2
                    PERFORM GEN-KNIGHT
                WHEN 3
                    MOVE 5 TO GK1
                    MOVE 8 TO GK2
                    PERFORM GEN-SLIDE
                WHEN 4
                    MOVE 1 TO GK1
                    MOVE 4 TO GK2
                    PERFORM GEN-SLIDE
                WHEN 5
                    MOVE 1 TO GK1
                    MOVE 8 TO GK2
                    PERFORM GEN-SLIDE
                WHEN 6
                    PERFORM GEN-KING
            END-EVALUATE
        END-IF
    END-PERFORM
    MOVE GN TO MCNT(GPLY + 1).

*> Adds GS -> GT for a single-step piece (knight/king), with captures scored MVV-LVA.
TRY-SQ.
    IF PC(GT) = 0
        IF GCAP = 0
            MOVE GS TO GM-F
            MOVE GT TO GM-T
            MOVE 0 TO GM-P
            MOVE 0 TO GM-S
            PERFORM ADD-MOVE
        END-IF
    ELSE
        IF PC(GT) > GOPP AND PC(GT) <= GOPP + 6
            COMPUTE GVV = VT(PC(GT) - GOPP)
            MOVE GS TO GM-F
            MOVE GT TO GM-T
            MOVE 0 TO GM-P
            COMPUTE GM-S = 10000 + GVV * 10 - GTY
            PERFORM ADD-MOVE
        END-IF
    END-IF.

*> Adds promotions GS -> GT (GPT = 5..2) with victim value GVV.
ADD-PROMOS.
    PERFORM VARYING GPT FROM 5 BY -1 UNTIL GPT < 2
        MOVE GS TO GM-F
        MOVE GT TO GM-T
        MOVE GPT TO GM-P
        COMPUTE GM-S = 9000 + VT(GPT) + GVV * 10
        PERFORM ADD-MOVE
    END-PERFORM.

GEN-PAWN.
    IF SIDE = 0
        MOVE 10 TO GD
    ELSE
        MOVE -10 TO GD
    END-IF
    COMPUTE GT = GS + GD
    IF PC(GT) = 0
        IF (SIDE = 0 AND GT >= 92) OR (SIDE = 1 AND GT <= 29)
            MOVE 0 TO GVV
            PERFORM ADD-PROMOS
        ELSE
            IF GCAP = 0
                MOVE GS TO GM-F
                MOVE GT TO GM-T
                MOVE 0 TO GM-P
                MOVE 0 TO GM-S
                PERFORM ADD-MOVE
                IF (SIDE = 0 AND GS >= 32 AND GS <= 39)
                        OR (SIDE = 1 AND GS >= 82 AND GS <= 89)
                    COMPUTE GT2 = GT + GD
                    IF PC(GT2) = 0
                        MOVE GS TO GM-F
                        MOVE GT2 TO GM-T
                        MOVE 0 TO GM-P
                        MOVE 0 TO GM-S
                        PERFORM ADD-MOVE
                    END-IF
                END-IF
            END-IF
        END-IF
    END-IF
    PERFORM VARYING GK FROM 1 BY 1 UNTIL GK > 2
        IF GK = 1
            COMPUTE GT = GS + GD + 1
        ELSE
            COMPUTE GT = GS + GD - 1
        END-IF
        IF PC(GT) > GOPP AND PC(GT) <= GOPP + 6
            COMPUTE GVV = VT(PC(GT) - GOPP)
            IF (SIDE = 0 AND GT >= 92) OR (SIDE = 1 AND GT <= 29)
                PERFORM ADD-PROMOS
            ELSE
                MOVE GS TO GM-F
                MOVE GT TO GM-T
                MOVE 0 TO GM-P
                COMPUTE GM-S = 10000 + GVV * 10 - 1
                PERFORM ADD-MOVE
            END-IF
        ELSE
            IF EPSQ > 0 AND GT = EPSQ AND PC(GT) = 0
                MOVE GS TO GM-F
                MOVE GT TO GM-T
                MOVE 0 TO GM-P
                COMPUTE GM-S = 10000 + 1000 - 1
                PERFORM ADD-MOVE
            END-IF
        END-IF
    END-PERFORM.

GEN-KNIGHT.
    MOVE 2 TO GTY
    PERFORM VARYING GK FROM 1 BY 1 UNTIL GK > 8
        COMPUTE GT = GS + NK(GK)
        PERFORM TRY-SQ
    END-PERFORM.

GEN-KING.
    MOVE 6 TO GTY
    PERFORM VARYING GK FROM 1 BY 1 UNTIL GK > 8
        COMPUTE GT = GS + KD(GK)
        PERFORM TRY-SQ
    END-PERFORM
    IF GCAP = 0
        PERFORM GEN-CASTLE
    END-IF.

*> Sliding pieces: directions GK1..GK2 of table KD; type in GTY.
GEN-SLIDE.
    PERFORM VARYING GK FROM GK1 BY 1 UNTIL GK > GK2
        MOVE GS TO GT
        MOVE 1 TO GRAY
        PERFORM UNTIL GRAY = 0
            COMPUTE GT = GT + KD(GK)
            IF PC(GT) = 0
                IF GCAP = 0
                    MOVE GS TO GM-F
                    MOVE GT TO GM-T
                    MOVE 0 TO GM-P
                    MOVE 0 TO GM-S
                    PERFORM ADD-MOVE
                END-IF
            ELSE
                MOVE 0 TO GRAY
                IF PC(GT) > GOPP AND PC(GT) <= GOPP + 6
                    COMPUTE GVV = VT(PC(GT) - GOPP)
                    MOVE GS TO GM-F
                    MOVE GT TO GM-T
                    MOVE 0 TO GM-P
                    COMPUTE GM-S = 10000 + GVV * 10 - GTY
                    PERFORM ADD-MOVE
                END-IF
            END-IF
        END-PERFORM
    END-PERFORM.

*> Castling for the king on its home square (GS = 26 white, 96 black).
GEN-CASTLE.
    IF SIDE = 0 AND GS = 26
        MOVE 26 TO GC-1
        MOVE 27 TO GC-2
        MOVE 28 TO GC-3
        IF CR(1:1) = "1" AND PC(27) = 0 AND PC(28) = 0 AND PC(29) = 4
            MOVE 1 TO ABY
            PERFORM CASTLE-SAFE
            IF GOK = 1
                MOVE 26 TO GM-F
                MOVE 28 TO GM-T
                MOVE 0 TO GM-P
                MOVE 0 TO GM-S
                PERFORM ADD-MOVE
            END-IF
        END-IF
        MOVE 26 TO GC-1
        MOVE 25 TO GC-2
        MOVE 24 TO GC-3
        IF CR(2:1) = "1" AND PC(25) = 0 AND PC(24) = 0 AND PC(23) = 0 AND PC(22) = 4
            MOVE 1 TO ABY
            PERFORM CASTLE-SAFE
            IF GOK = 1
                MOVE 26 TO GM-F
                MOVE 24 TO GM-T
                MOVE 0 TO GM-P
                MOVE 0 TO GM-S
                PERFORM ADD-MOVE
            END-IF
        END-IF
    END-IF
    IF SIDE = 1 AND GS = 96
        MOVE 96 TO GC-1
        MOVE 97 TO GC-2
        MOVE 98 TO GC-3
        IF CR(3:1) = "1" AND PC(97) = 0 AND PC(98) = 0 AND PC(99) = 10
            MOVE 0 TO ABY
            PERFORM CASTLE-SAFE
            IF GOK = 1
                MOVE 96 TO GM-F
                MOVE 98 TO GM-T
                MOVE 0 TO GM-P
                MOVE 0 TO GM-S
                PERFORM ADD-MOVE
            END-IF
        END-IF
        MOVE 96 TO GC-1
        MOVE 95 TO GC-2
        MOVE 94 TO GC-3
        IF CR(4:1) = "1" AND PC(95) = 0 AND PC(94) = 0 AND PC(93) = 0 AND PC(92) = 10
            MOVE 0 TO ABY
            PERFORM CASTLE-SAFE
            IF GOK = 1
                MOVE 96 TO GM-F
                MOVE 94 TO GM-T
                MOVE 0 TO GM-P
                MOVE 0 TO GM-S
                PERFORM ADD-MOVE
            END-IF
        END-IF
    END-IF.

*> GOK = 1 when none of GC-1..GC-3 is attacked by side ABY.
CASTLE-SAFE.
    MOVE 1 TO GOK
    MOVE GC-1 TO ASQ
    PERFORM ATT-SQ
    IF AATT = 1
        MOVE 0 TO GOK
    END-IF
    MOVE GC-2 TO ASQ
    PERFORM ATT-SQ
    IF AATT = 1
        MOVE 0 TO GOK
    END-IF
    MOVE GC-3 TO ASQ
    PERFORM ATT-SQ
    IF AATT = 1
        MOVE 0 TO GOK
    END-IF.

*> ---------------- ordering helpers ----------------
*> Moves the best-scored entry among L-I..L-CNT of ply L-MB into position L-I.
PICK-BEST.
    MOVE L-I TO PB-BEST
    COMPUTE PB-IX = L-MB + L-I
    MOVE MSC(PB-IX) TO PB-SC
    PERFORM VARYING PB-K FROM L-I BY 1 UNTIL PB-K > L-CNT
        COMPUTE PB-IX2 = L-MB + PB-K
        IF MSC(PB-IX2) > PB-SC
            MOVE MSC(PB-IX2) TO PB-SC
            MOVE PB-K TO PB-BEST
        END-IF
    END-PERFORM
    IF PB-BEST NOT = L-I
        COMPUTE PB-IX2 = L-MB + PB-BEST
        MOVE MFR(PB-IX) TO TW-F
        MOVE MFR(PB-IX2) TO MFR(PB-IX)
        MOVE TW-F TO MFR(PB-IX2)
        MOVE MTO(PB-IX) TO TW-T
        MOVE MTO(PB-IX2) TO MTO(PB-IX)
        MOVE TW-T TO MTO(PB-IX2)
        MOVE MPR(PB-IX) TO TW-P
        MOVE MPR(PB-IX2) TO MPR(PB-IX)
        MOVE TW-P TO MPR(PB-IX2)
        MOVE MSC(PB-IX) TO TW-S
        MOVE MSC(PB-IX2) TO MSC(PB-IX)
        MOVE TW-S TO MSC(PB-IX2)
    END-IF.

*> Root: the previous iteration's best move is searched first.
ROOT-BONUS.
    IF PREV-F > 0
        PERFORM VARYING BON-K FROM 1 BY 1 UNTIL BON-K > L-CNT
            COMPUTE BON-IX = L-MB + BON-K
            IF MFR(BON-IX) = PREV-F AND MTO(BON-IX) = PREV-T
                    AND MPR(BON-IX) = PREV-P
                ADD 1000000 TO MSC(BON-IX)
            END-IF
        END-PERFORM
    END-IF.

*> ---------------- clock and time control ----------------
NOW-CLOCK.
    MOVE FUNCTION CURRENT-DATE TO CDT-X
    COMPUTE NOW-MS = ((FUNCTION NUMVAL(CDT-X(9:2)) * 60
                     + FUNCTION NUMVAL(CDT-X(11:2))) * 60
                     + FUNCTION NUMVAL(CDT-X(13:2))) * 1000
                     + FUNCTION NUMVAL(CDT-X(15:2)) * 10.

*> Every 1024 nodes: look for stop/quit input, and check the time limit.
CHECK-TIME.
    DIVIDE NODES BY 1024 GIVING CT-Q REMAINDER CT-R
    IF CT-R = 0
        MOVE 2 TO CT-OP
        CALL "INPUTIO" USING CT-OP CT-LINE CT-RC
        IF CT-RC NOT = 0
            MOVE 1 TO STOPNOW
        END-IF
        IF DONE-DEPTH >= 1 AND TLIMIT > 0
            PERFORM NOW-CLOCK
            COMPUTE T-ELAPSED = NOW-MS - START-MS
            IF T-ELAPSED < 0
                ADD 86400000 TO T-ELAPSED
            END-IF
            IF T-ELAPSED >= TLIMIT
                MOVE 1 TO STOPNOW
            END-IF
        END-IF
    END-IF.

*> ---------------- alpha-beta search ----------------
NODE-SEARCH.
    ADD 1 TO NODES
    PERFORM CHECK-TIME
    MOVE LK-A TO L-PLY
    MOVE LK-B TO L-DEP
    MOVE LK-C TO L-ALPHA
    MOVE LK-D TO L-BETA
    MOVE 0 TO L-STOP
    IF STOPNOW = 1
        MOVE 0 TO LK-RES
        GOBACK
    END-IF
    IF L-DEP <= 0
        CALL "CHESS" USING BY CONTENT OP-QS BY CONTENT L-PLY
            BY CONTENT ZERO-V BY CONTENT L-ALPHA BY CONTENT L-BETA
            BY REFERENCE LK-STR BY REFERENCE L-RES
        MOVE L-RES TO LK-RES
        GOBACK
    END-IF
    IF L-PLY >= 120
        PERFORM EVAL-POS
        MOVE EV TO LK-RES
        GOBACK
    END-IF
    MOVE SIDE TO L-ME
    MOVE KSQ(L-ME + 1) TO ASQ
    COMPUTE ABY = 1 - L-ME
    PERFORM ATT-SQ
    MOVE AATT TO L-CHK
    MOVE L-PLY TO GPLY
    MOVE 0 TO GCAP
    PERFORM GEN-MOVES
    MOVE MCNT(L-PLY + 1) TO L-CNT
    COMPUTE L-MB = L-PLY * 256
    IF L-PLY = 0
        PERFORM ROOT-BONUS
    END-IF
    MOVE NEG-INF TO L-BEST
    MOVE 0 TO L-LEG
    MOVE 0 TO L-CUT
    PERFORM VARYING L-I FROM 1 BY 1 UNTIL L-I > L-CNT OR L-CUT = 1
        PERFORM PICK-BEST
        COMPUTE L-IDX = L-MB + L-I
        MOVE MFR(L-IDX) TO L-F
        MOVE MTO(L-IDX) TO L-T
        MOVE MPR(L-IDX) TO L-P
        MOVE L-F TO W-F
        MOVE L-T TO W-T
        MOVE L-P TO W-P
        MOVE L-PLY TO W-PLY
        PERFORM MAKE-MOVE
        MOVE KSQ(L-ME + 1) TO ASQ
        MOVE SIDE TO ABY
        PERFORM ATT-SQ
        IF AATT = 0
            MOVE 1 TO L-OK
        ELSE
            MOVE 0 TO L-OK
        END-IF
        IF L-OK = 1
            ADD 1 TO L-LEG
            COMPUTE L-NA = L-PLY + 1
            COMPUTE L-NB = L-DEP - 1
            COMPUTE L-NC = 0 - L-BETA
            COMPUTE L-ND = 0 - L-ALPHA
            CALL "CHESS" USING BY CONTENT OP-NODE BY CONTENT L-NA
                BY CONTENT L-NB BY CONTENT L-NC BY CONTENT L-ND
                BY REFERENCE LK-STR BY REFERENCE L-RES
            COMPUTE L-SC = 0 - L-RES
        END-IF
        MOVE L-F TO W-F
        MOVE L-T TO W-T
        MOVE L-PLY TO W-PLY
        PERFORM UNMAKE-MOVE
        IF L-OK = 1
            IF STOPNOW = 1
                MOVE 1 TO L-STOP
                MOVE 1 TO L-CUT
            ELSE
                IF L-SC > L-BEST
                    MOVE L-SC TO L-BEST
                    IF L-PLY = 0
                        MOVE L-F TO RB-F
                        MOVE L-T TO RB-T
                        MOVE L-P TO RB-P
                    END-IF
                END-IF
                IF L-SC > L-ALPHA
                    MOVE L-SC TO L-ALPHA
                END-IF
                IF L-ALPHA >= L-BETA
                    MOVE 1 TO L-CUT
                END-IF
            END-IF
        END-IF
    END-PERFORM
    IF L-STOP = 1
        MOVE 0 TO LK-RES
        GOBACK
    END-IF
    IF L-LEG = 0
        IF L-CHK = 1
            COMPUTE L-BEST = 0 - (MATE-V - L-PLY)
        ELSE
            MOVE 0 TO L-BEST
        END-IF
    END-IF
    MOVE L-BEST TO LK-RES
    GOBACK.

*> ---------------- quiescence search (captures; all evasions when in check) ----------------
QS-SEARCH.
    ADD 1 TO NODES
    PERFORM CHECK-TIME
    MOVE LK-A TO L-PLY
    MOVE LK-C TO L-ALPHA
    MOVE LK-D TO L-BETA
    MOVE 0 TO L-STOP
    IF STOPNOW = 1
        MOVE 0 TO LK-RES
        GOBACK
    END-IF
    MOVE SIDE TO L-ME
    MOVE KSQ(L-ME + 1) TO ASQ
    COMPUTE ABY = 1 - L-ME
    PERFORM ATT-SQ
    MOVE AATT TO L-CHK
    IF L-PLY >= 120
        PERFORM EVAL-POS
        MOVE EV TO LK-RES
        GOBACK
    END-IF
    IF L-CHK = 0
        PERFORM EVAL-POS
        MOVE EV TO L-BEST
        IF L-BEST >= L-BETA
            MOVE L-BEST TO LK-RES
            GOBACK
        END-IF
        IF L-BEST > L-ALPHA
            MOVE L-BEST TO L-ALPHA
        END-IF
        MOVE 1 TO GCAP
    ELSE
        IF L-PLY >= ITERDEP + 4
            PERFORM EVAL-POS
            MOVE EV TO LK-RES
            GOBACK
        END-IF
        MOVE NEG-INF TO L-BEST
        MOVE 0 TO GCAP
    END-IF
    MOVE L-PLY TO GPLY
    PERFORM GEN-MOVES
    MOVE MCNT(L-PLY + 1) TO L-CNT
    COMPUTE L-MB = L-PLY * 256
    MOVE 0 TO L-LEG
    MOVE 0 TO L-CUT
    PERFORM VARYING L-I FROM 1 BY 1 UNTIL L-I > L-CNT OR L-CUT = 1
        PERFORM PICK-BEST
        COMPUTE L-IDX = L-MB + L-I
        MOVE MFR(L-IDX) TO L-F
        MOVE MTO(L-IDX) TO L-T
        MOVE MPR(L-IDX) TO L-P
        MOVE L-F TO W-F
        MOVE L-T TO W-T
        MOVE L-P TO W-P
        MOVE L-PLY TO W-PLY
        PERFORM MAKE-MOVE
        MOVE KSQ(L-ME + 1) TO ASQ
        MOVE SIDE TO ABY
        PERFORM ATT-SQ
        IF AATT = 0
            MOVE 1 TO L-OK
        ELSE
            MOVE 0 TO L-OK
        END-IF
        IF L-OK = 1
            ADD 1 TO L-LEG
            COMPUTE L-NA = L-PLY + 1
            COMPUTE L-NC = 0 - L-BETA
            COMPUTE L-ND = 0 - L-ALPHA
            CALL "CHESS" USING BY CONTENT OP-QS BY CONTENT L-NA
                BY CONTENT ZERO-V BY CONTENT L-NC BY CONTENT L-ND
                BY REFERENCE LK-STR BY REFERENCE L-RES
            COMPUTE L-SC = 0 - L-RES
        END-IF
        MOVE L-F TO W-F
        MOVE L-T TO W-T
        MOVE L-PLY TO W-PLY
        PERFORM UNMAKE-MOVE
        IF L-OK = 1
            IF STOPNOW = 1
                MOVE 1 TO L-STOP
                MOVE 1 TO L-CUT
            ELSE
                IF L-SC > L-BEST
                    MOVE L-SC TO L-BEST
                END-IF
                IF L-SC > L-ALPHA
                    MOVE L-SC TO L-ALPHA
                END-IF
                IF L-ALPHA >= L-BETA
                    MOVE 1 TO L-CUT
                END-IF
            END-IF
        END-IF
    END-PERFORM
    IF L-STOP = 1
        MOVE 0 TO LK-RES
        GOBACK
    END-IF
    IF L-CHK = 1 AND L-LEG = 0
        COMPUTE L-BEST = 0 - (MATE-V - L-PLY)
    END-IF
    MOVE L-BEST TO LK-RES
    GOBACK.

*> ---------------- top-level iterative deepening ----------------
SEARCH-TOP.
    MOVE LK-A TO L-MAXD
    MOVE LK-B TO TLIMIT
    MOVE 0 TO STOPNOW
    MOVE 0 TO NODES
    MOVE 0 TO DONE-DEPTH
    MOVE 0 TO RB-F
    MOVE 0 TO PREV-F
    MOVE 0 TO L-FOUND
    PERFORM NOW-CLOCK
    MOVE NOW-MS TO START-MS
    MOVE 1 TO L-ITER
    PERFORM UNTIL L-ITER > L-MAXD OR STOPNOW = 1 OR L-FOUND = 1
        MOVE L-ITER TO ITERDEP
        MOVE 0 TO RB-F
        CALL "CHESS" USING BY CONTENT OP-NODE BY CONTENT ZERO-V
            BY CONTENT L-ITER BY CONTENT NEG-INF BY CONTENT POS-INF
            BY REFERENCE LK-STR BY REFERENCE L-RES
        IF STOPNOW = 0 AND RB-F > 0
            MOVE L-ITER TO DONE-DEPTH
            MOVE RB-F TO PREV-F
            MOVE RB-T TO PREV-T
            MOVE RB-P TO PREV-P
            MOVE L-RES TO L-SCORE
                PERFORM PRINT-INFO
            IF L-SCORE > MATE-V - 1000
                MOVE 1 TO L-FOUND
            END-IF
        END-IF
        ADD 1 TO L-ITER
    END-PERFORM
    IF PREV-F = 0
        PERFORM FIRST-LEGAL
    END-IF
    IF PREV-F = 0
        MOVE "0000" TO LK-STR
    ELSE
        MOVE PREV-F TO MV-F
        MOVE PREV-T TO MV-T
        MOVE PREV-P TO MV-P
        PERFORM MOVE-TXT
        MOVE MV-TXT TO LK-STR
    END-IF
    MOVE 0 TO LK-RES.

*> Fallback when no iteration completed: the first legal root move, if any.
FIRST-LEGAL.
    MOVE 0 TO GPLY
    MOVE 0 TO GCAP
    PERFORM GEN-MOVES
    MOVE SIDE TO L-ME
    MOVE 0 TO L-OK
    PERFORM VARYING L-I FROM 1 BY 1 UNTIL L-I > MCNT(1) OR L-OK = 1
        MOVE MFR(L-I) TO W-F
        MOVE MTO(L-I) TO W-T
        MOVE MPR(L-I) TO W-P
        MOVE 0 TO W-PLY
        PERFORM MAKE-MOVE
        MOVE KSQ(L-ME + 1) TO ASQ
        MOVE SIDE TO ABY
        PERFORM ATT-SQ
        IF AATT = 0
            MOVE 1 TO L-OK
            MOVE W-F TO PREV-F
            MOVE W-T TO PREV-T
            MOVE W-P TO PREV-P
        END-IF
        MOVE MFR(L-I) TO W-F
        MOVE MTO(L-I) TO W-T
        MOVE 0 TO W-PLY
        PERFORM UNMAKE-MOVE
    END-PERFORM.

*> Prints one "info" line for the completed iteration L-ITER.
PRINT-INFO.
    PERFORM NOW-CLOCK
    COMPUTE T-ELAPSED = NOW-MS - START-MS
    IF T-ELAPSED < 0
        ADD 86400000 TO T-ELAPSED
    END-IF
    MOVE L-ITER TO INFO-DEPTH
    MOVE NODES TO INFO-NODES
    MOVE T-ELAPSED TO INFO-TIME
    IF T-ELAPSED > 0
        COMPUTE NPS-W = NODES * 1000 / T-ELAPSED
    ELSE
        MOVE 0 TO NPS-W
    END-IF
    MOVE NPS-W TO INFO-NPS
    MOVE PREV-F TO MV-F
    MOVE PREV-T TO MV-T
    MOVE PREV-P TO MV-P
    PERFORM MOVE-TXT
    IF L-SCORE > MATE-V - 1000
        COMPUTE MATE-N = (MATE-V - L-SCORE + 1) / 2
        MOVE MATE-N TO INFO-CP
        DISPLAY "info depth " FUNCTION TRIM(INFO-DEPTH)
            " score mate " FUNCTION TRIM(INFO-CP)
            " nodes " FUNCTION TRIM(INFO-NODES)
            " time " FUNCTION TRIM(INFO-TIME)
            " nps " FUNCTION TRIM(INFO-NPS)
            " pv " FUNCTION TRIM(MV-TXT)
    ELSE
        IF L-SCORE < 0 - (MATE-V - 1000)
            COMPUTE MATE-N = (MATE-V + L-SCORE + 1) / 2
            COMPUTE MATE-N = 0 - MATE-N
            MOVE MATE-N TO INFO-CP
            DISPLAY "info depth " FUNCTION TRIM(INFO-DEPTH)
                " score mate " FUNCTION TRIM(INFO-CP)
                " nodes " FUNCTION TRIM(INFO-NODES)
                " time " FUNCTION TRIM(INFO-TIME)
                " nps " FUNCTION TRIM(INFO-NPS)
                " pv " FUNCTION TRIM(MV-TXT)
        ELSE
            MOVE L-SCORE TO INFO-CP
            DISPLAY "info depth " FUNCTION TRIM(INFO-DEPTH)
                " score cp " FUNCTION TRIM(INFO-CP)
                " nodes " FUNCTION TRIM(INFO-NODES)
                " time " FUNCTION TRIM(INFO-TIME)
                " nps " FUNCTION TRIM(INFO-NPS)
                " pv " FUNCTION TRIM(MV-TXT)
        END-IF
    END-IF.

*> ---------------- perft ----------------
PERFT-NODE.
    MOVE LK-A TO L-PLY
    MOVE LK-B TO L-DEP
    MOVE SIDE TO L-ME
    MOVE L-PLY TO GPLY
    MOVE 0 TO GCAP
    PERFORM GEN-MOVES
    MOVE MCNT(L-PLY + 1) TO L-CNT
    COMPUTE L-MB = L-PLY * 256
    MOVE 0 TO L-TOT
    PERFORM VARYING L-I FROM 1 BY 1 UNTIL L-I > L-CNT
        COMPUTE L-IDX = L-MB + L-I
        MOVE MFR(L-IDX) TO L-F
        MOVE MTO(L-IDX) TO L-T
        MOVE MPR(L-IDX) TO L-P
        MOVE L-F TO W-F
        MOVE L-T TO W-T
        MOVE L-P TO W-P
        MOVE L-PLY TO W-PLY
        PERFORM MAKE-MOVE
        MOVE KSQ(L-ME + 1) TO ASQ
        MOVE SIDE TO ABY
        PERFORM ATT-SQ
        IF AATT = 0
            IF L-DEP <= 1
                ADD 1 TO L-TOT
            ELSE
                COMPUTE L-NA = L-PLY + 1
                COMPUTE L-NB = L-DEP - 1
                CALL "CHESS" USING BY CONTENT OP-PERFT BY CONTENT L-NA
                    BY CONTENT L-NB BY CONTENT ZERO-V BY CONTENT ZERO-V
                    BY REFERENCE LK-STR BY REFERENCE L-RES
                ADD L-RES TO L-TOT
            END-IF
        END-IF
        MOVE L-F TO W-F
        MOVE L-T TO W-T
        MOVE L-PLY TO W-PLY
        PERFORM UNMAKE-MOVE
    END-PERFORM
    MOVE L-TOT TO LK-RES.

*> Root of perft: prints "move: count" per legal move, then the total.
PERFT-TOP.
    MOVE LK-A TO L-DEP
    MOVE SIDE TO L-ME
    MOVE 0 TO GPLY
    MOVE 0 TO GCAP
    PERFORM GEN-MOVES
    MOVE MCNT(1) TO L-CNT
    MOVE 0 TO L-MB
    MOVE 0 TO L-TOT
    PERFORM VARYING L-I FROM 1 BY 1 UNTIL L-I > L-CNT
        MOVE MFR(L-I) TO L-F
        MOVE MTO(L-I) TO L-T
        MOVE MPR(L-I) TO L-P
        MOVE L-F TO W-F
        MOVE L-T TO W-T
        MOVE L-P TO W-P
        MOVE 0 TO W-PLY
        PERFORM MAKE-MOVE
        MOVE KSQ(L-ME + 1) TO ASQ
        MOVE SIDE TO ABY
        PERFORM ATT-SQ
        MOVE 0 TO L-SC
        IF AATT = 0
            MOVE 1 TO L-OK
            IF L-DEP <= 1
                MOVE 1 TO L-SC
            ELSE
                COMPUTE L-NB = L-DEP - 1
                CALL "CHESS" USING BY CONTENT OP-PERFT BY CONTENT ONE-V
                    BY CONTENT L-NB BY CONTENT ZERO-V BY CONTENT ZERO-V
                    BY REFERENCE LK-STR BY REFERENCE L-RES
                MOVE L-RES TO L-SC
            END-IF
        ELSE
            MOVE 0 TO L-OK
        END-IF
        MOVE L-F TO W-F
        MOVE L-T TO W-T
        MOVE 0 TO W-PLY
        PERFORM UNMAKE-MOVE
        IF L-OK = 1
            ADD L-SC TO L-TOT
            MOVE L-F TO MV-F
            MOVE L-T TO MV-T
            MOVE L-P TO MV-P
            PERFORM MOVE-TXT
            MOVE L-SC TO CNT-ED
            DISPLAY FUNCTION TRIM(MV-TXT) ": " FUNCTION TRIM(CNT-ED)
        END-IF
    END-PERFORM
    MOVE L-TOT TO TOT-ED
    DISPLAY "Nodes searched: " FUNCTION TRIM(TOT-ED)
    MOVE 0 TO LK-RES.

END PROGRAM CHESS.
