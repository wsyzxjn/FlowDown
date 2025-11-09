//
//  Created by ktiays on 2025/2/12.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import RegexBuilder
import ServerEvent
import Tokenizers

open class RemoteChatClient: ChatService {
    private let session = URLSession.shared

    /// The ID of the model to use.
    ///
    /// The required section should be in alphabetical order.
    public let model: String
    public var baseURL: String?
    public var path: String?
    public var apiKey: String?

    public enum Error: Swift.Error {
        case invalidURL
        case invalidApiKey
        case invalidData
    }

    public var collectedErrors: String?

    public var additionalHeaders: [String: String] = [:]
    public var additionalField: [String: Any] = [:]

    public init(
        model: String,
        baseURL: String? = nil,
        path: String? = nil,
        apiKey: String? = nil,
        additionalHeaders: [String: String] = [:],
        additionalBodyField: [String: Any] = [:]
    ) {
        self.model = model
        self.baseURL = baseURL
        self.path = path
        self.apiKey = apiKey
        self.additionalHeaders = additionalHeaders
        additionalField = additionalBodyField
    }

    public func chatCompletionRequest(body: ChatRequestBody) async throws -> ChatResponseBody {
        let model = model
        logger.infoFile("starting non-streaming request to model: \(model) with \(body.messages.count) messages")
        let startTime = Date()
        var body = body
        body.model = model
        body.stream = false
        body.streamOptions = nil
        let request = try request(for: body, additionalField: additionalField)
        let (data, _) = try await session.data(for: request)
        logger.debugFile("received response data: \(data.count) bytes")
        if let error = extractError(fromInput: data) {
            logger.errorFile("received error from server: \(error.localizedDescription)")
            throw error
        }
        var response = try JSONDecoder().decode(ChatResponseBody.self, from: data)
        response.choices = response.choices.map { choice in
            var choice = choice
            choice.message = extractReasoningContent(from: choice.message)
            return choice
        }
        let duration = Date().timeIntervalSince(startTime)
        let contentLength = response.choices.first?.message.content?.count ?? 0
        logger.infoFile("completed non-streaming request in \(String(format: "%.2f", duration))s, content length: \(contentLength)")
        return response
    }

