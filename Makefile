%.2.ll: %.1.ll
	cat $^ | llvm-upgrade > $@

%.ll: scheme2llvm.scm
	cat $^ | gsi $^ > $@

%.bc: %.ll
	llvm-as $^

%.s: %.bc
	llc $^

%: %.s
	gcc $^ -o $@
