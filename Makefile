all: scheme2llvm.3

clean:
	-rm core *.3 *.bc *.s test/*.3 test/*.bc test/*.s test/*.ll

TEST_SRC := $(wildcard test/*.scm) 

tests: scheme2llvm.3 $(TEST_SRC:.scm=.3)

%.3.ll: %.scm scheme2llvm.3
	ulimit -v 50000; cat $< | ./scheme2llvm.3 > $@

scheme2llvm.3.ll: scheme2llvm.scm
	ulimit -v 50000; cat $< | ./scheme2llvm.3 > $@
	
scheme2llvm.csi.3.ll: scheme2llvm.scm
	cat $^ | csi -q $^ | awk -f script/transform_comments.awk > $@

scheme2llvm.csi: scheme2llvm.scm
	csc -O5 scheme2llvm.scm -o $@

%.bc: %.ll
	opt -std-compile-opts $^ -o $@

%.s: %.bc
	llc -tailcallopt $^

%: %.s
	clang $^ -o $@ -lgc

bootstrap:
	make scheme2llvm.3
	touch scheme2llvm.scm
	make scheme2llvm.3

benchmark:
	-rm scheme2llvm.3.ll
	/usr/bin/time -v make scheme2llvm.3.ll
