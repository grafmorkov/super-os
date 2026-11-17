/* SUPER OS - 64-bit hardware glue: GDT/TSS, IDT, PIC, PIT and ISR stubs.
 *
 * Everything here is called from the Quant kernel (kernel/kmain.qu) or by the
 * CPU itself. The Quant side declares these as `@export("...") extern`.
 */

.intel_syntax noprefix

.set KERNEL_CS, 0x08
.set KERNEL_DS, 0x10
.set USER_DS,   0x1B            /* 0x18 | RPL 3 */
.set USER_CS,   0x23            /* 0x20 | RPL 3 */
.set TSS_SEL,   0x28

.set SYS_STACK_SIZE, 65536

.section .text

/* ------------------------------------------------------------------ */
/* cpu_init - install GDT/TSS/IDT, remap the PIC and start the PIT.    */
/* ------------------------------------------------------------------ */
.global cpu_init
cpu_init:
    cli

    /* ---- TSS descriptor: patch base address into the GDT ---- */
    lea rax, [rip + tss]
    mov rcx, rax
    mov word ptr [rip + gdt + 0x28 + 2], cx
    shr rcx, 16
    mov byte ptr [rip + gdt + 0x28 + 4], cl
    shr rcx, 8
    mov byte ptr [rip + gdt + 0x28 + 7], cl
    shr rcx, 8
    mov dword ptr [rip + gdt + 0x28 + 8], ecx
    mov word ptr [rip + gdt + 0x28 + 0], 103       /* limit = sizeof(TSS)-1 */
    mov byte ptr [rip + gdt + 0x28 + 5], 0x89      /* present, 64-bit TSS */
    mov byte ptr [rip + gdt + 0x28 + 6], 0x00
    mov dword ptr [rip + gdt + 0x28 + 12], 0

    /* ---- TSS: ring-0 stack used for interrupts coming from ring 3 ---- */
    lea rax, [rip + syscall_stack_top]
    mov qword ptr [rip + tss + 4], rax
    mov word ptr [rip + tss + 102], 104            /* I/O map = end of TSS */

    lgdt [rip + gdtr]

    mov ax, KERNEL_DS
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov ax, TSS_SEL
    ltr ax

    /* ---- IDT: zero all 256 gates ---- */
    lea rdi, [rip + idt]
    xor eax, eax
    mov ecx, 4096 / 8
    rep stosq

    /* CPU exceptions 0..31 -> exc_stub */
    xor r9d, r9d
.Lexc_loop:
    mov rdi, r9
    lea rsi, [rip + exc_stub]
    mov edx, 0x8E
    call idt_set
    inc r9d
    cmp r9d, 32
    jb .Lexc_loop

    /* IRQ0 (timer), IRQ1 (keyboard), IRQ4 (COM1 receive) */
    mov rdi, 32
    lea rsi, [rip + irq0_stub]
    mov edx, 0x8E
    call idt_set

    mov rdi, 33
    lea rsi, [rip + irq1_stub]
    mov edx, 0x8E
    call idt_set

    mov rdi, 36
    lea rsi, [rip + irq4_stub]
    mov edx, 0x8E
    call idt_set

    /* int 0x80 - callable from ring 3 */
    mov rdi, 0x80
    lea rsi, [rip + syscall_stub]
    mov edx, 0xEE
    call idt_set

    lidt [rip + idtr]

    /* ---- PIC remap: IRQ0..15 -> vectors 32..47 ---- */
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al

    /* Unmask IRQ0, IRQ1 and IRQ4 on the master; mask the slave. */
    mov al, 0xEC
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    /* ---- PIT: channel 0, mode 3, ~100 Hz ---- */
    mov al, 0x36
    out 0x43, al
    mov ax, 11932
    out 0x40, al
    mov al, ah
    out 0x40, al

    ret

/* idt_set(vector=rdi, handler=rsi, flags=dl) */
idt_set:
    lea r8, [rip + idt]
    shl rdi, 4
    add r8, rdi
    mov rax, rsi
    mov word ptr [r8 + 0], ax
    mov word ptr [r8 + 2], KERNEL_CS
    mov byte ptr [r8 + 4], 0
    mov byte ptr [r8 + 5], dl
    shr rax, 16
    mov word ptr [r8 + 6], ax
    shr rax, 16
    mov dword ptr [r8 + 8], eax
    mov dword ptr [r8 + 12], 0
    ret

/* ------------------------------------------------------------------ */
/* Small helpers                                                       */
/* ------------------------------------------------------------------ */

.global enable_interrupts
enable_interrupts:
    sti
    ret

.global disable_interrupts
disable_interrupts:
    cli
    ret

/* Wait for one interrupt with interrupts enabled. */
.global hlt_once
hlt_once:
    sti
    hlt
    ret

.global get_ticks
get_ticks:
    mov rax, qword ptr [rip + ticks]
    ret

.global read_cr2
read_cr2:
    mov rax, cr2
    ret

.global user_get_exit_code
user_get_exit_code:
    mov rax, qword ptr [rip + user_exit_code]
    ret

