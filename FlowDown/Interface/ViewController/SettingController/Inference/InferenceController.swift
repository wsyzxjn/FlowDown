//
//  InferenceController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/2/25.
//

import AlertController
import ConfigurableKit
import MLX
import UIKit

extension SettingController.SettingContent {
    class InferenceController: StackScrollController {
        init() {
            super.init(nibName: nil, bundle: nil)
            title = String(localized: "Inference")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background
        }

        private let defaultConversationModel = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "quote.bubble"))
            $0.configure(title: "Default Model")
            $0.configure(description: "The model used for new conversations.")
        }

        private let defaultAuxiliaryModelAlignWithChatModel = ConfigurableBooleanBlockView(storage: .init(
            key: "InferenceController.defaultAuxiliaryModelAlignWithChatModel",
            defaultValue: true,
            storage: UserDefaultKeyValueStorage(suite: .standard)
        )).with {
            $0.configure(icon: UIImage(systemName: "quote.bubble"))
            $0.configure(title: "Use Chat Model")
            $0.configure(description: "Utilize the current chat model to assist with auxiliary tasks.")
        }

        private let defaultAuxiliaryModel = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "ellipsis.bubble"))
            $0.configure(title: "Task Model")
            $0.configure(description: "The model is used for auxiliary tasks such as generating conversation titles and web search keywords.")
        }

        private let defaultAuxiliaryVisualModel = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "eye"))
            $0.configure(title: "Auxiliary Visual Model")
            $0.configure(description: "The model is used for visual input when the current model does not support it. It will extract information before using the current model for inference.")
        }

        private let skipVisualAssessmentView = ConfigurableObject(
            icon: "arrowshape.zigzag.forward",
            title: "Skip Recognization If Possible",
            explain: "Skip the visual assessment process when the conversation model natively supports visual input. Enabling this option can improve the efficiency when using visual models, but if you switch to a model that does not support visual input after using it, the image information will be lost.",
            key: ModelManager.shared.defaultModelForAuxiliaryVisualTaskSkipIfPossibleKey,
            defaultValue: true,
            annotation: .boolean
        )
        .createView()

        override func setupContentViews() {
            super.setupContentViews()

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Conversation"
                )
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(defaultConversationModel)
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableObject(
                    icon: "character.bubble",
                    title: "Chat Template",
                    explain: "The template used for new conversations. You can customize the system prompt and other parameters here. Also known as assistant.",
                    ephemeralAnnotation: .page {
                        ChatTemplateListController()
                    }
                ).createView()
            )
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Task Model"
                )
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(defaultAuxiliaryModelAlignWithChatModel)
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(defaultAuxiliaryModel)
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "Using a local or mini model for this purpose will lower overall costs while maintaining a consistent experience."
                )
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Visual Assessment"
                )
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(defaultAuxiliaryVisualModel)
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(skipVisualAssessmentView)
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "While using a visual assessment model may result in some loss of information, it can make tasks requiring visual input possible."
                )
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            defer { updateDefaultModelinfoFile() }

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Parameters"
                )
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ModelManager.defaultPromptConfigurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ModelManager.extraPromptConfigurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ModelManager.includeDynamicSystemInfo.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ModelManager.temperatureConfigurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "The above parameters will be applied to all conversations."
                )
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            // Apple Intelligence Availability Section
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                stackView.addArrangedSubviewWithMargin(
                    ConfigurableSectionHeaderView().with(
                        header: "Apple Intelligence"
                    )
                ) { $0.bottom /= 2 }
                stackView.addArrangedSubview(SeparatorView())

                let appleIntelligenceStatusView = ConfigurableInfoView().with {
                    $0.configure(icon: UIImage(systemName: "apple.intelligence"))
                    $0.configure(title: "Apple Intelligence")
                    $0.configure(description: AppleIntelligenceModel.shared.availabilityDescription)
                    $0.configure(value: AppleIntelligenceModel.shared.availabilityStatus)
                }
                stackView.addArrangedSubviewWithMargin(appleIntelligenceStatusView)
                stackView.addArrangedSubview(SeparatorView())

                stackView.addArrangedSubviewWithMargin(
                    ConfigurableSectionFooterView().with(
                        footer: "Apple Intelligence provides on-device AI capabilities when available."
                    )
                ) { $0.top /= 2 }
                stackView.addArrangedSubview(SeparatorView())
            }

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "MLX"
                )
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(MLX.GPU.configurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "MLX is only available on Apple Silicon devices with Metal 3 support."
                )
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            updateDefaultModelinfoFile()
        }

        func updateDefaultModelinfoFile() {
            ModelManager.shared.checkDefaultModels()

            let defConvId = ModelManager.ModelIdentifier.defaultModelForConversation
            var handledConvModel = false
            if #available(iOS 26.0, macCatalyst 26.0, *), defConvId == AppleIntelligenceModel.shared.modelIdentifier {
                defaultConversationModel.configure(value: AppleIntelligenceModel.shared.modelDisplayName)
                // Add availability status as subtitle when Apple Intelligence is selected
                if !AppleIntelligenceModel.shared.isAvailable {
                    defaultConversationModel.configure(description: "Status: \(AppleIntelligenceModel.shared.availabilityStatus)")
                }
                defaultConversationModel.use { [weak self] in
                    guard let self else { return [] }
                    return ModelManager.shared.buildModelSelectionMenu(
                        currentSelection: ModelManager.ModelIdentifier.defaultModelForConversation,
                        allowSelectionWithNone: true
                    ) { [weak self] identifier in
                        ModelManager.ModelIdentifier.defaultModelForConversation = identifier
                        self?.updateDefaultModelinfoFile()
                    }
                }
                handledConvModel = true
            }
            if !handledConvModel {
                if let localModel = ModelManager.shared.localModel(identifier: defConvId) {
                    defaultConversationModel.configure(value: localModel.model_identifier)
                } else if let cloudModel = ModelManager.shared.cloudModel(identifier: defConvId) {
                    defaultConversationModel.configure(value: cloudModel.modelFullName)
                } else {
                    defaultConversationModel.configure(value: String(localized: "Not Configured"))
                }
                defaultConversationModel.use { [weak self] in
                    guard let self else { return [] }
                    return ModelManager.shared.buildModelSelectionMenu(
                        currentSelection: ModelManager.ModelIdentifier.defaultModelForConversation,
                        allowSelectionWithNone: true
                    ) { [weak self] identifier in
                        ModelManager.ModelIdentifier.defaultModelForConversation = identifier
                        self?.updateDefaultModelinfoFile()
                    }
                }
            }

            // When "Use Chat Model" is enabled, show the chat model
            // Otherwise, show the actual stored auxiliary model
            let devAuxId: String = if defaultAuxiliaryModelAlignWithChatModel.boolValue {
                ModelManager.ModelIdentifier.defaultModelForConversation
            } else {
                ModelManager.ModelIdentifier.storedAuxiliaryTaskModel
            }

            var handledAuxModel = false
            if #available(iOS 26.0, macCatalyst 26.0, *), devAuxId == AppleIntelligenceModel.shared.modelIdentifier {
                defaultAuxiliaryModel.configure(value: AppleIntelligenceModel.shared.modelDisplayName)
                // Add availability status as subtitle when Apple Intelligence is selected
                if !AppleIntelligenceModel.shared.isAvailable {
                    defaultAuxiliaryModel.configure(description: "Status: \(AppleIntelligenceModel.shared.availabilityStatus)")
                }
                handledAuxModel = true
            }
            if !handledAuxModel {
                if let localModel = ModelManager.shared.localModel(identifier: devAuxId) {
                    defaultAuxiliaryModel.configure(value: localModel.model_identifier)
                } else if let cloudModel = ModelManager.shared.cloudModel(identifier: devAuxId) {
                    defaultAuxiliaryModel.configure(value: cloudModel.modelFullName)
                } else {
                    defaultAuxiliaryModel.configure(value: String(localized: "Not Configured"))
                }
            }

            defaultAuxiliaryModel.use { [weak self] in
                guard let self else { return [] }
                if defaultAuxiliaryModelAlignWithChatModel.boolValue == true {
                    return []
                }
                return ModelManager.shared.buildModelSelectionMenu(
                    currentSelection: ModelManager.ModelIdentifier.storedAuxiliaryTaskModel,
                    allowSelectionWithNone: true
                ) { [weak self] identifier in
                    ModelManager.ModelIdentifier.defaultModelForAuxiliaryTask = identifier
                    self?.updateDefaultModelinfoFile()
                }
            }

            if defaultAuxiliaryModelAlignWithChatModel.boolValue {
                defaultAuxiliaryModel.alpha = 0.5
                defaultAuxiliaryModel.isUserInteractionEnabled = false
            } else {
                defaultAuxiliaryModel.alpha = 1.0
                defaultAuxiliaryModel.isUserInteractionEnabled = true
            }

            defaultAuxiliaryModelAlignWithChatModel.onUpdated = { [weak self] value in
                ModelManager.ModelIdentifier.defaultModelForAuxiliaryTaskWillUseCurrentChatModel = value
                self?.updateDefaultModelinfoFile()
            }

            let devAuxVisualId = ModelManager.ModelIdentifier.defaultModelForAuxiliaryVisualTask
            if let localModel = ModelManager.shared.localModel(identifier: devAuxVisualId) {
                defaultAuxiliaryVisualModel.configure(value: localModel.model_identifier)
            } else if let cloudModel = ModelManager.shared.cloudModel(identifier: devAuxVisualId) {
                defaultAuxiliaryVisualModel.configure(value: cloudModel.modelFullName)
            } else {
                defaultAuxiliaryVisualModel.configure(value: String(localized: "Not Configured"))
            }

            defaultAuxiliaryVisualModel.use { [weak self] in
                guard let self else { return [] }
                return ModelManager.shared.buildModelSelectionMenu(
                    currentSelection: ModelManager.ModelIdentifier.defaultModelForAuxiliaryVisualTask,
                    requiresCapabilities: [.visual],
                    allowSelectionWithNone: true
                ) { [weak self] identifier in
                    ModelManager.ModelIdentifier.defaultModelForAuxiliaryVisualTask = identifier
                    self?.updateDefaultModelinfoFile()
                }
            }
        }
    }
}

private class ConfigurableBooleanBlockView: ConfigurableBooleanView {
    var onUpdated: ((Bool) -> Void)?

    override func valueChanged() {
        super.valueChanged()
        onUpdated?(boolValue)
    }
}
