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
    return try self.scope.exec(utils.EmptyArray);
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
  try runtime.scope.push( .{ .Declare = .{ .identifier = "result",  .type = .LET } });

  // add = (a, b) => { return a + b; }
  //
  // note: This can be simplified to:
  // try fnScope.push( .{ .Read = ":0" });
  // try fnScope.push( .{ .Add = ":1" });
  // try fnScope.push( .{ .Return = {} });
  //
  // This however, demonstrates how JS will put the arguments into scope
  // as variables.
  const fnScope = try runtime.scope.createScope();
  try fnScope.push( .{ .Declare = .{ .identifier = "a",  .type = .CONST } });
  try fnScope.push( .{ .Set = .{ .identifier = "a", .value = ":0" }});
  try fnScope.push( .{ .Declare = .{ .identifier = "b",  .type = .CONST } });
  try fnScope.push( .{ .Set = .{ .identifier = "b", .value = ":1" }});
  try fnScope.push( .{ .Read = "a" });
  try fnScope.push( .{ .Add = "b" });
  try fnScope.push( .{ .Return = {} });
  try runtime.scope.push( .{ .SetReference = .{ .identifier = "add", .value = .{
    .Function = .{
      .scope = fnScope,
    },
  }}});

  // var result = add("10", "20");
  try runtime.scope.push( .{ .Read = "add" });
  var args = [_][]const u8 { "10", "20" };
  try runtime.scope.push( .{ .Invoke = .{ .args = &args }});
  try runtime.scope.push( .{ .Write = "result" });

  try runtime.exec();

  var result = try runtime.scope.getValue("result");
  try std.testing.expectEqualStrings("30", result);
}

test "Access vars from upper scope" {
  const runtime = try ESRuntime.init(TestAllocator);
  defer runtime.deinit();

  try runtime.scope.push( .{ .Declare = .{ .identifier = "a", .type = .CONST }});
  try runtime.scope.push( .{ .Declare = .{ .identifier = "funcA", .type = .CONST }});
  try runtime.scope.push( .{ .Declare = .{ .identifier = "ret", .type = .CONST }});

  try runtime.scope.push( .{ .Set = .{ .identifier = "a", .value = "25" }});

  const fnScope = try runtime.scope.createScope();
  try fnScope.push( .{ .Declare = .{ .identifier = "funcB", .type = .CONST }});
  try runtime.scope.push( .{ .SetReference = .{ .identifier = "funcA", .value = .{
    .Function = .{
      .scope = fnScope
    }
  }}});

  const nestedFnScope = try fnScope.createScope();
  try nestedFnScope.push( .{ .Read = "a" });
  try nestedFnScope.push( .{ .Add = "15" });
  try nestedFnScope.push( .{ .Return = {} });
  try fnScope.push( .{ .SetReference = .{ .identifier = "funcB", .value = .{
    .Function = .{
      .scope = nestedFnScope
    }
  }}});
  try fnScope.push( .{ .Read = "funcB" });
  try fnScope.push( .{ .Invoke = .{ .args = utils.EmptyArray }});
  try fnScope.push( .{ .Return = {} });

  try runtime.scope.push( .{ .Read = "funcA" });
  try runtime.scope.push( .{ .Invoke = .{ .args = utils.EmptyArray }});
  try runtime.scope.push( .{ .Write = "ret" });

  try runtime.exec();

  var result = try runtime.scope.getValue("ret");
  try std.testing.expectEqualStrings("40", result);
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
    "\nHello from console.log!\n",
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