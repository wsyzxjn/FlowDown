import AppIntents
import Foundation

struct EnableToolIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Enable Tool", defaultValue: "Enable Tool")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Enable a specific FlowDown tool or MCP server.",
            defaultValue: "Enable a specific FlowDown tool or MCP server."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Tool", defaultValue: "Tool"),
        requestValueDialog: IntentDialog("Which tool should be enabled?"),
        optionsProvider: ToolOptionsProvider()
    )
    var tool: ShortcutsEntities.ToolEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Enable \(\.$tool)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await ShortcutUtilities.enableTool(tool)
        let dialog = IntentDialog(.init(stringLiteral: message))
        return .result(value: message, dialog: dialog)
    }
}

extension EnableToolIntent {
    struct ToolOptionsProvider: DynamicOptionsProvider {
        func results() async throws -> [ShortcutsEntities.ToolEntity] {
            try await ShortcutsEntities.ToolQuery().allEntities()
        }

        func results(matching query: String) async throws -> [ShortcutsEntities.ToolEntity] {
            try await ShortcutsEntities.ToolQuery().entities(matching: query)
        }
    }
}
