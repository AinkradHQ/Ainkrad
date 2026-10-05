// Sources/Ainkrad/Core/AgentKit/Providers/AnyJSON.swift
import Foundation

/// Minimal decodable wrapper that captures an arbitrary JSON value as a
/// Foundation object — used to decode Gemini `functionCall.args` (whose shape
/// is tool-defined) without a concrete type.
struct AnyJSON: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) {
            value = v
        } else if let v = try? c.decode(Int.self) {
            value = v
        } else if let v = try? c.decode(Double.self) {
            value = v
        } else if let v = try? c.decode(String.self) {
            value = v
        } else if let v = try? c.decode([String: AnyJSON].self) {
            value = v.mapValues(\.value)
        } else if let v = try? c.decode([AnyJSON].self) {
            value = v.map(\.value)
        } else {
            value = [String: Any]()
        }
    }
}
