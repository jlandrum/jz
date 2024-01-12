const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const TestAllocator = std.testing.allocator;

const types = @import("types.zig");
const ESVarType = types.ESVarType;
const ESNumber = types.ESNumber;
const ESString = types.ESString;
const ESReference = types.ESReference;
const ESType = types.ESType;
const ESUndefined = types.ESUndefined;
const UNDEFINED = types.UNDEFINED;
const InvokeAssign = types.InvokeAssign;
const InvokeAdd = types.InvokeAdd;
const Instruction = types.Instruction;

const utils = @import("utils.zig");

/// Represents an execution scope. This can be the root execution
/// scope, or the body of a function.
const ESScope = struct {
  allocator: Allocator,
  /// The list of variables
  vars: StringHashMap(*ESReference),
  /// The list of instructions for this scope
  callStack: ArrayList(*Instruction),
  /// A special value used to hold values during their mutation.
  /// Future versions may support multiple registers, however unlike
  /// CPU registers, these are per-scope (which may allow for multi-threaded
  /// execution,
  register: ?ESType,

  /// Creates a new scope
  pub fn init(allocator: Allocator) !*ESScope {
    var ptr = try allocator.create(ESScope);
    ptr.* = ESScope {
      .allocator = allocator,
      .vars = StringHashMap(*ESReference).init(allocator),
      .callStack = ArrayList(*Instruction).init(allocator),
      .register = null,
    };

    // Pre-assign standard elements
    try ptr.declareVar("undefined", .CONST);
    try ptr.assignVar("undefined", UNDEFINED);
    try ptr.declareVar("NaN", .CONST);
    try ptr.assignVarNumber("NaN", std.math.nan(f64));
    try ptr.declareVar("Infinity", .CONST);
    try ptr.assignVarNumber("Infinity", std.math.inf(f64));

    return ptr;
  }

  pub fn push(self: *ESScope, invocation: Instruction) !void {
    var ptr = try self.allocator.create(Instruction);
    ptr.* = invocation;
    _ = try self.callStack.append(ptr);
  }

  pub fn declareVar(self: *ESScope, identifier: []const u8, vartype: ESVarType) !void {
    if (self.vars.get(identifier)) |value| {
      if (value.vartype == .CONST) {
        std.debug.print("Attempted to redeclare const {s}", .{identifier});
        return error.CannotRedeclareConst;
      }
    }

    const ptr = try self.allocator.create(ESReference);
    ptr.* = ESReference {
      .value = UNDEFINED,
      .vartype = vartype,
      .assigned = false,
      .readonly = false
    };

    try self.vars.put(identifier, ptr);
  }

  fn assignVar(self: *ESScope, identifier: []const u8, value: ESType) !void {
    if (self.vars.get(identifier)) |v| {
      if (v.vartype == .CONST and v.assigned) { return error.CannotReassignConst; }
      if (v.readonly) { return error.CannotAssignToReadOnly; }
      v.value = value;
      v.assigned = true;
      return;
    }
    return error.NoSuchIdentifier;
  }

  fn assignVarString(self: *ESScope, identifier: []const u8, value: []const u8) !void {
    return self.assignVar(identifier, ESType { .String = .{ .value = value } });
  }

  fn assignVarNumber(self: *ESScope, identifier: []const u8, value: f64) !void {
    return self.assignVar(identifier, ESType { .Number = .{ .value = value } });
  }

  pub fn debugValue(self: *ESScope, identifier: []const u8) !void {
    if (self.vars.get(identifier)) |v| {
      switch (v.value) {
        .String => |str| std.debug.print("{s}<String> = \"{s}\"\n", .{identifier, str.toString()}),
        .Number => |num|  std.debug.print("{s}<Number> = {s}\n", .{identifier, num.toString()}),
        .Undefined => |undf| std.debug.print("{s}<Undefined> = {s}\n", .{identifier, undf.toString()}),
      }
    } else {
      return std.debug.print("{s}<err> = {s} is not declared.\n", .{identifier, identifier});
    }
  }

  fn getVar(self: *ESScope, identifier: []const u8) ?ESType {
    if (self.vars.get(identifier)) |v| {
      return v.value;
    }
    return null;
  }

  pub fn exec(self: *ESScope) !void {
    for (self.callStack.items) |call| {
      switch (call.*) {
        .Set => |inv| {
          switch (inv.value[0]) {
            '"' => try self.assignVarString(inv.identifier, inv.value[1..inv.value.len-1]),
            '\'' => try self.assignVarString(inv.identifier, inv.value[1..inv.value.len-1]),
            else => {
              if (utils.isNumber(inv.value)) {
                try self.assignVarNumber(inv.identifier, utils.parseNumber(inv.value));
              } else if (self.getVar(inv.value)) |variable| {
                try self.assignVar(inv.identifier, variable);
              } else {
                return error.InvalidAssignment;
              }
            }
          }
        },
        .Read => |identifier| {
          if (self.getVar(identifier)) |variable| {
            const copy = variable;
            self.register = copy;
          } else {
            return error.ReferenceError;
          }
        },
        .Write => |identifier| {
          if (self.register) |register| {
            if (self.getVar(identifier)) |_| {
              try self.assignVar(identifier, register);
            } else {
              return error.ReferenceError;
            }
          } else {
            return error.RegisterEmpty;
          }
        },
        .Add => |value| {
          if (self.register) |*reg| {
            switch (reg.*) {
              .Number => |*num| {
                if (utils.isNumber(value)) {
                  num.value += utils.parseNumber(value);
                }
                else if (self.getVar(value)) |*varval| {
                  switch (varval.*) {
                    .Number => |*addval| {
                      num.value += addval.value;
                    },
                    else => {}
                  }
                }
              },
              else => {
                return error.NotImplemented;
              }
            }
          } else {
            return error.RegisterEmpty;
          }
        },
      }
    }
    //return error.NotImplemented;
  }

  pub fn getError(err: anyerror) []const u8 {
    switch (err) {
      .ReferenceError => return "Invalid reference",
      .InvalidAssignment => return "Invalid assignment",
      .NotImplemented => return "Operation not supported",
      .RegisterEmpty => return "Cannot perform operation with no active register",
      else => "Unknown error",
    }
  }

  pub fn deinit(self: *ESScope) void {
    var it = self.vars.valueIterator();
    while (it.next()) |entry| {
      self.allocator.destroy(entry.*);
    }
    for (self.callStack.items) |entry| {
      self.allocator.destroy(entry);
    }
    self.callStack.deinit();
    self.vars.deinit();
    self.allocator.destroy(self);
  }
};

