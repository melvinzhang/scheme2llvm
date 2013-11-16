all: scheme2llvm.2

%.2.ll: %.1.ll
	cat $^ | llvm-upgrade > $@

%.1.ll: %.scm ./scheme2llvm.2
	cat $< | ./scheme2llvm.2 | awk -f transform_comments.awk > $@
	
scheme2llvm.1.ll: scheme2llvm.scm
	cat $^ | gsi $^ | awk -f transform_comments.awk > $@

%.bc: %.ll
	llvm-as $^

%.s: %.bc
	llc $^

%: %.s
	gcc $^ -o $@ -lgc

TEST_SRC := $(wildcard test/*.scm) 

tests: $(TEST_SRC:.scm=.2)

clean:
	-rm *.2 *.bc *.s test/*.2 test/*.bc test/*.s
