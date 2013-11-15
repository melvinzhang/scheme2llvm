%.2.ll: %.1.ll
	cat $^ | llvm-upgrade > $@

%.1.ll: %.scm
	cat $^ | gsi scheme2llvm.scm | awk -f transform_comments.awk > $@

%.bc: %.ll
	llvm-as $^

%.s: %.bc
	llc $^

%: %.s
	gcc $^ -o $@
