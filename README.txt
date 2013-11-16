Makefile makes use of the following programs:
  gsi
    Gambit Scheme interpreter
  llvm-upgrade 
    found in LLVM 2.{0,1,2}
  gcc
  gawk

Issue: Compiler uses too much memory
"make issue/test-too-much-memory.1.ll" fails
"/usr/bin/time -v make test/test-closure.1.ll" shows maximum resident set as 1108628kb

Solution: switch from malloc bytecode to libgc's GC_malloc

libgc does not support tagged pointer, need to change representation to
regular pointers if we want to use libgc.
