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
const ESObject = types.ESObject;
const ESObjectImpl = types.ESObjectImpl;
const ESNativeFunction = types.ESNativeFunction;
const UNDEFINED = types.UNDEFINED;
const InvokeAssign = types.InvokeAssign;
const InvokeAdd = types.InvokeAdd;
const Instruction = types.Instruction;

const ESScope = @import("scope.zig").ESScope;

const gc = @import("gc.zig");
const utils = @import("utils.zig");

/// Handles execution of instructions
pub const ESRuntime = struct {
  allocator: Allocator,
  scope: *ESScope,
  objectManager: gc.ESObjectManager,

  pub fn init(allocator: Allocator) !*ESRuntime {
    var objectManager = gc.ESObjectManager.init(allocator);
    var ptr = try allocator.create(ESRuntime);
    var scope = try ESScope.init(allocator, &objectManager);
    try scope.initStdLib();

    ptr.* = ESRuntime {
      .allocator = allocator,
      .scope = scope,
      .objectManager = objectManager,
    };
    return ptr;
  }

  pub fn exec(self: *ESRuntime) !void {
    return try self.scope.exec();
  }

  pub fn deinit(self: *ESRuntime) void {
    self.objectManager.deinit();
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
  try runtime.scope.push( .{ .Declare = .{ .identifier = "a", .type = .CONST } });
  // a = "String!";
  try runtime.scope.push( .{ .Set = .{ .identifier = "a", .value = "\"String!\""} });

  try runtime.exec();
}

test "Ensure const cannot be reassigned" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  // Example code:
  // const a = "String!";
  // a = "Another string!";

  // Hoisted const a;
  try runtime.scope.push( .{ .Declare = .{ .identifier = "a", .type = .CONST } });
  // a = "String!";
  try runtime.scope.push( .{ .Set = .{ .identifier = "a", .value = "\"String!\""} });
  // a = "String!";
  try runtime.scope.push( .{ .Set = .{ .identifier = "a", .value = "\"Another string!\""} });

  try std.testing.expectError(error.CannotReassignConst, runtime.exec());
}

test "Ensure let can be reassigned" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  // Example code:
  // let a = "String!";
  // a = "Another string!";

  // Hoisted let a;
  try runtime.scope.push( .{ .Declare = .{ .identifier = "a", .type = .LET } });
  // a = "String!";
  try runtime.scope.push( .{ .Set = .{ .identifier = "a", .value = "\"String!\""} });
  // a = "Another string!";
  try runtime.scope.push( .{ .Set = .{ .identifier = "a", .value = "\"Another string!\""} });

  try runtime.exec();
}

test "Create and run method" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  // const add;
  try runtime.scope.push( .{ .Declare = .{ .identifier = "add",  .type = .CONST } });

  // add = () => { console.log("Hello World! :)"); }
  const fnScope = try runtime.scope.createScope();
  try fnScope.push( .{ .Read = "console" });
  try fnScope.push( .{ .ReadProperty = "log" });
  var args = [_][]const u8 {
    "Hello World! :)",
  };
  try fnScope.push( .{ .Invoke = .{ .args = &args } });
  try runtime.scope.push( .{ .SetReference = .{ .identifier = "add", .value = .{
    .Function = .{
      .scope = fnScope,
    },
  }}});

  // add();
  try runtime.scope.push( .{ .Read = "add" });
  try runtime.scope.push( .{ .Invoke = .{ .args = null }});

  try runtime.exec();
}

test "Dev Testbench" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  // const oneHundred;
  try runtime.scope.push( .{ .Declare = .{ .identifier = "oneHundred", .type = .CONST } });
  // const twoHundred;
  try runtime.scope.push(.{ .Declare = .{ .identifier = "twoHundred", .type = .CONST } });
  // let twoNinetyNine;
  try runtime.scope.push(.{ .Declare = .{ .identifier = "twoNinetyNine", .type = .LET } });

  // Vars can have their values set directly.
  // oneHundred = 100;
  try runtime.scope.push( .{ .Set = .{ .identifier = "oneHundred", .value = "100"} });
  // twoHundred = 200;
  try runtime.scope.push( .{ .Set = .{ .identifier = "twoHundred", .value = "200"} });

  // Vars can also have their values copied from another variable.
  // twoNinetyNine = oneHundred;
  try runtime.scope.push( .{ .Set = .{ .identifier = "twoNinetyNine", .value = "oneHundred"} });
  // twoNinetyNine += twoHundred;
  try runtime.scope.push( .{ .Read = "twoNinetyNine" });
  try runtime.scope.push( .{ .Add = "twoHundred" });
  try runtime.scope.push( .{ .Write = "twoNinetyNine" });

  // twoNinetyNine -= 100;
  try runtime.scope.push( .{ .Read = "twoNinetyNine" });
  try runtime.scope.push( .{ .Add = "-100" });
  try runtime.scope.push( .{ .Write = "twoNinetyNine" });
  // twoNinetyNine += 50 + 49;
  try runtime.scope.push( .{ .Read = "twoNinetyNine" });
  try runtime.scope.push( .{ .Add = "50" });
  try runtime.scope.push( .{ .Add = "49" });
  try runtime.scope.push( .{ .Write = "twoNinetyNine" });

  // An example of what would happen if you performed an operation but
  // did not capture the result; the allocator will get updated but
  // the var will not change.
  // twoNinetyNine - 299;
  try runtime.scope.push( .{ .Read = "twoNinetyNine" });
  try runtime.scope.push( .{ .Add = "-299" });

  // Attempts to call console.log
  try runtime.scope.push( .{ .Read = "console" });
  try runtime.scope.push( .{ .ReadProperty = "log" });
  var args = [_][]const u8 {
    "Hello World! :)",
  };
  try runtime.scope.push( .{ .Invoke = .{ .args = &args } });

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