Based on https://web.archive.org/web/20100125200317/http://www.ida.liu.se:80/~tobnu/scheme2llvm/compile.ss.heap

Major improvements include
  * updating LLVM IR output from 1.x to 3.7
  * garbage collection with libgc

Makefile makes use of the following programs:
  Required:
    llvm >= 3.7
    clang >= 3.7
  Optional:
    gawk
    csi - Chicken Scheme interpreter
    csc - Chicken Scheme compiler
