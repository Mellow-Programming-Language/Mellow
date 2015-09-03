	.file	"tls.c"
	.intel_syntax noprefix
	.text
.Ltext0:
	.section	.text.unlikely,"ax",@progbits
.LCOLDB0:
	.text
.LHOTB0:
	.p2align 4,,15
	.section	.text.unlikely
.Ltext_cold0:
	.text
	.globl	__get_tempstack
	.type	__get_tempstack, @function
__get_tempstack:
.LFB21:
	.file 1 "tls.c"
	.loc 1 18 0
	.cfi_startproc
	.loc 1 20 0
	mov	rax, QWORD PTR fs:tempstack@tpoff
	ret
	.cfi_endproc
.LFE21:
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
.LFB22:
	.loc 1 23 0
	.cfi_startproc
	sub	rsp, 8
	.cfi_def_cfa_offset 16
	.loc 1 24 0
	xor	r9d, r9d
	mov	r8d, -1
	mov	ecx, 34
	mov	edx, 3
	mov	esi, 4096
	xor	edi, edi
	call	mmap
.LVL0:
	mov	QWORD PTR fs:tempstack@tpoff, rax
	.loc 1 32 0
	add	rsp, 8
	.cfi_def_cfa_offset 8
	ret
	.cfi_endproc
.LFE22:
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
.LFB23:
	.loc 1 35 0
	.cfi_startproc
	.loc 1 37 0
	mov	rdi, QWORD PTR fs:tempstack@tpoff
	mov	esi, 4096
	jmp	munmap
.LVL1:
	.cfi_endproc
.LFE23:
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
.LFB24:
	.loc 1 41 0
	.cfi_startproc
	.loc 1 43 0
	mov	rax, QWORD PTR fs:currentthread@tpoff
	ret
	.cfi_endproc
.LFE24:
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
.LFB25:
	.loc 1 46 0
	.cfi_startproc
.LVL2:
	.loc 1 47 0
	mov	QWORD PTR fs:currentthread@tpoff, rdi
	ret
	.cfi_endproc
.LFE25:
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
.LFB26:
	.loc 1 51 0
	.cfi_startproc
	.loc 1 53 0
	mov	rax, QWORD PTR fs:mainstack@tpoff
	ret
	.cfi_endproc
.LFE26:
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
.LFB27:
	.loc 1 56 0
	.cfi_startproc
.LVL3:
	.loc 1 57 0
	mov	QWORD PTR fs:mainstack@tpoff, rdi
	ret
	.cfi_endproc
.LFE27:
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
	.text
.Letext0:
	.section	.text.unlikely
.Letext_cold0:
	.file 2 "/usr/lib/gcc/x86_64-unknown-linux-gnu/5.2.0/include/stddef.h"
	.file 3 "/usr/include/bits/types.h"
	.file 4 "/usr/include/libio.h"
	.file 5 "tls.h"
	.file 6 "/usr/include/stdio.h"
	.file 7 "/usr/include/sys/mman.h"
	.section	.debug_info,"",@progbits
