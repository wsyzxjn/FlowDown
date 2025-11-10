//
//  MLXModelCoordinator.swift
//  ChatClientKit
//
//  Created by GPT-5 Codex on 2025/11/10.
//

import Foundation
import MLXLLM
@preconcurrency import MLXLMCommon
import MLXVLM

public enum MLXModelKind: Equatable {
    case llm
    case vlm
}

public protocol MLXModelCoordinating: Sendable {
    func container(
        for configuration: ModelConfiguration,
        kind: MLXModelKind
    ) async throws -> ModelContainer

    func reset() async
}

public protocol MLXModelLoading {
    func loadLLM(configuration: ModelConfiguration) async throws -> ModelContainer
    func loadVLM(configuration: ModelConfiguration) async throws -> ModelContainer
}

public struct DefaultMLXModelLoader: MLXModelLoading {
    public init() {}

    public func loadLLM(configuration: ModelConfiguration) async throws -> ModelContainer {
        try await LLMModelFactory.shared.loadContainer(configuration: configuration)
    }

    public func loadVLM(configuration: ModelConfiguration) async throws -> ModelContainer {
        try await VLMModelFactory.shared.loadContainer(configuration: configuration)
    }
}

public actor MLXModelCoordinator: MLXModelCoordinating {
    public static let shared = MLXModelCoordinator()

    private struct CacheKey: Equatable {
        let identifier: ModelConfiguration.Identifier
        let kind: MLXModelKind
    }

    private let loader: MLXModelLoading
    private var cachedKey: CacheKey?
    private var cachedContainer: ModelContainer?
    private var pendingTask: LoadTask?

    public init(loader: MLXModelLoading = DefaultMLXModelLoader()) {
        self.loader = loader
    }

    public func container(
        for configuration: ModelConfiguration,
        kind: MLXModelKind
    ) async throws -> ModelContainer {
        let key = CacheKey(identifier: configuration.id, kind: kind)

        if let cachedKey, cachedKey == key, let cachedContainer {
            return cachedContainer
        }

        if let cachedKey, cachedKey != key {
            cachedContainer = nil
            pendingTask?.cancel()
            pendingTask = nil
        }

        if let task = pendingTask, cachedKey == key {
            return try await task.value()
        }

        let task = LoadTask(model: configuration, kind: kind, loader: loader)
        pendingTask = task
        cachedKey = key

        do {
            let container = try await task.value()
            cachedContainer = container
            pendingTask = nil
            return container
        } catch {
            if cachedKey == key {
                cachedKey = nil
            }
            pendingTask = nil
            throw error
        }
    }

    public func reset() async {
        cachedContainer = nil
        cachedKey = nil
        pendingTask?.cancel()
        pendingTask = nil
    }
}

private extension MLXModelCoordinator {
    final class LoadTask {
        private let task: Task<ModelContainer, Error>

        init(model configuration: ModelConfiguration, kind: MLXModelKind, loader: MLXModelLoading) {
            task = Task {
                switch kind {
                case .llm:
                    try await loader.loadLLM(configuration: configuration)
                case .vlm:
                    try await loader.loadVLM(configuration: configuration)
                }
            }
        }

        func value() async throws -> ModelContainer {
            try await task.value
        }

        func cancel() {
            task.cancel()
        }
    }
}
