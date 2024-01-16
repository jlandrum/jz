const std = @import("std");

const ESRuntime = @import("runtime.zig").ESRuntime;

const Allocator = std.mem.Allocator;
const TestAllocator = std.testing.allocator;
const ArrayList = std.ArrayList;
const equals = std.mem.eql;

const types = @import("./types.zig");
const Instruction = types.Instruction;

const ESLexerError = error {
  ParseError,
};

const ParseError = struct {
  cause: []const u8,
};

const ESToken = struct { value: types.ESVar };
const ESTokenList = std.ArrayList(ESToken);

const Context = enum {
  none, // Default state
  valueDecl //
};

pub const ESLexer = struct {
  allocator: Allocator,
  tokens: ArrayList([]const u8),
  callList: ArrayList(Instruction),
  err: ?ParseError,

  pub fn init(allocator: Allocator) ESLexer {
    return ESLexer {
      .callList = ArrayList(Instruction).init(allocator),
      .tokens = ArrayList([]const u8).init(allocator),
      .err = null,
      .allocator = allocator,
    };
  }

  pub fn deinit(self: *ESLexer) void {
    self.tokens.deinit();
    self.callList.deinit();
    if (self.err) |err| {
      self.allocator.free(err.cause);
    }
  }

  pub fn isIdentifierSeparator(c: u8) bool {
      return (c == ' ' or (c >= 33 and c <= 47) or (c >= 58 and c <= 64) or
              (c >= 91 and c <= 96) or (c >= 123 and c <= 126));
  }

  fn isOperator(c: u8) bool {
    const operators: []const u8 = "=+-*/!%&|^<>?:~";
    for (operators) |operator| {
        if (c == operator) {
            return true;
        }
    }
    return false;
  }

  fn parse(self: *ESLexer, text: []const u8) !void {
    try self.tokenize(text);
    var offset: u8 = 0;

    while (offset < self.tokens.items.len) {
      var focus = self.tokens.items[offset];

      // Ignore semicolons
      if (equals(u8, focus, ";")) {
        offset += 1;
        continue;
      }

      // Check for var assignment
      else if (equals(u8, focus, "var") or equals(u8, focus, "const") or equals(u8, focus, "let")) {
        var identifier = self.tokens.items[offset + 1];
        var assign = self.tokens.items[offset + 2];
        var rvalue = self.tokens.items[offset + 3];

        // Ensure properly formatted assign.
        if (!equals(u8, assign, "=")) {
         var err = try std.fmt.allocPrint(self.allocator, "Expected =, got {s}", .{assign});
         self.err = ParseError{ .cause = err };
         return ESLexerError.ParseError;
        }

        try self.callList.append( .{ .Declare = .{
         .identifier = identifier,
         .type = .LET,
        }});

        try self.callList.append( .{ .Set = .{
          .identifier = identifier,
          .value = rvalue,
        }});

        // Move past this statement
        offset += 3;
      }

      offset += 1;
    }
  }

  fn tokenize(self: *ESLexer, text: []const u8) !void {
    var start: u8 = 0;
    var end: u8 = 1;

    while (end < text.len) {
      // Current text we are reading for lexing
      var keyword: []const u8 = text[start..end];

      // Advance if we start on a space
      if (text[start] == ' ') {
        start += 1;
      }
      // Automatic Semicolon Insertion
      else if (text[start] == '\n') {
        if (start > 0 and text[start-1] != ';') {
          try self.tokens.append(";");
        }
        start += 1;
      }
      // Detect quotes and attempt to group as their own token for simplicity.
      else if (text[start] == '\'' or text[start] == '`' or text[start] == '"') {
        const quote = keyword[0];

        while (true) {
          end += 1;
          if (text[end] == quote and text[end-1] != '\\') {
            break;
          }
        }

        try self.tokens.append(text[start..end+1]);
        start = end+1;
        end += 1;
      }
      // If we're already on a separator, add it and advance
      else if (isIdentifierSeparator(text[start])) {
        // Collect operators
        if (isOperator(text[start])) {
          while (isOperator(text[end])) {
            end += 1;
          }
          try self.tokens.append(text[start..end]);
          start = end;
        } else {
          try self.tokens.append(text[start..end]);
          start += 1;
        }
      }
      // If we've reached a separator, pull the keyword and reset the start.
      else if (isIdentifierSeparator(text[end])) {
        try self.tokens.append(keyword);
        start = end;
      }

      end+=1;
    }
  }
};

test "Lexer: Read sample source file" {
  const runtime = try ESRuntime.init(TestAllocator);
  var lexer = ESLexer.init(TestAllocator);

  defer runtime.deinit();
  defer lexer.deinit();

  const input =
    \\ var a = 100;
    \\ var b = 200.5;
    \\ var c = "Hello, world!";
    \\ var d = NaN;
    \\ var e = undefined;
  ;

  lexer.parse(input) catch {
    std.log.err("An error occured: {s}", .{lexer.err.?.cause});
  };

  for (lexer.callList.items) |token| {
    try runtime.scope.push(token);
  }

  try runtime.exec();

  std.debug.print("\n=== Variable results ===\n", .{});
  try runtime.scope.debugValue("a");
  try runtime.scope.debugValue("b");
  try runtime.scope.debugValue("c");
  try runtime.scope.debugValue("d");
  try runtime.scope.debugValue("e");

  // std.debug.print("\n", .{});
  // for (lexer.tokens.items) |slice| {
  //   std.debug.print("Token: [{s}]\n", .{slice});
  // }
}