import Foundation
import AinkradHostRuntime

/// Lets the assistant search the notification feed.
///
/// `.read` class, and read is all it can do: the tool holds a
/// `SageSignalContext`, which itself only calls `page` and `search`. There is
/// no path from here to emitting or clearing anything — Sage answering "what
/// failed today?" must not be able to change the answer.
///
/// Optional because the feed can be absent: when the store cannot be opened at
/// launch the center degrades to memory, and if there is no center at all the
/// tool is simply not registered. A tool that exists and always errors teaches
/// the model to stop trying.
@MainActor
struct SignalSearchTool: AgentTool {
    /// Resolved at CALL time, not construction: the feed does not exist yet
    /// when the tool array is assembled. See `SignalReadAccess`.
    let access: SignalReadAccess

    let name = "signal_search"
    let description = """
        Search the user's Ainkrad notification feed — build failures, sync \
        errors, agent notifications, app installs. Use it to answer questions \
        about what happened, failed, or finished recently, rather than guessing \
        or asking the user to check.
        """
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string(
                        "Words to search for in notification titles and bodies, "
                        + "e.g. \"build failed\" or the name of an app."),
                ]),
            ]),
            "required": .array([.string("query")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let query = input["query"]?.stringValue else {
            throw ToolError.message("signal_search requires a \"query\" string.")
        }
        guard let context = access.context else {
            // Not an error either. The feed being unavailable is a fact about
            // this machine right now, and a tool that throws teaches the model
            // to stop calling it — including later, when it would have worked.
            return ToolResult(content: "The notification feed is unavailable on this machine.",
                              isError: false)
        }
        // No-match is a RESULT, not an error, for the same reason: `search`
        // returns a sentence saying nothing matched rather than an empty
        // string, which reads as a broken tool and invites a guess.
        return ToolResult(content: context.search(query), isError: false)
    }
}
