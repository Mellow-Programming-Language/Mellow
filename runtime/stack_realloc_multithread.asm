
    ; Defined in realloc_stack.c or tls.asm
    extern get_mainstack
    ; Defined in realloc_stack.c
    extern __mremap_stack

    SECTION .text

    ; extern void __realloc_stack(ThreadData* curThread);
    ; This function will allocate stack space twice as big as the previous
    ; allocated stack. In order to do this, this function must execute a stack
    ; other than the one it's resizing
    global __realloc_stack
__realloc_stack:
    ; We push rbp simply so that we have a start to the "linked list" of rbp's
    ; we need to fix in the new allocation. We don't actually use it
    push    rbp

    ; ThreadData* curThread is in rdi

    ; Preserve old rsp, setting up for __mremap_stack call
    mov     rsi, rsp

    ; Switch to the main thread stack
    call    get_mainstack
    mov     rsp, rax

    ; This call will invalidate the old thread stack, meaning once we come off
    ; the temporary stack, the move must be directly to the new allocation
    call    __mremap_stack
    ; We now have the new rsp in rax. This new rsp points into the newly
    ; allocated stack
    mov     rsp, rax

    pop     rbp
    ret
