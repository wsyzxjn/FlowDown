//
//  MainController+Boot.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/3/25.
//

import AlertController
import Combine
import Foundation
import UIKit

extension MainController {
    func queueBootMessage(text: String) {
        bootAlertMessageQueue.append(text)
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(presentNextBootMessage),
            object: nil
        )
        perform(#selector(presentNextBootMessage), with: nil, afterDelay: 0.5)
    }

    @objc func presentNextBootMessage() {
        let text = bootAlertMessageQueue.joined(separator: "\n")
        bootAlertMessageQueue.removeAll()

        let alert = AlertViewController(
            title: "External Resources",
            message: "\(text)"
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose {}
            }
        }
        var viewController: UIViewController = self
        while let child = viewController.presentedViewController {
            viewController = child
        }
        viewController.present(alert, animated: true)
    }

    func queueNewConversation(text: String, shouldSend: Bool = false) {
        Task { @MainActor in
            let conversation = ConversationManager.shared.createNewConversation(autoSelect: true)
            Logger.app.infoFile("created new conversation ID: \(conversation.id)")
            guard shouldSend else { return }
            try await Task.sleep(nanoseconds: 500_000_000)
            if self.chatView.conversationIdentifier == conversation.id {
                self.sendMessageToCurrentConversation(text)
            }
        }
    }
}
