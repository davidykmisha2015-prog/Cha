const std = @import("std");

pub const Tag = enum {
    number,
    string,
    plus,
    ident,
    kw_if,
    kw_else,
    lbrace,
    rbrace,
    equal,
    semicolon,
    minus,
    star,
    slash,
    lparen,
    rparen,
    eof,
    invalid,
};

pub const Token = struct {
    tag: Tag,
    value: i32 = 0,
    name: []const u8 = "",
};
pub const Lexer = struct {
    source: []const u8,
    cursor: usize = 0,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .cursor = 0,
        };
    }

    pub fn next(self: *Lexer) Token {
        while (self.cursor < self.source.len and std.ascii.isWhitespace(self.source[self.cursor])) {
            self.cursor += 1;
        }
        if (self.cursor >= self.source.len) {
            return .{ .tag = .eof };
        }

        const c = self.source[self.cursor];

        if (c == '"') {
            self.cursor += 1;
            const start = self.cursor;
            while (self.cursor < self.source.len and self.source[self.cursor] != '"') {
                self.cursor += 1;
            }
            const str_content = self.source[start..self.cursor];
            if (self.cursor < self.source.len and self.source[self.cursor] == '"') {
                self.cursor += 1;
            }
            return .{ .tag = .string, .name = str_content };
        }

        if (c >= '0' and c <= '9') {
            var val: i32 = 0;
            while (self.cursor < self.source.len and self.source[self.cursor] >= '0' and self.source[self.cursor] <= '9') {
                val = val * 10 + (self.source[self.cursor] - '0');
                self.cursor += 1;
            }
            return .{ .tag = .number, .value = val };
        }

        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
            const start = self.cursor;
            self.cursor += 1;
            while (self.cursor < self.source.len) {
                const next_c = self.source[self.cursor];
                if ((next_c >= 'a' and next_c <= 'z') or (next_c >= 'A' and next_c <= 'Z') or (next_c >= '0' and next_c <= '9') or next_c == '_') {
                    self.cursor += 1;
                } else {
                    break;
                }
            }
            const word = self.source[start..self.cursor];
            if (std.mem.eql(u8, word, "if")) return .{ .tag = .kw_if, .name = word };
            if (std.mem.eql(u8, word, "else")) return .{ .tag = .kw_else, .name = word };
            return .{ .tag = .ident, .name = word };
        }
        self.cursor += 1;
        return switch (c) {
            '+' => .{ .tag = .plus },
            '-' => .{ .tag = .minus },
            '*' => .{ .tag = .star },
            '/' => .{ .tag = .slash },
            '(' => .{ .tag = .lparen },
            ')' => .{ .tag = .rparen },
            '{' => .{ .tag = .lbrace },
            '}' => .{ .tag = .rbrace },
            '=' => .{ .tag = .equal },
            ';' => .{ .tag = .semicolon },
            else => .{ .tag = .invalid },
        };
    }
};
