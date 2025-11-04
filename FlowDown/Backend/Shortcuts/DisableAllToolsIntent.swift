import AppIntents
import Foundation

struct DisableAllToolsIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Disable All Tools", defaultValue: "Disable All Tools")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Turn off every built-in tool and all MCP servers.",
            defaultValue: "Turn off every built-in tool and all MCP servers."
        )
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Disable all FlowDown tools")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = await ShortcutUtilities.setAllToolsEnabled(false)

        let disabledCount = result.builtIn.updatedTools.count
        let skippedCount = result.builtIn.skippedTools.count
        let dialogText = String(
            localized: "Disabled built-in tools: \(disabledCount). Skipped: \(skippedCount). MCP servers disabled: \(result.mcpServersChanged) of \(result.mcpServerCount)."
        )

        let dialog = IntentDialog(.init(stringLiteral: dialogText))
        return .result(value: dialogText, dialog: dialog)
    }
}
