/* SUPER OS 32-bit Multiboot container.
 *
 * QEMU only accepts a 32-bit ELF for -kernel, so this stub is the bootable
 * image. It embeds the flat 64-bit Quant kernel (kernel64.bin), copies it to
 * KERNEL64_BASE, enables long mode and jumps into it.
 *
 * Boot protocol: Multiboot 1. QEMU sets EAX=0x2BADB002 and EBX=multiboot info.
 */

.intel_syntax noprefix

.set MB_MAGIC,    0x1BADB002
.set MB_FLAGS,    0x00000003          /* align modules, provide memory info */
.set MB_CHECKSUM, -(MB_MAGIC + MB_FLAGS)

.set KERNEL64_BASE, 0x200000

.section .multiboot, "a"
.align 4
mb_header:
    .long MB_MAGIC
    .long MB_FLAGS
    .long MB_CHECKSUM

.section .text.boot, "ax"
.code32
.global _start32
_start32:
    cli

    /* Keep the Multiboot info pointer in EBP across the mode switch. */
    mov ebp, ebx

    /* Copy the 64-bit kernel image to its link address. */
    cld
    mov esi, OFFSET kernel64_blob
    mov edi, KERNEL64_BASE
    .att_syntax prefix
    movl $kernel64_blob_end - kernel64_blob, %ecx
    .intel_syntax noprefix
    rep movsb

    /* Zero the page tables: 0x1000 .. 0x3FFF */
    mov edi, 0x1000
    xor eax, eax
    mov ecx, 0x3000 / 4
    rep stosd

    /* PML4[0] -> PDPT (0x2000), present + writable + user */
    mov eax, 0x2000
    or  eax, 0x07
    mov dword ptr [0x1000], eax

    /* PDPT[0] -> PD (0x3000), present + writable + user */
    mov eax, 0x3000
    or  eax, 0x07
    mov dword ptr [0x2000], eax

    /* PD: 512 x 2 MiB pages, identity map 0 .. 1 GiB.
     * U/S is set so the ring-3 userland can reach its code, stack and heap.
     */
    mov edi, 0x3000
    mov eax, 0x87                  /* present | writable | user | page size */
    mov ecx, 512
1:
    mov dword ptr [edi], eax
    mov dword ptr [edi + 4], 0
    add eax, 0x200000
    add edi, 8
    loop 1b

    /* CR4.PAE */
    mov eax, cr4
    or  eax, 0x20
    mov cr4, eax

    /* CR3 = PML4 */
    mov eax, 0x1000
    mov cr3, eax

    /* EFER.LME */
    mov ecx, 0xC0000080
    rdmsr
    or  eax, 0x100
    wrmsr

    /* CR0.PG | CR0.PE */
    mov eax, cr0
    or  eax, 0x80000001
    mov cr0, eax

    lgdt [gdt64_ptr]

    /* Far jump into the 64-bit code segment at KERNEL64_BASE. */
    .att_syntax prefix
    ljmp $0x08, $KERNEL64_BASE
    .intel_syntax noprefix

.section .rodata
.align 8
gdt64:
    .quad 0x0000000000000000
    .quad 0x00AF9A000000FFFF       /* 64-bit code, ring 0 */
    .quad 0x00AF92000000FFFF       /* data, ring 0 */
gdt64_end:

.section .data
.align 8
gdt64_ptr:
    .word gdt64_end - gdt64 - 1
    .long gdt64

/* The 64-bit kernel, linked as a flat binary at KERNEL64_BASE. */
.section .payload, "a"
.align 16
.global kernel64_blob
kernel64_blob:
    .incbin "kernel64.bin"
.global kernel64_blob_end
kernel64_blob_end:
