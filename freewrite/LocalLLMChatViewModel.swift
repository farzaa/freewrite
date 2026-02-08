//
//  LocalLLMChatViewModel.swift
//  freewrite
//
//  Created by Claude on 2/8/26.
//

import Foundation
import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
    }
}

@MainActor
class LocalLLMChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isGenerating: Bool = false
    @Published var currentStreamingResponse: String = ""
    @Published var hasCompletedInitialResponse: Bool = false

    private let llmManager: LocalLLMManager
    private let initialContext: String?

    // AI chat prompt matching ContentView
    private let aiChatPrompt = """
    below is my journal entry. wyt? talk through it with me like a friend. don't therpaize me and give me a whole breakdown, don't repeat my thoughts with headings. really take all of this, and tell me back stuff truly as if you're an old homie.

    Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot.

    do not just go through every single thing i say, and say it back to me. you need to proccess everythikng is say, make connections i don't see it, and deliver it all back to me as a story that makes me feel what you think i wanna feel. thats what the best therapists do.

    ideally, you're style/tone should sound like the user themselves. it's as if the user is hearing their own tone but it should still feel different, because you have different things to say and don't just repeat back they say.

    Reply in plain text only. Never use markdown, headings, bullet points, numbered lists, or code fences.

    else, start by saying, "hey, thanks for showing me this. my thoughts:"

    my entry:
    """

    init(llmManager: LocalLLMManager, initialContext: String? = nil) {
        self.llmManager = llmManager
        self.initialContext = initialContext
    }

    private func sanitizeMarkdown(_ text: String) -> String {
        var sanitized = text

        // Strip fenced code blocks while keeping content.
        sanitized = sanitized.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )

        // Remove common markdown markers at line starts.
        sanitized = sanitized.replacingOccurrences(
            of: "(?m)^\\s{0,3}#{1,6}\\s*",
            with: "",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "(?m)^\\s*[-*+]\\s+",
            with: "",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "(?m)^\\s*\\d+\\.\\s+",
            with: "",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "(?m)^\\s*>\\s?",
            with: "",
            options: .regularExpression
        )

        // Remove inline markdown markers.
        sanitized = sanitized.replacingOccurrences(
            of: "\\*\\*(.*?)\\*\\*",
            with: "$1",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "\\*(.*?)\\*",
            with: "$1",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "`([^`]*)`",
            with: "$1",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "\\[(.*?)\\]\\((.*?)\\)",
            with: "$1 ($2)",
            options: .regularExpression
        )

        return sanitized
    }

    func processInitialEntry() async {
        hasCompletedInitialResponse = false
        let trimmed = initialContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // If empty, just ask how to help
        if trimmed.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: "How can I help you?",
                timestamp: Date()
            ))
            hasCompletedInitialResponse = true
            return
        }

        // Non-empty entry: send in background with prompt, don't show it
        let fullPrompt = aiChatPrompt + "\n\n" + trimmed

        // Automatically get response using full prompt (but don't show the user message)
        isGenerating = true
        currentStreamingResponse = ""
        var rawStreamingResponse = ""

        do {
            // Stream response with full prompt
            for try await chunk in llmManager.streamResponse(to: fullPrompt) {
                rawStreamingResponse += chunk
                currentStreamingResponse = sanitizeMarkdown(rawStreamingResponse)
            }

            // Add complete assistant response
            messages.append(ChatMessage(
                role: .assistant,
                content: sanitizeMarkdown(rawStreamingResponse),
                timestamp: Date()
            ))

            currentStreamingResponse = ""
            isGenerating = false
            hasCompletedInitialResponse = true

        } catch {
            print("Error generating response: \(error)")
            messages.append(ChatMessage(
                role: .assistant,
                content: "Error: \(error.localizedDescription)",
                timestamp: Date()
            ))
            currentStreamingResponse = ""
            isGenerating = false
            hasCompletedInitialResponse = true
        }
    }

    func sendMessage() async {
        let input = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        // Add user message
        messages.append(ChatMessage(
            role: .user,
            content: input,
            timestamp: Date()
        ))

        // Clear input
        currentInput = ""
        isGenerating = true
        currentStreamingResponse = ""
        var rawStreamingResponse = ""

        do {
            // Stream response
            let plainTextInstruction = "Reply in plain text only. Never use markdown, headings, bullet points, numbered lists, or code fences.\n\n"
            for try await chunk in llmManager.streamResponse(to: plainTextInstruction + input) {
                rawStreamingResponse += chunk
                currentStreamingResponse = sanitizeMarkdown(rawStreamingResponse)
            }

            // Add complete assistant response
            messages.append(ChatMessage(
                role: .assistant,
                content: sanitizeMarkdown(rawStreamingResponse),
                timestamp: Date()
            ))

            currentStreamingResponse = ""
            isGenerating = false

        } catch {
            print("Error generating response: \(error)")
            messages.append(ChatMessage(
                role: .assistant,
                content: "Error: \(error.localizedDescription)",
                timestamp: Date()
            ))
            currentStreamingResponse = ""
            isGenerating = false
        }
    }

    func clearConversation() {
        messages.removeAll()
        currentStreamingResponse = ""
        llmManager.resetConversation()
    }
}
