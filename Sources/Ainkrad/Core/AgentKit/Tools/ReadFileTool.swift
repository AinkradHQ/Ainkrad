import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Tools/ReadFileTool.swift
import Foundation

/// Reads a UTF-8 text file at an absolute path. Any path is allowed (per the
/// Slice-2a decision); the approval HUD, not a path sandbox, is the gate.
struct ReadFileTool: AgentTool {
    static let maxBytes = 256 * 1024

    let name = "read_file"
    let description = "Read the UTF-8 text contents of a file at an absolute path on the user's machine."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the file to read."),
                ])
            ]),
            "required": .array([.string("path")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let path = input["path"]?.stringValue, !path.isEmpty else {
            throw ToolError.message("read_file requires a non-empty \"path\".")
        }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ToolError.message("No file exists at \(path).")
        }
        guard !isDirectory.boolValue else {
            throw ToolError.message("\(path) is a directory, not a file.")
        }
        // Enforce the cap via file attributes BEFORE reading, so a huge file is
        // never fully paged into memory just to be rejected.
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
            size > Self.maxBytes
        {
            throw ToolError.message("File is \(size) bytes; the read limit is \(Self.maxBytes).")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ToolError.message("Could not read \(path): \(error.localizedDescription).")
        }
        guard data.count <= Self.maxBytes else {
            throw ToolError.message("File is \(data.count) bytes; the read limit is \(Self.maxBytes).")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError.message("File at \(path) is not valid UTF-8 text.")
        }
        return ToolResult(content: text, isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let path = input["path"]?.stringValue ?? "?"
        return ToolApprovalPreview(title: "Read file", summary: path, diff: nil)
    }
}
