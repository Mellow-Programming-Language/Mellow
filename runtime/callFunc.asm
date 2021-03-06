
    extern malloc
    extern __GC_malloc_wrapped
    extern __GC_realloc_wrapped
    extern __GC_mellow_add_alloc_wrapped

    SECTION .bss
    global mainstack
    global currentthread
mainstack:      resq 1 ; Stored mainstack rsp
currentthread:  resq 1 ; Pointer to current thread

    SECTION .text

    ; extern void* __mellow_use_main_stack(...)
    ; wrapped function passed in r10
    global __mellow_use_main_stack
__mellow_use_main_stack:
    ; Note that this function may take some arbitrary set of arguments, possibly
    ; using all argument registers, and possibly having pushed arguments to the
    ; stack.
    ;
    ; Note that we have not set up the normal stack frame, so [rsp] is the
    ; return address on the stack
    ;
    ; TODO: It is the responsibility of this function to pass any stack
    ; arguments to the OS stack before the call is made. Once we start
    ; supporting stack-pushed arguments, [rsp] will point to the top of those
    ; arguments, so we'll probably need to start pushing the size of the stack
    ; arguments (usually 0 bytes) as part of the signature of this function, so
    ; that we know what to memcpy to the OS stack, since no registers will be
    ; free to track that

    ; Get curThread pointer
    mov     r11, qword [currentthread]
    ; Set curThread StackCur value with the current rsp of the green thread
    ; stack
    mov     qword [r11+24], rsp   ; ThreadData->t_StackCur
    ; Set stack pointer to the real OS-provided stack. Note that we don't save
    ; this value back off later; there's no reason to. We're using it purely for
    ; scratch space, and nothing of value is on it after we're done with it
    mov     rsp, qword [mainstack]

    ; TODO: We need to handle transfer of any stack-allocated arguments here-ish

    ; Call the function we're wrapping
    call    r10
    ; Get curThread pointer
    mov     r11, qword [currentthread]
    ; Restore the green thread stack
    mov     rsp, qword [r11+24]   ; ThreadData->t_StackCur
    ; Return, possibly with a populated rax
    ret

    ; extern void* __GC_malloc(uint64_t alloc_size, GC_Env* gc_env)
    ; which calls
    ; __GC_malloc_wrapped(
    ;     uint64_t size, GC_Env* gc_env, void** rsp, void** stack_bot
    ; )
    global __GC_malloc
__GC_malloc:
    mov     rdx, rsp
    ; Get curThread pointer
    mov     rcx, qword [currentthread]
    mov     rcx, qword [rcx+16]   ; ThreadData->t_StackBot
    mov     r10, __GC_malloc_wrapped
    call    __mellow_use_main_stack
    ret

    ; extern void* __GC_realloc(uint64_t alloc_size, GC_Env* gc_env)
    ; which calls
    ; __GC_realloc_wrapped(
    ;     void* ptr, uint64_t size, GC_Env* gc_env, void** rsp, void** stack_bot
    ; )
    global __GC_realloc
__GC_realloc:
    mov     rcx, rsp
    ; Get curThread pointer
    mov     r8, qword [currentthread]
    mov     r8, qword [r8+16]   ; ThreadData->t_StackBot
    mov     r10, __GC_realloc_wrapped
    call    __mellow_use_main_stack
    ret

    ; extern void __GC_mellow_add_alloc(
    ;     void* ptr, uint64_t size, GC_Env* gc_env
    ; )
    ; which calls
    ; extern void __GC_mellow_add_alloc_wrapped(
    ;     void* ptr, uint64_t size, GC_Env* gc_env
    ; )
    global __GC_mellow_add_alloc
__GC_mellow_add_alloc:
    mov     r10, __GC_mellow_add_alloc_wrapped
    call    __mellow_use_main_stack
    ret

    ; extern void yield();
    global yield
yield:
    ; Note that we have not set up the normal stack frame, so [rsp] is the
    ; return address on the stack, and rbp is whatever it is from the function
    ; that called yield()

    ; Get curThread pointer
    mov     rdx, qword [currentthread]
    ; Get return address
    mov     rax, [rsp]
    ; Pop return address off the stack
    add     rsp, 8
    ; Set validity of thread
    mov     byte [rdx+48], 1 ; ThreadData->stillValid
    ; Set return address to continue execution
    mov     [rdx+8], rax  ; ThreadData->curFuncAddr
    ; Set curThread StackCur value, now that rsp is pointing to the top of
    ; the stack of the function that just yielded
    mov     [rdx+24], rsp   ; ThreadData->t_StackCur
    ; Save rbp for thread
    mov     [rdx+40], rbp ; ThreadData->t_rbp

    jmp     schedulerReturn


    ; extern void callFunc(ThreadData* curThread);
    global callFunc
