const std = @import("std");

const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;
const Token = lexer_mod.Token;

pub const Parser = struct {
    lexer: Lexer,
    current_token: Token,
    had_error: bool = false,

    pub fn init(lexer: Lexer) Parser {
        var p = Parser{
            .lexer = lexer,
            .current_token = undefined,
            .had_error = false,
        };
        p.current_token = p.lexer.next();
        return p;
    }

    fn eat(self: *Parser) void {
        self.current_token = self.lexer.next();
    }

    fn primary(self: *Parser) i32 {
        const token = self.current_token;

        if (token.tag == .number) {
            self.eat();
            return token.value;
        }

        if (token.tag == .lparen) {
            self.eat();
            const val = self.parse();
            if (self.current_token.tag != .rparen) {
                std.debug.print("Syntax error: expected ')', found '{s}'\n", .{@tagName(self.current_token.tag)});
                self.had_error = true;
            } else {
                self.eat();
            }
            return val;
        }

        std.debug.print("Syntax error: expected number or '(', found '{s}'\n", .{@tagName(token.tag)});
        self.had_error = true;
        return 0;
    }
    fn term(self: *Parser) i32 {
        var left = self.primary();
        while (self.current_token.tag == .star or self.current_token.tag == .slash) {
            const tag = self.current_token.tag;
            self.eat();
            const right = self.primary();
            left = if (tag == .star) left * right else @divTrunc(left, right);
        }
        return left;
    }

    pub fn parse(self: *Parser) i32 {
        var left = self.term();
        while (self.current_token.tag == .plus or self.current_token.tag == .minus) {
            const tag = self.current_token.tag;
            self.eat();
            const right = self.term();
            left = if (tag == .plus) left + right else left - right;
        }
        return left;
    }
};
