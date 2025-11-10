//
//  RemoteChatClientAudioTests.swift
//  ChatClientKitTests
//
//  Created by Test Suite on 2025/11/10.
//

@testable import ChatClientKit
import Foundation
import Testing

@Suite("RemoteChatClient Audio Tests")
struct RemoteChatClientAudioTests {
    @Test("Non-streaming chat completion with audio input")
    func testNonStreamingChatCompletionWithAudio() async throws {
        let client = TestHelpers.makeOpenRouterClient()
        
        let audioBase64 = TestHelpers.createTestAudioBase64(format: "wav")
        
        let request = ChatRequestBody(messages: [
            .user(content: .parts([
                .text("What is in this audio?"),
                .audioBase64(audioBase64, format: "wav")
            ]))
        ])
        
        let response = try await client.chatCompletionRequest(body: request)
        
        #expect(response.choices.count > 0)
        let content = response.choices.first?.message.content ?? ""
        #expect(content.isEmpty == false)
    }
    
    @Test("Streaming chat completion with audio input")
    func testStreamingChatCompletionWithAudio() async throws {
        let client = TestHelpers.makeOpenRouterClient()
        
        let audioBase64 = TestHelpers.createTestAudioBase64(format: "wav")
        
        let request = ChatRequestBody(messages: [
            .user(content: .parts([
                .text("Transcribe this audio."),
                .audioBase64(audioBase64, format: "wav")
            ]))
        ])
        
        let stream = try await client.streamingChatCompletionRequest(body: request)
        
        var fullContent = ""
        for try await chunk in stream {
            if case let .chatCompletionChunk(completionChunk) = chunk {
                if let content = completionChunk.choices.first?.delta.content {
                    fullContent += content
                }
            }
        }
        
        #expect(fullContent.isEmpty == false)
    }
    
    @Test("Chat completion with audio and text")
    func testChatCompletionWithAudioAndText() async throws {
        let client = TestHelpers.makeOpenRouterClient()
        
        let audioBase64 = TestHelpers.createTestAudioBase64(format: "wav")
        
        let request = ChatRequestBody(messages: [
            .user(content: .parts([
                .text("What language is spoken in this audio?"),
                .audioBase64(audioBase64, format: "wav")
            ]))
        ])
        
        let response = try await client.chatCompletionRequest(body: request)
        
        #expect(response.choices.count > 0)
        let content = response.choices.first?.message.content ?? ""
        #expect(content.isEmpty == false)
    }
    
    @Test("Chat completion with audio in conversation")
    func testChatCompletionWithAudioInConversation() async throws {
        let client = TestHelpers.makeOpenRouterClient()
        
        let audioBase64 = TestHelpers.createTestAudioBase64(format: "wav")
        
        let request = ChatRequestBody(messages: [
            .user(content: .parts([
                .text("Listen to this audio."),
                .audioBase64(audioBase64, format: "wav")
            ])),
            .assistant(content: .text("I've processed the audio.")),
            .user(content: .text("What did you hear?"))
        ])
        
        let response = try await client.chatCompletionRequest(body: request)
        
        #expect(response.choices.count > 0)
        let content = response.choices.first?.message.content ?? ""
        #expect(content.isEmpty == false)
    }
    
    @Test("Streaming chat completion with audio and image")
    func testStreamingChatCompletionWithAudioAndImage() async throws {
        let client = TestHelpers.makeOpenRouterClient()
        
        let audioBase64 = TestHelpers.createTestAudioBase64(format: "wav")
        let imageURL = TestHelpers.createTestImageDataURL()
        
        let request = ChatRequestBody(messages: [
            .user(content: .parts([
                .text("I'm sending you both an audio and an image. Describe what you see and hear."),
                .audioBase64(audioBase64, format: "wav"),
                .imageURL(imageURL)
            ]))
        ])
        
        let stream = try await client.streamingChatCompletionRequest(body: request)
        
        var fullContent = ""
        for try await chunk in stream {
            if case let .chatCompletionChunk(completionChunk) = chunk {
                if let content = completionChunk.choices.first?.delta.content {
                    fullContent += content
                }
            }
        }
        
        #expect(fullContent.isEmpty == false)
    }
}

