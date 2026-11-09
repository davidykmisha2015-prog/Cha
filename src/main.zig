const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Compiler = @import("compiler.zig").Compiler;

pub fn main() void {
    const input = 
        \\print "Hello, world!";
        \\x = 40;
        \\y = 2;
        \\print x + y;
        \\print "All tests passed!";
    ;
    const output_file: [*:0]const u8 = "calc.bin";

    std.debug.print("Компілюємо вираз: \"{s}\"\n", .{input});

    var compiler = Compiler.init(Lexer.init(input));
    compiler.compileToElf(output_file);

    std.debug.print("Готово! Згенеровано нативний ELF64 бінарник: {s}\n", .{output_file});
}
