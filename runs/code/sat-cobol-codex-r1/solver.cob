       >>SOURCE FORMAT FREE
identification division.
program-id. solver.
environment division.
input-output section.
file-control.
    select in-file assign to file-name organization is line sequential
        file status is fs.
data division.
file section.
fd in-file.
01 in-line pic x(32767).
working-storage section.
01 file-name pic x(1024).
01 fs pic xx.
01 vars binary-long.
01 clauses binary-long.
01 max-vars constant as 10000.
01 max-clauses constant as 50000.
01 max-lits constant as 500000.
01 lits.
  02 lit pic s9(9) comp-5 occurs 500000.
01 starts.
  02 cstart binary-long occurs 50000.
01 ends.
  02 cend binary-long occurs 50000.
01 watches.
  02 watch-head binary-long occurs 20001.
01 clause-watches.
  02 cw occurs 50000.
    03 cwp1 binary-long.
    03 cwp2 binary-long.
01 watch-nodes.
  02 wn occurs 100000.
    03 wn-clause binary-long.
    03 wn-side binary-long.
    03 wn-next binary-long.
01 assigns.
  02 aval pic s9 occurs 10000.
01 trail.
  02 tv binary-long occurs 10000.
01 var-levels.
  02 vlevel binary-long occurs 10000.
01 var-reasons.
  02 vreason binary-long occurs 10000.
01 seen-vars.
  02 vseen binary-long occurs 10000.
01 learned-work.
  02 wlit pic s9(9) comp-5 occurs 10000.
01 wcount binary-long.
01 wcurr binary-long.
01 pivot-var binary-long.
01 pivot-reason binary-long.
01 trail-pos binary-long.
01 back-level binary-long.
01 old-depth binary-long.
01 learn-index binary-long.
01 learn-lit binary-long.
01 learn-reason binary-long.
01 found-pivot binary-long.
01 decisions.
  02 frame occurs 10000.
    03 dvar binary-long.
    03 dmark binary-long.
    03 dstate binary-long.
    03 dpol pic s9.
01 depth binary-long.
01 ntrail binary-long.
01 qhead binary-long.
01 watch-count binary-long.
01 head-index binary-long.
01 next-node binary-long.
01 prev-node binary-long.
01 cur-node binary-long.
01 node-side binary-long.
01 other-pos binary-long.
01 own-pos binary-long.
01 replace-pos binary-long.
01 old-index binary-long.
01 new-index binary-long.
01 other-lit binary-long.
01 other-var binary-long.
01 initial-conflict binary-long.
01 nlits binary-long.
01 nclauses binary-long.
01 i binary-long.
01 j binary-long.
01 k binary-long.
01 posn binary-long.
01 valn pic s9(9) comp-5.
01 signn binary-long.
01 num binary-long.
01 line-len binary-long.
01 tok1 pic x(20).
01 tok2 pic x(20).
01 tok3 pic x(20).
01 tok4 pic x(20).
01 first-char pic x.
01 litv binary-long.
01 unknowns binary-long.
01 score-weight binary-long.

01 satisfied binary-long.
01 unit-lit binary-long.
01 conflict binary-long.
01 conflict-clause binary-long.
01 assign-reason binary-long.
01 changed binary-long.
01 finished binary-long.
01 best-var binary-long.
01 best-score binary-long.
01 score binary-long.
01 pos-score binary-long.
01 neg-score binary-long.
01 scores.
  02 sc occurs 10000.
    03 spos binary-long.
    03 sneg binary-long.
01 rc binary-long.
01 arg-count binary-long.
01 out-val binary-long.
procedure division.
main.
    accept file-name from command-line
    if file-name = spaces
        display "usage: solver FILE"
        move 1 to return-code
        stop run
    end-if
    open input in-file
    if fs not = "00"
        display "cannot open input" upon syserr
        move 1 to return-code
        stop run
    end-if
    move 0 to vars clauses nlits nclauses
    perform until fs = "10"
        read in-file
            at end continue
            not at end perform parse-line
        end-read
    end-perform
    close in-file
    if vars < 0 or vars > 10000 or clauses > 50000 or nlits > 500000
        display "s UNSATISFIABLE"
        move 20 to return-code
        stop run
    end-if
    move 0 to depth ntrail
    perform varying i from 1 by 1 until i > vars
        move 0 to aval(i)
    end-perform
    perform init-watches
    if initial-conflict = 1
        display "s UNSATISFIABLE"
        move 20 to return-code
        stop run
    end-if
    move 0 to finished
    perform until finished = 1
        perform propagate
        if conflict = 1
            perform backtrack
        else
            perform choose-variable
            if best-var = 0
                perform print-sat
                move 10 to return-code
                stop run
            else
                add 1 to depth
                move best-var to dvar(depth)
                move ntrail to dmark(depth)
                move 0 to dstate(depth)
                move 1 to dpol(depth)
                if neg-score > pos-score move -1 to dpol(depth) end-if
                perform set-decision
            end-if
        end-if
    end-perform
    display "s UNSATISFIABLE"
    move 20 to return-code
    stop run.
