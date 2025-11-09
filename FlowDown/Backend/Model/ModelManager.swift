//
//  ModelManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import AlertController
import Combine
import ConfigurableKit
import Foundation
import OrderedCollections
import Storage
import UIKit

class ModelManager: NSObject {
    static let shared = ModelManager()
    static let flowdownModelConfigurationExtension = "fdmodel"

    enum TemperatureStrategy {
        case send(Double)
    }

    typealias ModelIdentifier = String
    typealias LocalModelIdentifier = LocalModel.ID
    typealias CloudModelIdentifier = CloudModel.ID

    let localModelDir: URL
    let localModelDownloadTempDir: URL

    var localModels: CurrentValueSubject<[LocalModel], Never> = .init([])
    var cloudModels: CurrentValueSubject<[CloudModel], Never> = .init([])

    let modelChangedPublisher: PassthroughSubject<Void, Never> = .init()

    let encoder = PropertyListEncoder()
    let decoder = PropertyListDecoder()

    @BareCodableStorage(key: "Model.Inference.Prompt.Default", defaultValue: PromptType.complete)
    var defaultPrompt: PromptType
    @BareCodableStorage(key: "Model.Inference.Prompt.Additional", defaultValue: "")
    var additionalPrompt: String
    @BareCodableStorage(key: "Model.Inference.Prompt.Temperature", defaultValue: 0.75)
    var temperature: Float
    @BareCodableStorage(key: "Model.Inference.SearchSensitivity", defaultValue: SearchSensitivity.balanced)
    var searchSensitivity: SearchSensitivity

    @BareCodableStorage(key: "Model.Default.Conversation", defaultValue: "")
    // swiftformat:disable:next redundantFileprivate
    fileprivate var defaultModelForConversation: String { didSet { checkDefaultModels() } }
    @BareCodableStorage(key: "Model.Default.Auxiliary.UseCurrentChatModel", defaultValue: true)
    // swiftformat:disable:next redundantFileprivate
    fileprivate var defaultModelForAuxiliaryTaskWillUseCurrentChatModel: Bool { didSet { checkDefaultModels() } }
    @BareCodableStorage(key: "Model.Default.Auxiliary", defaultValue: "")
    // swiftformat:disable:next redundantFileprivate
    fileprivate var defaultModelForAuxiliaryTask: String { didSet { checkDefaultModels() } }
    @BareCodableStorage(key: "Model.Default.AuxiliaryVisual", defaultValue: "")
    // swiftformat:disable:next redundantFileprivate
    fileprivate var defaultModelForAuxiliaryVisualTask: String { didSet { checkDefaultModels() } }
    @BareCodableStorage(key: "Model.Default.AuxiliaryVisual.SkipIfPossible", defaultValue: true)
    // swiftformat:disable:next redundantFileprivate
    var defaultModelForAuxiliaryVisualTaskSkipIfPossible: Bool
    var defaultModelForAuxiliaryVisualTaskSkipIfPossibleKey: String {
        _defaultModelForAuxiliaryVisualTaskSkipIfPossible.key
    }

    @BareCodableStorage(key: "Model.ChatInterface.CollapseReasoningSectionWhenComplete", defaultValue: false)
    var collapseReasoningSectionWhenComplete: Bool
    var collapseReasoningSectionWhenCompleteKey: String {
        _collapseReasoningSectionWhenComplete.key
    }

    @BareCodableStorage(key: "Model.ChatInterface.IncludeDynamicSystemInfo", defaultValue: true)
    var includeDynamicSystemInfo: Bool
    var includeDynamicSystemInfoKey: String {
        _includeDynamicSystemInfo.key
    }

    var cancellables: Set<AnyCancellable> = []

    override private init() {
        assert(LocalModelIdentifier.self == ModelIdentifier.self)
        assert(CloudModelIdentifier.self == ModelIdentifier.self)

        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        localModelDir = base.appendingPathComponent("Models.Local")
        localModelDownloadTempDir = base.appendingPathComponent("Models.Local.Temp")

        super.init()

        try? FileManager.default.createDirectory(
            at: localModelDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? FileManager.default.createDirectory(
            at: localModelDownloadTempDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        localModels.send(scanLocalModels())
        cloudModels.send(scanCloudModels())

        // make sure after scan!
        Publishers.CombineLatest(
            localModels,
            cloudModels
        )
        .ensureMainThread()
        .sink { [weak self] _ in
            self?.modelChangedPublisher.send(())
            self?.checkDefaultModels()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SyncEngine.CloudModelChanged)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.CloudModelChanged")
                guard let self else { return }
                cloudModels.send(scanCloudModels())
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SyncEngine.LocalDataDeleted)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.LocalDataDeleted")
                guard let self else { return }
                cloudModels.send(scanCloudModels())
            }
            .store(in: &cancellables)

        Self.defaultPromptConfigurableObject.whenValueChange(type: PromptType.RawValue.self) { [weak self] output in
            guard let output, let value = PromptType(rawValue: output) else { return }
            self?.defaultPrompt = value
        }
        Self.temperatureConfigurableObject.whenValueChange(type: Float.self) { [weak self] output in
            self?.temperature = output ?? 0.75
        }
    }

    func checkDefaultModels() {
        defer { modelChangedPublisher.send() }

        let appleIntelligenceId: String? = if #available(iOS 26.0, macCatalyst 26.0, *) {
            AppleIntelligenceModel.shared.modelIdentifier
        } else {
            nil
        }
        if !defaultModelForConversation.isEmpty,
           localModel(identifier: defaultModelForConversation) == nil,
           cloudModel(identifier: defaultModelForConversation) == nil,
           !(appleIntelligenceId != nil && defaultModelForConversation == appleIntelligenceId)
        {
            Logger.model.debugFile("reset defaultModelForConversation due to not found")
            defaultModelForConversation = ""
        }

        if !defaultModelForAuxiliaryTask.isEmpty,
           localModel(identifier: defaultModelForAuxiliaryTask) == nil,
           cloudModel(identifier: defaultModelForAuxiliaryTask) == nil,
           !(appleIntelligenceId != nil && defaultModelForAuxiliaryTask == appleIntelligenceId)
        {
            Logger.model.debugFile("reset defaultModelForAuxiliaryTask due to not found")
            defaultModelForAuxiliaryTask = ""
        }

