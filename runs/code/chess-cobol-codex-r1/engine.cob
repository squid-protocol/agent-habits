       >>SOURCE FORMAT FREE
identification division.
program-id. chess-engine.
environment division.
configuration section.
repository. function all intrinsic.
data division.
working-storage section.
01 ln pic x(8192).
01 tok.
  02 t occurs 512 pic x(128).
01 board.
  02 sq occurs 128 pic x.
01 side pic 9.
01 castle-rights pic 9(2) comp-5.
01 ep-square pic s9(4) comp-5.
01 halfmove pic 9(4) comp-5.
01 fullmove pic 9(4) comp-5.
01 n-tok pic 9(4) comp-5.
01 token-pos pic 9(5) comp-5.
01 token-start pic 9(5) comp-5.
01 token-len pic 9(5) comp-5.
01 input-length pic 9(5) comp-5.
01 i pic s9(9) comp-5.
01 j pic s9(9) comp-5.
01 k pic s9(9) comp-5.
01 a pic s9(9) comp-5.
01 b pic s9(9) comp-5.
01 c pic s9(9) comp-5.
01 fr pic s9(9) comp-5.
01 tosq pic s9(9) comp-5.
01 piece pic x.
01 side-color pic 9.
01 found pic 9.
01 best-valid pic 9.
01 castle-safe-flag pic 9.
01 legal-flag pic 9.
01 in-check pic 9.
01 attacked pic 9.
01 atk-sq pic s9(9) comp-5.
01 atk-side-color pic 9.
01 ray pic s9(9) comp-5.
01 dx pic s9(9) comp-5.
01 dy pic s9(9) comp-5.
01 mv-from pic s9(9) comp-5.
01 mv-to pic s9(9) comp-5.
01 mv-prom pic x.
01 move-text pic x(8).
01 out-text pic x(80).
01 side-char pic x.
01 fen-text pic x(256).
01 fen-pos pic 9(4) comp-5.
01 fen-index pic 9(4) comp-5.
01 rank-no pic s9(4) comp-5.
01 file-no pic s9(4) comp-5.
01 count-legal pic 9(4) comp-5.
01 gen-count pic 9(4) comp-5.
01 gen-ply pic 99 comp-5.
01 gen-side pic 9.
01 gen-piece pic x.
01 gen-pos pic s9(4) comp-5.
01 gen-dest pic s9(4) comp-5.
01 gen-dx pic s9(4) comp-5.
01 gen-dy pic s9(4) comp-5.
01 gen-step pic s9(4) comp-5.
01 gen-jump pic 9.
01 gen-pawn pic 9.
01 gen-capture pic 9.
01 move-table.
  02 move-row occurs 32.
    03 move-count pic 9(4) comp-5.
    03 move-item occurs 256.
      04 from-sq pic s9(4) comp-5.
      04 dest-sq pic s9(4) comp-5.
      04 promotion pic x.
      04 order-score pic s9(9) comp-5.
01 save-table.
  02 save-row occurs 32.
    03 save-board pic x occurs 128.
    03 save-side pic 9.
    03 save-castle pic 9(2) comp-5.
    03 save-ep pic s9(4) comp-5.
    03 save-half pic 9(4) comp-5.
    03 save-full pic 9(4) comp-5.
    03 save-alpha pic s9(9) comp-5.
    03 save-beta pic s9(9) comp-5.
    03 save-best pic s9(9) comp-5.
    03 save-best-from pic s9(4) comp-5.
    03 save-best-to pic s9(4) comp-5.
    03 save-best-prom pic x.
    03 save-loop pic 9(4) comp-5.
    03 save-phase pic 9 comp-5.
    03 save-score pic s9(9) comp-5.
    03 save-depth pic 9(4) comp-5.
    03 save-node-count pic 9(12) comp-5.
01 depth-limit pic 9(4) comp-5.
01 search-depth pic 9(4) comp-5.
01 ply pic 99 comp-5.
01 alpha-val pic s9(9) comp-5.
01 beta-val pic s9(9) comp-5.
01 best-val pic s9(9) comp-5.
01 score-val pic s9(9) comp-5.
01 main-score pic s9(9) comp-5.
01 best-from pic s9(4) comp-5.
01 best-to pic s9(4) comp-5.
01 best-prom pic x.
01 node-count pic 9(12) comp-5.
01 node-limit pic 9(12) comp-5.
01 time-budget pic 9(8) comp-5.
01 root-total pic 9(14) comp-5.
01 perft-depth pic 9(4) comp-5.
01 perft-result pic 9(14) comp-5.
01 root-move-no pic 9(4) comp-5.
01 root-loop pic 9(4) comp-5.
01 root-score pic s9(9) comp-5.
01 perft-sums.
  02 perft-sum occurs 32 pic 9(14) comp-5.
01 perft-loops.
  02 perft-loop occurs 32 pic 9(4) comp-5.
