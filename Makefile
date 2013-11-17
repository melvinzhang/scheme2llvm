all: scheme2llvm.2

clean:
	-rm core *.2 *.bc *.s *.ll test/*.2 test/*.bc test/*.s test/*.ll

TEST_SRC := $(wildcard test/*.scm) 

tests: scheme2llvm.2 $(TEST_SRC:.scm=.2)

%.2.ll: %.1.ll
	cat $^ | llvm-upgrade > $@

%.1.ll: %.scm scheme2llvm.2
	ulimit -v 50000; cat $< | ./scheme2llvm.2 | awk -f script/transform_comments.awk > $@

scheme2llvm.ll: scheme2llvm.scm scheme2llvm.scm
	ulimit -v 50000; cat $< | ./scheme2llvm.2 | awk -f script/transform_comments.awk > $@

scheme2llvm.1.ll: scheme2llvm.scm
	ulimit -v 50000; cat $< | ./scheme2llvm.2 | awk -f script/transform_comments.awk > $@
	
scheme2llvm.gsi.1.ll: scheme2llvm.scm
	cat $^ | gsi $^ | awk -f script/transform_comments.awk > $@

%.bc: %.ll
	llvm-as $^

%.s: %.bc
	llc $^

%: %.s
	gcc $^ -o $@ -lgc

