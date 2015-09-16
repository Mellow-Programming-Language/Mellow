
    ; Defined in scheduler.c or tls.asm
    extern __get_tempstack
    ; Defined in scheduler.c
    extern __mremap_stack

    SECTION .text

    ; extern void __realloc_stack(ThreadData* curThread);
    ; This function will allocate stack space twice as big as the previous
    ; allocated stack. In order to do this, this function must execute on its
    ; own temporary stack.
    global __realloc_stack
__realloc_stack:
    ; We push rbp simply so that we have a start to the "linked list" of rbp's
    ; we need to fix in the new allocation. We don't actually use it
    push    rbp

    ; ThreadData* curThread is in rdi

    ; Preserve old rsp, setting up for __mremap_stack call
    mov     rsi, rsp

    ; See realloc_stack.h; the size of the temp stack is (4096). We have the
    ; beginning of our tempstack in rax, so set rsp to the end of the stack
    ; space, minus some buffer because I'm not super sure of these things. Also,
    ; we hand-verify that __get_tempstack does not write to any register other
    ; than rax, though it does write to rax (pushing return address on call)
    call    __get_tempstack
    mov     rsp, rax                ; Lowest address of tempstack in rsp
    add     rsp, 3968               ; Set rsp to the top of the stack - 128

    ; This call will invalidate the old thread stack, meaning once we come off
    ; the temporary stack, the move must be directly to the new allocation
    call    __mremap_stack
    ; We now have the new rsp in rax. This new rsp points into the newly
    ; allocated stack
    mov     rsp, rax

    pop     rbp
    ret