.Ldebug_info0:
	.long	0x434
	.value	0x4
	.long	.Ldebug_abbrev0
	.byte	0x8
	.uleb128 0x1
	.long	.LASF63
	.byte	0xc
	.long	.LASF64
	.long	.LASF65
	.quad	.Ltext0
	.quad	.Letext0-.Ltext0
	.long	.Ldebug_line0
	.uleb128 0x2
	.byte	0x8
	.byte	0x5
	.long	.LASF0
	.uleb128 0x3
	.long	.LASF9
	.byte	0x2
	.byte	0xd8
	.long	0x3f
	.uleb128 0x2
	.byte	0x8
	.byte	0x7
	.long	.LASF1
	.uleb128 0x4
	.byte	0x4
	.byte	0x5
	.string	"int"
	.uleb128 0x2
	.byte	0x8
	.byte	0x5
	.long	.LASF2
	.uleb128 0x2
	.byte	0x10
	.byte	0x4
	.long	.LASF3
	.uleb128 0x2
	.byte	0x1
	.byte	0x8
	.long	.LASF4
	.uleb128 0x2
	.byte	0x2
	.byte	0x7
	.long	.LASF5
	.uleb128 0x2
	.byte	0x4
	.byte	0x7
	.long	.LASF6
	.uleb128 0x2
	.byte	0x1
	.byte	0x6
	.long	.LASF7
	.uleb128 0x2
	.byte	0x2
	.byte	0x5
	.long	.LASF8
	.uleb128 0x3
	.long	.LASF10
	.byte	0x3
	.byte	0x83
	.long	0x2d
	.uleb128 0x3
	.long	.LASF11
	.byte	0x3
	.byte	0x84
	.long	0x2d
	.uleb128 0x2
	.byte	0x8
	.byte	0x7
	.long	.LASF12
	.uleb128 0x5
	.byte	0x8
	.uleb128 0x6
	.byte	0x8
	.long	0xa3
	.uleb128 0x2
	.byte	0x1
	.byte	0x6
	.long	.LASF13
	.uleb128 0x7
	.long	.LASF43
	.byte	0xd8
	.byte	0x4
	.byte	0xf5
	.long	0x22a
	.uleb128 0x8
	.long	.LASF14
	.byte	0x4
	.byte	0xf6
	.long	0x46
	.byte	0
	.uleb128 0x8
	.long	.LASF15
	.byte	0x4
	.byte	0xfb
	.long	0x9d
	.byte	0x8
	.uleb128 0x8
	.long	.LASF16
	.byte	0x4
	.byte	0xfc
	.long	0x9d
	.byte	0x10
	.uleb128 0x8
	.long	.LASF17
	.byte	0x4
	.byte	0xfd
	.long	0x9d
	.byte	0x18
	.uleb128 0x8
	.long	.LASF18
	.byte	0x4
	.byte	0xfe
	.long	0x9d
	.byte	0x20
	.uleb128 0x8
	.long	.LASF19
	.byte	0x4
	.byte	0xff
	.long	0x9d
	.byte	0x28
	.uleb128 0x9
	.long	.LASF20
	.byte	0x4
	.value	0x100
	.long	0x9d
	.byte	0x30
	.uleb128 0x9
	.long	.LASF21
	.byte	0x4
	.value	0x101
	.long	0x9d
	.byte	0x38
	.uleb128 0x9
	.long	.LASF22
	.byte	0x4
	.value	0x102
	.long	0x9d
	.byte	0x40
	.uleb128 0x9
	.long	.LASF23
	.byte	0x4
	.value	0x104
	.long	0x9d
	.byte	0x48
	.uleb128 0x9
	.long	.LASF24
	.byte	0x4
	.value	0x105
	.long	0x9d
	.byte	0x50
	.uleb128 0x9
	.long	.LASF25
	.byte	0x4
	.value	0x106
	.long	0x9d
	.byte	0x58
	.uleb128 0x9
	.long	.LASF26
	.byte	0x4
	.value	0x108
	.long	0x262
	.byte	0x60
	.uleb128 0x9
	.long	.LASF27
	.byte	0x4
	.value	0x10a
	.long	0x268
	.byte	0x68
	.uleb128 0x9
	.long	.LASF28
	.byte	0x4
	.value	0x10c
	.long	0x46
	.byte	0x70
	.uleb128 0x9
	.long	.LASF29
	.byte	0x4
	.value	0x110
	.long	0x46
	.byte	0x74
	.uleb128 0x9
	.long	.LASF30
	.byte	0x4
	.value	0x112
	.long	0x7e
	.byte	0x78
	.uleb128 0x9
	.long	.LASF31
	.byte	0x4
	.value	0x116
	.long	0x62
	.byte	0x80
	.uleb128 0x9
	.long	.LASF32
	.byte	0x4
	.value	0x117
	.long	0x70
	.byte	0x82
	.uleb128 0x9
	.long	.LASF33
	.byte	0x4
	.value	0x118
	.long	0x26e
	.byte	0x83
	.uleb128 0x9
	.long	.LASF34
	.byte	0x4
	.value	0x11c
	.long	0x27e
	.byte	0x88
	.uleb128 0x9
	.long	.LASF35
	.byte	0x4
	.value	0x125
	.long	0x89
	.byte	0x90
	.uleb128 0x9
	.long	.LASF36
	.byte	0x4
	.value	0x12e
	.long	0x9b
	.byte	0x98
	.uleb128 0x9
	.long	.LASF37
	.byte	0x4
	.value	0x12f
	.long	0x9b
	.byte	0xa0
	.uleb128 0x9
	.long	.LASF38
	.byte	0x4
	.value	0x130
	.long	0x9b
	.byte	0xa8
	.uleb128 0x9
	.long	.LASF39
	.byte	0x4
	.value	0x131
	.long	0x9b
	.byte	0xb0
	.uleb128 0x9
	.long	.LASF40
	.byte	0x4
	.value	0x132
	.long	0x34
	.byte	0xb8
	.uleb128 0x9
	.long	.LASF41
	.byte	0x4
	.value	0x134
	.long	0x46
	.byte	0xc0
	.uleb128 0x9
	.long	.LASF42
	.byte	0x4
	.value	0x136
	.long	0x284
	.byte	0xc4
	.byte	0
	.uleb128 0xa
	.long	.LASF66
	.byte	0x4
	.byte	0x9a
	.uleb128 0x7
	.long	.LASF44
	.byte	0x18
	.byte	0x4
	.byte	0xa0
	.long	0x262
	.uleb128 0x8
	.long	.LASF45
	.byte	0x4
	.byte	0xa1
	.long	0x262
	.byte	0
	.uleb128 0x8
	.long	.LASF46
	.byte	0x4
	.byte	0xa2
	.long	0x268
	.byte	0x8
	.uleb128 0x8
	.long	.LASF47
	.byte	0x4
	.byte	0xa6
	.long	0x46
	.byte	0x10
	.byte	0
	.uleb128 0x6
	.byte	0x8
	.long	0x231
	.uleb128 0x6
	.byte	0x8
	.long	0xaa
	.uleb128 0xb
	.long	0xa3
	.long	0x27e
	.uleb128 0xc
	.long	0x94
	.byte	0
	.byte	0
	.uleb128 0x6
	.byte	0x8
	.long	0x22a
	.uleb128 0xb
	.long	0xa3
	.long	0x294
	.uleb128 0xc
	.long	0x94
	.byte	0x13
	.byte	0
	.uleb128 0x2
	.byte	0x8
	.byte	0x7
	.long	.LASF48
	.uleb128 0xd
	.long	.LASF51
	.byte	0x1
	.byte	0x11
	.long	0x9b
	.quad	.LFB21
	.quad	.LFE21-.LFB21
	.uleb128 0x1
	.byte	0x9c
	.uleb128 0xe
	.long	.LASF49
	.byte	0x1
	.byte	0x16
	.quad	.LFB22
	.quad	.LFE22-.LFB22
	.uleb128 0x1
	.byte	0x9c
	.long	0x306
	.uleb128 0xf
	.quad	.LVL0
	.long	0x421
	.uleb128 0x10
	.uleb128 0x1
	.byte	0x55
	.uleb128 0x1
	.byte	0x30
	.uleb128 0x10
	.uleb128 0x1
	.byte	0x54
	.uleb128 0x3
	.byte	0xa
	.value	0x1000
	.uleb128 0x10
	.uleb128 0x1
	.byte	0x51
	.uleb128 0x1
	.byte	0x33
	.uleb128 0x10
	.uleb128 0x1
	.byte	0x52
	.uleb128 0x2
	.byte	0x8
	.byte	0x22
	.uleb128 0x10
	.uleb128 0x1
	.byte	0x58
	.uleb128 0x2
	.byte	0x9
	.byte	0xff
	.uleb128 0x10
	.uleb128 0x1
	.byte	0x59
	.uleb128 0x1
	.byte	0x30
	.byte	0
	.byte	0
	.uleb128 0xe
	.long	.LASF50
	.byte	0x1
	.byte	0x22
	.quad	.LFB23
	.quad	.LFE23-.LFB23
	.uleb128 0x1
	.byte	0x9c
	.long	0x339
	.uleb128 0x11
	.quad	.LVL1
	.long	0x42c
	.uleb128 0x10
	.uleb128 0x1
	.byte	0x54
	.uleb128 0x3
	.byte	0xa
	.value	0x1000
	.byte	0
	.byte	0
	.uleb128 0xd
	.long	.LASF52
	.byte	0x1
	.byte	0x28
	.long	0x9b
	.quad	.LFB24
	.quad	.LFE24-.LFB24
	.uleb128 0x1
	.byte	0x9c
	.uleb128 0x12
	.long	.LASF54
	.byte	0x1
	.byte	0x2d
	.quad	.LFB25
	.quad	.LFE25-.LFB25
	.uleb128 0x1
	.byte	0x9c
	.long	0x381
	.uleb128 0x13
	.string	"val"
	.byte	0x1
	.byte	0x2d
	.long	0x9b
	.uleb128 0x1
	.byte	0x55
	.byte	0
	.uleb128 0xd
	.long	.LASF53
	.byte	0x1
	.byte	0x32
	.long	0x9b
	.quad	.LFB26
	.quad	.LFE26-.LFB26
	.uleb128 0x1
	.byte	0x9c
	.uleb128 0x12
	.long	.LASF55
	.byte	0x1
	.byte	0x37
	.quad	.LFB27
	.quad	.LFE27-.LFB27
	.uleb128 0x1
	.byte	0x9c
	.long	0x3c9
	.uleb128 0x13
	.string	"val"
	.byte	0x1
	.byte	0x37
	.long	0x9b
	.uleb128 0x1
	.byte	0x55
	.byte	0
	.uleb128 0x14
	.long	.LASF56
	.byte	0x5
	.byte	0x5
	.long	0x9b
	.uleb128 0xa
	.byte	0xe
	.long	currentthread@dtpoff, 0
	.byte	0xe0
	.uleb128 0x14
	.long	.LASF57
	.byte	0x5
	.byte	0x6
	.long	0x9b
	.uleb128 0xa
	.byte	0xe
	.long	mainstack@dtpoff, 0
	.byte	0xe0
	.uleb128 0x14
	.long	.LASF58
	.byte	0x5
	.byte	0x7
	.long	0x9b
	.uleb128 0xa
	.byte	0xe
	.long	tempstack@dtpoff, 0
	.byte	0xe0
	.uleb128 0x15
	.long	.LASF59
	.byte	0x6
	.byte	0xa8
	.long	0x268
	.uleb128 0x15
	.long	.LASF60
	.byte	0x6
	.byte	0xa9
	.long	0x268
	.uleb128 0x16
	.long	.LASF61
	.long	.LASF61
	.byte	0x7
	.byte	0x39
	.uleb128 0x16
	.long	.LASF62
	.long	.LASF62
	.byte	0x7
	.byte	0x4c
	.byte	0
	.section	.debug_abbrev,"",@progbits
