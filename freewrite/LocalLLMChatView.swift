//
//  LocalLLMChatView.swift
//  freewrite
//
//  Created by Claude on 2/8/26.
//

import SwiftUI

struct LocalLLMChatView: View {
    @StateObject private var viewModel: LocalLLMChatViewModel
    @ObservedObject var llmManager: LocalLLMManager
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"
    let onDismiss: () -> Void

    @State private var isHoveringBack = false
    @State private var isHoveringClear = false
    @State private var isHoveringModel = false

    private var colorScheme: ColorScheme {
        colorSchemeString == "dark" ? .dark : .light
    }

    init(currentEntry: String, llmManager: LocalLLMManager, onDismiss: @escaping () -> Void) {
        self._llmManager = ObservedObject(wrappedValue: llmManager)
        self._viewModel = StateObject(wrappedValue: LocalLLMChatViewModel(
            llmManager: llmManager,
            initialContext: currentEntry
        ))
        self.onDismiss = onDismiss
    }

    var body: some View {
        let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
        let textHoverColor = colorScheme == .light ? Color.black : Color.white
        let backgroundColor = colorScheme == .light ? Color.white : Color.black
        let bodyTextColor = colorScheme == .light
            ? Color(red: 0.20, green: 0.20, blue: 0.20)
            : Color(red: 0.9, green: 0.9, blue: 0.9)
        let canShowInput = llmManager.loadingState == .ready && viewModel.hasCompletedInitialResponse
        let bottomNavReservedSpace: CGFloat = 112

        ZStack {
            backgroundColor.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.messages) { message in
                            JournalEntry(message: message, colorScheme: colorScheme)
                                .id(message.id)
                        }

                        if llmManager.loadingState == .loading {
                            Text("loading model...")
                                .font(.custom("Lato-Regular", size: 16))
                                .foregroundColor(.secondary)
                                .padding(.top, 24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("model-loading")
                        }

                        if viewModel.isGenerating && viewModel.currentStreamingResponse.isEmpty {
                            Text("thinking...")
                                .font(.custom("Lato-Regular", size: 16))
                                .foregroundColor(.secondary)
                                .padding(.top, 24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("thinking")
                        }

                        if viewModel.isGenerating && !viewModel.currentStreamingResponse.isEmpty {
                            JournalEntry(
                                message: ChatMessage(
                                    role: .assistant,
                                    content: viewModel.currentStreamingResponse,
                                    timestamp: Date()
                                ),
                                colorScheme: colorScheme
                            )
                            .id("streaming")
                        }

                        Group {
                            if canShowInput {
                                HStack {
                                    TextField("type your message...", text: $viewModel.currentInput)
                                        .textFieldStyle(.plain)
                                        .font(.custom("Lato-Regular", size: 18))
                                        .foregroundColor(bodyTextColor)
                                        .disabled(viewModel.isGenerating || llmManager.loadingState != .ready)
                                        .onSubmit {
                                            Task {
                                                await viewModel.sendMessage()
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.top, 30)
                        .padding(.bottom, 100)

                        Color.clear
                            .frame(height: bottomNavReservedSpace)
                            .id("bottom-anchor")
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 700)
                }
                .frame(maxWidth: .infinity)
                .scrollIndicators(.never)
                .onChange(of: viewModel.messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isGenerating) { isGenerating in
                    if isGenerating {
                        withAnimation {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.currentStreamingResponse) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
            }

            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 8) {
                        Button(action: onDismiss) {
                            Text("Back")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(isHoveringBack ? textHoverColor : textColor)
                        .onHover { hovering in
                            isHoveringBack = hovering
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }

                        Text("•")
                            .foregroundColor(.gray)

                        Button(action: {
                            viewModel.clearConversation()
                        }) {
                            Text("Clear")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(isHoveringClear ? textHoverColor : textColor)
                        .onHover { hovering in
                            isHoveringClear = hovering
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .padding(8)
                    .cornerRadius(6)

                    Spacer()

                    HStack(spacing: 8) {
                        if case .error = llmManager.loadingState {
                            Text("Error")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        } else {
                            Text("Local")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Text("•")
                            .foregroundColor(.gray)

                        Menu {
                            ForEach(llmManager.availableModels) { model in
                                Button(model.displayName) {
                                    llmManager.selectedModel = model
                                    Task {
                                        await llmManager.loadModelIfNeeded()
                                    }
                                }
                            }
                        } label: {
                            Text(llmManager.selectedModel?.displayName ?? "Select Model")
                                .font(.system(size: 13))
                                .foregroundColor(isHoveringModel ? textHoverColor : textColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(llmManager.loadingState == .loading || viewModel.isGenerating || llmManager.availableModels.isEmpty)
                        .onHover { hovering in
                            isHoveringModel = hovering
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .padding(8)
                    .cornerRadius(6)
                }
                .padding()
                .background(backgroundColor)
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .background(backgroundColor)
        .preferredColorScheme(colorScheme)
        .task {
            // Scan for available models first
            llmManager.scanForModels()

            // Load model when view appears
            await llmManager.loadModelIfNeeded()

            // After model loads, process initial entry if present
            if llmManager.loadingState == .ready {
                await viewModel.processInitialEntry()
            }
        }
    }
}

struct JournalEntry: View {
    let message: ChatMessage
    let colorScheme: ColorScheme

    private var messageFont: Font {
        if message.role == .user {
            return .custom("Lato-Regular", size: 18)
        }
        return .custom("Times New Roman", size: 18)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.content)
                .font(messageFont)
                .lineSpacing(10)
                .foregroundColor(colorScheme == .light ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
