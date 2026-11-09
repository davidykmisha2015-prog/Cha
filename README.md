# Zig Native ELF64 Compiler

A minimalist, zero-dependency Ahead-of-Time (AOT) compiler written in **Zig 0.16.0** that emits executable Linux **ELF64** machine-code binaries directly to disk without any external tools (no LLVM, no GCC, no assemblers, and no libc).

## 🚀 Features

- **Direct ELF64 Generation**: Emits raw 64-byte `Elf64_Ehdr` (ELF Header) and 56-byte `Elf64_Phdr` (Program Header) directly from memory.
- **Pure x86_64 Machine Code**: Emits raw opcodes for arithmetic computations (`add`, `sub`, `imul`, `idiv`) using stack operations (`push`, `pop`, `rax`, `rbx`).
- **Native I/O via Linux Syscalls**:
  - Inlines a pure assembly `itoa` routine that converts 64-bit integer results into ASCII strings directly on the processor stack.
  - Invokes `sys_write` (syscall 1) to print to `stdout`.
  - Exits cleanly via `sys_exit(0)` (syscall 60).
- **Zero Dependencies**: Independent of libc, dynamic linkers, or third-party packages. The generated binaries are standalone static executables (~170–220 bytes in size!).

## 📂 Architecture

```
src/
├── lexer.zig     # Tokenizer scanning numbers, operators, identifiers
├── parser.zig    # Recursive descent parser with operator precedence
├── compiler.zig  # x86_64 machine code emitter & ELF64 binary generator
└── main.zig      # Driver pipeline & entrypoint
```

## 🛠️ Build & Run

```bash
# 1. Compile and run the compiler
zig build run

# 2. Execute the generated native Linux ELF binary
./calc.bin
```
