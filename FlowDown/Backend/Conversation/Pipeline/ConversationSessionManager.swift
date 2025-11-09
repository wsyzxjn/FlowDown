//
//  ConversationSessionManager.swift
//  FlowDown
//
//  Created by ktiays on 2025/2/12.
//

import ChatClientKit
import Combine
import Foundation
import Storage

final class ConversationSessionManager {
    typealias Session = ConversationSession

    // MARK: - Singleton

    static let shared = ConversationSessionManager()

    // MARK: - State

    private var sessions: [Conversation.ID: Session] = [:]
    private var messageChangedObserver: Any?
    private var pendingRefresh: Set<Conversation.ID> = []
    private let logger = Logger(subsystem: "wiki.qaq.flowdown", category: "ConversationSessionManager")

    private var executingSessions: Set<Conversation.ID> = []
    let executingSessionsPublisher = PassthroughSubject<Set<Conversation.ID>, Never>()

    // MARK: - Lifecycle

    private init() {
        messageChangedObserver = NotificationCenter.default.addObserver(
            forName: SyncEngine.MessageChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            handleMessageChanged(notification)
        }
    }

    deinit {
        if let messageChangedObserver {
            NotificationCenter.default.removeObserver(messageChangedObserver)
        }
    }

    // MARK: - Public APIs

    func session(for conversationID: Conversation.ID) -> Session {
        if let cached = sessions[conversationID] { return cached }
        #if DEBUG
            ConversationSession.allowedInit = conversationID
        #endif
        let newSession = Session(id: conversationID)
        sessions[conversationID] = newSession
        return newSession
    }

    func invalidateSession(for conversationID: Conversation.ID) {
        sessions.removeValue(forKey: conversationID)
        pendingRefresh.remove(conversationID)
        markSessionCompleted(conversationID)
    }

    // MARK: - Message Change Handling

    private func handleMessageChanged(_ notification: Notification) {
        // Only update message lists; do not touch conversation sidebar (no scanAll here).
        guard let info = notification.userInfo?[SyncEngine.MessageNotificationKey] as? MessageNotificationInfo else {
            logger.infoFile("MessageChanged without detail; refreshing all cached sessions")
            for (_, session) in sessions {
                refreshSafely(session)
            }
            return
        }

        var affected = Set<Conversation.ID>()
        for (cid, _) in info.modifications {
            affected.insert(cid)
        }
        for (cid, _) in info.deletions {
            affected.insert(cid)
        }
        guard !affected.isEmpty else { return }

        for cid in affected {
            guard let session = sessions[cid] else { continue }
            refreshSafely(session)
        }
    }

    private func refreshSafely(_ session: Session) {
        // Avoid refreshing while a streaming task is active to prevent UI errors.
        if let task = session.currentTask, !task.isCancelled {
            logger.debugFile("Defer refresh for session \(String(describing: session.id)) due to active task")
            if !pendingRefresh.contains(session.id) {
                pendingRefresh.insert(session.id)
            }
            return
        }
        // No active task or task is cancelled, safe to refresh immediately
        session.refreshContentsFromDatabase()
    }

    func resolvePendingRefresh(for sessionID: Conversation.ID) {
        guard pendingRefresh.contains(sessionID) else { return }
        guard let session = sessions[sessionID] else {
            pendingRefresh.remove(sessionID)
            return
        }
        // Task completed, now safe to refresh
        logger.infoFile("Executing pending refresh for session \(String(describing: sessionID))")
        session.refreshContentsFromDatabase()
        pendingRefresh.remove(sessionID)
    }

    // MARK: - Execution State Management

    func markSessionExecuting(_ sessionID: Conversation.ID) {
        executingSessions.insert(sessionID)
        executingSessionsPublisher.send(executingSessions)
    }

    func markSessionCompleted(_ sessionID: Conversation.ID) {
        executingSessions.remove(sessionID)
        executingSessionsPublisher.send(executingSessions)
    }

    func isSessionExecuting(_ sessionID: Conversation.ID) -> Bool {
        executingSessions.contains(sessionID)
    }
}
