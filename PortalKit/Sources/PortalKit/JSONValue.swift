import Foundation

/// JSONValue is any JSON: what GraphQL variables and answers hold before they
/// are read into the app's own types.
public enum JSONValue: Equatable, Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }

    /// The value under key, when this is an object that has it.
    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    /// The string this holds, when it is one.
    public var stringValue: String? {
        if case .string(let string) = self { return string }
        return nil
    }
}

extension JSONValue {
    public var boolValue: Bool? {
        if case .bool(let bool) = self { return bool }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let number) = self { return number }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    /// The object this holds, or the object a string holds as JSON text. The
    /// server sends `metadata` either way, and sometimes encoded twice.
    public var objectValue: [String: JSONValue]? {
        switch self {
        case .object(let object):
            return object
        case .string(let text):
            guard text.hasPrefix("{") || text.hasPrefix("\""), let data = text.data(using: .utf8),
                let parsed = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return nil }
            if case .string = parsed { return parsed.objectValue }
            return parsed.objectValue
        default:
            return nil
        }
    }
}