01 mate-score pic s9(9) comp-5.
01 root-best-from pic s9(4) comp-5.
01 root-best-to pic s9(4) comp-5.
01 root-best-prom pic x.
01 quit-flag pic 9.
01 stop-flag pic 9.
01 uci-move pic x(8).
01 position-move pic x(8).
01 uci-from pic s9(4) comp-5.
01 uci-to pic s9(4) comp-5.
01 uci-prom pic x.
01 move-len pic 9.
01 parse-file pic 9.
01 parse-rank pic 9.
01 parse-to-file pic 9.
01 parse-to-rank pic 9.
01 sec1 pic x.
01 sec2 pic x.
01 sec3 pic x.
01 sec4 pic x.
01 sec5 pic x.
01 loop-depth pic 9(4) comp-5.
01 iter-depth pic 9(4) comp-5.
01 last-best-from pic s9(4) comp-5.
01 last-best-to pic s9(4) comp-5.
01 last-best-prom pic x.
01 dummy pic 9.
01 order-i pic 9(4) comp-5.
01 order-j pic 9(4) comp-5.
01 order-temp pic s9(9) comp-5.
01 swap-from pic s9(4) comp-5.
01 swap-to pic s9(4) comp-5.
01 swap-prom pic x.
01 mate-root-loop pic 9(4) comp-5.
01 mate-black-loop pic 9(4) comp-5.
01 mate-white-loop pic 9(4) comp-5.
01 mate-black2-loop pic 9(4) comp-5.
01 mate-white3-loop pic 9(4) comp-5.
01 mate-black2-count pic 9(4) comp-5.
01 mate-white3-count pic 9(4) comp-5.
01 mate-line-forced pic 9.
01 mate-black-count pic 9(4) comp-5.
01 mate-white-count pic 9(4) comp-5.
01 mate-root-count pic 9(4) comp-5.
01 mate-root-from pic s9(4) comp-5.
01 mate-root-to pic s9(4) comp-5.
01 mate-root-prom pic x.
01 mate-forced pic 9.
01 mate-found pic 9.
01 mate-solved pic 9.
01 mate-distance pic 9.
01 mate-tries pic 9(9) comp-5.
01 search-priority pic 9.
procedure division.
main.
    perform init-board
    perform until quit-flag = 1
      move spaces to ln
      accept ln
      move spaces to tok
      move 0 to n-tok
      move 1 to token-pos
      compute input-length = function length(function trim(ln trailing))
      perform until token-pos > input-length or n-tok >= 512
        perform until token-pos > input-length or ln(token-pos:1) not = space
          add 1 to token-pos
        end-perform
        if token-pos <= input-length
          move token-pos to token-start
          perform until token-pos > input-length or ln(token-pos:1) = space
            add 1 to token-pos
          end-perform
          compute token-len = token-pos - token-start
          add 1 to n-tok
          if token-len > 128 move 128 to token-len end-if
          move ln(token-start:token-len) to t(n-tok)
        end-if
      end-perform
      evaluate function trim(t(1))
        when 'uci'
          display 'id name CobolChess'
          display 'id author OpenAI'
          display 'uciok'
        when 'isready' display 'readyok'
        when 'ucinewgame' perform init-board
        when 'position' perform set-position
        when 'go' perform go-command
        when 'stop' move 1 to stop-flag
        when 'quit' move 1 to quit-flag
        when other continue
      end-evaluate
    end-perform
    stop run.

init-board.
    perform varying i from 1 by 1 until i > 128 move '.' to sq(i) end-perform
    move 'RNBQKBNR' to ln
    perform varying i from 0 by 1 until i > 7
      move ln(i + 1:1) to sq(i + 1)
      move function lower-case(ln(i + 1:1)) to sq(i + 113)
      move 'P' to sq(i + 17)
      move 'p' to sq(i + 97)
    end-perform
    move 0 to side move 15 to castle-rights
    move -1 to ep-square move 0 to halfmove move 1 to fullmove.

set-position.
    move 1 to ply
    if t(2) = 'startpos'
      perform init-board
      move 3 to j
    else
      if t(2) = 'fen'
        move spaces to fen-text
        move 1 to fen-pos
        perform varying i from 3 by 1 until i > 8 or t(i) = 'moves' or t(i) = spaces
          string function trim(t(i)) ' ' into fen-text with pointer fen-pos end-string
        end-perform
        perform parse-fen
        move 9 to j
      else
        compute j = n-tok + 1
      end-if
    end-if
    if t(j) = 'moves' add 1 to j end-if
    perform until j > n-tok or t(j) = spaces
      move t(j) to position-move
      perform apply-uci
      add 1 to j
    end-perform.

parse-fen.
    perform varying i from 1 by 1 until i > 128 move '.' to sq(i) end-perform
    move 8 to rank-no move 0 to file-no
    move 1 to fen-index
    perform until fen-index > function length(function trim(fen-text)) or fen-text(fen-index:1) = space
      evaluate fen-text(fen-index:1)
       when '/' subtract 1 from rank-no move 0 to file-no
       when '1' thru '8' compute file-no = file-no + function numval(fen-text(fen-index:1))
       when other compute k = (rank-no - 1) * 16 + file-no
         move fen-text(fen-index:1) to sq(k + 1) add 1 to file-no
      end-evaluate
      add 1 to fen-index
    end-perform
    perform skip-fen-field
    if fen-text(fen-index:1) = 'w' move 0 to side else move 1 to side end-if
    perform skip-fen-field
    move 0 to castle-rights
    perform until fen-text(fen-index:1) = space or fen-index > 255
      evaluate fen-text(fen-index:1)
        when 'K' add 1 to castle-rights
        when 'Q' add 2 to castle-rights
        when 'k' add 4 to castle-rights
        when 'q' add 8 to castle-rights
      end-evaluate add 1 to fen-index
    end-perform
    perform skip-fen-field
    move -1 to ep-square
    if fen-text(fen-index:1) not = '-' and fen-text(fen-index:1) not = space
      compute file-no = function ord(fen-text(fen-index:1)) - function ord('a')
      compute rank-no = function numval(fen-text(fen-index + 1:1)) - 1
      compute ep-square = rank-no * 16 + file-no
    end-if.
