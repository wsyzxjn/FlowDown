//
//  ModelManager+Inference.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/29/25.
//

import ChatClientKit
import Foundation
import FoundationModels
import GPTEncoder
import MLX
import Storage
import UIKit

extension ModelManager {
    // - imageProcessingFailure : "height: 1 must be larger than factor: 28"
    static let testImage: UIImage = .init(
        color: .accent,
        size: .init(width: 64, height: 64)
    )

    private static let testImageDataURL: URL? = {
        guard let data = testImage.pngData() else { return nil }
        let base64 = data.base64EncodedString()
        return URL(string: "data:image/png;base64,\(base64)")
    }()

    func testLocalModel(_ model: LocalModel, completion: @escaping (Result<Void, Error>) -> Void) {
        guard MLX.GPU.isSupported else {
            completion(.failure(NSError(domain: "GPU", code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Your device does not support MLX."),
            ])))
            return
        }
        Task.detached {
            assert(!Thread.isMainThread)

            do {
                let preferredKind: MLXModelKind = model.capabilities.contains(.visual) ? .vlm : .llm
                let client = MLXChatClient(
                    url: ModelManager.shared.modelContent(for: model),
                    preferredKind: preferredKind
                )
                await client.errorCollector.clear()

                let userContent: ChatRequestBody.Message.MessageContent<String, [ChatRequestBody.Message.ContentPart]> = {
                    guard model.capabilities.contains(.visual),
                          let imageURL = Self.testImageDataURL
                    else {
                        return .text("YES or NO")
                    }
                    return .parts([
                        .text("YES or NO"),
                        .imageURL(imageURL, detail: .low),
                    ])
                }()

                let stream = try await client.streamingChatCompletionRequest(
                    body: .init(
                        messages: [
                            .system(content: .text("Reply YES to every query.")),
                            .user(content: userContent),
                        ],
                        maxCompletionTokens: 32,
                        temperature: 0
                    )
                )

                var reasoning = ""
                var reasoningContent = ""
                var responseContent = ""
                var collectedToolCalls: [ToolCallRequest] = []

                for try await object in stream {
                    switch object {
                    case let .chatCompletionChunk(chunk):
                        guard let delta = chunk.choices.first?.delta else { continue }
                        if let value = delta.reasoning { reasoning += value }
                        if let value = delta.reasoningContent { reasoningContent += value }
                        if let value = delta.content { responseContent += value }
                    case let .tool(call):
                        collectedToolCalls.append(call)
                    }
                }

                var trimmedContent = responseContent
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                for terminator in ChatClientConstants.additionalTerminatingTokens {
                    while trimmedContent.hasSuffix(terminator) {
                        trimmedContent.removeLast(terminator.count)
                    }
                }

                trimmedContent = trimmedContent.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmedContent.isEmpty,
                   reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   collectedToolCalls.isEmpty
                {
                    if let error = await client.collectedErrors, !error.isEmpty {
                        throw NSError(
                            domain: "Model",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: error]
                        )
                    }

                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to generate text.")]
                            )
                        )
                    )
                } else {
                    Logger.model.debugFile("model \(model.model_identifier) generates output for test case: \(trimmedContent)")
                    completion(.success(()))
                }
            } catch {
                Logger.model.errorFile("local model test failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    func testCloudModel(_ model: CloudModel, completion: @escaping (Result<Void, Error>) -> Void) {
        var dic: [String: Any] = [
            "model": model.model_identifier,
            "stream": true,
            "messages": [
                [
                    "role": "system",
                    "content": "Reply YES to every query.",
                ],
                [
                    "role": "user",
                    "content": "YES or NO",
                ],
            ],
        ]
        // Get model's configured bodyFields for testing
        if !model.bodyFields.isEmpty,
           let data = model.bodyFields.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            for (key, value) in jsonObject where dic[key] == nil {
                dic[key] = value
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dic),
              let endpoint = URL(string: model.endpoint)
        else {
            completion(
                .failure(
                    NSError(
                        domain: "Model",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid model configuration.")]
                    )
                )
            )
            return
        }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !model.token.isEmpty { request.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization") }
        // model.headers can override default headers including Authorization
        for value in model.headers {
            request.setValue(value.value, forHTTPHeaderField: value.key)
        }
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { _, resp, _ in
            guard let resp = resp as? HTTPURLResponse else {
                completion(
                    .failure(
                        NSError(
                            domain: "Model",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid response.")]
                        )
                    )
                )
                return
            }
            guard resp.statusCode == 200 else {
                completion(
                    .failure(
                        NSError(
                            domain: "Model",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: String(format: String(localized: "Invalid status code: %d"), resp.statusCode)]
                        )
                    )
                )
                return
            }
            completion(.success(()))
        }.resume()
    }

    func testAppleIntelligenceModel(completion: @escaping (Result<Void, Error>) -> Void) {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            guard AppleIntelligenceModel.shared.isAvailable else {
                completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Apple Intelligence is not available: \(AppleIntelligenceModel.shared.availabilityStatus)")])))
                return
            }
            Task {
                do {
                    let client = AppleIntelligenceChatClient()
                    let body = ChatRequestBody(
                        messages: [
                            .system(content: .text("Reply YES to every query.")),
                            .user(content: .text("YES or NO")),
                        ],
                        temperature: 0
                    )
                    let response = try await client.chatCompletionRequest(body: body)
                    if let content = response.choices.first?.message.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        completion(.success(()))
                    } else if let toolCalls = response.choices.first?.message.toolCalls, !toolCalls.isEmpty {
                        completion(.success(()))
                    } else {
                        completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from Apple Intelligence."])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        } else {
            completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requires iOS 26+"])))
        }
    }
}

extension ModelManager {
    /// Get the body fields configured for a cloud model
    /// - Parameter identifier: The model identifier
    /// - Returns: A dictionary of body fields, or empty dictionary if not found or empty
    public func modelBodyFields(for identifier: ModelIdentifier) -> [String: Any] {
        guard let model = cloudModel(identifier: identifier),
              !model.bodyFields.isEmpty,
              let data = model.bodyFields.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return jsonObject
    }

    private func chatService(
        for identifier: ModelIdentifier,
        additionalBodyField: [String: Any]
    ) throws -> any ChatService {
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            return AppleIntelligenceChatClient()
        }
        if let model = cloudModel(identifier: identifier) {
            // Use additionalBodyField directly without merging model's bodyFields
            // Callers should explicitly merge bodyFields if needed
            return RemoteChatClient(
                model: model.model_identifier,
                baseURL: model.endpoint,
                apiKey: model.token,
                additionalHeaders: model.headers,
                additionalBodyField: additionalBodyField
            )
        } else if let model = localModel(identifier: identifier) {
            let preferredKind: MLXModelKind = model.capabilities.contains(.visual) ? .vlm : .llm
            return MLXChatClient(
                url: modelContent(for: model),
                preferredKind: preferredKind
            )
        } else {
            throw NSError(
                domain: "Model",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Model not found.")]
            )
        }
    }

    struct InferenceMessage: Hashable {
        var reasoningContent: String
        var content: String

        // a json representation for tool call
        var toolCallRequests: [ToolCallRequest]

        init(reasoningContent: String = .init(), content: String = .init(), tool: [ToolCallRequest] = []) {
            self.reasoningContent = reasoningContent
            self.content = content
            toolCallRequests = tool
        }
    }

    func prepareRequestBody(
        modelID: ModelIdentifier,
        messages: [ChatRequestBody.Message]
    ) throws -> [ChatRequestBody.Message] {
        var messages = messages
        if let model = cloudModel(identifier: modelID) {
            // this model requires developer mode to work
            if model.capabilities.contains(.developerRole) {
                messages = messages.map { message in
                    switch message {
                    case let .system(content, name):
                        .developer(content: content, name: name)
                    default:
                        message
                    }
                }
            }
        }
        return messages
    }

    func infer(
        with modelID: ModelIdentifier,
        maxCompletionTokens: Int? = nil,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]? = nil
    ) async throws -> InferenceMessage {
        let stream = try await streamingInfer(
            with: modelID,
            maxCompletionTokens: maxCompletionTokens,
            input: input,
            tools: tools
        )

        var latest: InferenceMessage?
        for try await message in stream {
            latest = message
        }
        return latest ?? .init()
    }

    func streamingInfer(
        with modelID: ModelIdentifier,
        maxCompletionTokens: Int? = nil,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]? = nil
    ) async throws -> AsyncThrowingStream<InferenceMessage, any Error> {
        let client = try chatService(
            for: modelID,
            additionalBodyField: modelBodyFields(for: modelID)
        )
        await client.errorCollector.clear()
        let requestTemperature: Double = switch temperatureStrategy(for: modelID) {
        case let .send(value):
            value
        }

        let stream = try await client.streamingChatCompletionRequest(
            body: .init(
                messages: prepareRequestBody(modelID: modelID, messages: input),
                maxCompletionTokens: maxCompletionTokens,
                temperature: requestTemperature,
                tools: tools
            )
        ).compactMap { streamObject -> InferenceMessage in
            var msg = InferenceMessage()
            switch streamObject {
            case let .chatCompletionChunk(chunk):
                let delta = chunk.choices.first?.delta
                let reasoning = delta?.reasoning ?? .init()
                let reasoningContent = delta?.reasoningContent ?? .init()

                msg.reasoningContent = if reasoning == reasoningContent, !reasoning.isEmpty {
                    reasoning
                } else {
                    [reasoning, reasoningContent].filter { !$0.isEmpty }.joined()
                }
                msg.content = delta?.content ?? .init()
            case let .tool(call):
                msg.toolCallRequests = [call]
            }
            return msg
        }
        var responseContent: InferenceMessage = .init()
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var collectedToolCalls: [ToolCallRequest] = []

                    for try await chunk in stream {
                        //
                        // we assuming server sent us delta content with 0.5s each time
                        // so make sure all of our content is shown before that
                        //
                        // on average 2ms is required to display the text content
                        // and by running at 120fps we need to update no longer then 8ms
                        //

                        // by calculating for 10ms each time, 0.5s to show all, max update is 50 times
                        var counter = 0

                        // 10ms
                        func sleepOnce() async {
                            try? await Task.sleep(nanoseconds: 10 * 1_000_000)
                            counter = 0
                        }

                        let newReasoningContentLength = chunk.reasoningContent.count
                        let newReasoningContentChunkSize = max(1, newReasoningContentLength / 50)
                        counter = 0

                        for char in chunk.reasoningContent {
                            responseContent.reasoningContent += String(char)
                            counter += 1
                            if counter > newReasoningContentChunkSize {
                                continuation.yield(.init(
                                    reasoningContent: responseContent.reasoningContent
                                        .trimmingCharacters(in: .whitespacesAndNewlines),
                                    content: responseContent.content
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                ))
                                await sleepOnce()
                            }
                        }

                        let newContentLength = chunk.content.count
                        let newContentChunkSize = max(1, newContentLength / 50)
                        counter = 0

                        for char in chunk.content {
                            responseContent.content += String(char)
                            counter += 1
                            if counter > newContentChunkSize {
                                continuation.yield(.init(
                                    reasoningContent: responseContent.reasoningContent
                                        .trimmingCharacters(in: .whitespacesAndNewlines),
                                    content: responseContent.content
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                ))
                                await sleepOnce()
                            }
                        }

                        collectedToolCalls.append(contentsOf: chunk.toolCallRequests)
                    }

                    let _reasoningContent = responseContent.reasoningContent
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    var _responseContent = responseContent.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    for terminator in ChatClientConstants.additionalTerminatingTokens {
                        while _responseContent.hasSuffix(terminator) {
                            _responseContent.removeLast(terminator.count)
                        }
                    }

                    let final = InferenceMessage(
                        reasoningContent: _reasoningContent,
                        content: _responseContent,
                        tool: collectedToolCalls
                    )
                    continuation.yield(final)

                    // upon finish, check if any thing was returned
                    if final.content.isEmpty,
                       final.reasoningContent.isEmpty,
                       final.toolCallRequests.isEmpty
                    {
                        // if not, collect the error if we had any
                        if let error = await client.collectedErrors {
                            throw NSError(
                                domain: String(localized: "Inference Service"),
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: error]
                            )
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func calculateEstimateTokensUsingCommonEncoder(
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]
    ) -> Int {
        assert(!Thread.isMainThread)

        func text(
            _ content: ChatRequestBody.Message.MessageContent<String, [String]>
        ) -> String {
            switch content {
            case let .text(text):
                text
            case let .parts(strings):
                strings.joined(separator: "\n")
            }
        }

        // will pass to encoder later
        var estimatedInferenceText = ""

        // when processing images, assume 1 image = 512 tokens
        var estimatedAdditionalTokens = 0

        for message in input {
            switch message {
            case let .assistant(content, name, refusal, calls):
                estimatedInferenceText += "role: assistant\n"
                if let content { estimatedInferenceText += text(content) }
                if let name { estimatedInferenceText += "name: \(name)\n" }
                if let refusal { estimatedInferenceText += "refusal: \(refusal)\n" }
                if let calls { estimatedInferenceText += "calls: \(calls)\n" }
            case let .system(content, name):
                estimatedInferenceText += "role: assistant\n"
                estimatedInferenceText += text(content)
                if let name { estimatedInferenceText += "name: \(name)\n" }
            case let .user(content, name):
                estimatedInferenceText += "role: user\n"
                if let name { estimatedInferenceText += "name: \(name)\n" }
                switch content {
                case let .text(text):
                    estimatedInferenceText += text
                case let .parts(contentParts):
                    for part in contentParts {
                        switch part {
                        case let .text(text): estimatedInferenceText += text
                        case .imageURL: estimatedAdditionalTokens += 512
                        case .audioBase64: estimatedAdditionalTokens += 1024
                        }
                    }
                }
            case let .developer(content, name):
                estimatedInferenceText += "role: developer\n"
                estimatedInferenceText += text(content)
                if let name { estimatedInferenceText += "name: \(name)\n" }
            case let .tool(content, id):
                estimatedInferenceText += "role: tool \(id)\n"
                estimatedInferenceText += text(content)
            }
        }

        if !tools.isEmpty {
            let encoder = JSONEncoder()
            if let toolText = try? encoder.encode(tools),
               let toolString = String(data: toolText, encoding: .utf8)
            {
                estimatedInferenceText += "tools: \(toolString)\n"
            } else { assertionFailure() }
        }

        let encoder = GPTEncoder()
        let tokens = encoder.encode(text: estimatedInferenceText)

        return tokens.count + estimatedAdditionalTokens
    }
}