parse-line.
    move in-line(1:1) to first-char
    if first-char = "c" or first-char = "C" or first-char = spaces
        exit paragraph
    end-if
    if first-char = "p"
        unstring in-line delimited by all spaces into tok1 tok2 tok3 tok4 tok1
        move function numval(tok3) to vars
        move function numval(tok1) to clauses
        exit paragraph
    end-if
    compute line-len = function length(function trim(in-line trailing))
    move 1 to posn
    perform until posn > line-len
        perform skip-spaces
        if posn <= line-len
            move 1 to signn
            if in-line(posn:1) = "-"
                move -1 to signn
                add 1 to posn
            end-if
            move 0 to num
            perform until posn > line-len or in-line(posn:1) = space or in-line(posn:1) = x"09"
                if in-line(posn:1) >= "0" and in-line(posn:1) <= "9"
                    compute num = num * 10 + function numval(in-line(posn:1))
                end-if
                add 1 to posn
            end-perform
            compute valn = num * signn
            if valn = 0
                add 1 to nclauses
                if nclauses <= 50000
                    compute cend(nclauses) = nlits
                    if nclauses = 1
                        move 1 to cstart(nclauses)
                    else
                        compute cstart(nclauses) = cend(nclauses - 1) + 1
                    end-if
                end-if
            else
                add 1 to nlits
                if nlits <= 500000
                    move valn to lit(nlits)
                end-if
            end-if
        end-if
    end-perform.
skip-spaces.
    perform until posn > line-len or (in-line(posn:1) not = space and in-line(posn:1) not = x"09")
        add 1 to posn
    end-perform.
set-literal.
    compute j = function abs(litv)
    if j >= 1 and j <= vars
        if litv > 0
            move 1 to out-val
        else
            move -1 to out-val
        end-if
        if aval(j) = 0
            move out-val to aval(j)
            add 1 to ntrail
            move j to tv(ntrail)
            move depth to vlevel(j)
            move assign-reason to vreason(j)
            move 1 to changed
        else
            if aval(j) not = out-val
                move 1 to conflict
            end-if
        end-if
    end-if.
init-watches.
    move 0 to watch-count initial-conflict qhead
    perform varying i from 1 by 1 until i > 20001
        move 0 to watch-head(i)
    end-perform
    perform varying i from 1 by 1 until i > nclauses
        compute j = cend(i) - cstart(i) + 1
        if j <= 0
            move 1 to initial-conflict
        else
            if j = 1
                move lit(cstart(i)) to litv
                move i to assign-reason
                move 0 to conflict
                perform set-literal
                if conflict = 1 move 1 to initial-conflict end-if
            else
                move cstart(i) to cwp1(i)
                compute cwp2(i) = cstart(i) + 1
                add 1 to watch-count
                move i to wn-clause(watch-count)
                move 1 to wn-side(watch-count)
                move lit(cwp1(i)) to litv
                perform literal-watch-index
                move watch-head(head-index) to wn-next(watch-count)
                move watch-count to watch-head(head-index)
                add 1 to watch-count
                move i to wn-clause(watch-count)
                move 2 to wn-side(watch-count)
                move lit(cwp2(i)) to litv
                perform literal-watch-index
                move watch-head(head-index) to wn-next(watch-count)
                move watch-count to watch-head(head-index)
            end-if
        end-if
    end-perform.
literal-watch-index.
    compute j = function abs(litv)
    if litv > 0
        compute head-index = j * 2
    else
        compute head-index = j * 2 + 1
    end-if.
