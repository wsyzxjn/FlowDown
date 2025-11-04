import AppIntents
import ChatClientKit
import Foundation

struct GenerateChatResponseIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Quick Reply", defaultValue: "Quick Reply")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Send a message and get the model's response.",
            defaultValue: "Send a message and get the model's response."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model", defaultValue: "Model"),
        requestValueDialog: IntentDialog("Which model should answer?")
    )
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: LocalizedStringResource("Message", defaultValue: "Message"),
        requestValueDialog: IntentDialog("What do you want to ask?")
    )
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Quick Reply")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw FlowDownShortcutError.emptyMessage }

        let modelIdentifier = try await resolveModelIdentifier()

        let context = await MainActor.run { () -> (prompt: String, bodyFields: [String: Any]) in
            let manager = ModelManager.shared
            var prompt = manager.defaultPrompt.createPrompt()
            let additional = manager.additionalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !additional.isEmpty {
                if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    prompt = additional
                } else {
                    prompt += "\n" + additional
                }
            }
            return (prompt, manager.modelBodyFields(for: modelIdentifier))
        }

        var requestMessages: [ChatRequestBody.Message] = []
        let trimmedPrompt = context.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            requestMessages.append(.system(content: .text(trimmedPrompt)))
        }
        requestMessages.append(.user(content: .text(trimmedMessage)))

        let inference = try await ModelManager.shared.infer(
            with: modelIdentifier,
            input: requestMessages
        )

        var response = inference.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if response.isEmpty {
            response = inference.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !response.isEmpty else { throw FlowDownShortcutError.emptyResponse }

        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }

    private func resolveModelIdentifier() async throws -> ModelManager.ModelIdentifier {
        if let model {
            return model.id
        }

        return try await MainActor.run {
            let manager = ModelManager.shared

            let defaultConversationModel = ModelManager.ModelIdentifier.defaultModelForConversation
            if !defaultConversationModel.isEmpty {
                return defaultConversationModel
            }

            if let firstCloud = manager.cloudModels.value.first(where: { !$0.id.isEmpty })?.id {
                return firstCloud
            }

            if let firstLocal = manager.localModels.value.first(where: { !$0.id.isEmpty })?.id {
                return firstLocal
            }

            if #available(iOS 26.0, macCatalyst 26.0, *), AppleIntelligenceModel.shared.isAvailable {
                return AppleIntelligenceModel.shared.modelIdentifier
            }

            throw FlowDownShortcutError.modelUnavailable
        }
    }
}
