const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Compiler = @import("compiler.zig").Compiler;

pub fn main() void {
    const input = 
        \\print "Testing Cha if/else...";
        \\x = 10;
        \\if (x) {
        \\    print "Branch THEN: x is true!";
        \\} else {
        \\    print "Branch ELSE: error!";
        \\}
        \\y = 0;
        \\if (y) {
        \\    print "Branch THEN: error!";
        \\} else {
        \\    print "Branch ELSE: y is false!";
        \\}
        \\print "All tests passed successfully!";
    ;
    const output_file: [*:0]const u8 = "calc.bin";

    std.debug.print("Компілюємо вираз: \"{s}\"\n", .{input});

    var compiler = Compiler.init(Lexer.init(input));
    compiler.compileToElf(output_file);

    std.debug.print("Готово! Згенеровано нативний ELF64 бінарник: {s}\n", .{output_file});
}