callFunc:
    push    rbp                     ; set up stack frame
    mov     rbp, rsp

    ; ThreadData* thread is initially in rdi
    mov     rcx, rdi            ; ThreadData* thread

    ; Set the currentthread value
    mov     qword [currentthread], rcx ; ThreadData* thread

    ; Determine if we are starting a new thread, or if we're continuing
    ; execution
    mov     r8, qword [rcx+8] ; ThreadData->curFuncAddr (0 if start of thread)
    test    r8, r8
    ; If not zero, then continue where we left off
    jne     continueThread

    ; If we get here, we're starting the execution of a new thread

    ; Since we're starting a new thread, grab and save the funcAddr
    mov     r11, qword [rcx]    ; ThreadData->funcAddr
    mov     qword [rcx+8], r11  ; ThreadData->curFuncAddr, init to start of func

    ; Use the gcEnv field (which shares space in an anonymous union with
    ; funcAddr, which we no longer need to store) to malloc a new GC_Env object
    push    rcx
    mov     rdi, 48             ; sizeof(GC_Env)
    call    malloc
    pop     rcx

    ; Initialize the new GC_Env object
    mov     qword [rax], 0      ; Set GC_Env->allocs to NULL
    mov     qword [rax+8], 0    ; Set GC_Env->allocs_len to 0
    mov     qword [rax+16], 0   ; Set GC_Env->allocs_end to 0
    mov     qword [rax+24], 0   ; Set GC_Env->ptr_hashset_t to 0
    mov     qword [rax+32], 0   ; Set GC_Env->last_collection to 0
    mov     qword [rax+40], 0   ; Set GC_Env->total_alloced to 0
    ; Set ThreadData->gcEnv to the new GC_Env object
    mov     qword [rcx], rax

    ; Set edi (rdi) to stackArgsSize (64 bit registers are upper-cleared when
    ; assigned by 32-bit mov's)
    mov     edi, dword [rcx+52] ; ThreadData->stackArgsSize
    ; Grab other necessary ThreadData fields
    mov     rdx, qword [rcx+16] ; ThreadData->t_StackBot
    mov     rax, qword [rcx+56] ; ThreadData->regVars

    ; Set stack pointer to be before arguments. Note that rdi is set by edi
    sub     rdx, rdi
    ; Allocate 8 bytes on stack for return address
    sub     rdx, 8
    mov     qword [rdx], schedulerReturn

    ; Store the value of the main stack pointer, and store rbp as top value
    push    rbp
    mov     qword [mainstack], rsp
    mov     rsp, rdx

    mov     r11, qword [rcx+8]  ; ThreadData->curFuncAddr, start of function

    ; Move the register function arguments into the relevant registers
    mov     rdi, qword [rax]
    mov     rsi, qword [rax+8]
    mov     rdx, qword [rax+16]
    mov     rcx, qword [rax+24]
    mov     r8, qword [rax+32]
    mov     r9, qword [rax+40]
    movsd   xmm0, [rax+48]
    movsd   xmm1, [rax+56]
    movsd   xmm2, [rax+64]
    movsd   xmm3, [rax+72]
    movsd   xmm4, [rax+80]
    movsd   xmm5, [rax+88]
    movsd   xmm6, [rax+96]
    movsd   xmm7, [rax+104]

    jmp     r11                     ; Call function


continueThread:
    ; ThreadData* thread is in rcx
    ; In order to restart execution, we need to set rsp to correct value,
    ; and then "return" to the previous stage of execution. As part of setting
    ; up for a clean return, push rbp as the last thing on the mainstack
    push    rbp
    ; Save mainstack rsp
    mov     qword [mainstack], rsp
    ; Set rsp to StackCur of current thread
    mov     rsp, qword [rcx+24] ; ThreadData->t_StackCur
    ; Set rbp to t_rbp of current thread
    mov     rbp, qword [rcx+40] ; ThreadData->t_rbp
    ; Set stillValid to 0, to account for possibly naturally returning from
    ; the function at the end of its execution. A thread is still valid if
    ; stillValid != 0 OR curFuncAddr == 0 (meaning thread hasn't started yet)
    mov     byte [rcx+48], 0    ; ThreadData->stillValid
    ; Get "return" address to return to thread execution point
    mov     rcx, qword [rcx+8] ; ThreadData->curFuncAddr
    ; Jump back into function
    jmp     rcx


schedulerReturn:
    ; Restore the value of the main stack pointer
    mov     rsp, qword [mainstack]
    ; Restore current rbp
    pop     rbp

    mov     rsp, rbp                ; takedown stack frame
    pop     rbp
    ret