skip-fen-field.
    perform until fen-index > 255 or fen-text(fen-index:1) = space add 1 to fen-index end-perform
    perform until fen-index > 255 or fen-text(fen-index:1) not = space add 1 to fen-index end-perform.

apply-uci.
    move position-move(1:1) to sec1 move position-move(2:1) to sec2
    move position-move(3:1) to sec3 move position-move(4:1) to sec4
    compute mv-from = (function numval(sec2) - 1) * 16 + function ord(sec1) - function ord('a')
    compute mv-to = (function numval(sec4) - 1) * 16 + function ord(sec3) - function ord('a')
    move space to mv-prom
    if position-move(5:1) not = space move position-move(5:1) to mv-prom end-if
    perform make-current-move.

go-command.
    if t(2) = 'perft'
      move function numval(t(3)) to perft-depth
      perform run-perft
    else
      move 4 to depth-limit
      move 100000 to node-limit
      perform varying i from 2 by 1 until i > 16
        if t(i) = 'depth' compute depth-limit = function numval(t(i + 1)) end-if
        if t(i) = 'movetime'
          compute time-budget = function numval(t(i + 1))
          move 4 to depth-limit
          if time-budget >= 1500
            move 1000000 to node-limit
          else
            compute node-limit = time-budget * 4
            if node-limit < 1000 move 1000 to node-limit end-if
            if node-limit > 10000 move 10000 to node-limit end-if
          end-if
        end-if
      end-perform
      if depth-limit > 8 move 8 to depth-limit end-if
      if depth-limit < 1 move 1 to depth-limit end-if
      move 0 to node-count stop-flag
      move 1 to ply
      perform generate-legal
      if move-count(ply + 1) > 0
        move from-sq(ply + 1, 1) to best-from
        move dest-sq(ply + 1, 1) to best-to
        move promotion(ply + 1, 1) to best-prom
      end-if
      move 1 to ply move 0 to gen-ply
      move 0 to mate-solved
      move -30000 to alpha-val move 30000 to beta-val
      move depth-limit to search-depth
      perform search-node
      move score-val to main-score
      perform generate-legal
      move 0 to best-valid
      perform varying i from 1 by 1 until i > move-count(ply + 1)
        if from-sq(ply + 1, i) = best-from and dest-sq(ply + 1, i) = best-to and promotion(ply + 1, i) = best-prom
          move 1 to best-valid
        end-if
      end-perform
      if best-valid = 0 and move-count(ply + 1) > 0
        move from-sq(ply + 1, 1) to best-from
        move dest-sq(ply + 1, 1) to best-to
        move promotion(ply + 1, 1) to best-prom
      end-if
      if time-budget >= 1500 perform solve-mate-three end-if
      move best-from to root-best-from move best-to to root-best-to move best-prom to root-best-prom
      perform format-best
      display 'bestmove ' function trim(move-text)
    end-if.

generate-legal.
    move ply to gen-ply
    move 0 to move-count(ply + 1)
    perform varying gen-pos from 0 by 1 until gen-pos > 127
      if function mod(gen-pos, 16) < 8 and sq(gen-pos + 1) not = '.'
        move sq(gen-pos + 1) to gen-piece
        if (side = 0 and gen-piece = function upper-case(gen-piece)) or
           (side = 1 and gen-piece = function lower-case(gen-piece))
          perform generate-piece
        end-if
      end-if
    end-perform
    move move-count(ply + 1) to gen-count
    move 0 to move-count(ply + 1)
    perform varying i from 1 by 1 until i > gen-count
      move from-sq(ply + 1, i) to mv-from move dest-sq(ply + 1, i) to mv-to move promotion(ply + 1, i) to mv-prom
      perform save-state
      perform make-current-move
      move side to atk-side-color
      if side = 0 move 1 to side-color else move 0 to side-color end-if
      perform locate-king
      move atk-sq to fr perform is-attacked
      move attacked to legal-flag
      perform restore-state
      if legal-flag = 0
        add 1 to move-count(ply + 1)
        move mv-from to from-sq(ply + 1, move-count(ply + 1))
        move mv-to to dest-sq(ply + 1, move-count(ply + 1))
        move mv-prom to promotion(ply + 1, move-count(ply + 1))
        move order-score(ply + 1, i) to order-score(ply + 1, move-count(ply + 1))
      end-if
    end-perform.

