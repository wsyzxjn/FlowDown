//
//  ConversationManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import Combine
import ConfigurableKit
import Foundation
import OrderedCollections
import Storage
import UIKit

class ConversationManager: NSObject {
    static let shared = ConversationManager()

    @BareCodableStorage(key: "wiki.qaq.conversation.editor.objects", defaultValue: [:])
    private var _temporaryEditorObjects: [Conversation.ID: RichEditorView.Object] {
        didSet { assert(!Thread.isMainThread) }
    }

    var temporaryEditorObjects: [Conversation.ID: RichEditorView.Object] = [:] {
        didSet {
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(saveObjects),
                object: nil
            )
            perform(#selector(saveObjects), with: nil, afterDelay: 1.0)
        }
    }

    let conversations: CurrentValueSubject<OrderedDictionary<Conversation.ID, Conversation>, Never> = .init([:])

    private var cancellables = Set<AnyCancellable>()

    override private init() {
        super.init()
        temporaryEditorObjects = _temporaryEditorObjects
        Logger.app.infoFile("\(temporaryEditorObjects.count) temporary editor objects loaded.")
        scanAll()

        NotificationCenter.default.publisher(for: SyncEngine.ConversationChanged)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.ConversationChanged")
                self?.scanAll()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SyncEngine.LocalDataDeleted)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.LocalDataDeleted")
                self?.scanAll()
            }
            .store(in: &cancellables)
    }

    @objc private func saveObjects() {
        Task.detached { [weak self] in
            guard let self else { return }
            _temporaryEditorObjects = temporaryEditorObjects
            Logger.app.infoFile("\(temporaryEditorObjects.count) temporary editor objects saved.")
        }
    }
}

extension Conversation {
    var interfaceImage: UIImage {
        if let image = UIImage(data: icon) {
            return image
        }
        return "💬"
            .textToImage(size: 64)
            ?? .init(systemName: "quote.bubble")
            ?? .starShine
    }
}
