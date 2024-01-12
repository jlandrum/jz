// TODO: Don't look at me - I'm broken while the runtime is being worked on :)

const std = @import("std");

const Allocator = std.mem.Allocator;
const TestAllocator = std.testing.allocator;
const ArrayList = std.ArrayList;

const equals = std.mem.eql;

const types = @import("./types.zig");

const ESCall = types.ESCall;
const ESVarAssign = types.ESVarAssign;

const ESLexerError = error {
  ParseError,
};

const ParseError = struct {
  cause: []const u8,
};

const ESToken = struct {
  value: types.ESVar,
};
const ESTokenList = std.ArrayList(ESToken);

const Context = enum {
  none, // Default state
  valueDecl //
};

pub const ESLexer = struct {
  allocator: Allocator,
  tokens: ArrayList([]const u8),
  callList: ArrayList(ESCall),
  err: ?ParseError,

  pub fn init(allocator: Allocator) ESLexer {
    return ESLexer {
      .callList = ArrayList(ESCall).init(allocator),
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

    var start: u8 = 0;
    var end: u8 = 1;
    // var context: Context = .none;

    while (start < self.tokens.items.len) {
      var focus = self.tokens.items[start];

      // Ignore semicolons
      if (equals(u8, focus, ";")) {
        start += 1;
      }
      // Check for var assignment
      else if (equals(u8, focus, "var") or equals(u8, focus, "const") or equals(u8, focus, "let")) {
         var identifier = self.tokens.items[start + 1];
         var assign = self.tokens.items[start + 2];

         // This won't work for complex statements, yet.
         var value = self.tokens.items[start + 3];

         // Ensure properly formatted assign.
         if (!equals(u8, assign, "=")) {
           var err = try std.fmt.allocPrint(self.allocator, "Expected =, got {s}", .{assign});
           self.err =  ParseError{.cause = err };
           return ESLexerError.ParseError;
         }

         try self.callList.append(ESCall{
          .VarAssign = ESVarAssign{
            .name = identifier,
            .value = value,
            .type = .esvar, // TODO: All vars will be standard vars for now
            }
         });

         // Log action
         std.debug.print("ASSIGN {s} = {s}\n", .{identifier, value});

         // Move past this statement
         start += 4;
         end = start;
      }
      else
      {
        // Assume it's an operation
        var identifier = self.tokens.items[start];
        var action = self.tokens.items[start+1];
        var val = self.tokens.items[start+2];

        if (action[0] == '(') {
          std.debug.print("INVOKE {s}\n", .{identifier});
        } else if (action[0] == '.') {
          std.debug.print("ACCESS {s}\n", .{identifier});
        } else {
          std.debug.print("OPERATION {s} {s} {s}\n", .{focus, action, val});
          start += 2;
          end = start;
        }

        // while (self.tokens.items[start][0] != ';') {
        //   start+=1;
        // }
        // end=start;
        //
        //
        // // move ahead
        start += 1;
      }
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

test "Temp" {
  const input =
    \\ var a = 1;
    \\ a += 20300;
    \\ console.log(a);
  ;

  var lexer = ESLexer.init(TestAllocator);
  lexer.parse(input) catch {
    std.log.err("An error occured: {s}", .{lexer.err.?.cause});
  };
  defer lexer.deinit();

  // std.debug.print("\n", .{});
  // for (lexer.tokens.items) |slice| {
  //   std.debug.print("Token: [{s}]\n", .{slice});
  // }
}