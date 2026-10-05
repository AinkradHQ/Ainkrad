import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/InProcessTransport.swift
import Foundation

/// Carries MCP JSON-RPC to an Ainkrad app's in-process `MCPAppServer`.
///
/// Deliberately dumb: encode, hand to the activator, yield the reply. All
/// lifecycle (is the app open, should it be launched, did the launch time out)
/// belongs to `AppServerActivator`, so this stays a pipe and can be reasoned
/// about the same way `StdioTransport` is.
///
/// Unlike stdio/HTTP there is no process or socket to establish, so `start()`
/// is a no-op and every failure surfaces on `send`.
actor InProcessTransport: MCPTransport {
    private let appID: String
    private let activator: AppServerActivator
    private let box = MCPSharedContinuationBox()

    init(appID: String, activator: AppServerActivator) {
        self.appID = appID
        self.activator = activator
    }

    func start() async throws {}

    func send(_ message: JSONValue) async throws {
        let encoded: String
        do {
            let data = try JSONEncoder().encode(message)
            guard let string = String(data: data, encoding: .utf8) else {
                throw MCPError.protocolError("could not encode outbound message as UTF-8")
            }
            encoded = string
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.protocolError(String(describing: error))
        }

        let reply: String
        do {
            reply = try await activator.dispatch(appID: appID, message: encoded)
        } catch let failure as AppDispatchFailure {
            throw MCPError.transport(Self.describe(failure))
        } catch {
            throw MCPError.transport(String(describing: error))
        }

        // A notification produces no reply. Yielding an empty frame here would
        // make MCPClient's read loop log a malformed message on every
        // `notifications/initialized` — swallow it instead.
        guard !reply.isEmpty else { return }
        guard let value = JSONValue.parse(reply) else {
            throw MCPError.protocolError("app '\(appID)' returned a non-JSON reply")
        }
        box.yield(value)
    }

    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in box.set(continuation) }
    }

    func stop() async { box.finish() }

    /// Failure text the model actually sees — names the app and the cause.
    private static func describe(_ failure: AppDispatchFailure) -> String {
        switch failure {
        case .notInstalled(let id):
            return "app '\(id)' is not installed or publishes no MCP server"
        case .disabled(let id):
            return "app '\(id)' is switched off in settings"
        case .launchTimedOut(let id):
            return "app '\(id)' did not open in time"
        }
    }
}
