# SUPER OS

A small experimental x86-64 OS written almost entirely in my own systems programming language, [Quant](https://github.com/quant-lang/quant). A bit of GASM is used for initial CPU setup and low-level stuff.

**NOTE: I vibe-coded this project specifically for a video. It's an experiment, not a serious OS of mine.**

[Russian version of README](README_RU.md)

## How it works

QEMU boots SUPER OS as a 32-bit Multiboot 1 image. A small assembly bootloader sets up the page tables, switches the CPU into 64-bit long mode, and transfers control to the Quant kernel.

After startup, the kernel initializes the console, interrupts, a simple allocator, the system call interface, and a shell. It can also load ELF64 programs and run them in user mode (ring 3). User programs are compiled using Quant's custom `x86_64-superos` target.

Most of the kernel lives in a single file: `kernel/kmain.qu`. Assembly is used wherever low-level CPU setup is required.

```text
QEMU -kernel build/superos.elf [-initrd build/demo.elf]
  -> boot32.s   Multiboot, page tables, long-mode switch
  -> boot64.s   64-bit entry point, kernel stack, call kmain()
  -> kmain.qu   console, drivers, system calls, ELF loader, shell
       -> enter_user() -> ELF64 program in ring 3 via int 0x80
```

## Project structure

```text
kernel/
  boot32.s       32-bit Multiboot entry point and long-mode setup
  boot64.s       64-bit entry point and kernel stack
  hw.s           GDT/TSS/IDT, PIC/PIT, interrupt handlers, ring-3 transitions
  kmain.qu       Kernel: console, input, heap, system calls, loader, shell
  boot32.ld      Linker script for the bootable ELF32 image
  kernel64.ld    Linker script for the flat kernel at 0x200000

user/
  hello.qu       Minimal hello-world program
  demo.qu        System call demonstration

scripts/
  build.ps1 / build.sh           Build the kernel and user programs
  run.ps1 / run.sh               Run the OS in QEMU
  test-qemu.ps1 / test-qemu.sh   Automated headless boot test
  qemu-common.ps1 / qemu-common.sh  Shared QEMU helper functions
```

Each script comes in two flavours: a PowerShell version (`.ps1`, for Windows)
and a bash version (`.sh`, for Unix-like shells). Both live in `scripts/` and
take equivalent arguments; the examples below use PowerShell, but every command
has a `.sh` counterpart.

## Requirements

You'll need the following to build and run SUPER OS:

- The Quant compiler built from `..\quant`, with support for the `x86_64-superos` target. The default expected path is `..\quant\build\bin\qu.exe`.
- LLVM: `clang.exe` and `ld.lld.exe`. The default path is `C:\tools\clang\bin`.
- QEMU for x86-64: `qemu-system-x86_64.exe`.

The scripts use these paths by default. You can override them using environment variables:

| Variable | Description |
| --- | --- |
| `QUANT_DIR` | Path to the Quant repository |
| `QUANT_EXE` | Path to `qu.exe` |
| `CLANG_DIR` | Directory containing `clang.exe` and `ld.lld.exe` |
| `QEMU_EXE` | Path to `qemu-system-x86_64.exe` |

By default, `QUANT_DIR` points to `C:\Users\Zero\repo\quant`.

## Building

You can build the kernel and user programs using PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

The following files will be generated:

```text
build/superos.elf   Bootable OS image
build/hello.elf     Minimal user program
build/demo.elf      System call test program
```

To build a different user program, pass its source file through `-UserPrograms`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1 -UserPrograms user\demo.qu
```

The output ELF filename will match the source filename.

The kernel is always compiled with `--target x86_64-superos`. The kernel itself is regular Quant code linked into a flat binary.

If you modify `..\quant\std\superos\io\io.qu`, you'll need to rebuild the Quant compiler so the updated standard library is included in the build:

```powershell
cmake --build ..\quant\build
```

## Running

### Using the serial console

The easiest way to run the OS is:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1
```

To automatically load and run a user program at startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Initrd build\demo.elf
```

The serial console is connected to COM1, so the shell runs directly in your current terminal. Type `poweroff` to exit QEMU. You can also use `Ctrl+C`.

### Using the QEMU graphical window

To run the OS with a VGA console in a separate window:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Gui
```

To load a user program as well:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Gui -Initrd build\demo.elf
```

If GTK is unavailable, you can try SDL:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Gui -Display sdl
```

Click inside the QEMU window to enter commands using the emulated PS/2 keyboard. Serial output is also displayed in the terminal.

- `Ctrl+Alt+G` releases the keyboard and mouse.
- `Ctrl+Alt+F` toggles fullscreen mode.

When the `-Initrd` parameter is provided, the kernel automatically loads and runs the specified ELF program once at startup, then drops into the shell. You can run it again using the `run` command.

## Testing

There's a separate script for testing the boot process. It runs QEMU without a graphical window, sends commands through the serial port, captures the output, and terminates the emulator using `isa-debug-exit`.

Run the default test:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-qemu.ps1
```

Run with a custom command sequence:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-qemu.ps1 -CommandList "help;ticks;mem;poweroff"
```

Test a user program:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-qemu.ps1 -Initrd build\hello.elf
```

You can also provide both a program and a command list:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-qemu.ps1 -Initrd build\demo.elf -CommandList "hello from ring 3;poweroff"
```

Available parameters:

- `-Initrd` — ELF file to load at startup.
- `-CommandList` — List of commands separated by `;`.
- `-BootWaitMs` — Time to wait after boot.
- `-CharDelayMs` — Delay between sending characters.

The scripts also handle a couple of QEMU quirks:

- If the initrd path contains spaces, the file is copied to `%TEMP%\superos-initrd\` first.
- QEMU's serial console may drop large chunks of input, so the test script sends characters with a small delay between them.

When `poweroff` succeeds, QEMU may exit with code `1`. This is expected: `isa-debug-exit` converts the guest system's exit code `0` into host exit code `1`.

## Shell commands

The shell is intentionally simple. Its main purpose is to test the kernel without having to rebuild everything after every change.

| Command | Description |
| --- | --- |
| `help` | List available commands |
| `run`, `exec`, `hello` | Load and run the ELF passed through `-initrd` |
| `echo TEXT` | Print text |
| `clear` | Clear the VGA console |
| `ver` | Show version information |
| `mem` | Print heap and user stack addresses |
| `ticks` | Show PIT ticks since boot |
| `reboot` | Reboot the system through the keyboard controller |
| `poweroff` | Exit QEMU through `isa-debug-exit`, with an ACPI fallback |

## User programs and system calls

SUPER OS can run Quant programs compiled for its custom OS target:

```powershell
..\quant\build\bin\qu.exe --target x86_64-superos user\hello.qu -o build\hello.elf
```

The compiler produces a non-PIE ELF64 `ET_EXEC` executable with a base address of `0x400000` and the SysV AMD64 ABI.

The kernel loads the `PT_LOAD` segments, zeroes the remaining `.bss` section, and transfers control to the program in ring 3. The top of the user stack is located at `0x600000`.

System calls are handled through `int 0x80`.

| Number | Name | Arguments | Result |
| --- | --- | --- | --- |
| 0 | `read` | `fd, buf, len` | Number of bytes read |
| 1 | `write` | `fd, buf, len` | Number of bytes written |
| 9 | `mmap` | `addr, len, prot, flags, fd, offset` | Address |
| 11 | `munmap` | `addr, len` | `0` |
| 12 | `sbrk` | `increment` | Previous break value |
| 24 | `yield` | None | `0` |
| 39 | `getpid` | None | `1` |
| 60 | `exit` | `code` | Does not return |

The system call number is passed through `RAX`, while arguments are passed through `RDI`, `RSI`, `RDX`, `R10`, `R8`, and `R9`. The result is returned in `RAX`. Errors are represented by negative `errno` values.

The implementation of `std::io` for this target is located in `..\quant\std\superos\io\io.qu`. It provides wrappers around system calls: `print`, `println`, `print_char`, `read`, `write`, `mmap`, `munmap`, `sbrk`, `yield`, `getpid`, and `exit`.

Here's a minimal user program:

```qu
load "std::io";
using std::io;

@entry i32 main() {
    println("hello from a Quant SUPER OS user program");
    return 0;
}
```

## Memory map

The current memory map looks like this:

| Address | Purpose |
| --- | --- |
| `0x1000 - 0x3FFF` | PML4/PDPT/PD page tables, 2 MiB identity-mapped pages |
| `0x30000 - 0x33FFF` | Kernel scratch memory: input ring buffer, shell line, number buffer |
| `0x100000` | 32-bit Multiboot container |
| `0x200000` | Flat 64-bit Quant kernel |
| Module start | QEMU-provided `-initrd` image, for example at `0x11B000` |
| `0x400000` | User ELF base |
| `0x600000` | Top of the user stack, which grows downward |
| `0x800000 - 0x4000000` | User heap for `sbrk` and `mmap` |

The first 1 GiB of memory is identity-mapped using 2 MiB pages. These pages are marked as accessible from user mode so programs running in ring 3 can access their own code, stack, and heap.

There is one obvious downside to this approach: proper address-space isolation is not implemented yet.

## Limitations

- **Only one program at a time.** There's no scheduler, preemption, or proper process management. `yield` simply executes `hlt` for now.
- **Basic memory management.** `mmap` works as a bump allocator, while `munmap` does nothing.
- **No filesystem or block devices.** User programs are provided through `-initrd`.
- **No SMP or APIC support.** Only the legacy PIC/PIT setup is implemented.
- **Basic serial input.** The console expects `-serial stdio`, and input is line-oriented and handled by the kernel.
- **No proper memory isolation.** User mode exists, but the shared identity mapping allows programs to access kernel memory and the memory of other programs.

## Why?

SUPER OS started as an experiment for a video. I wanted to see whether it was even possible to write an OS in Quant. Instead of yet another program running in a terminal, this project has a bootloader, a kernel, system calls, and the ability to run custom ELF programs.

The project doesn't claim to be practical or complete. I just wanted to try writing a small OS in my own language using vibe coding and see what would come out of it.

**Don't take the name SUPER OS too seriously.**