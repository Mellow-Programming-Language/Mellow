	.file	"tls.c"
	.intel_syntax noprefix
	.text
.Ltext0:
	.p2align 4,,15
	.globl	__get_tempstack
	.type	__get_tempstack, @function
__get_tempstack:
.LFB50:
	.file 1 "tls.c"
	.loc 1 18 0
	.cfi_startproc
	.loc 1 20 0
	mov	rax, QWORD PTR fs:tempstack@tpoff
	ret
	.cfi_endproc
.LFE50:
	.size	__get_tempstack, .-__get_tempstack
	.p2align 4,,15
	.globl	__init_tempstack
	.type	__init_tempstack, @function
__init_tempstack:
.LFB51:
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
	.loc 1 30 0
	add	rsp, 8
	.cfi_def_cfa_offset 8
	ret
	.cfi_endproc
.LFE51:
	.size	__init_tempstack, .-__init_tempstack
	.p2align 4,,15
	.globl	__free_tempstack
	.type	__free_tempstack, @function
__free_tempstack:
.LFB52:
	.loc 1 33 0
	.cfi_startproc
	.loc 1 34 0
	mov	rdi, QWORD PTR fs:tempstack@tpoff
	mov	esi, 4096
	jmp	munmap
.LVL1:
	.cfi_endproc
.LFE52:
	.size	__free_tempstack, .-__free_tempstack
	.p2align 4,,15
	.globl	get_currentthread
	.type	get_currentthread, @function
get_currentthread:
.LFB53:
	.loc 1 38 0
	.cfi_startproc
	.loc 1 40 0
	mov	rax, QWORD PTR fs:currentthread@tpoff
	ret
	.cfi_endproc
.LFE53:
	.size	get_currentthread, .-get_currentthread
	.p2align 4,,15
	.globl	set_currentthread
	.type	set_currentthread, @function
set_currentthread:
.LFB54:
	.loc 1 43 0
	.cfi_startproc
.LVL2:
	.loc 1 44 0
	mov	QWORD PTR fs:currentthread@tpoff, rdi
	ret
	.cfi_endproc
.LFE54:
	.size	set_currentthread, .-set_currentthread
	.p2align 4,,15
	.globl	get_mainstack
	.type	get_mainstack, @function
get_mainstack:
.LFB55:
	.loc 1 48 0
	.cfi_startproc
	.loc 1 50 0
	mov	rax, QWORD PTR fs:mainstack@tpoff
	ret
	.cfi_endproc
.LFE55:
	.size	get_mainstack, .-get_mainstack
	.p2align 4,,15
	.globl	set_mainstack
	.type	set_mainstack, @function
set_mainstack:
.LFB56:
	.loc 1 53 0
	.cfi_startproc
.LVL3:
	.loc 1 54 0
	mov	QWORD PTR fs:mainstack@tpoff, rdi
	ret
	.cfi_endproc
.LFE56:
	.size	set_mainstack, .-set_mainstack
	.section	.tbss,"awT",@nobits
	.align 16
	.type	tempstack, @object
	.size	tempstack, 8
tempstack:
	.zero	8
	.align 16
	.type	mainstack, @object
	.size	mainstack, 8
mainstack:
	.zero	8
	.align 16
	.type	currentthread, @object
	.size	currentthread, 8
currentthread:
	.zero	8
	.text
.Letext0:
	.file 2 "/usr/lib/gcc/x86_64-linux-gnu/4.8/include/stddef.h"
	.file 3 "/usr/include/x86_64-linux-gnu/bits/types.h"
	.file 4 "/usr/include/libio.h"
	.file 5 "tls.h"
	.file 6 "/usr/include/stdio.h"
	.file 7 "/usr/include/x86_64-linux-gnu/sys/mman.h"
	.section	.debug_info,"",@progbits
.Ldebug_info0:
	.long	0x45b
	.value	0x4
	.long	.Ldebug_abbrev0
	.byte	0x8
	.uleb128 0x1
	.long	.LASF60
	.byte	0x1
	.long	.LASF61
	.long	.LASF62
	.quad	.Ltext0
	.quad	.Letext0-.Ltext0
	.long	.Ldebug_line0
	.uleb128 0x2
	.byte	0x8
	.byte	0x5
	.long	.LASF0
	.uleb128 0x3
	.long	.LASF7
	.byte	0x2
	.byte	0xd4
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
	.byte	0x1
	.byte	0x8
	.long	.LASF2
	.uleb128 0x2
	.byte	0x2
	.byte	0x7
	.long	.LASF3
	.uleb128 0x2
	.byte	0x4
	.byte	0x7
	.long	.LASF4
	.uleb128 0x2
	.byte	0x1
	.byte	0x6
	.long	.LASF5
	.uleb128 0x2
	.byte	0x2
	.byte	0x5
	.long	.LASF6
	.uleb128 0x3
	.long	.LASF8
	.byte	0x3
	.byte	0x83
	.long	0x2d
	.uleb128 0x3
	.long	.LASF9
	.byte	0x3
	.byte	0x84
	.long	0x2d
	.uleb128 0x2
	.byte	0x8
	.byte	0x7
	.long	.LASF10
	.uleb128 0x5
	.byte	0x8
	.uleb128 0x6
	.byte	0x8
	.long	0x95
	.uleb128 0x2
	.byte	0x1
	.byte	0x6
	.long	.LASF11
	.uleb128 0x7
	.long	.LASF41
	.byte	0xd8
	.byte	0x4
	.byte	0xf5
	.long	0x21c
	.uleb128 0x8
	.long	.LASF12
	.byte	0x4
	.byte	0xf6
	.long	0x46
	.byte	0
	.uleb128 0x8
	.long	.LASF13
	.byte	0x4
	.byte	0xfb
	.long	0x8f
	.byte	0x8
	.uleb128 0x8
	.long	.LASF14
	.byte	0x4
	.byte	0xfc
	.long	0x8f
	.byte	0x10
	.uleb128 0x8
	.long	.LASF15
	.byte	0x4
	.byte	0xfd
	.long	0x8f
	.byte	0x18
	.uleb128 0x8
	.long	.LASF16
	.byte	0x4
	.byte	0xfe
	.long	0x8f
	.byte	0x20
	.uleb128 0x8
	.long	.LASF17
	.byte	0x4
	.byte	0xff
	.long	0x8f
	.byte	0x28
	.uleb128 0x9
	.long	.LASF18
	.byte	0x4
	.value	0x100
	.long	0x8f
	.byte	0x30
	.uleb128 0x9
	.long	.LASF19
	.byte	0x4
	.value	0x101
	.long	0x8f
	.byte	0x38
	.uleb128 0x9
	.long	.LASF20
	.byte	0x4
	.value	0x102
	.long	0x8f
	.byte	0x40
	.uleb128 0x9
	.long	.LASF21
	.byte	0x4
	.value	0x104
	.long	0x8f
	.byte	0x48
	.uleb128 0x9
	.long	.LASF22
	.byte	0x4
	.value	0x105
	.long	0x8f
	.byte	0x50
	.uleb128 0x9
	.long	.LASF23
	.byte	0x4
	.value	0x106
	.long	0x8f
	.byte	0x58
	.uleb128 0x9
	.long	.LASF24
	.byte	0x4
	.value	0x108
	.long	0x254
	.byte	0x60
	.uleb128 0x9
	.long	.LASF25
	.byte	0x4
	.value	0x10a
	.long	0x25a
	.byte	0x68
	.uleb128 0x9
	.long	.LASF26
	.byte	0x4
	.value	0x10c
	.long	0x46
	.byte	0x70
	.uleb128 0x9
	.long	.LASF27
	.byte	0x4
	.value	0x110
	.long	0x46
	.byte	0x74
	.uleb128 0x9
	.long	.LASF28
	.byte	0x4
	.value	0x112
	.long	0x70
	.byte	0x78
	.uleb128 0x9
	.long	.LASF29
	.byte	0x4
	.value	0x116
	.long	0x54
	.byte	0x80
	.uleb128 0x9
	.long	.LASF30
	.byte	0x4
	.value	0x117
	.long	0x62
	.byte	0x82
	.uleb128 0x9
	.long	.LASF31
	.byte	0x4
	.value	0x118
	.long	0x260
	.byte	0x83
	.uleb128 0x9
	.long	.LASF32
	.byte	0x4
	.value	0x11c
	.long	0x270
	.byte	0x88
	.uleb128 0x9
	.long	.LASF33
	.byte	0x4
	.value	0x125
	.long	0x7b
	.byte	0x90
	.uleb128 0x9
	.long	.LASF34
	.byte	0x4
	.value	0x12e
	.long	0x8d
	.byte	0x98
	.uleb128 0x9
	.long	.LASF35
	.byte	0x4
	.value	0x12f
	.long	0x8d
	.byte	0xa0
	.uleb128 0x9
	.long	.LASF36
	.byte	0x4
	.value	0x130
	.long	0x8d
	.byte	0xa8
	.uleb128 0x9
	.long	.LASF37
	.byte	0x4
	.value	0x131
	.long	0x8d
	.byte	0xb0
	.uleb128 0x9
	.long	.LASF38
	.byte	0x4
	.value	0x132
	.long	0x34
	.byte	0xb8
	.uleb128 0x9
	.long	.LASF39
	.byte	0x4
	.value	0x134
	.long	0x46
	.byte	0xc0
	.uleb128 0x9
	.long	.LASF40
	.byte	0x4
	.value	0x136
	.long	0x276
	.byte	0xc4
	.byte	0
	.uleb128 0xa
	.long	.LASF63
	.byte	0x4
	.byte	0x9a
	.uleb128 0x7
	.long	.LASF42
	.byte	0x18
	.byte	0x4
	.byte	0xa0
	.long	0x254
	.uleb128 0x8
	.long	.LASF43
	.byte	0x4
	.byte	0xa1
	.long	0x254
	.byte	0
	.uleb128 0x8
	.long	.LASF44
	.byte	0x4
	.byte	0xa2
	.long	0x25a
	.byte	0x8
	.uleb128 0x8
	.long	.LASF45
	.byte	0x4
	.byte	0xa6
	.long	0x46
	.byte	0x10
	.byte	0
	.uleb128 0x6
	.byte	0x8
	.long	0x223
	.uleb128 0x6
	.byte	0x8
	.long	0x9c
	.uleb128 0xb
	.long	0x95
	.long	0x270
	.uleb128 0xc
	.long	0x86
	.byte	0
	.byte	0
	.uleb128 0x6
	.byte	0x8
	.long	0x21c
	.uleb128 0xb
	.long	0x95
	.long	0x286
	.uleb128 0xc
	.long	0x86
	.byte	0x13
	.byte	0
	.uleb128 0x2
	.byte	0x8
	.byte	0x5
	.long	.LASF46
	.uleb128 0x2
	.byte	0x8
	.byte	0x7
	.long	.LASF47
	.uleb128 0xd
	.long	.LASF50
	.byte	0x1
	.byte	0x11
	.long	0x8d
	.quad	.LFB50
	.quad	.LFE50-.LFB50
	.uleb128 0x1
	.byte	0x9c
	.uleb128 0xe
	.long	.LASF48
	.byte	0x1
	.byte	0x16
	.quad	.LFB51
	.quad	.LFE51-.LFB51
	.uleb128 0x1
	.byte	0x9c
	.long	0x2ff
	.uleb128 0xf
	.quad	.LVL0
	.long	0x41a
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
	.long	.LASF49
	.byte	0x1
	.byte	0x20
	.quad	.LFB52
	.quad	.LFE52-.LFB52
	.uleb128 0x1
	.byte	0x9c
	.long	0x332
	.uleb128 0x11
	.quad	.LVL1
	.long	0x448
	.uleb128 0x10
	.uleb128 0x1
	.byte	0x54
	.uleb128 0x3
	.byte	0xa
	.value	0x1000
	.byte	0
	.byte	0
	.uleb128 0xd
	.long	.LASF51
	.byte	0x1
	.byte	0x25
	.long	0x8d
	.quad	.LFB53
	.quad	.LFE53-.LFB53
	.uleb128 0x1
	.byte	0x9c
	.uleb128 0x12
	.long	.LASF53
	.byte	0x1
	.byte	0x2a
	.quad	.LFB54
	.quad	.LFE54-.LFB54
	.uleb128 0x1
	.byte	0x9c
	.long	0x37a
	.uleb128 0x13
	.string	"val"
	.byte	0x1
	.byte	0x2a
	.long	0x8d
	.uleb128 0x1
	.byte	0x55
	.byte	0
	.uleb128 0xd
	.long	.LASF52
	.byte	0x1
	.byte	0x2f
	.long	0x8d
	.quad	.LFB55
	.quad	.LFE55-.LFB55
	.uleb128 0x1
	.byte	0x9c
	.uleb128 0x12
	.long	.LASF54
	.byte	0x1
	.byte	0x34
	.quad	.LFB56
	.quad	.LFE56-.LFB56
	.uleb128 0x1
	.byte	0x9c
	.long	0x3c2
	.uleb128 0x13
	.string	"val"
	.byte	0x1
	.byte	0x34
	.long	0x8d
	.uleb128 0x1
	.byte	0x55
	.byte	0
	.uleb128 0x14
	.long	.LASF55
	.byte	0x5
	.byte	0x5
	.long	0x8d
	.uleb128 0xa
	.byte	0xe
	.long	currentthread@dtpoff, 0
	.byte	0xe0
	.uleb128 0x14
	.long	.LASF56
	.byte	0x5
	.byte	0x6
	.long	0x8d
	.uleb128 0xa
	.byte	0xe
	.long	mainstack@dtpoff, 0
	.byte	0xe0
	.uleb128 0x14
	.long	.LASF57
	.byte	0x5
	.byte	0x7
	.long	0x8d
	.uleb128 0xa
	.byte	0xe
	.long	tempstack@dtpoff, 0
	.byte	0xe0
	.uleb128 0x15
	.long	.LASF58
	.byte	0x6
	.byte	0xa8
	.long	0x25a
	.uleb128 0x15
	.long	.LASF59
	.byte	0x6
	.byte	0xa9
	.long	0x25a
	.uleb128 0x16
	.long	.LASF64
	.byte	0x7
	.byte	0x39
	.long	0x8d
	.long	0x448
	.uleb128 0x17
	.long	0x8d
	.uleb128 0x17
	.long	0x34
	.uleb128 0x17
	.long	0x46
	.uleb128 0x17
	.long	0x46
	.uleb128 0x17
	.long	0x46
	.uleb128 0x17
	.long	0x70
	.byte	0
	.uleb128 0x18
	.long	.LASF65
	.byte	0x7
	.byte	0x4c
	.long	0x46
	.uleb128 0x17
	.long	0x8d
	.uleb128 0x17
	.long	0x34
	.byte	0
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
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x3c
	.uleb128 0x19
	.uleb128 0x1
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0x17
	.uleb128 0x5
	.byte	0
	.uleb128 0x49
	.uleb128 0x13
	.byte	0
	.byte	0
	.uleb128 0x18
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
	.uleb128 0x49
	.uleb128 0x13
	.uleb128 0x3c
	.uleb128 0x19
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
.LASF55:
	.string	"currentthread"
.LASF41:
	.string	"_IO_FILE"
.LASF23:
	.string	"_IO_save_end"
.LASF56:
	.string	"mainstack"
.LASF7:
	.string	"size_t"
.LASF10:
	.string	"sizetype"
.LASF33:
	.string	"_offset"
.LASF17:
	.string	"_IO_write_ptr"
.LASF12:
	.string	"_flags"
.LASF19:
	.string	"_IO_buf_base"
.LASF40:
	.string	"_unused2"
.LASF6:
	.string	"short int"
.LASF24:
	.string	"_markers"
.LASF14:
	.string	"_IO_read_end"
.LASF60:
	.string	"GNU C 4.8.4 -masm=intel -mtune=generic -march=x86-64 -g -O3 -fstack-protector"
.LASF49:
	.string	"__free_tempstack"
.LASF46:
	.string	"long long int"
.LASF32:
	.string	"_lock"
.LASF65:
	.string	"munmap"
.LASF0:
	.string	"long int"
.LASF51:
	.string	"get_currentthread"
.LASF29:
	.string	"_cur_column"
.LASF53:
	.string	"set_currentthread"
.LASF45:
	.string	"_pos"
.LASF44:
	.string	"_sbuf"
.LASF28:
	.string	"_old_offset"
.LASF2:
	.string	"unsigned char"