propagate.
    move 0 to conflict
    if qhead > ntrail move ntrail to qhead end-if
    perform until qhead >= ntrail or conflict = 1
        add 1 to qhead
        move tv(qhead) to j
        if aval(j) > 0
            compute litv = 0 - j
        else
            move j to litv
        end-if
        perform literal-watch-index
        move head-index to old-index
        move watch-head(old-index) to cur-node
        move 0 to prev-node
        perform until cur-node = 0 or conflict = 1
            move wn-next(cur-node) to next-node
            move wn-clause(cur-node) to i
            move wn-side(cur-node) to node-side
            if node-side = 1
                move cwp1(i) to own-pos
                move cwp2(i) to other-pos
            else
                move cwp2(i) to own-pos
                move cwp1(i) to other-pos
            end-if
            move lit(other-pos) to other-lit
            compute other-var = function abs(other-lit)
            move 0 to satisfied
            if (other-lit > 0 and aval(other-var) = 1) or
               (other-lit < 0 and aval(other-var) = -1)
                move 1 to satisfied
            end-if
            move 0 to replace-pos
            if satisfied = 0
                perform varying k from cstart(i) by 1 until k > cend(i) or replace-pos > 0
                    if k not = own-pos and k not = other-pos
                        move lit(k) to litv
                        compute j = function abs(litv)
                        if aval(j) = 0 or
                           (litv > 0 and aval(j) = 1) or
                           (litv < 0 and aval(j) = -1)
                            move k to replace-pos
                        end-if
                    end-if
                end-perform
                if replace-pos > 0
                    if prev-node = 0
                        move next-node to watch-head(old-index)
                    else
                        move next-node to wn-next(prev-node)
                    end-if
                    if node-side = 1
                        move replace-pos to cwp1(i)
                    else
                        move replace-pos to cwp2(i)
                    end-if
                    move lit(replace-pos) to litv
                    perform literal-watch-index
                    move watch-head(head-index) to wn-next(cur-node)
                    move cur-node to watch-head(head-index)
                else
                    if aval(other-var) not = 0
                        move 1 to conflict
                        move i to conflict-clause
                    else
                        move other-lit to litv
                        move i to assign-reason
                        perform set-literal
                        if conflict = 1 move i to conflict-clause end-if
                        move cur-node to prev-node
                    end-if
                end-if
            else
                move cur-node to prev-node
            end-if
            if replace-pos > 0
                move next-node to cur-node
            else
                if satisfied = 1 or conflict = 0
                    move next-node to cur-node
                else
                    move 0 to cur-node
                end-if
            end-if
        end-perform
    end-perform.
choose-variable.
    perform varying i from 1 by 1 until i > vars
        move 0 to spos(i) sneg(i)
    end-perform
    perform varying i from 1 by 1 until i > nclauses
        move 0 to satisfied unknowns
        perform varying k from cstart(i) by 1 until k > cend(i)
            move lit(k) to litv
            compute j = function abs(litv)
            if j >= 1 and j <= vars
                if aval(j) = 0
                    add 1 to unknowns
                else
                    if (litv > 0 and aval(j) = 1) or (litv < 0 and aval(j) = -1)
                        move 1 to satisfied
                    end-if
                end-if
            end-if
        end-perform
        if unknowns = 2 move 4 to score-weight else
            if unknowns = 3 move 2 to score-weight else move 1 to score-weight end-if
        end-if
        if satisfied = 0
            perform varying k from cstart(i) by 1 until k > cend(i)
                move lit(k) to litv
                compute j = function abs(litv)
                if j >= 1 and j <= vars and aval(j) = 0
                    if litv > 0
                        add score-weight to spos(j)
                    else
                        add score-weight to sneg(j)
                    end-if
                end-if
            end-perform
        end-if
    end-perform
    move 0 to best-var best-score pos-score neg-score
    perform varying i from 1 by 1 until i > vars
        compute score = spos(i) * sneg(i) + spos(i) + sneg(i)
        if score > best-score
            move i to best-var
            move score to best-score
            move spos(i) to pos-score
            move sneg(i) to neg-score
        end-if
    end-perform.
set-decision.
    move 0 to assign-reason
    if dpol(depth) > 0
        move dvar(depth) to litv
    else
        compute litv = 0 - dvar(depth)
    end-if
    perform set-literal.
backtrack.
    perform until depth = 0 or conflict = 0
        perform until ntrail <= dmark(depth)
            move tv(ntrail) to j
            move 0 to aval(j)
            subtract 1 from ntrail
        end-perform
        move ntrail to qhead
        if dstate(depth) = 0
            move 1 to dstate(depth)
            compute dpol(depth) = 0 - dpol(depth)
            move 0 to conflict
            perform set-decision
        else
            subtract 1 from depth
        end-if
    end-perform
    if depth = 0 and conflict = 1
        move 1 to finished
    end-if.
print-sat.
    display "s SATISFIABLE"
    display "v" with no advancing
    perform varying i from 1 by 1 until i > vars
        if aval(i) = 0 move -1 to aval(i) end-if
        if aval(i) > 0
            display " " i with no advancing
        else
            compute out-val = 0 - i
            display " " out-val with no advancing
        end-if
        if function mod(i, 20) = 0
            display " 0"
            display "v" with no advancing
        end-if
    end-perform
    display " 0".
end program solver.
