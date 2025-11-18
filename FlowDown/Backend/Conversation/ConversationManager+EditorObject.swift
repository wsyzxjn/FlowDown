//
//  ConversationManager+EditorObject.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import AlertController
import Combine
import ConfigurableKit
import Foundation
import Storage

extension ConversationManager {
    func getRichEditorObject(identifier: Conversation.ID) -> RichEditorView.Object? {
        temporaryEditorObjects[identifier]
    }

    func setRichEditorObject(identifier: Conversation.ID, _ object: RichEditorView.Object?) {
        if let object {
            temporaryEditorObjects[identifier] = object
        } else {
            temporaryEditorObjects.removeValue(forKey: identifier)
        }
    }

    func clearRichEditorObject() {
        temporaryEditorObjects.removeAll()
    }
}

extension ConversationManager {
    static let removeAllEditorObjectsPublisher: PassthroughSubject<Void, Never> = .init()
    static let removeAllEditorObjects: ConfigurableObject = .init(
        icon: "eraser",
        title: "Clear Editing",
        explain: "This will delete all edits, including unsent conversation text and attachments.",
        ephemeralAnnotation: .action { controller in
            let alert = AlertViewController(
                title: "Clear Editing",
                message: "This will delete all edits, including unsent conversation text and attachments."
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "Cancel") {
                    context.dispose()
                }
                context.addAction(title: "Clear", attribute: .accent) {
                    context.dispose {
                        ConversationManager.shared.clearRichEditorObject()
                        removeAllEditorObjectsPublisher.send(())
                        Indicator.present(
                            title: "Done",
                            preset: .done,
                            referencingView: controller.view
                        )
                    }
                }
            }
            controller.present(alert, animated: true)
        }
    )
}
