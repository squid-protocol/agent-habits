## Family A: S vs X (one-sided, Holm)
  A1 doc_per_code_line        cells  7  S> 5  X> 2  tie 0  pred S > X      p 0.2266  holm 0.6797
  A2 funcs_commented_share    cells 10  S> 4  X> 2  tie 4  pred S > X      p 0.3438  holm 0.6875
  A3 early_exit_per_1k        cells 10  S> 1  X> 9  tie 0  pred X > S      p 0.0107  holm 0.0537
  A4 python_helper            cells  8  S> 0  X> 0  tie 8  pred X > S      p 1.0000  holm 1.0000
  A5 while_per_1k             cells  8  S> 6  X> 2  tie 0  pred S > X      p 0.1445  holm 0.5781
## Family B: K vs X (one-sided, Holm)
  B1 doc_per_code_line        cells  7  K> 6  X> 1  tie 0  pred K > X      p 0.0625  holm 0.2188
  B2 funcs_commented_share    cells 10  K>10  X> 0  tie 0  pred K > X      p 0.0010  holm 0.0049
  B3 early_exit_per_1k        cells 10  K> 2  X> 8  tie 0  pred X > K      p 0.0547  holm 0.2188
  B4 python_helper            cells  8  K> 0  X> 0  tie 8  pred X > K      p 1.0000  holm 1.0000
  B5 while_per_1k             cells  8  K> 4  X> 4  tie 0  pred K > X      p 0.6367  holm 1.0000
## Family C: K vs S (two-sided, Holm)
  C1 doc_per_code_line        cells 10  K>10  S> 0  tie 0  pred two-sided  p 0.0020  holm 0.0098
  C2 funcs_commented_share    cells 10  K>10  S> 0  tie 0  pred two-sided  p 0.0020  holm 0.0098
  C3 early_exit_per_1k        cells 10  K> 6  S> 3  tie 1  pred two-sided  p 0.5078  holm 1.0000
  C4 python_helper            cells  8  K> 0  S> 0  tie 8  pred two-sided  p 1.0000  holm 1.0000
  C5 while_per_1k             cells  8  K> 0  S> 8  tie 0  pred two-sided  p 0.0078  holm 0.0234
## Family D: S vs S2 (two-sided, Holm)
  D1 doc_per_code_line        cells 10  S> 5  S2> 4  tie 1  pred two-sided  p 1.0000  holm 1.0000
  D2 funcs_commented_share    cells 10  S> 3  S2> 2  tie 5  pred two-sided  p 1.0000  holm 1.0000
  D3 early_exit_per_1k        cells 10  S> 5  S2> 5  tie 0  pred two-sided  p 1.0000  holm 1.0000
  D4 python_helper            cells  8  S> 0  S2> 0  tie 8  pred two-sided  p 1.0000  holm 1.0000
  D5 while_per_1k             cells  8  S> 5  S2> 3  tie 0  pred two-sided  p 0.7266  holm 1.0000
## Family E: K vs K2 (two-sided, Holm)
  E1 doc_per_code_line        cells 10  K> 6  K2> 4  tie 0  pred two-sided  p 0.7539  holm 1.0000
  E2 funcs_commented_share    cells 10  K> 7  K2> 3  tie 0  pred two-sided  p 0.3438  holm 1.0000
  E3 early_exit_per_1k        cells 10  K> 3  K2> 5  tie 2  pred two-sided  p 0.7266  holm 1.0000
  E4 python_helper            cells  8  K> 0  K2> 1  tie 7  pred two-sided  p 1.0000  holm 1.0000
  E5 while_per_1k             cells  8  K> 4  K2> 4  tie 0  pred two-sided  p 1.0000  holm 1.0000
