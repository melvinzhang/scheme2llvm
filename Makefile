%.2.ll: %.1.ll
	cat $^ | llvm-upgrade > $@

%.1.ll: %.scm
	cat $^ | gsi scheme2llvm.scm | awk -f transform_comments.awk > $@

%.self: %.scm
	cat $^ | ./scheme2llvm.2 | awk -f transform_comments.awk | grep "^;"

%.bc: %.ll
	llvm-as $^

%.s: %.bc
	llc $^

%: %.s
	gcc $^ -o $@
