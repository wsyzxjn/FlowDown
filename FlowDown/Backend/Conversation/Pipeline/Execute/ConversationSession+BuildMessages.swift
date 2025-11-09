//
//  ConversationSession+BuildMessages.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import Storage

extension ConversationSession {
    func buildInitialRequestMessages(
        _ requestMessages: inout [ChatRequestBody.Message],
        _ modelCapabilities: Set<ModelCapabilities>
    ) async {
        for message in messages {
            switch message.role {
            case .system:
                guard !message.document.isEmpty else { continue }
                requestMessages.append(.system(content: .text(message.document)))
            case .user:
                let attachments: [RichEditorView.Object.Attachment] = attachments(for: message.objectId).compactMap {
                    guard let type = RichEditorView.Object.Attachment.AttachmentType(rawValue: $0.type) else {
                        return nil
                    }
                    return .init(
                        type: type,
                        name: $0.name,
                        previewImage: $0.previewImageData,
                        imageRepresentation: $0.imageRepresentation,
                        textRepresentation: $0.representedDocument,
                        storageSuffix: $0.storageSuffix
                    )
                }
                let attachmentMessages = await makeMessageFromAttachments(
                    attachments,
                    modelCapabilities: modelCapabilities
                )
                if !attachmentMessages.isEmpty {
                    // Add the content of the previous attachments to the conversation context.
                    requestMessages.append(contentsOf: attachmentMessages)
                }
                if !message.document.isEmpty {
                    requestMessages.append(.user(content: .text(message.document)))
                } else {
                    assertionFailure()
                }
            case .assistant:
                guard !message.document.isEmpty else { continue }
                requestMessages.append(.assistant(content: .text(message.document)))
            case .webSearch:
                let result = message.webSearchStatus.searchResults
                var index = 0
                let content = result.compactMap {
                    index += 1
                    return """
                    <index>\(index)</index>
                    <title>\($0.title)</title>
                    <url>\($0.url.absoluteString)</url>
                    <content>\($0.toolResult)</content>
                    """
                }
                requestMessages.append(.tool(
                    content: .text(content.joined(separator: "\n")),
                    toolCallID: message.id
                ))
            case .toolHint:
                let content = message.toolStatus.message
                requestMessages.append(.tool(
                    content: .text(content),
                    toolCallID: message.id
                ))
            default:
                continue
            }
        }
    }

    func makeMessageFromAttachments(
        _ attachments: [RichEditorView.Object.Attachment],
        modelCapabilities: Set<ModelCapabilities>
    ) async -> [ChatRequestBody.Message] {
        let supportsVision = modelCapabilities.contains(.visual)
        let supportsAudio = modelCapabilities.contains(.auditory)
        var result: [ChatRequestBody.Message] = []
        for attach in attachments {
            if let message = await processAttachments(
                attach,
                supportsVision: supportsVision,
                supportsAudio: supportsAudio
            ) {
                result.append(message)
            }
        }
        return result
    }

    private func processAttachments(
        _ attachment: RichEditorView.Object.Attachment,
        supportsVision: Bool,
        supportsAudio: Bool
    ) async -> ChatRequestBody.Message? {
        switch attachment.type {
        case .text:
            return .user(content: .text(["[\(attachment.name)]", attachment.textRepresentation].joined(separator: "\n")))
        case .image:
            if supportsVision {
                guard let image = UIImage(data: attachment.imageRepresentation),
                      let base64 = image.pngBase64String(),
                      let url = URL(string: "data:image/png;base64,\(base64)")
                else {
                    assertionFailure()
                    return nil
                }
                if !attachment.textRepresentation.isEmpty {
                    return .user(
                        content: .parts([
                            .imageURL(url),
                            .text(attachment.textRepresentation),
                        ])
                    )
                } else {
                    return .user(content: .parts([.imageURL(url)]))
                }
            } else {
                guard !attachment.textRepresentation.isEmpty else {
                    logger.info("[-] image attachment ignored because not processed")
                    return nil
                }
                return .user(content: .text(["[\(attachment.name)]", attachment.textRepresentation].joined(separator: "\n")))
            }
        case .audio:
            if supportsAudio {
                let data = attachment.imageRepresentation
                // treat this data as m4a, process to transcoding what's so ever
                do {
                    let content = try await AudioTranscoder.transcode(data: data, fileExtension: "m4a", output: .compressedQualityWAV)
                    let base64 = content.data.base64EncodedString()
                    var parts: [ChatRequestBody.Message.ContentPart] = [
                        .audioBase64(base64, format: "wav"),
                    ]
                    let description = attachment.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !description.isEmpty {
                        parts.append(.text(["[\(attachment.name)]", description].joined(separator: "\n")))
                    } else {
                        parts.append(.text("[\(attachment.name)]"))
                    }
                    return .user(content: .parts(parts))
                } catch {
                    logger.error("[-] audio attachment transcoding failed: \(error.localizedDescription)")
                    return .user(content: .text("Audio attachment \"\(attachment.name)\" was skipped because transcoding failed."))
                }
            } else {
                let description = attachment.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines)
                if description.isEmpty {
                    let fallback = String(localized: "Audio attachment \"\(attachment.name)\" was skipped because the active model does not support audio input.")
                    return .user(content: .text(fallback))
                } else {
                    return .user(content: .text(["[\(attachment.name)]", description].joined(separator: "\n")))
                }
            }
        }
    }
}
