/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A typed key for data stored on a ``Node``.
///
/// Key names are serialized, so packages should use a stable namespace such as
/// `com.example.feature.block-id`.
public struct NodeStateKey<Value: Codable & Equatable> {
  public let name: String
  public let defaultValue: Value

  public init(_ name: String, defaultValue: Value) {
    self.name = name
    self.defaultValue = defaultValue

    if let conflict = NodeStateTypeRegistry.register(name: name, defaultValue: defaultValue) {
      assertionFailure(
        "NodeState key \"\(name)\" was registered for both \(conflict.existingType) and \(conflict.newType)."
      )
    }
  }
}

internal enum NodeStateJSONValue: Codable, Equatable {
  case null
  case bool(Bool)
  case integer(Int64)
  case unsignedInteger(UInt64)
  case number(Double)
  case string(String)
  case array([NodeStateJSONValue])
  case object([String: NodeStateJSONValue])

  init<Value: Encodable>(_ value: Value) throws {
    let data = try JSONEncoder().encode(value)
    self = try JSONDecoder().decode(NodeStateJSONValue.self, from: data)
  }

  func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
    let data = try JSONEncoder().encode(self)
    return try JSONDecoder().decode(type, from: data)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(UInt64.self) {
      self = .unsignedInteger(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([NodeStateJSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: NodeStateJSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .unsignedInteger(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }
}

internal final class NodeStateStorage {
  var values: [String: NodeStateJSONValue]

  init(values: [String: NodeStateJSONValue] = [:]) {
    self.values = values
  }

  func copy() -> NodeStateStorage {
    NodeStateStorage(values: values)
  }

  func valuesForEncoding() -> [String: NodeStateJSONValue] {
    values.filter { name, value in
      !NodeStateTypeRegistry.isDefaultValue(value, forName: name)
    }
  }
}

private struct NodeStateTypeDescriptor {
  let type: ObjectIdentifier
  let typeName: String
  let defaultValue: NodeStateJSONValue?
}

private enum NodeStateTypeRegistry {
  struct Conflict {
    let existingType: String
    let newType: String
  }

  private static let lock = NSLock()
  private static var descriptors: [String: NodeStateTypeDescriptor] = [:]

  static func register<Value: Codable & Equatable>(
    name: String,
    defaultValue: Value
  ) -> Conflict? {
    let descriptor = NodeStateTypeDescriptor(
      type: ObjectIdentifier(Value.self),
      typeName: String(reflecting: Value.self),
      defaultValue: try? NodeStateJSONValue(defaultValue)
    )

    lock.lock()
    defer { lock.unlock() }

    if let existing = descriptors[name], existing.type != descriptor.type {
      return Conflict(existingType: existing.typeName, newType: descriptor.typeName)
    }

    descriptors[name] = descriptor
    return nil
  }

  static func isDefaultValue(_ value: NodeStateJSONValue, forName name: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let defaultValue = descriptors[name]?.defaultValue else {
      return false
    }
    return defaultValue == value
  }
}