.Ldebug_abbrev0:
	.uleb128 0x1
	.uleb128 0x11
	.byte	0x1
	.uleb128 0x25
	.uleb128 0xe
	.uleb128 0x13
	.uleb128 0xb
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x1b
	.uleb128 0xe
	.uleb128 0x11
	.uleb128 0x1
	.uleb128 0x12
	.uleb128 0x7
	.uleb128 0x10
	.uleb128 0x17
	.byte	0
	.byte	0
	.uleb128 0x2
	.uleb128 0x24
	.byte	0
	.uleb128 0xb
	.uleb128 0xb
	.uleb128 0x3e
	.uleb128 0xb
	.uleb128 0x3
	.uleb128 0xe
	.byte	0
	.byte	0
	.uleb128 0x3
	.uleb128 0x16
	.byte	0
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x49
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0x4
	.uleb128 0x24
	.byte	0
	.uleb128 0xb
	.uleb128 0xb
	.uleb128 0x3e
	.uleb128 0xb
	.uleb128 0x3
	.uleb128 0x8
	.byte	0
	.byte	0
	.uleb128 0x5
	.uleb128 0xf
	.byte	0
	.uleb128 0xb
	.uleb128 0xb
	.byte	0
	.byte	0
	.uleb128 0x6
	.uleb128 0xf
	.byte	0
	.uleb128 0xb
	.uleb128 0xb
	.uleb128 0x49
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0x7
	.uleb128 0x13
	.byte	0x1
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0xb
	.uleb128 0xb
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x1
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0x8
	.uleb128 0xd
	.byte	0
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x38
	.uleb128 0xb
	.byte	0
	.byte	0
	.uleb128 0x9
	.uleb128 0xd
	.byte	0
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0x5
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x38
	.uleb128 0xb
	.byte	0
	.byte	0
	.uleb128 0xa
	.uleb128 0x16
	.byte	0
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.byte	0
	.byte	0
	.uleb128 0xb
	.uleb128 0x1
	.byte	0x1
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x1
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0xc
	.uleb128 0x21
	.byte	0
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x2f
	.uleb128 0xb
	.byte	0
	.byte	0
	.uleb128 0xd
	.uleb128 0x2e
	.byte	0
	.uleb128 0x3f
	.uleb128 0x19
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x11
	.uleb128 0x1
	.uleb128 0x12
	.uleb128 0x7
	.uleb128 0x40
	.uleb128 0x18
	.uleb128 0x2117
	.uleb128 0x19
	.byte	0
	.byte	0
	.uleb128 0xe
	.uleb128 0x2e
	.byte	0x1
	.uleb128 0x3f
	.uleb128 0x19
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x11
	.uleb128 0x1
	.uleb128 0x12
	.uleb128 0x7
	.uleb128 0x40
	.uleb128 0x18
	.uleb128 0x2117
	.uleb128 0x19
	.uleb128 0x1
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0xf
	.uleb128 0x4109
	.byte	0x1
	.uleb128 0x11
	.uleb128 0x1
	.uleb128 0x31
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0x10
	.uleb128 0x410a
	.byte	0
	.uleb128 0x2
	.uleb128 0x18
	.uleb128 0x2111
	.uleb128 0x18
	.byte	0
	.byte	0
	.uleb128 0x11
	.uleb128 0x4109
	.byte	0x1
	.uleb128 0x11
	.uleb128 0x1
	.uleb128 0x2115
	.uleb128 0x19
	.uleb128 0x31
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0x12
	.uleb128 0x2e
	.byte	0x1
	.uleb128 0x3f
	.uleb128 0x19
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x27
	.uleb128 0x19
	.uleb128 0x11
	.uleb128 0x1
	.uleb128 0x12
	.uleb128 0x7
	.uleb128 0x40
	.uleb128 0x18
	.uleb128 0x2117
	.uleb128 0x19
	.uleb128 0x1
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0x13
	.uleb128 0x5
	.byte	0
	.uleb128 0x3
	.uleb128 0x8
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x2
	.uleb128 0x18
	.byte	0
	.byte	0
	.uleb128 0x14
	.uleb128 0x34
	.byte	0
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x2
	.uleb128 0x18
	.byte	0
	.byte	0
	.uleb128 0x15
	.uleb128 0x34
	.byte	0
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x3f
	.uleb128 0x19
	.uleb128 0x3c
	.uleb128 0x19
	.byte	0
	.byte	0
	.uleb128 0x16
	.uleb128 0x2e
	.byte	0
	.uleb128 0x3f
	.uleb128 0x19
	.uleb128 0x3c
	.uleb128 0x19
	.uleb128 0x6e
	.uleb128 0xe
	.uleb128 0x3
	.uleb128 0xe
	.uleb128 0x3a
	.uleb128 0xb
	.uleb128 0x3b
	.uleb128 0xb
	.byte	0
	.byte	0
	.byte	0
	.section	.debug_aranges,"",@progbits
	.long	0x2c
	.value	0x2
	.long	.Ldebug_info0
	.byte	0x8
	.byte	0
	.value	0
	.value	0
	.quad	.Ltext0
	.quad	.Letext0-.Ltext0
	.quad	0
	.quad	0
	.section	.debug_line,"",@progbits