    private func processReasoningContent(
        _ content: [String],
        _ reasoningContent: [String],
        _ isInsideReasoningContent: inout Bool,
        _ contentBuffer: inout String,
        _ response: inout ChatCompletionChunk
    ) {
        // now we can decode <think> and </think> tag for that purpose
        // transfer all content to buffer, and begin our process
        let previousBuffer = contentBuffer
        var hasProcessedReasoningToken = isInsideReasoningContent
        let bufferContent = contentBuffer + content.joined() // 将缓冲区内容和新内容合并
        assert(reasoningContent.isEmpty)
        contentBuffer = "" // 清空缓冲区

        if !isInsideReasoningContent {
            if let range = bufferContent.range(of: REASONING_START_TOKEN) {
                hasProcessedReasoningToken = true
                let beforeReasoning = String(bufferContent[..<range.lowerBound])
                    .trimmingCharactersFromEnd(in: .whitespacesAndNewlines)
                let afterReasoningBegin = String(bufferContent[range.upperBound...])
                    .trimmingCharactersFromStart(in: .whitespacesAndNewlines)

                // 检查同一块内容中是否有结束标记
                if let endRange = afterReasoningBegin.range(of: REASONING_END_TOKEN) {
                    // 有开始也有结束标记 - 完整的推理块
                    let reasoningText = String(afterReasoningBegin[..<endRange.lowerBound])
                        .trimmingCharactersFromEnd(in: .whitespacesAndNewlines)
                    let remainingText = String(afterReasoningBegin[endRange.upperBound...])
                        .trimmingCharactersFromStart(in: .whitespacesAndNewlines)

                    // 只发送一个delta，避免多delta丢失问题
                    if !beforeReasoning.isEmpty {
                        response = .init(choices: [.init(delta: .init(content: beforeReasoning))])
                        // 将reasoning和remaining放回buffer，下次处理
                        if !reasoningText.isEmpty || !remainingText.isEmpty {
                            contentBuffer = "<think>\(reasoningText)</think>\(remainingText)"
                        }
                    } else if !reasoningText.isEmpty {
                        response = .init(choices: [.init(delta: .init(reasoningContent: reasoningText))])
                        // 将remaining放到buffer
                        if !remainingText.isEmpty {
                            contentBuffer = remainingText
                        }
                    } else if !remainingText.isEmpty {
                        response = .init(choices: [.init(delta: .init(content: remainingText))])
                    } else {
                        response = .init(choices: [])
                    }
                } else {
                    // 有开始标记但没有结束标记 - 进入推理内容
                    isInsideReasoningContent = true
                    if !beforeReasoning.isEmpty {
                        response = .init(choices: [.init(delta: .init(content: beforeReasoning))])
                        // 将reasoning内容放回buffer
                        if !afterReasoningBegin.isEmpty {
                            contentBuffer = afterReasoningBegin
                        }
                    } else if !afterReasoningBegin.isEmpty {
                        response = .init(choices: [.init(delta: .init(reasoningContent: afterReasoningBegin))])
                    } else {
                        response = .init(choices: [])
                    }
                }
            }
        } else {
            // 我们已经在推理内容中，检查是否有结束标记
            hasProcessedReasoningToken = true
            if let range = bufferContent.range(of: REASONING_END_TOKEN) {
                // 找到结束标记 - 退出推理模式
                isInsideReasoningContent = false

                let reasoningText = String(bufferContent[..<range.lowerBound])
                    .trimmingCharactersFromEnd(in: .whitespacesAndNewlines)
                let remainingText = String(bufferContent[range.upperBound...])
                    .trimmingCharactersFromStart(in: .whitespacesAndNewlines)

                // 只发送reasoning，remainingText放到buffer避免丢失
                if !reasoningText.isEmpty {
                    response = .init(choices: [.init(delta: .init(reasoningContent: reasoningText))])
                } else {
                    response = .init(choices: [])
                }
                // 将remaining内容放到buffer，下次作为普通内容发送
                if !remainingText.isEmpty {
                    contentBuffer = remainingText
                }
            } else {
                // 仍在推理内容中
                response = .init(choices: [.init(delta: .init(
                    reasoningContent: bufferContent
                ))])
            }
        }

        if !hasProcessedReasoningToken,
           !previousBuffer.isEmpty,
           !previousBuffer.contains(REASONING_START_TOKEN),
           !previousBuffer.contains(REASONING_END_TOKEN)
        {
            if response.choices.isEmpty {
                response = .init(choices: [.init(delta: .init(content: previousBuffer))])
            } else {
                var updatedChoices = response.choices
                let firstChoice = updatedChoices[0]
                let mergedContent = previousBuffer + (firstChoice.delta.content ?? "")
                let updatedDelta = ChatCompletionChunk.Choice.Delta(
                    content: mergedContent,
                    reasoning: firstChoice.delta.reasoning,
                    reasoningContent: firstChoice.delta.reasoningContent,
                    refusal: firstChoice.delta.refusal,
                    role: firstChoice.delta.role,
                    toolCalls: firstChoice.delta.toolCalls
                )
                updatedChoices[0] = .init(
                    delta: updatedDelta,
                    finishReason: firstChoice.finishReason,
                    index: firstChoice.index
                )
                response.choices = updatedChoices
            }
        }
    }

    private func flushBufferedContent(
        _ contentBuffer: inout String,
        isInsideReasoningContent: inout Bool,
        continuation: AsyncStream<ChatServiceStreamObject>.Continuation
    ) {
        guard !contentBuffer.isEmpty else { return }

        if isInsideReasoningContent {
            continuation.yield(.chatCompletionChunk(chunk: .init(
                choices: [.init(delta: .init(reasoningContent: contentBuffer))]
            )))
            contentBuffer = ""
            isInsideReasoningContent = false
            return
        }

        while !contentBuffer.isEmpty {
            let pendingBuffer = contentBuffer
            var response = ChatCompletionChunk(choices: [])
            processReasoningContent([], [], &isInsideReasoningContent, &contentBuffer, &response)

            if !response.choices.isEmpty {
                continuation.yield(.chatCompletionChunk(chunk: response))
                continue
            }

            if pendingBuffer.contains(REASONING_START_TOKEN) || pendingBuffer.contains(REASONING_END_TOKEN) {
                let sanitized = pendingBuffer
                    .replacingOccurrences(of: REASONING_START_TOKEN, with: "")
                    .replacingOccurrences(of: REASONING_END_TOKEN, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !sanitized.isEmpty {
                    continuation.yield(.chatCompletionChunk(chunk: .init(
                        choices: [.init(delta: .init(reasoningContent: sanitized))]
                    )))
                }
            } else {
                continuation.yield(.chatCompletionChunk(chunk: .init(
                    choices: [.init(delta: .init(content: pendingBuffer))]
                )))
            }
            contentBuffer = ""
        }
    }

    public func streamingChatCompletionRequest(
        body: ChatRequestBody
    ) async throws -> AnyAsyncSequence<ChatServiceStreamObject> {
        let model = model
        var body = body
        body.model = model
        body.stream = true

        // streamOptions is not supported when running up on cohere api
        // body.streamOptions = .init(includeUsage: true)
        let request = try request(for: body, additionalField: additionalField)
        logger.infoFile("starting streaming request to model: \(model) with \(body.messages.count) messages, temperature: \(body.temperature ?? 1.0)")

        let stream = AsyncStream<ChatServiceStreamObject> { continuation in
            Task.detached {
                // Extracts or preserves the reasoning content within a `ChoiceMessage`.

                var canDecodeReasoningContent = true
                var isInsideReasoningContent = false
                var contentBuffer = "" // 用于缓存跨chunk的内容
                let toolCallCollector: ToolCallCollector = .init()
                var chunkCount = 0
                var totalContentLength = 0

                let eventSource = EventSource()
                let dataTask = eventSource.dataTask(for: request)

                for await event in dataTask.events() {
                    switch event {
                    case .open:
                        logger.infoFile("connection was opened.")
                    case let .error(error):
                        logger.errorFile("received an error: \(error)")
                        self.collect(error: error)
                    case let .event(event):
                        guard let data = event.data?.data(using: .utf8) else {
                            continue
                        }
                        if let text = String(data: data, encoding: .utf8) {
                            if text.lowercased() == "[DONE]".lowercased() {
                                logger.debugFile("received done from upstream")
                                continue
                            }
                        }
                        do {
                            var response = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)

                            // Extract reasoning content from API (if any)
                            let reasoningContent = [
                                response.choices.map(\.delta).compactMap(\.reasoning),
                                response.choices.map(\.delta).compactMap(\.reasoningContent),
                            ].flatMap(\.self).filter { !$0.isEmpty }

                            // If API provides non-empty reasoning content, it has native support
                            if canDecodeReasoningContent, !reasoningContent.isEmpty {
                                canDecodeReasoningContent = false
                            }

                            // Only process <think> tags if API doesn't have native reasoning support
                            if canDecodeReasoningContent {
                                let content = response.choices.map(\.delta).compactMap(\.content)
                                self.processReasoningContent(content, [], &isInsideReasoningContent, &contentBuffer, &response)
                            }

                            for delta in response.choices {
                                for toolDelta in delta.delta.toolCalls ?? [] {
                                    toolCallCollector.submit(delta: toolDelta)
                                }
                                if let content = delta.delta.content {
                                    totalContentLength += content.count
                                }
                            }

                            chunkCount += 1
                            continuation.yield(.chatCompletionChunk(chunk: response))
                        } catch {
                            if let text = String(data: data, encoding: .utf8) {
                                logger.log("text content associated with this error \(text)")
                            }
                            self.collect(error: error)
                        }
                        if let decodeError = self.extractError(fromInput: data) {
                            self.collect(error: decodeError)
                        }
                    case .closed:
                        logger.infoFile("connection was closed.")
                    }
                }

                // 刷新缓冲区中剩余的内容
                self.flushBufferedContent(&contentBuffer, isInsideReasoningContent: &isInsideReasoningContent, continuation: continuation)

                toolCallCollector.finalizeCurrentDeltaContent()
                for call in toolCallCollector.pendingRequests {
                    continuation.yield(.tool(call: call))
                }
                logger.infoFile("streaming completed: received \(chunkCount) chunks, total content length: \(totalContentLength), tool calls: \(toolCallCollector.pendingRequests.count)")
                continuation.finish()
            }
        }
        return stream.eraseToAnyAsyncSequence()
    }

    private func collect(error: Swift.Error) {
        if let error = error as? EventSourceError {
            switch error {
            case .undefinedConnectionError:
                collectedErrors = String(localized: "Unable to connect to the server.", bundle: .module)
            case let .connectionError(statusCode, response):
                if let decodedError = extractError(fromInput: response) {
                    collectedErrors = decodedError.localizedDescription
                } else {
                    collectedErrors = String(localized: "Connection error: \(statusCode)", bundle: .module)
                }
            case .alreadyConsumed:
                assertionFailure()
            }
            return
        }
        collectedErrors = error.localizedDescription
        logger.errorFile("collected error: \(error.localizedDescription)")
    }

    private func extractError(fromInput input: Data) -> Swift.Error? {
        let dic = try? JSONSerialization.jsonObject(with: input, options: []) as? [String: Any]
        guard let dic else { return nil }

        if let status = dic["status"] as? Int, (400 ... 599).contains(status) {
            // something must be wrong
            let error = dic["error"] as? String ?? String(localized: "Unknown Error", bundle: .module)
            var errorMessage = "Server returns an error: \(status) \(error)"
            // looking for message filed in any of the nested dictionaries
            var bfs: [Any] = [dic]
            while !bfs.isEmpty {
                let current = bfs.removeFirst()
                if let currentDic = current as? [String: Any] {
                    if let message = currentDic["message"] as? String {
                        errorMessage = message
                        break
                    }
                    for (_, value) in currentDic {
                        bfs.append(value)
                    }
                }
            }
            return NSError(domain: error, code: status, userInfo: [
                NSLocalizedDescriptionKey: errorMessage,
            ])
        }

        if let errorContent = dic["error"] as? [String: Any], !errorContent.isEmpty {
            var message = errorContent["message"] as? String ?? String(localized: "Unknown Error", bundle: .module)
            let code = errorContent["code"] as? Int ?? 403
            if let metadata = errorContent["metadata"] as? [String: Any],
               let metadataMessage = metadata["message"] as? String
            {
                message += " \(metadataMessage)"
            }
            return NSError(domain: String(localized: "Server Error"), code: code, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Server returns an error: \(code) \(message)", bundle: .module),
            ])
        }