/// Handles execution of instructions
pub const ESRuntime = struct {
  allocator: Allocator,
  scope: *ESScope,

  pub fn init(allocator: Allocator) !*ESRuntime {
    var ptr = try allocator.create(ESRuntime);
    var scope = try ESScope.init(allocator);

    ptr.* = ESRuntime {
      .allocator = allocator,
      .scope = scope,
    };
    return ptr;
  }

  pub fn exec(self: *ESRuntime) !void {
    return try self.scope.exec();
  }

  pub fn deinit(self: *ESRuntime) void {
    self.scope.deinit();
    self.allocator.destroy(self);
  }
};

test "Create var and assign" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  // Example code:
  // const a = "String!";

  // Hoisted const a;
  try runtime.scope.declareVar("a", .CONST);
  // a = "String!";
  try runtime.scope.push(Instruction { .Set = .{ .identifier = "a", .value = "\"String!\""} });

  try runtime.exec();
}

test "Ensure const cannot be reassigned" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  // Example code:
  // const a = "String!";
  // a = "Another string!";

  // Hoisted const a;
  try runtime.scope.declareVar("a", .CONST);
  // a = "String!";
  try runtime.scope.push(Instruction { .Set = .{ .identifier = "a", .value = "\"String!\""} });
  // a = "String!";
  try runtime.scope.push(Instruction { .Set = .{ .identifier = "a", .value = "\"Another string!\""} });

  try std.testing.expectError(error.CannotReassignConst, runtime.exec());
}

test "Ensure let can be reassigned" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  // Example code:
  // let a = "String!";
  // a = "Another string!";

  // Hoisted let a;
  try runtime.scope.declareVar("a", .LET);
  // a = "String!";
  try runtime.scope.push(Instruction { .Set = .{ .identifier = "a", .value = "\"String!\""} });
  // a = "Another string!";
  try runtime.scope.push(Instruction { .Set = .{ .identifier = "a", .value = "\"Another string!\""} });

  try runtime.exec();
}

test "Dev Testbench" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  // const oneHundred;
  try runtime.scope.declareVar("oneHundred", .CONST);
  // const twoHundred;
  try runtime.scope.declareVar("twoHundred", .CONST);
  // let twoNinetyNine;
  try runtime.scope.declareVar("twoNinetyNine", .LET);

  // Vars can have their values set directly.
  // oneHundred = 100;
  try runtime.scope.push(Instruction { .Set = .{ .identifier = "oneHundred", .value = "100"} });
  // twoHundred = 200;
  try runtime.scope.push(Instruction { .Set = .{ .identifier = "twoHundred", .value = "200"} });

  // Vars can also have their values copied from another variable.
  // twoNinetyNine = oneHundred;
  try runtime.scope.push(Instruction { .Set = .{ .identifier = "twoNinetyNine", .value = "oneHundred"} });
  // twoNinetyNine += twoHundred;
  try runtime.scope.push(Instruction { .Read = "twoNinetyNine" });
  try runtime.scope.push(Instruction { .Add = "twoHundred" });
  try runtime.scope.push(Instruction { .Write = "twoNinetyNine" });

  // twoNinetyNine -= 100;
  try runtime.scope.push(Instruction { .Read = "twoNinetyNine" });
  try runtime.scope.push(Instruction { .Add = "-100" });
  try runtime.scope.push(Instruction { .Write = "twoNinetyNine" });
  // twoNinetyNine += 50 + 49;
  try runtime.scope.push(Instruction { .Read = "twoNinetyNine" });
  try runtime.scope.push(Instruction { .Add = "50" });
  try runtime.scope.push(Instruction { .Add = "49" });
  try runtime.scope.push(Instruction { .Write = "twoNinetyNine" });

  // An example of what would happen if you performed an operation but
  // did not capture the result; the allocator will get updated but
  // the var will not change.
  // twoNinetyNine - 299;
  try runtime.scope.push(Instruction { .Read = "twoNinetyNine" });
  try runtime.scope.push(Instruction { .Add = "-299" });

  try runtime.exec();

  // Should result in twoNinetyNine<Number> = 299 being output.
  std.debug.print("== Primitives ==\n",.{});
  try runtime.scope.debugValue("undefined");
  try runtime.scope.debugValue("NaN");
  try runtime.scope.debugValue("Infinity");
  std.debug.print("== Variables in current scope ==\n",.{});
  try runtime.scope.debugValue("oneHundred");
  try runtime.scope.debugValue("twoHundred");
  try runtime.scope.debugValue("twoNinetyNine");
  std.debug.print("== Non-existent variable ==\n",.{});
  try runtime.scope.debugValue("nonExist");
}