/* user_exit(code): mark the running ring-3 program as finished. */
.global user_exit
user_exit:
    mov qword ptr [rip + user_exit_code], rdi
    mov qword ptr [rip + user_exit_flag], 1
    ret

/* Hard reboot through the keyboard controller. */
.global machine_reboot
machine_reboot:
    cli
    mov al, 0xFE
    out 0x64, al
1:
    hlt
    jmp 1b

/* ------------------------------------------------------------------ */
/* Ring-3 entry                                                        */
/* ------------------------------------------------------------------ */
/* enter_user(entry=rdi, stack_top=rsi)
 * Saves the kernel callee-saved registers and the kernel stack pointer, then
 * iretq's into ring 3. sys_exit() restores this frame and returns here.
 */
.global enter_user
enter_user:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov qword ptr [rip + saved_kernel_rsp], rsp
    mov qword ptr [rip + user_exit_flag], 0
    mov qword ptr [rip + user_exit_code], 0

    push USER_DS                 /* SS */
    push rsi                     /* RSP */
    push 0x202                   /* RFLAGS: IF=1 */
    push USER_CS                 /* CS */
    push rdi                     /* RIP */
    iretq

/* ------------------------------------------------------------------ */
/* ISR stubs                                                           */
/* ------------------------------------------------------------------ */
/* All stubs save the full register set so a ring-3 program can be resumed
 * exactly where it was interrupted. Frame layout after the pushes (index of
 * *u64 from RSP):
 *   0 r15  1 r14  2 r13  3 r12  4 r11  5 r10  6 r9  7 r8
 *   8 rbp  9 rdi 10 rsi 11 rdx 12 rcx 13 rbx 14 rax
 */
.macro SAVE_REGS
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
.endm

.macro RESTORE_REGS
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
.endm

/* Timer tick. */
irq0_stub:
    SAVE_REGS
    inc qword ptr [rip + ticks]
    mov al, 0x20
    out 0x20, al
    RESTORE_REGS
    iretq

/* PS/2 keyboard: scan code -> Quant keyboard_irq(). */
irq1_stub:
    SAVE_REGS
    xor eax, eax
    in al, 0x60
    movzx edi, al
    call keyboard_irq
    mov al, 0x20
    out 0x20, al
    RESTORE_REGS
    iretq

/* COM1 receive: drain the whole FIFO, one byte at a time. */
irq4_stub:
    SAVE_REGS
.Lserial_rx:
    mov dx, 0x3FD
    in al, dx
    test al, 1
    jz .Lserial_rx_done
    mov dx, 0x3F8
    in al, dx
    movzx edi, al
    call serial_irq
    jmp .Lserial_rx
.Lserial_rx_done:
    mov al, 0x20
    out 0x20, al
    RESTORE_REGS
    iretq

/* CPU exception: report and stop. CR2 holds the faulting address for #PF. */
exc_stub:
    SAVE_REGS
    mov rdi, cr2
    call kernel_exception
1:
    cli
    hlt
    jmp 1b

/* int 0x80: Quant gets a pointer to the saved register frame. */
syscall_stub:
    SAVE_REGS
    mov rdi, rsp
    call syscall_handler
    cmp qword ptr [rip + user_exit_flag], 0
    jne .Luser_exit
    RESTORE_REGS
    iretq

.Luser_exit:
    mov qword ptr [rip + user_exit_flag], 0
    mov rsp, qword ptr [rip + saved_kernel_rsp]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

/* ------------------------------------------------------------------ */
/* Data                                                               */
/* ------------------------------------------------------------------ */
.section .data

.align 16
.global gdt
gdt:
    .quad 0x0000000000000000       /* 0x00 null */
    .quad 0x00AF9A000000FFFF       /* 0x08 kernel code */
    .quad 0x00CF92000000FFFF       /* 0x10 kernel data */
    .quad 0x00CFF2000000FFFF       /* 0x18 user data (DPL 3) */
    .quad 0x00AFFA000000FFFF       /* 0x20 user code (DPL 3) */
    .quad 0x0000000000000000       /* 0x28 TSS descriptor (patched) */
    .quad 0x0000000000000000
gdt_end:

.align 16
gdtr:
    .word gdt_end - gdt - 1
    .quad gdt

.align 16
idtr:
    .word 4095
    .quad idt

.align 16
tss:
    .long 0                        /* reserved */
    .quad 0                        /* rsp0 (patched) */
    .quad 0                        /* rsp1 */
    .quad 0                        /* rsp2 */
    .quad 0                        /* reserved */
    .quad 0, 0, 0, 0, 0, 0, 0      /* ist1..ist7 */
    .quad 0                        /* reserved */
    .word 0                        /* reserved */
    .word 104                      /* i/o map base */
tss_end:

.align 8
ticks:            .quad 0
user_exit_flag:   .quad 0
user_exit_code:   .quad 0
saved_kernel_rsp: .quad 0

.section .bss
.align 16
idt:
    .skip 4096

.align 16
syscall_stack_bottom:
    .skip SYS_STACK_SIZE
syscall_stack_top:
