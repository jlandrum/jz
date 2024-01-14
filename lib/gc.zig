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
const UNDEFINED = types.UNDEFINED;
const InvokeAssign = types.InvokeAssign;
const InvokeAdd = types.InvokeAdd;
const Instruction = types.Instruction;

pub const ESObjectManager = struct {
  allocator: Allocator,
  objects: ArrayList(*ESObjectImpl),

  pub fn init(allocator: Allocator) ESObjectManager {
    const objman = ESObjectManager{
      .allocator = allocator,
      .objects = ArrayList(*ESObjectImpl).init(allocator),
    };

    return objman;
  }

  pub fn createObject(self: *ESObjectManager) !ESObject {
    const obj = try ESObjectImpl.init(self.allocator);
    _ = try self.objects.append(obj);

    return ESObject {
      .value = obj,
    };
  }

  pub fn deinit(self: *ESObjectManager) void {
    for (self.objects.items) |obj| {
      self.allocator.destroy(obj);
    }
    // var it = self.objects.valueIterator();
    // while (it.next()) |item| {
    //   self.allocator.destroy(item.*);
    // }
    self.objects.deinit();
  }
};