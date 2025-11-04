import AppIntents
import Foundation

struct EnableAllToolsIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Enable All Tools", defaultValue: "Enable All Tools")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Enable every built-in tool and all MCP servers.",
            defaultValue: "Enable every built-in tool and all MCP servers."
        )
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Enable all FlowDown tools")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = await ShortcutUtilities.setAllToolsEnabled(true)

        let enabledCount = result.builtIn.updatedTools.count
        let skippedCount = result.builtIn.skippedTools.count
        let dialogText = String(
            localized: "Enabled built-in tools: \(enabledCount). Skipped: \(skippedCount). MCP servers enabled: \(result.mcpServersChanged) of \(result.mcpServerCount)."
        )

        let dialog = IntentDialog(.init(stringLiteral: dialogText))
        return .result(value: dialogText, dialog: dialog)
    }
}
