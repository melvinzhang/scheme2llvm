all: scheme2llvm.3

clean:
	-rm core *.3 *.bc *.s *.ll test/*.3 test/*.bc test/*.s test/*.ll

TEST_SRC := $(wildcard test/*.scm) 

tests: scheme2llvm.3 $(TEST_SRC:.scm=.3)

%.3.ll: %.scm scheme2llvm.3
	ulimit -v 50000; cat $< | ./scheme2llvm.3 | awk -f script/transform_comments.awk > $@

scheme2llvm.ll: scheme2llvm.scm scheme2llvm.scm
	ulimit -v 50000; cat $< | ./scheme2llvm.3 | awk -f script/transform_comments.awk > $@

scheme2llvm.3.ll: scheme2llvm.scm
	ulimit -v 50000; cat $< | ./scheme2llvm.3 | awk -f script/transform_comments.awk > $@
	
scheme2llvm.gsi.3.ll: scheme2llvm.scm
	cat $^ | gsi $^ | awk -f script/transform_comments.awk > $@

%.bc: %.ll
	llvm-as $^

%.s: %.bc
	llc $^

%: %.s
	gcc $^ -o $@ -lgc

