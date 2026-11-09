const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;

// 1. Стандартний 64-бітний заголовок ELF (64 байти)
const Elf64_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

// 2. Program Header: інструкція для ядра Linux, куди вантажити код у RAM (56 байтів)
const Elf64_Phdr = extern struct {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
};

pub const Compiler = struct {
    lexer: Lexer,
    tok: Token,
    code_buf: [2048]u8 = undefined,
    code_len: usize = 0,
    var_names: [16][]const u8 = undefined,
    var_count: usize = 0,

    pub fn init(lexer: Lexer) Compiler {
        var c = Compiler{
            .lexer = lexer,
            .tok = undefined,
            .code_len = 0,
        };
        c.tok = c.lexer.next();
        return c;
    }

    fn eat(self: *Compiler) void {
        self.tok = self.lexer.next();
    }

    fn getVarOffset(self: *Compiler, name: []const u8) u8 {
        for (self.var_names[0..self.var_count], 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast((i + 1) * 8);
        }
        self.var_names[self.var_count] = name;
        self.var_count += 1;
        return @intCast(self.var_count * 8);
    }

    fn emitByte(self: *Compiler, b: u8) void {
        self.code_buf[self.code_len] = b;
        self.code_len += 1;
    }

    fn emitBytes(self: *Compiler, bytes: []const u8) void {
        @memcpy(self.code_buf[self.code_len .. self.code_len + bytes.len], bytes);
        self.code_len += bytes.len;
    }

    // Завантажуємо число в регістр EAX і кладемо на стек процесора
    fn emitNumber(self: *Compiler, val: i32) void {
        self.emitByte(0xB8); // mov eax, imm32
        const val_u32: u32 = @bitCast(val);
        const bytes: [4]u8 = @bitCast(val_u32);
        self.emitBytes(&bytes);
        self.emitByte(0x50); // push rax
    }

    fn primary(self: *Compiler) void {
        if (self.tok.tag == .number) {
            const val = self.tok.value;
            self.eat();
            self.emitNumber(val);
            return;
        }

        if (self.tok.tag == .ident) {
            const offset = self.getVarOffset(self.tok.name);
            self.eat();
            const disp: u8 = 0 -% offset;
            self.emitBytes(&[_]u8{ 0x48, 0x8B, 0x45, disp, 0x50 });
            return;
        }

        if (self.tok.tag == .lparen) {
            self.eat();
            self.expr();
            if (self.tok.tag == .rparen) {
                self.eat();
            }
            return;
        }
    }

    fn term(self: *Compiler) void {
        self.primary();
        while (self.tok.tag == .star or self.tok.tag == .slash) {
            const op = self.tok.tag;
            self.eat();
            self.primary();

            if (op == .star) {
                // pop rbx; pop rax; imul eax, ebx; push rax
                self.emitBytes(&[_]u8{ 0x5B, 0x58, 0x0F, 0xAF, 0xC3, 0x50 });
            } else {
                // pop rbx; pop rax; cdq; idiv ebx; push rax
                self.emitBytes(&[_]u8{ 0x5B, 0x58, 0x99, 0xF7, 0xFB, 0x50 });
            }
        }
    }

    pub fn expr(self: *Compiler) void {
        self.term();
        while (self.tok.tag == .plus or self.tok.tag == .minus) {
            const op = self.tok.tag;
            self.eat();
            self.term();

            if (op == .plus) {
                // pop rbx; pop rax; add eax, ebx; push rax
                self.emitBytes(&[_]u8{ 0x5B, 0x58, 0x01, 0xD8, 0x50 });
            } else {
                // pop rbx; pop rax; sub eax, ebx; push rax
                self.emitBytes(&[_]u8{ 0x5B, 0x58, 0x29, 0xD8, 0x50 });
            }
        }
    }

    // Друк цілого числа з EAX у stdout через itoa + sys_write
    fn emitPrint(self: *Compiler) void {
        self.emitBytes(&[_]u8{
            0x48, 0x83, 0xEC, 0x20, // sub rsp, 32 (буфер під ASCII на стеку)
            0x48, 0x8D, 0x74, 0x24, 0x1F, // lea rsi, [rsp + 31]
            0xC6, 0x06, 0x0A, // mov byte [rsi], 10 ('\n')
            0xBB, 0x0A, 0x00, 0x00, 0x00, // mov ebx, 10
            // loop: itoa
            0x31, 0xD2, // xor edx, edx
            0xF7, 0xF3, // div ebx
            0x80, 0xC2, 0x30, // add dl, '0' (48)
            0x48, 0xFF, 0xCE, // dec rsi
            0x88, 0x16, // mov [rsi], dl
            0x85, 0xC0, // test eax, eax
            0x75, 0xF0, // jnz loop (-16 bytes)
            // sys_write(1, rsi, count)
            0xB8, 0x01, 0x00, 0x00, 0x00, // mov eax, 1 (sys_write)
            0xBF, 0x01, 0x00, 0x00, 0x00, // mov edi, 1 (stdout)
            0x48, 0x8D, 0x54, 0x24, 0x20, // lea rdx, [rsp + 32]
            0x48, 0x29, 0xF2, // sub rdx, rsi (count)
            0x0F, 0x05, // syscall
            0x48, 0x83, 0xC4, 0x20, // add rsp, 32 (звільняємо стек буфера)
        });
    }

    // Друк текстового рядка у stdout через sys_write
    fn emitPrintString(self: *Compiler, str: []const u8) void {
        const str_len: u32 = @intCast(str.len + 1); // +1 для '\n'

        // 1. Стрибок через байти тексту (щоб CPU не виконував літери як команди)
        if (str_len <= 127) {
            self.emitByte(0xEB); // jmp short
            self.emitByte(@intCast(str_len));
        } else {
            self.emitByte(0xE9); // jmp near
            self.emitBytes(&@as([4]u8, @bitCast(str_len)));
        }

        // 2. Байти тексту + перенесення рядка (\n)
        const str_addr: u64 = 0x400078 + self.code_len;
        self.emitBytes(str);
        self.emitByte(0x0A); // '\n'

        // 3. sys_write(stdout=1, buf=str_addr, count=str_len)
        self.emitByte(0xB8); // mov eax, 1 (sys_write)
        self.emitBytes(&@as([4]u8, @bitCast(@as(u32, 1))));

        self.emitByte(0xBF); // mov edi, 1 (stdout)
        self.emitBytes(&@as([4]u8, @bitCast(@as(u32, 1))));

        self.emitBytes(&[_]u8{ 0x48, 0xBE }); // mov rsi, imm64 (адреса тексту)
        self.emitBytes(&@as([8]u8, @bitCast(str_addr)));

        self.emitByte(0xBA); // mov edx, imm32 (довжина тексту)
        self.emitBytes(&@as([4]u8, @bitCast(str_len)));

        self.emitBytes(&[_]u8{ 0x0F, 0x05 }); // syscall (друк у термінал)
    }

    // Залатування 32-бітного відносного зміщення для умовного/безумовного стрибка
    fn patch32(self: *Compiler, patch_pos: usize) void {
        const offset = @as(i32, @intCast(self.code_len)) - @as(i32, @intCast(patch_pos + 4));
        const bytes: [4]u8 = @bitCast(offset);
        @memcpy(self.code_buf[patch_pos .. patch_pos + 4], &bytes);
    }

    fn block(self: *Compiler) void {
        if (self.tok.tag == .lbrace) {
            self.eat(); // eat '{'
            while (self.tok.tag != .rbrace and self.tok.tag != .eof) {
                self.statement();
            }
            if (self.tok.tag == .rbrace) {
                self.eat(); // eat '}'
            }
        } else {
            self.statement();
        }
    }

    fn ifStatement(self: *Compiler) void {
        self.eat(); // eat "if"

        if (self.tok.tag == .lparen) self.eat();
        self.expr();
        if (self.tok.tag == .rparen) self.eat();

        // pop rax
        self.emitByte(0x58);
        // test eax, eax
        self.emitBytes(&[_]u8{ 0x85, 0xC0 });

        // jz rel32 (0x0F, 0x84, [imm32])
        self.emitBytes(&[_]u8{ 0x0F, 0x84, 0x00, 0x00, 0x00, 0x00 });
        const patch_jz = self.code_len - 4;

        self.block();

        if (self.tok.tag == .kw_else) {
            self.eat(); // eat "else"

            // jmp rel32 (0xE9, [imm32]) наприкінці THEN
            self.emitByte(0xE9);
            self.emitBytes(&[_]u8{ 0x00, 0x00, 0x00, 0x00 });
            const patch_jmp = self.code_len - 4;

            // Залатуємо jz на початок ELSE
            self.patch32(patch_jz);

            self.block();

            // Залатуємо jmp на кінець ELSE
            self.patch32(patch_jmp);
        } else {
            // Якщо else немає - залатуємо jz на поточну точку
            self.patch32(patch_jz);
        }
    }

    fn statement(self: *Compiler) void {
        if (self.tok.tag == .semicolon) {
            self.eat();
            return;
        }

        if (self.tok.tag == .kw_if) {
            self.ifStatement();
            return;
        }

        // print "рядок" або print <вираз>;
        if (self.tok.tag == .ident and std.mem.eql(u8, self.tok.name, "print")) {
            self.eat(); // eat "print"

            // Якщо друкуємо готовий текст у лапках
            if (self.tok.tag == .string) {
                const str = self.tok.name;
                self.eat();
                if (self.tok.tag == .semicolon) self.eat();

                self.emitPrintString(str);
                return;
            }

            // Якщо друкуємо числовий вираз
            self.expr();
            if (self.tok.tag == .semicolon) self.eat();

            self.emitByte(0x58); // pop rax
            self.emitPrint();
            return;
        }

        // <ident> = <expr>;
        if (self.tok.tag == .ident) {
            const var_name = self.tok.name;
            const offset = self.getVarOffset(var_name);
            self.eat(); // eat ident
            if (self.tok.tag == .equal) {
                self.eat(); // eat '='
                self.expr();
                if (self.tok.tag == .semicolon) self.eat();

                // pop rax; mov [rbp - offset], rax
                const disp: u8 = 0 -% offset;
                self.emitBytes(&[_]u8{ 0x58, 0x48, 0x89, 0x45, disp });
                return;
            }
        }

        // Звичайний арифметичний вираз
        self.expr();
        if (self.tok.tag == .semicolon) self.eat();
        self.emitByte(0x58); // pop rax
        self.emitPrint();
    }

    // Компілює програму у нативний ELF64 виконуваний бінарник Linux
    pub fn compileToElf(self: *Compiler, output_path: [*:0]const u8) void {
        // Пролог функції (setup stack frame anchor):
        // push rbp; mov rbp, rsp; sub rsp, 128
        self.emitBytes(&[_]u8{ 0x55, 0x48, 0x89, 0xE5, 0x48, 0x81, 0xEC, 0x80, 0x00, 0x00, 0x00 });

        while (self.tok.tag != .eof) {
            self.statement();
        }

        // Епілог функції та чистий вихід:
        // mov rsp, rbp; pop rbp; xor edi, edi; mov eax, 60; syscall (sys_exit 0)
        self.emitBytes(&[_]u8{
            0x48, 0x89, 0xEC, // mov rsp, rbp
            0x5D,             // pop rbp
            0x31, 0xFF,       // xor edi, edi (код 0)
            0xB8, 0x3C, 0x00, 0x00, 0x00, // mov eax, 60 (sys_exit)
            0x0F, 0x05,       // syscall
        });

        const total_filesz: u64 = 120 + self.code_len;

        var ehdr: Elf64_Ehdr = undefined;
        @memset(&ehdr.e_ident, 0);
        @memcpy(ehdr.e_ident[0..4], "\x7fELF");
        ehdr.e_ident[4] = 2; // 64-bit
        ehdr.e_ident[5] = 1; // Little-endian
        ehdr.e_ident[6] = 1; // ELF Version
        ehdr.e_type = 2; // ET_EXEC
        ehdr.e_machine = 0x3E; // x86_64
        ehdr.e_version = 1;
        ehdr.e_entry = 0x400078; // 0x400000 + 120 байтів заголовків
        ehdr.e_phoff = 64;
        ehdr.e_shoff = 0;
        ehdr.e_flags = 0;
        ehdr.e_ehsize = 64;
        ehdr.e_phentsize = 56;
        ehdr.e_phnum = 1;
        ehdr.e_shentsize = 0;
        ehdr.e_shnum = 0;
        ehdr.e_shstrndx = 0;

        var phdr: Elf64_Phdr = undefined;
        phdr.p_type = 1; // PT_LOAD
        phdr.p_flags = 5; // PF_R | PF_X
        phdr.p_offset = 0;
        phdr.p_vaddr = 0x400000;
        phdr.p_paddr = 0x400000;
        phdr.p_filesz = total_filesz;
        phdr.p_memsz = total_filesz;
        phdr.p_align = 0x1000;

        const fd = std.posix.system.openat(
            std.os.linux.AT.FDCWD,
            output_path,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
            0o755,
        );
        const fd_i32: i32 = @intCast(fd);

        const ehdr_bytes: [*]const u8 = @ptrCast(&ehdr);
        _ = std.posix.system.write(fd_i32, ehdr_bytes, 64);

        const phdr_bytes: [*]const u8 = @ptrCast(&phdr);
        _ = std.posix.system.write(fd_i32, phdr_bytes, 56);

        _ = std.posix.system.write(fd_i32, self.code_buf[0..self.code_len].ptr, self.code_len);
        _ = std.posix.system.close(fd_i32);
    }
};