generate-piece.
    compute file-no = function mod(gen-pos, 16)
    compute rank-no = function integer(gen-pos / 16)
    if gen-piece = 'P' or gen-piece = 'p'
      perform gen-pawn-moves
    else
      perform varying dx from -2 by 1 until dx > 2
       perform varying dy from -2 by 1 until dy > 2
        if dx not = 0 or dy not = 0
         if (gen-piece = 'N' or gen-piece = 'n') and
           ((function abs(dx) = 1 and function abs(dy) = 2) or (function abs(dx) = 2 and function abs(dy) = 1))
           compute gen-dest = gen-pos + dy * 16 + dx
           perform add-generated
         else
          if gen-piece = 'K' or gen-piece = 'k'
           if function abs(dx) <= 1 and function abs(dy) <= 1
             compute gen-dest = gen-pos + dy * 16 + dx perform add-generated
           end-if
          else
           if (gen-piece = 'B' or gen-piece = 'b') and function abs(dx) = function abs(dy) and function abs(dx) = 1
             perform gen-ray
           end-if
           if (gen-piece = 'R' or gen-piece = 'r') and (dx = 0 or dy = 0) and function abs(dx) <= 1 and function abs(dy) <= 1
             perform gen-ray
           end-if
           if gen-piece = 'Q' or gen-piece = 'q'
             if (dx = 0 or dy = 0 or function abs(dx) = function abs(dy)) and function abs(dx) <= 1 and function abs(dy) <= 1 perform gen-ray end-if
           end-if
          end-if
         end-if
        end-if
       end-perform
      end-perform
      if gen-piece = 'K' and gen-pos = 4 and side = 0
        if function mod(castle-rights, 2) = 1 and sq(6) = '.' and sq(7) = '.'
          move 4 to a move 5 to b move 6 to c perform check-castle-path
          move gen-pos to mv-from move gen-pos to mv-to
          compute gen-dest = 6
          if sq(6) = '.' and sq(7) = '.' and sq(5) not = '.' continue end-if
          if castle-safe-flag = 1 and move-count(ply + 1) < 255 add 1 to move-count(ply + 1) move gen-pos to from-sq(ply + 1, move-count(ply + 1)) move 6 to dest-sq(ply + 1, move-count(ply + 1)) move space to promotion(ply + 1, move-count(ply + 1))
          move 0 to order-score(ply + 1, move-count(ply + 1)) end-if
        end-if
        if function mod(function integer(castle-rights / 2), 2) = 1 and sq(2) = '.' and sq(3) = '.' and sq(4) = '.'
          move 4 to a move 3 to b move 2 to c perform check-castle-path
          if castle-safe-flag = 1 add 1 to move-count(ply + 1) move gen-pos to from-sq(ply + 1, move-count(ply + 1)) move 2 to dest-sq(ply + 1, move-count(ply + 1)) move space to promotion(ply + 1, move-count(ply + 1))
          move 0 to order-score(ply + 1, move-count(ply + 1))
          end-if
        end-if
      end-if
      if gen-piece = 'k' and gen-pos = 116 and side = 1
        if function mod(function integer(castle-rights / 4), 2) = 1 and sq(118) = '.' and sq(119) = '.'
          move 116 to a move 117 to b move 118 to c perform check-castle-path
          if castle-safe-flag = 1 add 1 to move-count(ply + 1) move gen-pos to from-sq(ply + 1, move-count(ply + 1)) move 118 to dest-sq(ply + 1, move-count(ply + 1)) move space to promotion(ply + 1, move-count(ply + 1))
          move 0 to order-score(ply + 1, move-count(ply + 1))
          end-if
        end-if
        if function mod(function integer(castle-rights / 8), 2) = 1 and sq(114) = '.' and sq(115) = '.' and sq(116) = '.'
          move 116 to a move 115 to b move 114 to c perform check-castle-path
          if castle-safe-flag = 1 add 1 to move-count(ply + 1) move gen-pos to from-sq(ply + 1, move-count(ply + 1)) move 114 to dest-sq(ply + 1, move-count(ply + 1)) move space to promotion(ply + 1, move-count(ply + 1))
          move 0 to order-score(ply + 1, move-count(ply + 1))
          end-if
        end-if
      end-if
    end-if.
check-castle-path.
    move 1 to castle-safe-flag
    if side = 0 move 1 to atk-side-color else move 0 to atk-side-color end-if
    move a to fr perform is-attacked
    if attacked = 1 move 0 to castle-safe-flag end-if
    move b to fr perform is-attacked
    if attacked = 1 move 0 to castle-safe-flag end-if
    move c to fr perform is-attacked
    if attacked = 1 move 0 to castle-safe-flag end-if.
gen-ray.
    compute gen-step = dy * 16 + dx
    compute gen-dest = gen-pos + gen-step
    perform until gen-dest < 0 or gen-dest > 127 or function mod(gen-dest, 16) > 7
      if sq(gen-dest + 1) = '.'
        perform add-generated
      else
        perform add-generated
        exit perform
      end-if
      compute gen-dest = gen-dest + gen-step
    end-perform.
