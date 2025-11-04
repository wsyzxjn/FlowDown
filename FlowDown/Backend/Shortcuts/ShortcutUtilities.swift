import AppIntents
import Foundation
import Storage
import UIKit

enum ShortcutUtilitiesError: LocalizedError {
    case unableToCreateURL
    case failedToLaunchApplication
    case invalidMessageEncoding
    case conversationNotFound
    case conversationHasNoMessages
    case toolNotFound
    case serverNotFound

    var errorDescription: String? {
        switch self {
        case .unableToCreateURL:
            String(localized: "Unable to construct FlowDown URL.")
        case .failedToLaunchApplication:
            String(localized: "Failed to launch FlowDown.")
        case .invalidMessageEncoding:
            String(localized: "Unable to encode the provided message.")
        case .conversationNotFound:
            String(localized: "No conversations were found.")
        case .conversationHasNoMessages:
            String(localized: "The latest conversation does not contain any messages.")
        case .toolNotFound:
            String(localized: "The selected tool could not be located.")
        case .serverNotFound:
            String(localized: "The selected MCP server could not be located.")
        }
    }
}

enum ShortcutUtilities {
    private static let flowDownScheme = "flowdown"
    private static let newConversationHost = "new"

    static func launchFlowDownForNewConversation(message: String?) async throws -> String {
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let urlString: String
        if trimmedMessage.isEmpty {
            urlString = "\(flowDownScheme)://\(newConversationHost)"
        } else {
            guard let encoded = trimmedMessage.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                throw ShortcutUtilitiesError.invalidMessageEncoding
            }
            urlString = "\(flowDownScheme)://\(newConversationHost)/\(encoded)"
        }

        guard let url = URL(string: urlString) else {
            throw ShortcutUtilitiesError.unableToCreateURL
        }

        let launched = await UIApplication.shared.open(url)

        guard launched else { throw ShortcutUtilitiesError.failedToLaunchApplication }

        if trimmedMessage.isEmpty {
            return String(localized: "FlowDown launched to start a new conversation.")
        } else {
            return String(localized: "FlowDown launched with your message.")
        }
    }

    static func latestConversationTranscript() throws -> String {
        guard let latestConversation = sdb.conversationList().first else {
            throw ShortcutUtilitiesError.conversationNotFound
        }

        let messages = sdb.listMessages(within: latestConversation.id)
            .filter { [.user, .assistant].contains($0.role) }

        guard !messages.isEmpty else {
            throw ShortcutUtilitiesError.conversationHasNoMessages
        }

        let title = latestConversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var transcript: [String] = []
        if !title.isEmpty {
            transcript.append("# \(title)")
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        for message in messages {
            let role = message.role == .user
                ? String(localized: "User")
                : String(localized: "Assistant")

            let timestamp = formatter.string(from: message.creation)
            var contentParts: [String] = []

            let mainContent = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
            if !mainContent.isEmpty {
                contentParts.append(mainContent)
            }

            let reasoning = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reasoning.isEmpty, message.role == .assistant {
                contentParts.append(String(localized: "(Reasoning) \(reasoning)"))
            }

            transcript.append("**\(role)** [\(timestamp)]\n\(contentParts.joined(separator: "\n\n"))")
        }

        return transcript.joined(separator: "\n\n")
    }

    struct ToolToggleResult {
        let updatedTools: [String]
        let skippedTools: [String]
    }

    @MainActor
    private static func toggleBuiltInTools(on enabled: Bool) -> ToolToggleResult {
        let manager = ModelToolsManager.shared
        var updated: [String] = []
        var skipped: [String] = []
        var processedTypes: Set<ObjectIdentifier> = []

        for tool in manager.tools {
            let identifier = ObjectIdentifier(type(of: tool))
            guard processedTypes.insert(identifier).inserted else { continue }

            if tool is MTWaitForNextRound {
                skipped.append(tool.interfaceName)
                continue
            }

            if tool is MCPTool {
                skipped.append(tool.interfaceName)
                continue
            }

            if tool.isEnabled != enabled {
                tool.isEnabled = enabled
                updated.append(tool.interfaceName)
            }
        }

        return .init(updatedTools: updated, skippedTools: skipped)
    }

    static func setAllToolsEnabled(_ enabled: Bool) async -> (builtIn: ToolToggleResult, mcpServerCount: Int, mcpServersChanged: Int) {
        let builtInResult = await MainActor.run { toggleBuiltInTools(on: enabled) }

        let servers = MCPService.shared.servers.value
        var changed = 0
        for server in servers {
            if server.isEnabled == enabled { continue }
            MCPService.shared.edit(identifier: server.id) {
                $0.update(\.isEnabled, to: enabled)
            }
            changed += 1
        }

        return (builtInResult, servers.count, changed)
    }

    static func enableTool(_ entity: ShortcutsEntities.ToolEntity) async throws -> String {
        switch entity.kind {
        case let .builtin(typeName):
            let wasUpdated = await MainActor.run { () -> Bool in
                let manager = ModelToolsManager.shared
                guard let tool = manager.tools.first(where: { String(reflecting: type(of: $0)) == typeName }) else {
                    return false
                }
                if tool is MTWaitForNextRound || tool is MCPTool {
                    return false
                }
                if !tool.isEnabled {
                    tool.isEnabled = true
                    return true
                }
                return true
            }

            guard wasUpdated else { throw ShortcutUtilitiesError.toolNotFound }
            return String(localized: "Enabled tool: \(entity.displayName)")

        case let .mcp(serverID):
            var found = false
            MCPService.shared.edit(identifier: serverID) {
                $0.update(\.isEnabled, to: true)
                found = true
            }
            guard found else { throw ShortcutUtilitiesError.serverNotFound }
            return String(localized: "Enabled MCP server: \(entity.displayName)")
        }
    }
}
