//
//  TestHelpers.swift
//  ChatClientKitTests
//
//  Created by Test Suite on 2025/11/10.
//

@testable import ChatClientKit
import CoreFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing

/// Helper functions for tests
enum TestHelpers {
    /// Gets API key from environment variable
    static func requireAPIKey(_ name: String = "OPENROUTER_API_KEY") -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".testing")
                .appendingPathComponent("openrouter.sk")
            let content = (try? String(contentsOf: url, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let content, !content.isEmpty else {
                Issue.record("Environment variable \(name) is not set. Please define it in your .zshrc before running tests.")
                return "sk-is-missing"
            }
            return content
        }
        return value
    }
    
    /// Creates a RemoteChatClient configured for OpenRouter with google/gemini-2.5-pro
    static func makeOpenRouterClient() -> RemoteChatClient {
        let apiKey = requireAPIKey()
        return RemoteChatClient(
            model: "google/gemini-2.5-pro",
            baseURL: "https://openrouter.ai/api",
            path: "/v1/chat/completions",
            apiKey: apiKey,
            additionalHeaders: [
                "HTTP-Referer": "https://github.com/FlowDown/ChatClientKit",
                "X-Title": "ChatClientKit Tests"
            ]
        )
    }
    
    /// Creates a simple test image as base64 data URL using Core Graphics
    static func createTestImageDataURL(width: Int = 100, height: Int = 100) -> URL {
        let size = CGSize(width: width, height: height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Failed to create CGContext")
        }
        
        // Draw a red rectangle
        context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        context.fill(CGRect(origin: .zero, size: size))
        
        guard let cgImage = context.makeImage() else {
            fatalError("Failed to create CGImage")
        }
        
        // Convert to PNG data
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.png" as CFString, 1, nil) else {
            fatalError("Failed to create image destination")
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Failed to finalize image destination")
        }
        
        let pngData = mutableData as Data
        let base64String = pngData.base64EncodedString()
        let dataURLString = "data:image/png;base64,\(base64String)"
        return URL(string: dataURLString)!
    }
    
    /// Creates a simple test audio as base64 data
    static func createTestAudioBase64(format: String = "wav") -> String {
        // Create a minimal WAV file header (44 bytes) + some silence
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(36).littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // channels
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16000).littleEndian) { Data($0) }) // sample rate
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(32000).littleEndian) { Data($0) }) // byte rate
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) }) // block align
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // bits per sample
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })
        
        return wavData.base64EncodedString()
    }
}

