import AppIntents
import Foundation

struct CreateConverstaionExecuteChatIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Create Conversation", defaultValue: "Create Conversation")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Open FlowDown and optionally start a conversation with a message.",
            defaultValue: "Open FlowDown and optionally start a conversation with a message."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Initial Message", defaultValue: "Initial Message"),
        requestValueDialog: IntentDialog("What message should FlowDown use to start the chat?")
    )
    var message: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create conversation")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let outcome = try await ShortcutUtilities.launchFlowDownForNewConversation(message: message)
        let dialog = IntentDialog(.init(stringLiteral: outcome))
        return .result(value: outcome, dialog: dialog)
    }
}
