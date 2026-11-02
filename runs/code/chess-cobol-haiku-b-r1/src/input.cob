       IDENTIFICATION DIVISION.
       PROGRAM-ID. INPIO.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "chs.cpy".
       01 IBUF      PIC X(65536).
       01 IBLEN     PIC S9(9) COMP-5 VALUE 0.
       01 TMPB      PIC X(65536).
       01 TMPPTR    USAGE POINTER.
       01 INITED    PIC S9(4) COMP-5 VALUE 0.
       01 ZERODD    PIC S9(9) COMP-5 VALUE 0.
       01 F4DD      PIC S9(9) COMP-5 VALUE 4.
       01 NBDD      PIC S9(9) COMP-5 VALUE 2048.
       01 RDLEN     PIC S9(9) COMP-5 VALUE 4096.
       01 RDN       PIC S9(9) COMP-5.
       01 USWAIT    PIC S9(9) COMP-5 VALUE 1000.
       01 IX        PIC S9(9) COMP-5.
       01 LFPOS     PIC S9(9) COMP-5.
       01 LLEN      PIC S9(9) COMP-5.
       01 REMN      PIC S9(9) COMP-5.
       01 DONE      PIC S9(4) COMP-5.
       01 LN2       PIC X(4096).
       LINKAGE SECTION.
       01 LK-MODE   PIC S9(4) COMP-5.
       01 LK-LINE   PIC X(4096).
       01 LK-STATE  PIC S9(4) COMP-5.
      *> LK-MODE 1: block until a full line is read (LK-STATE 1) or input ends (LK-STATE 2).
      *> LK-MODE 2: poll during a search; consume stop/quit/isready lines, never block.
       PROCEDURE DIVISION USING LK-MODE LK-LINE LK-STATE.
       IO-MAIN.
           IF INITED = 0
               MOVE 1 TO INITED
               CALL "fcntl" USING BY VALUE ZERODD BY VALUE F4DD BY VALUE NBDD
           END-IF
           MOVE 0 TO LK-STATE
           MOVE 0 TO DONE
           PERFORM UNTIL DONE = 1
               PERFORM FIND-LF
               IF LFPOS > 0
                   PERFORM TAKE-LINE
                   IF LK-MODE = 1
                       MOVE LN2 TO LK-LINE
                       MOVE 1 TO LK-STATE
                       MOVE 1 TO DONE
                   ELSE
                       PERFORM HANDLE-LINE
                   END-IF
               ELSE
                   PERFORM READ-CHUNK
                   IF RDN = 0
                       MOVE 2 TO LK-STATE
                       MOVE 1 TO B-QUITREQ
                       MOVE 1 TO DONE
                   ELSE
                       IF RDN < 0
                           IF LK-MODE = 1
                               CALL "usleep" USING BY VALUE USWAIT
                           ELSE
                               MOVE 1 TO DONE
                           END-IF
                       END-IF
                   END-IF
               END-IF
           END-PERFORM
           GOBACK.

       FIND-LF.
           MOVE 0 TO LFPOS
           PERFORM VARYING IX FROM 1 BY 1 UNTIL IX > IBLEN OR LFPOS > 0
               IF IBUF(IX:1) = X"0A"
                   MOVE IX TO LFPOS
               END-IF
           END-PERFORM.

       TAKE-LINE.
           COMPUTE LLEN = LFPOS - 1
           MOVE SPACES TO LN2
           IF LLEN > 0
               MOVE IBUF(1:LLEN) TO LN2
           END-IF
           COMPUTE REMN = IBLEN - LFPOS
           IF REMN > 0
               MOVE IBUF(LFPOS + 1:REMN) TO TMPB(1:REMN)
               MOVE TMPB(1:REMN) TO IBUF(1:REMN)
           END-IF
           MOVE REMN TO IBLEN.

       READ-CHUNK.
           SET TMPPTR TO ADDRESS OF TMPB
           CALL "read" USING BY VALUE ZERODD BY VALUE TMPPTR BY VALUE RDLEN
           MOVE RETURN-CODE TO RDN
           IF RDN > 0 AND IBLEN + RDN <= 65536
               MOVE TMPB(1:RDN) TO IBUF(IBLEN + 1:RDN)
               ADD RDN TO IBLEN
           END-IF.

       HANDLE-LINE.
           IF LN2(1:4) = "stop"
               MOVE 1 TO B-STOPREQ
           END-IF
           IF LN2(1:4) = "quit"
               MOVE 1 TO B-STOPREQ
               MOVE 1 TO B-QUITREQ
           END-IF
           IF LN2(1:7) = "isready"
               DISPLAY "readyok"
               CALL "fflush" USING BY VALUE 0
           END-IF.
       END PROGRAM INPIO.
