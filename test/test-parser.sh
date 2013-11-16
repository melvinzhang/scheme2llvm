#!/usr/bin/env zsh
for i in `seq 1 82`; do
    echo $i;
    { awk -f script/head.awk max=$i scheme2llvm.scm ; echo ")" } > $i.tmp;
    cat $i.tmp | ./scheme2llvm.2 > $i.out;
done
