# The purpose of this file is to provide bare-minimum ASM code for TLS
# operations, with NASM documentation (or perhaps even capability) lacking
# proper TLS support. This file was generated from 'tls.c'. It is kept as a
# distinct file so as to be certain during the build process of the compiler
# that the functions implemented in this file are bare, and do not modify
# anything but the registers rip and rax. The ret modifies rsp, but in doing so,
# sets it to what rsp was pre-call of these functions.

	.file	"tls.c"
	.intel_syntax noprefix
	.section	.text.unlikely,"ax",@progbits
.LCOLDB0:
	.text
.LHOTB0:
	.p2align 4,,15
	.globl	get_currentthread
	.type	get_currentthread, @function
get_currentthread:
.LFB0:
	.cfi_startproc
	mov	rax, QWORD PTR fs:currentthread@tpoff
	ret
	.cfi_endproc
.LFE0:
	.size	get_currentthread, .-get_currentthread
	.section	.text.unlikely
.LCOLDE0:
	.text
.LHOTE0:
	.section	.text.unlikely
.LCOLDB1:
	.text
.LHOTB1:
	.p2align 4,,15
	.globl	set_currentthread
	.type	set_currentthread, @function
set_currentthread:
.LFB1:
	.cfi_startproc
	mov	QWORD PTR fs:currentthread@tpoff, rdi
	ret
	.cfi_endproc
.LFE1:
	.size	set_currentthread, .-set_currentthread
	.section	.text.unlikely
.LCOLDE1:
	.text
.LHOTE1:
	.section	.text.unlikely
.LCOLDB2:
	.text
.LHOTB2:
	.p2align 4,,15
	.globl	get_mainstack
	.type	get_mainstack, @function
get_mainstack:
.LFB2:
	.cfi_startproc
	mov	rax, QWORD PTR fs:mainstack@tpoff
	ret
	.cfi_endproc
.LFE2:
	.size	get_mainstack, .-get_mainstack
	.section	.text.unlikely
.LCOLDE2:
	.text
.LHOTE2:
	.section	.text.unlikely
.LCOLDB3:
	.text
.LHOTB3:
	.p2align 4,,15
	.globl	set_mainstack
	.type	set_mainstack, @function
set_mainstack:
.LFB3:
	.cfi_startproc
	mov	QWORD PTR fs:mainstack@tpoff, rdi
	ret
	.cfi_endproc
.LFE3:
	.size	set_mainstack, .-set_mainstack
	.section	.text.unlikely
.LCOLDE3:
	.text
.LHOTE3:
	.globl	mainstack
	.section	.tbss,"awT",@nobits
	.align 8
	.type	mainstack, @object
	.size	mainstack, 8
mainstack:
	.zero	8
	.globl	currentthread
	.align 8
	.type	currentthread, @object
	.size	currentthread, 8
currentthread:
	.zero	8
	.ident	"GCC: (GNU) 5.1.0"
	.section	.note.GNU-stack,"",@progbits
