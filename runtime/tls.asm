	.file	"tls.c"
	.intel_syntax noprefix
	.section	.text.unlikely,"ax",@progbits
.LCOLDB0:
	.text
.LHOTB0:
	.p2align 4,,15
	.globl	__get_tempstack
	.type	__get_tempstack, @function
__get_tempstack:
.LFB0:
	.cfi_startproc
	mov	rax, QWORD PTR fs:tempstack@tpoff
	ret
	.cfi_endproc
.LFE0:
	.size	__get_tempstack, .-__get_tempstack
	.section	.text.unlikely
.LCOLDE0:
	.text
.LHOTE0:
	.section	.text.unlikely
.LCOLDB1:
	.text
.LHOTB1:
	.p2align 4,,15
	.globl	__init_tempstack
	.type	__init_tempstack, @function
__init_tempstack:
.LFB1:
	.cfi_startproc
	sub	rsp, 8
	.cfi_def_cfa_offset 16
	xor	r9d, r9d
	mov	r8d, -1
	mov	ecx, 34
	mov	edx, 3
	mov	esi, 4096
	xor	edi, edi
	call	mmap
	mov	QWORD PTR fs:tempstack@tpoff, rax
	add	rsp, 8
	.cfi_def_cfa_offset 8
	ret
	.cfi_endproc
.LFE1:
	.size	__init_tempstack, .-__init_tempstack
	.section	.text.unlikely
.LCOLDE1:
	.text
.LHOTE1:
	.section	.text.unlikely
.LCOLDB2:
	.text
.LHOTB2:
	.p2align 4,,15
	.globl	__free_tempstack
	.type	__free_tempstack, @function
__free_tempstack:
.LFB2:
	.cfi_startproc
	mov	rdi, QWORD PTR fs:tempstack@tpoff
	mov	esi, 4096
	jmp	munmap
	.cfi_endproc
.LFE2:
	.size	__free_tempstack, .-__free_tempstack
	.section	.text.unlikely
.LCOLDE2:
	.text
.LHOTE2:
	.section	.text.unlikely
.LCOLDB3:
	.text
.LHOTB3:
	.p2align 4,,15
	.globl	get_currentthread
	.type	get_currentthread, @function
get_currentthread:
.LFB3:
	.cfi_startproc
	mov	rax, QWORD PTR fs:currentthread@tpoff
	ret
	.cfi_endproc
.LFE3:
	.size	get_currentthread, .-get_currentthread
	.section	.text.unlikely
.LCOLDE3:
	.text
.LHOTE3:
	.section	.text.unlikely
.LCOLDB4:
	.text
.LHOTB4:
	.p2align 4,,15
	.globl	set_currentthread
	.type	set_currentthread, @function
set_currentthread:
.LFB4:
	.cfi_startproc
	mov	QWORD PTR fs:currentthread@tpoff, rdi
	ret
	.cfi_endproc
.LFE4:
	.size	set_currentthread, .-set_currentthread
	.section	.text.unlikely
.LCOLDE4:
	.text
.LHOTE4:
	.section	.text.unlikely
.LCOLDB5:
	.text
.LHOTB5:
	.p2align 4,,15
	.globl	get_mainstack
	.type	get_mainstack, @function
get_mainstack:
.LFB5:
	.cfi_startproc
	mov	rax, QWORD PTR fs:mainstack@tpoff
	ret
	.cfi_endproc
.LFE5:
	.size	get_mainstack, .-get_mainstack
	.section	.text.unlikely
.LCOLDE5:
	.text
.LHOTE5:
	.section	.text.unlikely
.LCOLDB6:
	.text
.LHOTB6:
	.p2align 4,,15
	.globl	set_mainstack
	.type	set_mainstack, @function
set_mainstack:
.LFB6:
	.cfi_startproc
	mov	QWORD PTR fs:mainstack@tpoff, rdi
	ret
	.cfi_endproc
.LFE6:
	.size	set_mainstack, .-set_mainstack
	.section	.text.unlikely
.LCOLDE6:
	.text
.LHOTE6:
	.section	.tbss,"awT",@nobits
	.align 8
	.type	tempstack, @object
	.size	tempstack, 8
tempstack:
	.zero	8
	.align 8
	.type	mainstack, @object
	.size	mainstack, 8
mainstack:
	.zero	8
	.align 8
	.type	currentthread, @object
	.size	currentthread, 8
currentthread:
	.zero	8
	.ident	"GCC: (GNU) 5.2.0"
	.section	.note.GNU-stack,"",@progbits
