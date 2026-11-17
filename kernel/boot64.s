/* SUPER OS 64-bit entry (Quant kernel side).
 *
 * boot32 copies this flat image to KERNEL64_BASE and jumps here in long mode
 * with EBP holding the Multiboot info pointer.
 */

.intel_syntax noprefix

.set KERNEL64_BASE, 0x200000

.section .text.boot, "ax"
.code64
.global _start64
_start64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    lea rsp, [rip + kstack_top]
    mov edi, ebp                   /* Multiboot info pointer (before RBP dies) */
    xor rbp, rbp
    call kmain

.global kernel_halt
kernel_halt:
    cli
1:
    hlt
    jmp 1b

/* ------------------------------------------------------------------ */
/* Hardware helpers called from Quant                                  */
/* ------------------------------------------------------------------ */

.global outb
outb:                              /* void outb(i32 port, i32 value) */
    mov dx, di
    mov al, sil
    out dx, al
    ret

.global inb
inb:                               /* i32 inb(i32 port) */
    mov dx, di
    xor eax, eax
    in  al, dx
    ret

.global outl
outl:                              /* void outl(i32 port, u32 value) */
    mov dx, di
    mov eax, esi
    out dx, eax
    ret

.global io_wait
io_wait:
    mov dx, 0x80
    xor al, al
    out dx, al
    ret

.global hlt
hlt:
    hlt
    ret

.section .data
.align 16
kstack_bottom:
    .skip 65536
kstack_top:
