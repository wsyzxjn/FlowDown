//
//  RemoteChatClient.swift
//  ChatClientKit
//
//  Created by ktiays on 2025/2/12.
//  Refactored by GPT-5 Codex on 2025/11/10.
//

import Foundation
import ServerEvent

open class RemoteChatClient: ChatService {
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

    private let session: URLSessioning
    private let eventSourceFactory: EventSourceProducing
    private let responseDecoderFactory: () -> JSONDecoding
    private let chunkDecoderFactory: () -> JSONDecoding
    private let errorExtractor: RemoteChatErrorExtractor
    private let reasoningParser: ReasoningContentParser

    public convenience init(
        model: String,
        baseURL: String? = nil,
        path: String? = nil,
        apiKey: String? = nil,
        additionalHeaders: [String: String] = [:],
        additionalBodyField: [String: Any] = [:]
    ) {
        self.init(
            model: model,
            baseURL: baseURL,
            path: path,
            apiKey: apiKey,
            additionalHeaders: additionalHeaders,
            additionalBodyField: additionalBodyField,
            dependencies: .live
        )
    }

    init(
        model: String,
        baseURL: String? = nil,
        path: String? = nil,
        apiKey: String? = nil,
        additionalHeaders: [String: String] = [:],
        additionalBodyField: [String: Any] = [:],
        dependencies: RemoteChatClientDependencies
    ) {
        self.model = model
        self.baseURL = baseURL
        self.path = path
        self.apiKey = apiKey
        self.additionalHeaders = additionalHeaders
        additionalField = additionalBodyField
        session = dependencies.session
        eventSourceFactory = dependencies.eventSourceFactory
        responseDecoderFactory = dependencies.responseDecoderFactory
        chunkDecoderFactory = dependencies.chunkDecoderFactory
        errorExtractor = dependencies.errorExtractor
        reasoningParser = dependencies.reasoningParser
    }

    public func chatCompletionRequest(body: ChatRequestBody) async throws -> ChatResponseBody {
        logger.infoFile("starting non-streaming request to model: \(model) with \(body.messages.count) messages")
        let startTime = Date()

        var requestBody = body
        requestBody.model = model
        requestBody.stream = false
        requestBody.streamOptions = nil

        let builder = makeRequestBuilder()
        let request = try builder.makeRequest(body: requestBody, additionalField: additionalField)
        let (data, _) = try await session.data(for: request)
        logger.debugFile("received response data: \(data.count) bytes")

        if let error = errorExtractor.extractError(from: data) {
            logger.errorFile("received error from server: \(error.localizedDescription)")
            throw error
        }

        let responseDecoder = RemoteChatResponseDecoder(
            decoder: responseDecoderFactory(),
            reasoningParser: reasoningParser
        )
        let response = try responseDecoder.decodeResponse(from: data)
        let duration = Date().timeIntervalSince(startTime)
        let contentLength = response.choices.first?.message.content?.count ?? 0
        logger.infoFile("completed non-streaming request in \(String(format: "%.2f", duration))s, content length: \(contentLength)")
        return response
    }

    public func streamingChatCompletionRequest(
        body: ChatRequestBody
    ) async throws -> AnyAsyncSequence<ChatServiceStreamObject> {
        var requestBody = body
        requestBody.model = model
        requestBody.stream = true

        let builder = makeRequestBuilder()
        let request = try builder.makeRequest(body: requestBody, additionalField: additionalField)
        logger.infoFile("starting streaming request to model: \(model) with \(body.messages.count) messages, temperature: \(body.temperature ?? 1.0)")

        let processor = RemoteChatStreamProcessor(
            eventSourceFactory: eventSourceFactory,
            chunkDecoder: chunkDecoderFactory(),
            errorExtractor: errorExtractor,
            reasoningParser: reasoningParser
        )

        return processor.stream(request: request) { [weak self] error in
            self?.collect(error: error)
        }
    }

    private func makeRequestBuilder() -> RemoteChatRequestBuilder {
        RemoteChatRequestBuilder(
            baseURL: baseURL,
            path: path,
            apiKey: apiKey,
            additionalHeaders: additionalHeaders
        )
    }

    private func collect(error: Swift.Error) {
        if let error = error as? EventSourceError {
            switch error {
            case .undefinedConnectionError:
                collectedErrors = String(localized: "Unable to connect to the server.")
            case let .connectionError(statusCode, response):
                if let decodedError = errorExtractor.extractError(from: response) {
                    collectedErrors = decodedError.localizedDescription
                } else {
                    collectedErrors = String(localized: "Connection error: \(statusCode)")
                }
            case .alreadyConsumed:
                assertionFailure()
            }
            return
        }
        collectedErrors = error.localizedDescription
        logger.errorFile("collected error: \(error.localizedDescription)")
    }
}