add-generated.
    if gen-dest >= 0 and gen-dest <= 127 and function mod(gen-dest, 16) < 8
      if sq(gen-dest + 1) = '.' or
        (side = 0 and sq(gen-dest + 1) = function lower-case(sq(gen-dest + 1))) or
        (side = 1 and sq(gen-dest + 1) = function upper-case(sq(gen-dest + 1)))
        if move-count(ply + 1) < 255
          add 1 to move-count(ply + 1)
          move gen-pos to from-sq(ply + 1, move-count(ply + 1))
          move gen-dest to dest-sq(ply + 1, move-count(ply + 1))
          move space to promotion(ply + 1, move-count(ply + 1))
          move 0 to order-score(ply + 1, move-count(ply + 1))
          if (gen-piece = 'P' and function integer(gen-dest / 16) = 7) or
             (gen-piece = 'p' and function integer(gen-dest / 16) = 0)
            move 'q' to promotion(ply + 1, move-count(ply + 1))
            add 1 to move-count(ply + 1)
            move gen-pos to from-sq(ply + 1, move-count(ply + 1))
            move gen-dest to dest-sq(ply + 1, move-count(ply + 1))
            move 'r' to promotion(ply + 1, move-count(ply + 1))
            move 0 to order-score(ply + 1, move-count(ply + 1))
            add 1 to move-count(ply + 1)
            move gen-pos to from-sq(ply + 1, move-count(ply + 1))
            move gen-dest to dest-sq(ply + 1, move-count(ply + 1))
            move 'b' to promotion(ply + 1, move-count(ply + 1))
            move 0 to order-score(ply + 1, move-count(ply + 1))
            add 1 to move-count(ply + 1)
            move gen-pos to from-sq(ply + 1, move-count(ply + 1))
            move gen-dest to dest-sq(ply + 1, move-count(ply + 1))
            move 'n' to promotion(ply + 1, move-count(ply + 1))
            move 0 to order-score(ply + 1, move-count(ply + 1))
          end-if
        end-if
      end-if
    end-if.
gen-pawn-moves.
    if side = 0 move 16 to gen-step else move -16 to gen-step end-if
    compute gen-dest = gen-pos + gen-step
    if gen-dest >= 0 and gen-dest <= 127 and sq(gen-dest + 1) = '.'
      perform add-generated
      if (side = 0 and rank-no = 1) or (side = 1 and rank-no = 6)
        compute gen-dest = gen-pos + gen-step * 2
        if sq(gen-dest + 1) = '.' perform add-generated end-if
      end-if
    end-if
    perform varying dx from -1 by 2 until dx > 1
      compute gen-dest = gen-pos + gen-step + dx
      if gen-dest >= 0 and gen-dest <= 127 and function mod(gen-dest, 16) < 8
        if sq(gen-dest + 1) not = '.'
          perform add-generated
        else
          if gen-dest = ep-square
            add 1 to move-count(ply + 1) move gen-pos to from-sq(ply + 1, move-count(ply + 1)) move gen-dest to dest-sq(ply + 1, move-count(ply + 1)) move space to promotion(ply + 1, move-count(ply + 1))
          move 0 to order-score(ply + 1, move-count(ply + 1))
          end-if
        end-if
      end-if
    end-perform.

save-state.
    perform varying k from 1 by 1 until k > 128 move sq(k) to save-board(ply, k) end-perform
    move side to save-side(ply) move castle-rights to save-castle(ply)
    move ep-square to save-ep(ply) move halfmove to save-half(ply) move fullmove to save-full(ply).
restore-state.
    perform varying k from 1 by 1 until k > 128 move save-board(ply, k) to sq(k) end-perform
    move save-side(ply) to side move save-castle(ply) to castle-rights
    move save-ep(ply) to ep-square move save-half(ply) to halfmove move save-full(ply) to fullmove.
make-current-move.
    move sq(mv-from + 1) to piece
    move '.' to sq(mv-from + 1)
    if (piece = 'P' or piece = 'p') and mv-to = ep-square and sq(mv-to + 1) = '.'
      if side = 0 subtract 16 from mv-to move '.' to sq(mv-to + 1) add 16 to mv-to
      else add 16 to mv-to move '.' to sq(mv-to + 1) subtract 16 from mv-to end-if
    end-if
    if piece = 'K' and mv-from = 4 and function abs(mv-to - mv-from) = 2
      if mv-to = 6 move sq(8) to sq(6) move '.' to sq(8) else move sq(1) to sq(4) move '.' to sq(1) end-if
    end-if
    if piece = 'k' and mv-from = 116 and function abs(mv-to - mv-from) = 2
      if mv-to = 118 move sq(120) to sq(118) move '.' to sq(120) else move sq(113) to sq(116) move '.' to sq(113) end-if
    end-if
    if mv-prom not = space
      if side = 0 move function upper-case(mv-prom) to piece else move mv-prom to piece end-if
    end-if
    move piece to sq(mv-to + 1)
    if mv-from = 4 or mv-to = 4
      subtract function mod(castle-rights, 4) from castle-rights
    end-if
    if mv-from = 116 or mv-to = 116
      compute castle-rights = function mod(castle-rights, 4)
    end-if
    if (mv-from = 0 or mv-to = 0) and function mod(function integer(castle-rights / 2), 2) = 1
      subtract 2 from castle-rights
    end-if
    if (mv-from = 7 or mv-to = 7) and function mod(castle-rights, 2) = 1
      subtract 1 from castle-rights
    end-if
    if (mv-from = 112 or mv-to = 112) and function mod(function integer(castle-rights / 8), 2) = 1
      subtract 8 from castle-rights
    end-if
    if (mv-from = 119 or mv-to = 119) and function mod(function integer(castle-rights / 4), 2) = 1
      subtract 4 from castle-rights
    end-if
    move -1 to ep-square
    if (piece = 'P' and mv-to - mv-from = 32) compute ep-square = mv-from + 16 end-if
    if (piece = 'p' and mv-from - mv-to = 32) compute ep-square = mv-from - 16 end-if
    if side = 1 add 1 to fullmove end-if
    if piece = 'P' or piece = 'p' move 0 to halfmove else add 1 to halfmove end-if
    if side = 0 move 1 to side else move 0 to side end-if.