.LASF52:
	.string	"get_mainstack"
.LASF5:
	.string	"signed char"
.LASF47:
	.string	"long long unsigned int"
.LASF62:
	.string	"/home/creeser/Projects/Mellow/runtime"
.LASF4:
	.string	"unsigned int"
.LASF42:
	.string	"_IO_marker"
.LASF31:
	.string	"_shortbuf"
.LASF16:
	.string	"_IO_write_base"
.LASF61:
	.string	"tls.c"
.LASF13:
	.string	"_IO_read_ptr"
.LASF20:
	.string	"_IO_buf_end"
.LASF11:
	.string	"char"
.LASF64:
	.string	"mmap"
.LASF43:
	.string	"_next"
.LASF34:
	.string	"__pad1"
.LASF35:
	.string	"__pad2"
.LASF36:
	.string	"__pad3"
.LASF37:
	.string	"__pad4"
.LASF38:
	.string	"__pad5"
.LASF54:
	.string	"set_mainstack"
.LASF3:
	.string	"short unsigned int"
.LASF48:
	.string	"__init_tempstack"
.LASF1:
	.string	"long unsigned int"
.LASF18:
	.string	"_IO_write_end"
.LASF9:
	.string	"__off64_t"
.LASF26:
	.string	"_fileno"
.LASF25:
	.string	"_chain"
.LASF8:
	.string	"__off_t"
.LASF50:
	.string	"__get_tempstack"
.LASF22:
	.string	"_IO_backup_base"
.LASF58:
	.string	"stdin"
.LASF27:
	.string	"_flags2"
.LASF39:
	.string	"_mode"
.LASF15:
	.string	"_IO_read_base"
.LASF30:
	.string	"_vtable_offset"
.LASF57:
	.string	"tempstack"
.LASF21:
	.string	"_IO_save_base"
.LASF59:
	.string	"stdout"
.LASF63:
	.string	"_IO_lock_t"
	.ident	"GCC: (Ubuntu 4.8.4-2ubuntu1~14.04) 4.8.4"
	.section	.note.GNU-stack,"",@progbits
