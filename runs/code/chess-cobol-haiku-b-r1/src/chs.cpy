      *> Shared chess state (EXTERNAL: every program that COPYs this sees the same storage).
      *> Board: 1-based mailbox, 10 columns wide. Square = 22 + file + 10*rank (a1=22, h8=99).
      *> Piece types: 0 empty, 1 P, 2 N, 3 B, 4 R, 5 Q, 6 K, 9 off-board.
      *> Colour: 0 white, 1 black, 2 none (empty or off-board).
       01 CHS EXTERNAL.
          05 B-PT     PIC S9(4) COMP-5 OCCURS 120.
          05 B-COL    PIC S9(4) COMP-5 OCCURS 120.
          05 B-SIDE   PIC S9(4) COMP-5.
          05 B-CR     PIC S9(4) COMP-5 OCCURS 4.
          05 B-EPS    PIC S9(4) COMP-5.
          05 B-KSQ    PIC S9(4) COMP-5 OCCURS 2.
          05 B-MAT    PIC S9(9) COMP-5.
          05 B-VAL    PIC S9(9) COMP-5 OCCURS 10.
          05 B-NOFF   PIC S9(4) COMP-5 OCCURS 8.
          05 B-KOFF   PIC S9(4) COMP-5 OCCURS 8.
          05 B-SP     PIC S9(9) COMP-5.
          05 B-NODES  PIC S9(18) COMP-5.
          05 B-CNT    PIC S9(9) COMP-5.
          05 B-ABRT   PIC S9(4) COMP-5.
          05 B-TLIM   PIC S9(9) COMP-5.
          05 B-T0     PIC S9(9) COMP-5.
          05 B-ITERD  PIC S9(4) COMP-5.
          05 B-BMF    PIC S9(4) COMP-5.
          05 B-BMT    PIC S9(4) COMP-5.
          05 B-BMP    PIC S9(4) COMP-5.
          05 B-STOPREQ PIC S9(4) COMP-5.
          05 B-QUITREQ PIC S9(4) COMP-5.
          05 B-UFR    PIC S9(4) COMP-5 OCCURS 1024.
          05 B-UTO    PIC S9(4) COMP-5 OCCURS 1024.
          05 B-UPT    PIC S9(4) COMP-5 OCCURS 1024.
          05 B-UCT    PIC S9(4) COMP-5 OCCURS 1024.
          05 B-UCC    PIC S9(4) COMP-5 OCCURS 1024.
          05 B-UCS    PIC S9(4) COMP-5 OCCURS 1024.
          05 B-UEP    PIC S9(4) COMP-5 OCCURS 1024.
          05 B-UCR    PIC S9(4) COMP-5 OCCURS 4096.
       01 MVL EXTERNAL.
          05 M-FR     PIC S9(4) COMP-5 OCCURS 16384.
          05 M-TO     PIC S9(4) COMP-5 OCCURS 16384.
          05 M-PR     PIC S9(4) COMP-5 OCCURS 16384.
          05 M-SC     PIC S9(9) COMP-5 OCCURS 16384.