        return nil
    }

    private func request(for body: ChatRequestBody, additionalField: [String: Any] = [:]) throws -> URLRequest {
        guard let baseURL else {
            logger.errorFile("invalid base URL")
            throw Error.invalidURL
        }
        guard let apiKey else {
            logger.errorFile("invalid API key")
            throw Error.invalidApiKey
        }

        var path = path ?? ""
        if !path.isEmpty, !path.starts(with: "/") {
            path = "/\(path)"
        }

        guard var urlComponents = URLComponents(string: baseURL),
              let pathComponents = URLComponents(string: path)
        else {
            logger.errorFile("failed to parse URL components from baseURL: \(baseURL), path: \(path)")
            throw Error.invalidURL
        }

        urlComponents.path += pathComponents.path
        urlComponents.queryItems = pathComponents.queryItems

        guard let url = urlComponents.url else {
            logger.errorFile("failed to construct final URL from components")
            throw Error.invalidURL
        }

        logger.debugFile("constructed request URL: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // additionalHeaders can override default headers including Authorization
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if !additionalField.isEmpty {
            var originalDictionary: [String: Any] = [:]
            if let data = request.httpBody,
               let dic = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                originalDictionary = dic
            }
            for (key, value) in additionalField {
                originalDictionary[key] = value
            }
            request.httpBody = try JSONSerialization.data(
                withJSONObject: originalDictionary,
                options: []
            )
        }

        return request
    }

    /// Extracts or preserves the reasoning content within a `ChoiceMessage`.
    ///
    /// This function inspects the provided `ChoiceMessage` to determine if it already contains
    /// a `reasoningContent` value, indicating compliance with the expected API format. If present,
    /// the original `ChoiceMessage` is returned unchanged. Otherwise, it attempts to extract the text
    /// enclosed within `<think>` and `</think>` tags from the `content` property,
    /// creating a new `ChoiceMessage` with the extracted content assigned to `reasoningContent`.
    ///
    /// - Parameter choice: The `ChoiceMessage` object to process.
    /// - Returns: A `ChoiceMessage` object, either the original if `reasoningContent` exists, or a new one
    ///            with extracted reasoning content if applicable; returns the original if extraction fails.
    private func extractReasoningContent(from choice: ChoiceMessage) -> ChoiceMessage {
        if false
            || choice.reasoning?.isEmpty == false
            || choice.reasoningContent?.isEmpty == false
        {
            // A reasoning content already exists, so return the original choice.
            return choice
        }

        guard let content = choice.content else {
            return choice
        }

        guard let startRange = content.range(of: REASONING_START_TOKEN),
              let endRange = content.range(of: REASONING_END_TOKEN, range: startRange.upperBound ..< content.endIndex)
        else {
            // No reasoning content found, return the original choice.
            return choice
        }

        let reasoningRange = startRange.upperBound ..< endRange.lowerBound

        let leading = content[..<startRange.lowerBound]
        let trailing = content[endRange.upperBound...]

        let reasoningContent = content[reasoningRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remainingContent = String(
            (leading + trailing)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )

        var newChoice = choice
        newChoice.content = remainingContent
        newChoice.reasoningContent = reasoningContent
        return newChoice
    }
}

class ToolCallCollector {
    var functionName: String = ""
    var functionArguments: String = ""
    var currentId: Int?
    var pendingRequests: [ToolCallRequest] = []

    func submit(delta: ChatCompletionChunk.Choice.Delta.ToolCall) {
        guard let function = delta.function else { return }

        if currentId != delta.index { finalizeCurrentDeltaContent() }
        currentId = delta.index

        if let name = function.name, !name.isEmpty {
            functionName.append(name)
        }
        if let arguments = function.arguments {
            functionArguments.append(arguments)
        }
    }

    func finalizeCurrentDeltaContent() {
        guard !functionName.isEmpty || !functionArguments.isEmpty else {
            return
        }
        let call = ToolCallRequest(name: functionName, args: functionArguments)
        logger.debugFile("tool call finalized: \(call.name) with args: \(call.args)")
        pendingRequests.append(call)
        functionName = ""
        functionArguments = ""
    }
}