.Ldebug_line0:
	.section	.debug_str,"MS",@progbits,1
.LASF56:
	.string	"currentthread"
.LASF43:
	.string	"_IO_FILE"
.LASF25:
	.string	"_IO_save_end"
.LASF57:
	.string	"mainstack"
.LASF9:
	.string	"size_t"
.LASF12:
	.string	"sizetype"
.LASF35:
	.string	"_offset"
.LASF19:
	.string	"_IO_write_ptr"
.LASF14:
	.string	"_flags"
.LASF21:
	.string	"_IO_buf_base"
.LASF42:
	.string	"_unused2"
.LASF8:
	.string	"short int"
.LASF26:
	.string	"_markers"
.LASF16:
	.string	"_IO_read_end"
.LASF50:
	.string	"__free_tempstack"
.LASF63:
	.string	"GNU C11 5.2.0 -masm=intel -mtune=generic -march=x86-64 -g -O3"
.LASF2:
	.string	"long long int"
.LASF34:
	.string	"_lock"
.LASF62:
	.string	"munmap"
.LASF0:
	.string	"long int"
.LASF52:
	.string	"get_currentthread"
.LASF31:
	.string	"_cur_column"
.LASF54:
	.string	"set_currentthread"
.LASF47:
	.string	"_pos"
