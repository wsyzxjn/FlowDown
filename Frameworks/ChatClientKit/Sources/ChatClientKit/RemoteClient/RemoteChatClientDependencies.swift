//
//  RemoteChatClientDependencies.swift
//  ChatClientKit
//
//  Created by GPT-5 Codex on 2025/11/10.
//

import Foundation
import ServerEvent

protocol URLSessioning {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessioning {}

protocol EventStreamTask {
    func events() -> AsyncStream<EventSource.EventType>
}

protocol EventSourceProducing {
    func makeDataTask(for request: URLRequest) -> EventStreamTask
}

struct DefaultEventSourceFactory: EventSourceProducing {
    func makeDataTask(for request: URLRequest) -> EventStreamTask {
        let eventSource = EventSource()
        let dataTask = eventSource.dataTask(for: request)
        return DefaultEventStreamTask(dataTask: dataTask)
    }
}

private struct DefaultEventStreamTask: EventStreamTask {
    let dataTask: EventSource.DataTask

    func events() -> AsyncStream<EventSource.EventType> {
        dataTask.events()
    }
}

struct RemoteChatClientDependencies {
    var session: URLSessioning
    var eventSourceFactory: EventSourceProducing
    var responseDecoderFactory: () -> JSONDecoding
    var chunkDecoderFactory: () -> JSONDecoding
    var errorExtractor: RemoteChatErrorExtractor
    var reasoningParser: ReasoningContentParser

    static var live: RemoteChatClientDependencies {
        .init(
            session: URLSession.shared,
            eventSourceFactory: DefaultEventSourceFactory(),
            responseDecoderFactory: { JSONDecoderWrapper() },
            chunkDecoderFactory: { JSONDecoderWrapper() },
            errorExtractor: RemoteChatErrorExtractor(),
            reasoningParser: ReasoningContentParser()
        )
    }
}

protocol JSONDecoding {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

struct JSONDecoderWrapper: JSONDecoding {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
        try decoder.decode(type, from: data)
    }
}
