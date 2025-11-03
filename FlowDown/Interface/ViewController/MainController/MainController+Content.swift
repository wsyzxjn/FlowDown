//
//  MainController+Content.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/20/25.
//

import Combine
import Foundation
import Storage
import UIKit

extension MainController {
    func setupViews() {
        textureBackground.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        sidebarLayoutView.clipsToBounds = true
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous

        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .background
        contentShadowView.layer.cornerRadius = contentView.layer.cornerRadius
        contentShadowView.layer.cornerCurve = contentView.layer.cornerCurve

        contentShadowView.snp.makeConstraints { make in
            make.edges.equalTo(contentView)
        }

        sidebarDragger.snp.makeConstraints { make in
            make.right.equalTo(contentView.snp.left)
            make.top.bottom.equalToSuperview()
            make.width.equalTo(10)
        }

        contentView.hideKeyboardWhenTappedAround()

        chatView.onCreateNewChat = { [weak self] in
            self?.requestNewChat()
        }
        chatView.onSuggestNewChat = { [weak self] id in
            guard let self else { return }
            load(id)
        }
        chatView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        setupChatSelectionSubscription()

        sidebar.newChatButton.delegate = self
        sidebar.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        sidebar.conversationSelectionView.tableView.gestureRecognizers?.forEach {
            guard $0 is UIPanGestureRecognizer else { return }
            $0.cancelsTouchesInView = false
        }

        #if !targetEnvironment(macCatalyst)
            chatView.escapeButton.actionBlock = { [weak self] in
                self?.view.doWithAnimation {
                    self?.isSidebarCollapsed.toggle()
                }
            }
        #endif
    }

    private func setupChatSelectionSubscription() {
        ChatSelection.shared.selection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationId in
                Logger.ui.debugFile("MainController received chat selection update: \(conversationId ?? "nil")")
                self?.load(conversationId)
            }
            .store(in: &cancellables)
    }

    func load(_ conv: Conversation.ID?) {
        Logger.ui.debugFile("load called with conversation: \(conv ?? "-1")")
        chatView.prepareForReuse()
        guard let identifier = conv else { return }

        chatView.use(conversation: identifier)
        if !isSidebarCollapsed, // 已经展开的状态下
           !allowSidebarPersistence // sidebar 和 chatview 水火不容
        {
            // 关上
            view.doWithAnimation { self.isSidebarCollapsed = true }
        }

        let session = ConversationSessionManager.shared.session(for: identifier)
        session.updateModels()
    }
}