        if !defaultModelForAuxiliaryVisualTask.isEmpty {
            let localModelSatisfied = localModel(identifier: defaultModelForAuxiliaryVisualTask)?.capabilities.contains(.visual) ?? false
            let cloudModelSatisfied = cloudModel(identifier: defaultModelForAuxiliaryVisualTask)?.capabilities.contains(.visual) ?? false
            let appleIntelligenceSatisfied = false // Apple Intelligence does not support visual capabilities
            if !localModelSatisfied, !cloudModelSatisfied, !appleIntelligenceSatisfied {
                Logger.model.debugFile("reset defaultModelForAuxiliaryVisualTask due to not found")
                defaultModelForAuxiliaryVisualTask = ""
            }
        }
    }

    func modelName(identifier: ModelIdentifier?) -> String {
        guard let identifier else { return "-" }
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            return AppleIntelligenceModel.shared.modelDisplayName
        }
        return cloudModel(identifier: identifier)?.modelFullName
            ?? localModel(identifier: identifier)?.model_identifier
            ?? "-"
    }

    func modelCapabilities(identifier: ModelIdentifier) -> Set<ModelCapabilities> {
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            // no endpoint
            return [.tool]
        }
        if let cloudModel = cloudModel(identifier: identifier) {
            return cloudModel.capabilities
        }
        if let localModel = localModel(identifier: identifier) {
            return localModel.capabilities
        }
        return []
    }

    func modelContextLength(identifier: ModelIdentifier) -> Int {
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            // Apple Intelligence: context length is not public, use a safe default
            return 8192
        }
        if let cloudModel = cloudModel(identifier: identifier) {
            return cloudModel.context.rawValue
        }
        if let localModel = localModel(identifier: identifier) {
            return localModel.context.rawValue
        }
        return 8192
    }

    func temperatureStrategy(for identifier: ModelIdentifier?) -> TemperatureStrategy {
        if let identifier, let cloudModel = cloudModel(identifier: identifier) {
            switch cloudModel.temperature_preference {
            case .inherit:
                break
            case .custom:
                if let override = cloudModel.temperature_override {
                    return .send(override)
                }
            }
        }

        if let identifier, let localModel = localModel(identifier: identifier) {
            switch localModel.temperature_preference {
            case .inherit:
                break
            case .custom:
                if let override = localModel.temperature_override {
                    return .send(override)
                }
            }
        }

        return .send(Double(temperature))
    }

    func displayTextForTemperature(
        preference: ModelTemperaturePreference,
        override: Double?
    ) -> String {
        switch preference {
        case .inherit:
            return String(localized: "Inference default")
        case .custom:
            if let override {
                return String(
                    format: String(localized: "Custom @ %.2f"),
                    override
                )
            }
            return String(localized: "Custom")
        }
    }

    var temperaturePresets: [(title: String, value: Double, icon: String)] {
        [
            (String(localized: "Freezing @ 0.0"), 0.0, "snowflake"),
            (String(localized: "Precise @ 0.25"), 0.25, "thermometer.low"),
            (String(localized: "Stable @ 0.5"), 0.5, "thermometer.low"),
            (String(localized: "Humankind @ 0.75"), 0.75, "thermometer.medium"),
            (String(localized: "Creative @ 1.0"), 1.0, "thermometer.medium"),
            (String(localized: "Imaginative @ 1.5"), 1.5, "thermometer.high"),
            (String(localized: "Magical @ 2.0"), 2.0, "thermometer.high"),
        ]
    }

    func importModels(at urls: [URL], controller: UIViewController) {
        Indicator.progress(
            title: "Importing Model",
            controller: controller
        ) { completionHandler in
            assert(!Thread.isMainThread)
            var success: [String] = []
            var errors: [String] = []
            for url in urls {
                if url.pathExtension.lowercased() == "zip" {
                    let result = ModelManager.shared.unpackAndImport(modelAt: url)
                    switch result {
                    case let .success(model):
                        success.append(model.model_identifier)
                    case let .failure(error):
                        errors.append(error.localizedDescription)
                    }
                    continue
                }
                if url.pathExtension.lowercased() == "plist" || url.pathExtension.lowercased() == "fdmodel" {
                    do {
                        let model = try ModelManager.shared.importCloudModel(at: url)
                        success.append(model.model_identifier)
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                    continue
                }
                errors.append(url.lastPathComponent)
            }
            if let error = errors.first {
                throw NSError(domain: "ModelImport", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            let count = success.count
            await completionHandler {
                let message = String(
                    format: String(localized: "Imported %d Models"),
                    count
                )
                Indicator.present(title: "\(message)")
            }
        }
    }
}

extension ModelManager.ModelIdentifier {
    static var defaultModelForAuxiliaryTaskWillUseCurrentChatModel: Bool {
        get { ModelManager.shared.defaultModelForAuxiliaryTaskWillUseCurrentChatModel }
        set { ModelManager.shared.defaultModelForAuxiliaryTaskWillUseCurrentChatModel = newValue }
    }

    static var defaultModelForConversation: Self {
        get { ModelManager.shared.defaultModelForConversation }
        set { ModelManager.shared.defaultModelForConversation = newValue }
    }

    static var defaultModelForAuxiliaryTask: Self {
        get {
            if defaultModelForAuxiliaryTaskWillUseCurrentChatModel {
                ModelManager.shared.defaultModelForConversation
            } else {
                ModelManager.shared.defaultModelForAuxiliaryTask
            }
        }
        set { ModelManager.shared.defaultModelForAuxiliaryTask = newValue }
    }

    /// Returns the stored auxiliary model identifier, ignoring the "use chat model" setting
    static var storedAuxiliaryTaskModel: Self { ModelManager.shared.defaultModelForAuxiliaryTask }

    static var defaultModelForAuxiliaryVisualTask: Self {
        get { ModelManager.shared.defaultModelForAuxiliaryVisualTask }
        set { ModelManager.shared.defaultModelForAuxiliaryVisualTask = newValue }
    }
}