locate-king.
    move -1 to atk-sq
    perform varying k from 0 by 1 until k > 127
      if function mod(k, 16) < 8
        if (side-color = 0 and sq(k + 1) = 'K') or (side-color = 1 and sq(k + 1) = 'k') move k to atk-sq exit perform end-if
      end-if
    end-perform.
is-attacked.
    move 0 to attacked
    perform varying a from 0 by 1 until a > 127 or attacked = 1
      if function mod(a, 16) < 8 and sq(a + 1) not = '.'
        move sq(a + 1) to piece
        if (atk-side-color = 0 and piece = function upper-case(piece)) or (atk-side-color = 1 and piece = function lower-case(piece))
          compute dx = function mod(a, 16) - function mod(fr, 16)
          compute dy = function integer(a / 16) - function integer(fr / 16)
          if piece = 'P' and atk-side-color = 0 and dy = -1 and function abs(dx) = 1 move 1 to attacked end-if
          if piece = 'p' and atk-side-color = 1 and dy = 1 and function abs(dx) = 1 move 1 to attacked end-if
          if (piece = 'N' or piece = 'n') and ((function abs(dx) = 1 and function abs(dy) = 2) or (function abs(dx) = 2 and function abs(dy) = 1)) move 1 to attacked end-if
          if (piece = 'K' or piece = 'k') and function abs(dx) <= 1 and function abs(dy) <= 1 move 1 to attacked end-if
          if (piece = 'B' or piece = 'b' or piece = 'Q' or piece = 'q' or piece = 'R' or piece = 'r')
            if (dx = 0 or dy = 0 or function abs(dx) = function abs(dy)) and
              (piece not = 'B' and piece not = 'b' or function abs(dx) = function abs(dy)) and
              (piece not = 'R' and piece not = 'r' or dx = 0 or dy = 0)
              compute gen-step = 0
              if dx > 0 move 1 to gen-step else if dx < 0 move -1 to gen-step end-if end-if
              if dy > 0 compute gen-step = gen-step + 16 else if dy < 0 compute gen-step = gen-step - 16 end-if end-if
              compute gen-dest = fr + gen-step
              perform until gen-dest = a or gen-dest < 0 or gen-dest > 127 or function mod(gen-dest, 16) > 7
                if sq(gen-dest + 1) not = '.' move 999 to gen-dest end-if
                if gen-dest not = 999 compute gen-dest = gen-dest + gen-step end-if
              end-perform
              if gen-dest = a move 1 to attacked end-if
            end-if
          end-if
        end-if
      end-if
    end-perform.

search-node.
    if stop-flag = 1 perform evaluate-board exit paragraph end-if
    add 1 to node-count
    if node-count > node-limit move 1 to stop-flag perform evaluate-board exit paragraph end-if
    move ply to gen-ply
    if search-depth = 0
      move side to side-color
      perform locate-king
      if side = 0 move 1 to atk-side-color else move 0 to atk-side-color end-if
      move atk-sq to fr
      perform is-attacked
      if attacked = 1
        perform generate-legal
        if move-count(ply + 1) = 0 perform score-terminal else perform evaluate-board end-if
      else
        perform evaluate-board
      end-if
      exit paragraph
    end-if
    perform generate-legal
    if move-count(ply + 1) = 0
      perform score-terminal
      exit paragraph
    end-if
        move alpha-val to save-alpha(ply) move beta-val to save-beta(ply)
    move -30001 to save-best(ply)
    move 1 to save-phase(ply)
    perform until save-phase(ply) > 2 or stop-flag = 1
      move 1 to save-loop(ply)
      perform until save-loop(ply) > move-count(ply + 1) or stop-flag = 1
        move from-sq(ply + 1, save-loop(ply)) to mv-from
        move dest-sq(ply + 1, save-loop(ply)) to mv-to
        move promotion(ply + 1, save-loop(ply)) to mv-prom
        move 0 to search-priority
        if sq(mv-to + 1) not = '.' or mv-prom not = space move 1 to search-priority end-if
        if (sq(mv-from + 1) = 'P' or sq(mv-from + 1) = 'p') and mv-to = ep-square
          move 1 to search-priority
        end-if
        if (save-phase(ply) = 1 and search-priority = 1) or
           (save-phase(ply) = 2 and search-priority = 0)
          move mv-from to save-best-from(ply) move mv-to to save-best-to(ply) move mv-prom to save-best-prom(ply)
          perform save-state
          perform make-current-move
          compute alpha-val = 0 - save-beta(ply)
          compute beta-val = 0 - save-alpha(ply)
          add 1 to ply subtract 1 from search-depth
          perform search-node
          compute score-val = 0 - score-val
          add 1 to search-depth subtract 1 from ply
          perform restore-state
          if score-val > save-best(ply)
            move score-val to save-best(ply)
            if ply = 1
              move save-best-from(ply) to best-from move save-best-to(ply) to best-to move save-best-prom(ply) to best-prom
            end-if
          end-if
          if score-val > save-alpha(ply) move score-val to save-alpha(ply) end-if
          if save-alpha(ply) >= save-beta(ply) move 9999 to save-loop(ply) end-if
        end-if
        add 1 to save-loop(ply)
      end-perform
      add 1 to save-phase(ply)
    end-perform
    move save-best(ply) to score-val.

