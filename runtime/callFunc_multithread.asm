
    extern malloc
    extern free

    ; From tls.asm
    extern get_currentthread
    extern set_currentthread
    extern get_mainstack
    extern set_mainstack

    SECTION .text

    ; extern void yield();
    global yield
yield:
    ; Note that we have not set up the normal stack frame, so [rsp] is the the
    ; return address on the stack, and rbp is whatever it is from the function
    ; that called yield()

    ; Get curThread pointer in rax
    call    get_currentthread
    ; Get return address
    mov     rdx, [rsp]
    ; Pop return address off the stack
    add     rsp, 8
    ; Set validity of thread
    mov     byte [rax+48], 1 ; ThreadData->stillValid
    ; Set return address to continue execution
    mov     [rax+8], rdx  ; ThreadData->curFuncAddr
    ; Set curThread StackCur value, now that rsp is pointing to the top of
    ; the stack of the function that just yielded
    mov     [rax+24], rsp   ; ThreadData->t_StackCur
    ; Save rbp for thread
    mov     [rax+40], rbp ; ThreadData->t_rbp

    jmp     schedulerReturn


    ; extern void callFunc(ThreadData* curThread);
    global callFunc
callFunc:
    push    rbp                     ; set up stack frame
    mov     rbp, rsp

    ; ThreadData* curThread is initially in rdi
    mov     rcx,  rdi            ; ThreadData* curThread

    ; Set currentthread pointer to TLS
    call    set_currentthread

    ; curThread is still in rcx, a guarantee we assume about the implementation
    ; of set_currentthread

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
    mov     rdi, 24             ; sizeof(GC_Env)
    call    malloc
    pop     rcx
    ; Initialize the new GC_Env object
    mov     qword [rax], 0      ; Set GC_Env->allocs to NULL
    mov     qword [rax+8], 0    ; Set GC_Env->allocs_len to 0
    mov     qword [rax+16], 0   ; Set GC_Env->allocs_end to 0
    ; Set ThreadData->gcEnv to the new GC_Env object
    mov     qword [rcx], rax

    ; Set r10d (r10) to stackArgsSize (64 bit registers are upper-cleared when
    ; assigned by 32-bit mov's)
    mov     r10d, dword [rcx+52] ; ThreadData->stackArgsSize
    ; Grab other necessary ThreadData fields
    mov     rdx,  qword [rcx+16] ; ThreadData->t_StackBot
    mov     rax,  qword [rcx+56] ; ThreadData->regVars

    ; Set stack pointer to be before arguments
    sub     rdx, r10            ; Note that we're using the value in r10d here
    ; Allocate 8 bytes on stack for return address
    sub     rdx, 8
    mov     qword [rdx], schedulerReturn

    ; Store the value of the main stack pointer, and store rbp as top value
    push    rbp
    mov     rdi, rsp
    call    set_mainstack
    mov     rsp, rdx

    mov     r11, qword [rcx+8]  ; ThreadData->curFuncAddr, start of function

    ; Move the register function arguments into the relevant registers
    mov     rdi,  qword [rax]
    mov     rsi,  qword [rax+8]
    mov     rdx,  qword [rax+16]
    mov     rcx,  qword [rax+24]
    mov     r8,   qword [rax+32]
    mov     r9,   qword [rax+40]
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
    mov     rdi, rsp
    call    set_mainstack
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
    call    get_mainstack
    mov     rsp, rax
    ; Restore current rbp
    pop     rbp

    mov     rsp, rbp                ; takedown stack frame
    pop     rbp
    ret
