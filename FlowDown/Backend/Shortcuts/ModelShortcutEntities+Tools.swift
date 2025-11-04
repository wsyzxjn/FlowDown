import AppIntents
import Foundation
import Storage

extension ShortcutsEntities {
    struct ToolEntity: AppEntity, Identifiable {
        enum Kind: Equatable {
            case builtin(String)
            case mcp(ModelContextServer.ID)

            var identifier: String {
                switch self {
                case let .builtin(typeName):
                    "builtin:\(typeName)"
                case let .mcp(serverID):
                    "mcp:\(serverID)"
                }
            }
        }

        static var typeDisplayRepresentation: TypeDisplayRepresentation {
            .init(name: LocalizedStringResource("Tool", defaultValue: "Tool"))
        }

        static var defaultQuery: ToolQuery { .init() }

        let id: String
        let name: String
        let subtitle: String
        let kind: Kind
        let isEnabled: Bool
        let searchKeywords: [String]

        var displayName: String { name }

        var displayRepresentation: DisplayRepresentation {
            DisplayRepresentation(
                title: LocalizedStringResource(stringLiteral: name),
                subtitle: LocalizedStringResource(stringLiteral: subtitle)
            )
        }

        init(kind: Kind, name: String, subtitle: String, isEnabled: Bool, searchKeywords: [String]) {
            id = kind.identifier
            self.kind = kind
            self.name = name
            self.subtitle = subtitle
            self.isEnabled = isEnabled
            self.searchKeywords = searchKeywords
        }

        func matches(_ term: String) -> Bool {
            let lowered = term.lowercased()
            if name.lowercased().contains(lowered) { return true }
            if subtitle.lowercased().contains(lowered) { return true }
            if searchKeywords.contains(where: { $0.lowercased().contains(lowered) }) { return true }
            return false
        }
    }

    struct ToolQuery: EntityQuery {
        func entities(for identifiers: [ToolEntity.ID]) async throws -> [ToolEntity] {
            let available = await loadEntities()
            let wanted = Set(identifiers)
            return available.filter { wanted.contains($0.id) }
        }

        func suggestedEntities() async throws -> [ToolEntity] {
            let available = await loadEntities()
            return Array(available.prefix(8))
        }

        func entities(matching string: String) async throws -> [ToolEntity] {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return try await allEntities() }
            return await loadEntities().filter { $0.matches(trimmed) }
        }

        func allEntities() async throws -> [ToolEntity] {
            await loadEntities()
        }

        private func loadEntities() async -> [ToolEntity] {
            await MainActor.run {
                var results: [ToolEntity] = []

                let manager = ModelToolsManager.shared
                var processedTypes: Set<ObjectIdentifier> = []
                for tool in manager.tools {
                    let typeIdentifier = ObjectIdentifier(type(of: tool))
                    guard processedTypes.insert(typeIdentifier).inserted else { continue }

                    if tool is MTWaitForNextRound { continue }
                    if tool is MCPTool { continue }

                    let typeName = String(reflecting: type(of: tool))
                    let subtitle = String(localized: "Built-in Tool")

                    let keywords: [String] = [
                        tool.interfaceName,
                        tool.functionName,
                        typeName,
                    ]

                    let entity = ToolEntity(
                        kind: .builtin(typeName),
                        name: tool.interfaceName,
                        subtitle: subtitle,
                        isEnabled: tool.isEnabled,
                        searchKeywords: keywords
                    )
                    results.append(entity)
                }

                let servers = MCPService.shared.servers.value
                for server in servers {
                    let name = server.displayName
                    let subtitle = String(localized: "MCP Server")

                    var keywords: [String] = [name]
                    if !server.endpoint.isEmpty {
                        keywords.append(server.endpoint)
                    }
                    if !server.comment.isEmpty {
                        keywords.append(server.comment)
                    }

                    let entity = ToolEntity(
                        kind: .mcp(server.id),
                        name: name,
                        subtitle: subtitle,
                        isEnabled: server.isEnabled,
                        searchKeywords: keywords
                    )
                    results.append(entity)
                }

                return results.sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }
}