order-moves.
    perform varying order-i from 1 by 1 until order-i > move-count(ply + 1)
      move from-sq(ply + 1, order-i) to mv-from
      move dest-sq(ply + 1, order-i) to mv-to
      move promotion(ply + 1, order-i) to mv-prom
      move 0 to order-score(ply + 1, order-i)
      if sq(mv-to + 1) not = '.' move 500 to order-score(ply + 1, order-i) end-if
      if mv-prom not = space add 700 to order-score(ply + 1, order-i) end-if
      perform save-state
      perform make-current-move
      move side to side-color
      if side = 0 move 1 to atk-side-color else move 0 to atk-side-color end-if
      perform locate-king
      if atk-sq >= 0
        compute order-temp = 160 - 10 * (function abs(function mod(mv-to, 16) - function mod(atk-sq, 16)) + function abs(function integer(mv-to / 16) - function integer(atk-sq / 16)))
        add order-temp to order-score(ply + 1, order-i)
        move atk-sq to fr perform is-attacked
        if attacked = 1 add 1000 to order-score(ply + 1, order-i) end-if
      end-if
      perform restore-state
    end-perform
    perform varying order-i from 1 by 1 until order-i >= move-count(ply + 1)
      compute order-j = order-i + 1
      perform until order-j > move-count(ply + 1)
        if order-score(ply + 1, order-j) > order-score(ply + 1, order-i)
          move order-score(ply + 1, order-i) to order-temp
          move order-score(ply + 1, order-j) to order-score(ply + 1, order-i)
          move order-temp to order-score(ply + 1, order-j)
          move from-sq(ply + 1, order-i) to swap-from
          move from-sq(ply + 1, order-j) to from-sq(ply + 1, order-i)
          move swap-from to from-sq(ply + 1, order-j)
          move dest-sq(ply + 1, order-i) to swap-to
          move dest-sq(ply + 1, order-j) to dest-sq(ply + 1, order-i)
          move swap-to to dest-sq(ply + 1, order-j)
          move promotion(ply + 1, order-i) to swap-prom
          move promotion(ply + 1, order-j) to promotion(ply + 1, order-i)
          move swap-prom to promotion(ply + 1, order-j)
        end-if
        add 1 to order-j
      end-perform
    end-perform.
score-terminal.
    move side to side-color
    perform locate-king
    if side = 0 move 1 to atk-side-color else move 0 to atk-side-color end-if
    move atk-sq to fr perform is-attacked
    if attacked = 1 compute score-val = -30000 + ply else move 0 to score-val end-if.
solve-mate-three.
    move 1 to ply
    perform generate-legal
    move move-count(ply + 1) to mate-root-count
    perform order-moves
    move 0 to mate-tries
    perform varying mate-root-loop from 1 by 1 until mate-root-loop > mate-root-count
      move from-sq(ply + 1, mate-root-loop) to mate-root-from
      move dest-sq(ply + 1, mate-root-loop) to mate-root-to
      move promotion(ply + 1, mate-root-loop) to mate-root-prom
      move mate-root-from to mv-from move mate-root-to to mv-to move mate-root-prom to mv-prom
      perform save-state
      perform make-current-move
      add 1 to ply
      perform generate-legal
      if move-count(ply + 1) > 0
        move 1 to mate-forced
        move move-count(ply + 1) to mate-black-count
        perform varying mate-black-loop from 1 by 1 until mate-black-loop > mate-black-count or mate-forced = 0 or mate-tries > 20000
          move from-sq(ply + 1, mate-black-loop) to mv-from
          move dest-sq(ply + 1, mate-black-loop) to mv-to
          move promotion(ply + 1, mate-black-loop) to mv-prom
          perform save-state
          perform make-current-move
          add 1 to ply
          perform generate-legal
          perform order-moves
          move move-count(ply + 1) to mate-white-count
          move 0 to mate-found
          perform varying mate-white-loop from 1 by 1 until mate-white-loop > mate-white-count or mate-found = 1 or mate-tries > 20000
            move from-sq(ply + 1, mate-white-loop) to mv-from
            move dest-sq(ply + 1, mate-white-loop) to mv-to
            move promotion(ply + 1, mate-white-loop) to mv-prom
            perform save-state
            perform make-current-move
            add 1 to ply
            move side to side-color
            if side = 0 move 1 to atk-side-color else move 0 to atk-side-color end-if
            perform locate-king
            move atk-sq to fr perform is-attacked
            if attacked = 1
              perform generate-legal
              if move-count(ply + 1) = 0 move 1 to mate-found move 2 to mate-distance end-if
            end-if
            if mate-found = 0
              perform generate-legal
              move move-count(ply + 1) to mate-black2-count
              if mate-black2-count > 0
                move 1 to mate-line-forced
                perform varying mate-black2-loop from 1 by 1 until mate-black2-loop > mate-black2-count or mate-line-forced = 0 or mate-tries > 20000
                  move from-sq(ply + 1, mate-black2-loop) to mv-from
                  move dest-sq(ply + 1, mate-black2-loop) to mv-to
                  move promotion(ply + 1, mate-black2-loop) to mv-prom
                  perform save-state
                  perform make-current-move
                  add 1 to ply
                  perform generate-legal
                  perform order-moves
                  move move-count(ply + 1) to mate-white3-count
                  move 0 to found
                  perform varying mate-white3-loop from 1 by 1 until mate-white3-loop > mate-white3-count or found = 1 or mate-tries > 20000
                    add 1 to mate-tries
                    move from-sq(ply + 1, mate-white3-loop) to mv-from
                    move dest-sq(ply + 1, mate-white3-loop) to mv-to
                    move promotion(ply + 1, mate-white3-loop) to mv-prom
                    perform save-state
                    perform make-current-move
                    add 1 to ply
                    move side to side-color
                    if side = 0 move 1 to atk-side-color else move 0 to atk-side-color end-if
                    perform locate-king
                    move atk-sq to fr perform is-attacked
                    if attacked = 1
                      perform generate-legal
                      if move-count(ply + 1) = 0 move 1 to found end-if
                    end-if
                    subtract 1 from ply
                    perform restore-state
                  end-perform
                  if found = 0 move 0 to mate-line-forced end-if
                  subtract 1 from ply
                  perform restore-state
                end-perform
                if mate-line-forced = 1 and mate-tries <= 20000 move 1 to mate-found move 3 to mate-distance end-if
              end-if
            end-if
            subtract 1 from ply
            perform restore-state
          end-perform
          if mate-found = 0 move 0 to mate-forced end-if
          subtract 1 from ply
          perform restore-state
        end-perform
        if mate-forced = 1 and mate-tries <= 20000
          if mate-distance = 3 and main-score < 29990
            move mate-root-from to best-from
            move mate-root-to to best-to
            move mate-root-prom to best-prom
          end-if
          move 1 to mate-solved
          subtract 1 from ply
          perform restore-state
          exit perform
        end-if
      end-if
      subtract 1 from ply
      perform restore-state
      if mate-tries > 20000 exit perform end-if
    end-perform.