.LASF46:
	.string	"_sbuf"
.LASF30:
	.string	"_old_offset"
.LASF3:
	.string	"long double"
.LASF4:
	.string	"unsigned char"
.LASF53:
	.string	"get_mainstack"
.LASF7:
	.string	"signed char"
.LASF48:
	.string	"long long unsigned int"
.LASF65:
	.string	"/home/collin/Projects/Mellow/runtime"
.LASF6:
	.string	"unsigned int"
.LASF44:
	.string	"_IO_marker"
.LASF33:
	.string	"_shortbuf"
.LASF18:
	.string	"_IO_write_base"
.LASF64:
	.string	"tls.c"
.LASF15:
	.string	"_IO_read_ptr"
.LASF22:
	.string	"_IO_buf_end"
.LASF13:
	.string	"char"
.LASF61:
	.string	"mmap"
.LASF45:
	.string	"_next"
.LASF36:
	.string	"__pad1"
.LASF37:
	.string	"__pad2"
.LASF38:
	.string	"__pad3"
.LASF39:
	.string	"__pad4"
.LASF40:
	.string	"__pad5"
.LASF55:
	.string	"set_mainstack"
.LASF5:
	.string	"short unsigned int"
.LASF49:
	.string	"__init_tempstack"
.LASF1:
	.string	"long unsigned int"
.LASF20:
	.string	"_IO_write_end"
.LASF11:
	.string	"__off64_t"
.LASF28:
	.string	"_fileno"
.LASF27:
	.string	"_chain"
.LASF10:
	.string	"__off_t"
.LASF51:
	.string	"__get_tempstack"
.LASF24:
	.string	"_IO_backup_base"
.LASF59:
	.string	"stdin"
.LASF29:
	.string	"_flags2"
.LASF41:
	.string	"_mode"
.LASF17:
	.string	"_IO_read_base"
.LASF32:
	.string	"_vtable_offset"
.LASF58:
	.string	"tempstack"
.LASF23:
	.string	"_IO_save_base"
.LASF60:
	.string	"stdout"
.LASF66:
	.string	"_IO_lock_t"
	.ident	"GCC: (GNU) 5.2.0"
	.section	.note.GNU-stack,"",@progbits
