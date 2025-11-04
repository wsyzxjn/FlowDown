//
//  InferenceIntentHandler.swift
//  FlowDown
//
//  Created by qaq on 4/11/2025.
//

import AppIntents
import ChatClientKit
import Foundation
import Storage

enum InferenceIntentHandler {
    struct Options {
        let allowsImages: Bool
        let allowsTools: Bool
    }

    static func execute(
        model: ShortcutsEntities.ModelEntity?,
        message: String,
        image: IntentFile?,
        options: Options
    ) async throws -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImage = image != nil

        if trimmedMessage.isEmpty, !(options.allowsImages && hasImage) {
            throw FlowDownShortcutError.emptyMessage
        }

        let modelIdentifier = try await resolveModelIdentifier(model: model)
        let prompt = await preparePrompt()

        var requestMessages: [ChatRequestBody.Message] = []
        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestMessages.append(.system(content: .text(prompt)))
        }

        let capabilities = await MainActor.run {
            ModelManager.shared.modelCapabilities(identifier: modelIdentifier)
        }

        var contentParts: [ChatRequestBody.Message.ContentPart] = []
        if let image {
            guard options.allowsImages else { throw FlowDownShortcutError.imageNotAllowed }
            guard capabilities.contains(.visual) else { throw FlowDownShortcutError.imageNotSupportedByModel }
            try contentParts.append(prepareImageContentPart(from: image))
        }

        if !trimmedMessage.isEmpty {
            if contentParts.isEmpty {
                requestMessages.append(.user(content: .text(trimmedMessage)))
            } else {
                contentParts.append(.text(trimmedMessage))
                requestMessages.append(.user(content: .parts(contentParts)))
            }
        } else if !contentParts.isEmpty {
            requestMessages.append(.user(content: .parts(contentParts)))
        }

        guard requestMessages.contains(where: { candidate in
            if case .user = candidate { return true }
            return false
        }) else {
            throw FlowDownShortcutError.emptyMessage
        }

        var toolDefinitions: [ChatRequestBody.Tool]? = nil
        if options.allowsTools {
            guard capabilities.contains(.tool) else { throw FlowDownShortcutError.toolsNotSupportedByModel }
            let tools = await ModelToolsManager.shared.getEnabledToolsIncludeMCP()
            let definitions = tools.map(\.definition)
            if !definitions.isEmpty {
                toolDefinitions = definitions
            }
        }

        let inference = try await ModelManager.shared.infer(
            with: modelIdentifier,
            input: requestMessages,
            tools: toolDefinitions
        )

        var response = inference.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if response.isEmpty {
            response = inference.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !response.isEmpty else { throw FlowDownShortcutError.emptyResponse }
        return response
    }

    private static func resolveModelIdentifier(model: ShortcutsEntities.ModelEntity?) async throws -> ModelManager.ModelIdentifier {
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

    static func preparePrompt() async -> String {
        await MainActor.run {
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
            return prompt
        }
    }

    static func prepareImageContentPart(from file: IntentFile) throws -> ChatRequestBody.Message.ContentPart {
        var data = file.data
        if data.isEmpty, let url = file.fileURL {
            data = try Data(contentsOf: url)
        }

        guard !data.isEmpty, let image = UIImage(data: data) else {
            throw FlowDownShortcutError.invalidImage
        }

        let processed = resize(image: image, maxDimension: 1024)
        guard let pngData = processed.pngData() else {
            throw FlowDownShortcutError.invalidImage
        }
        let base64 = pngData.base64EncodedString()
        guard let url = URL(string: "data:image/png;base64,\(base64)") else {
            throw FlowDownShortcutError.invalidImage
        }
        return .imageURL(url)
    }

    static func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}