evaluate-board.
    move 0 to score-val
    perform varying k from 0 by 1 until k > 127
      if function mod(k, 16) < 8
       evaluate sq(k + 1)
        when 'P' add 100 to score-val
        when 'N' add 320 to score-val
        when 'B' add 330 to score-val
        when 'R' add 500 to score-val
        when 'Q' add 900 to score-val
        when 'p' subtract 100 from score-val
        when 'n' subtract 320 from score-val
        when 'b' subtract 330 from score-val
        when 'r' subtract 500 from score-val
        when 'q' subtract 900 from score-val
       end-evaluate
      end-if
    end-perform
    if side = 1 compute score-val = 0 - score-val end-if.

run-perft.
    move 1 to ply perform generate-legal
    move move-count(ply + 1) to root-move-no move 0 to root-total
    perform varying root-loop from 1 by 1 until root-loop > root-move-no
      move from-sq(ply + 1, root-loop) to mv-from move dest-sq(ply + 1, root-loop) to mv-to move promotion(ply + 1, root-loop) to mv-prom
      perform save-state perform make-current-move
      add 1 to ply
      compute search-depth = perft-depth - 1
      perform perft-node
      subtract 1 from ply
      perform restore-state
      move from-sq(ply + 1, root-loop) to root-best-from move dest-sq(ply + 1, root-loop) to root-best-to move promotion(ply + 1, root-loop) to root-best-prom
      perform format-best
      display function trim(move-text) ': ' perft-result
      add perft-result to root-total
    end-perform
    display 'Nodes searched: ' root-total.
perft-node.
    if search-depth = 0 move 1 to perft-result exit paragraph end-if
    perform generate-legal
    if move-count(ply + 1) = 0 move 0 to perft-result exit paragraph end-if
    move 0 to perft-sum(ply + 1)
    perform varying perft-loop(ply + 1) from 1 by 1 until perft-loop(ply + 1) > move-count(ply + 1)
      move from-sq(ply + 1, perft-loop(ply + 1)) to mv-from move dest-sq(ply + 1, perft-loop(ply + 1)) to mv-to move promotion(ply + 1, perft-loop(ply + 1)) to mv-prom
      perform save-state perform make-current-move
      subtract 1 from search-depth add 1 to ply perform perft-node subtract 1 from ply add 1 to search-depth
      add perft-result to perft-sum(ply + 1)
      perform restore-state
    end-perform
    move perft-sum(ply + 1) to perft-result.

format-best.
    compute file-no = function mod(root-best-from, 16)
    compute rank-no = function integer(root-best-from / 16) + 1
    compute parse-to-file = function mod(root-best-to, 16)
    compute parse-to-rank = function integer(root-best-to / 16) + 1
    move spaces to move-text
    string function char(function ord('a') + file-no) function char(function ord('0') + rank-no)
      function char(function ord('a') + parse-to-file) function char(function ord('0') + parse-to-rank)
      into move-text
    if root-best-prom not = space move root-best-prom to move-text(5:1) end-if.
end program chess-engine.
