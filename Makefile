%.2.ll: %.1.ll
	cat $^ | llvm-upgrade > $@

%.1.ll: %.scm
	cat $^ | gsi scheme2llvm.scm > $@

%.bc: %.ll
	llvm-as $^

%.s: %.bc
	llc $^

%: %.s
	gcc $^ -o $@
