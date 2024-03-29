const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;

const types = @import("types.zig");
const ESReference = types.ESReference;
const Instruction = types.Instruction;
const ESType = types.ESType;
const UNDEFINED = types.UNDEFINED;
const ESVarType = types.ESVarType;
const ESString = types.ESString;

const gc = @import("gc.zig");
const utils = @import("utils.zig");

/// Represents an execution scope. This can be the root execution
/// scope, or the body of a function.
pub const ESScope = struct {
  allocator: Allocator,
  vars: StringHashMap(*ESReference),
  callStack: ArrayList(*Instruction),
  register: ?ESType,
  objectManager: *gc.ESObjectManager,
  childScopes: ArrayList(*ESScope),
  parentScope: ?*ESScope,

  // TODO: Move
  pub fn log(args: [][]const u8) void {
    std.debug.print("{s}\n", .{args[0]});
  }

  /// Creates a new scope
  pub fn init(allocator: Allocator, objectManager: *gc.ESObjectManager) !*ESScope {
    var ptr = try allocator.create(ESScope);

    ptr.* = ESScope {
      .allocator = allocator,
      .vars = StringHashMap(*ESReference).init(allocator),
      .callStack = ArrayList(*Instruction).init(allocator),
      .register = null,
      .objectManager = objectManager,
      .childScopes = ArrayList(*ESScope).init(allocator),
      .parentScope = null,
    };
    return ptr;
  }

  pub fn initStdLib(self: *ESScope) !void {
      // Pre-assign standard elements
      try self.declareVar("undefined", .CONST);
      try self.assignVar("undefined", UNDEFINED);
      try self.declareVar("NaN", .CONST);
      try self.assignVar("NaN", .{ .Number = .{ .value = std.math.nan(f64) }});
      try self.declareVar("Infinity", .CONST);
      try self.assignVar("Infinity", .{ .Number = .{ .value = std.math.inf(f64) }});
      try self.declareVar("console", .CONST);

      var console = ESType { .Object = try self.objectManager.createObject() };
      var fnptr = @intFromPtr(&ESScope.log);
      try console.Object.value.addProperty("log", .{
        .NativeFunction = .{
          .value = fnptr,
        }
      });
      try self.assignVar("console", console);
  }

  pub fn push(self: *ESScope, invocation: Instruction) !void {
    var ptr = try self.allocator.create(Instruction);
    ptr.* = invocation;
    _ = try self.callStack.append(ptr);
  }

  fn declareVar(self: *ESScope, identifier: []const u8, vartype: ESVarType) !void {
    const key = try self.allocator.alloc(u8, identifier.len);
    std.mem.copy(u8, key, identifier);

    if (self.vars.get(identifier)) |value| {
      if (value.vartype == .CONST) {
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

    try self.vars.put(key, ptr);
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

  pub fn createScope(self: *ESScope) !*ESScope {
    var childScope = try ESScope.init(self.allocator, self.objectManager);
    childScope.parentScope = self;
    _ = try self.childScopes.append(childScope);
    return childScope;
  }

  pub fn getValue(self: *ESScope, identifier: []const u8) ![]const u8 {
    if (self.vars.get(identifier)) |v| {
      switch (v.value) {
        .String => |str| return str.toString(),
        .Number => |num| return num.toString(),
        .Undefined => |undf| return undf.toString(),
        .Object => |obj| return obj.toString(),
        .Function => |func| return func.toString(),
        .NativeFunction => |fun| return fun.toString(),
      }
    } else {
      return "undefined";
    }
  }

  pub fn debugValue(self: *ESScope, identifier: []const u8) !void {
    if (self.vars.get(identifier)) |v| {
      switch (v.value) {
        .String => |str| std.debug.print("{s}<String> = \"{s}\"\n", .{identifier, str.toString()}),
        .Number => |num|  std.debug.print("{s}<Number> = {s}\n", .{identifier, num.toString()}),
        .Undefined => |undf| std.debug.print("{s}<Undefined> = {s}\n", .{identifier, undf.toString()}),
        .Object => |obj| std.debug.print("{s}<Object> = {s}\n", .{identifier, obj.toString()}),
        .Function => |func| std.debug.print("{s}<Function> = {s}\n", .{identifier, func.toString()}),
        .NativeFunction => |fun| std.debug.print("{s}<NativeFunction> = {s}\n", .{identifier, fun.toString()}),
      }
    } else {
      return std.debug.print("{s}<err> = {s} is not declared.\n", .{identifier, identifier});
    }
  }

  fn getVar(self: *ESScope, identifier: []const u8) ?ESType {
    var currentScope: ?*ESScope = self;

    while (currentScope) |scope| {
      if (scope.vars.get(identifier)) |v| {
        return v.value;
      } else {
        currentScope = scope.parentScope;
      }
    }

    return null;
  }

  fn stringToESType(self: *ESScope, value: []const u8) !ESType {
    switch (value[0]) {
      // Strings
      '"' => return .{ .String = .{ .value = value[1..value.len-1] }},
      '\'' => return .{ .String = .{ .value = value[1..value.len-1] }},
      // Numbers or vars
      else => {
        if (utils.isNumber(value)) {
          return .{ .Number = .{ .value = utils.parseNumber(value) }};
        } else if (self.getVar(value)) |variable| {
          return variable;
        } else {
          return error.InvalidAssignment;
        }
      }
    }
  }

  pub fn exec(self: *ESScope, _args: ?[][]const u8) !void {
    if (_args) |args| {
      for (args, 0..) |arg, i| {
        var buf: [10]u8 = undefined;
        const index = try std.fmt.bufPrint(buf[0..], ":{d}", .{i});
        const value = try self.stringToESType(arg);

        try self.declareVar(index, .CONST);
        try self.assignVar(index, value);
      }
    }

    for (self.callStack.items) |call| {
      switch (call.*) {
        .Declare => |declVar| {
          try self.declareVar(declVar.identifier, declVar.type);
        },
        .Set => |inv| {
          const value = try stringToESType(self, inv.value);
          try self.assignVar(inv.identifier, value);
        },
        .SetReference => |setref| {
          try self.assignVar(setref.identifier, setref.value);
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
        .ReadProperty => |identifier| {
          if (self.register) |registerItem| {
            switch (registerItem) {
              .Object => |objContainer| {
                var obj = objContainer.value;
                if (obj.properties.get(identifier)) |prop| {
                  self.register = prop;
                } else {
                  return error.NoSuchProperty;
                }
              },
              else => {
                return error.NotAnObject;
              }
            }
          } else {
            return error.ReferenceError;
          }
        },
        .Invoke => |invocation| {
          if (self.register) |registerItem| {
            switch (registerItem) {
              .NativeFunction => |func| {
                var funcCast = func;
                try funcCast.call(invocation.args);
              },
              .Function => |func| {
                var funcCast = func;
                try funcCast.call(invocation.args);
              },
              else => {
                return error.NotAFunction;
              }
            }
          }
          // NO-OP
        },
        .Return => {
          if (self.parentScope) |parentScope| {
            parentScope.register = self.register;
          } else {
            return error.ReturnFromRootScope;
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
    // Destroy variables

    {
      var it = self.vars.valueIterator();
      while (it.next()) |entry| {
        self.allocator.destroy(entry.*);
      }
    }

    {
      var it = self.vars.keyIterator();
      while (it.next()) |entry| {
        self.allocator.free(entry.*);
      }
    }

    // Destroy call stack
    for (self.callStack.items) |entry| {
      self.allocator.destroy(entry);
    }

    // Destroy child scopes
    for (self.childScopes.items) |entry| {
      entry.deinit();
    }

    // Destroy everything else
    self.callStack.deinit();
    self.vars.deinit();
    self.childScopes.deinit();
    self.allocator.destroy(self);
  }
};