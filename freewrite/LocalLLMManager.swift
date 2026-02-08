//
//  LocalLLMManager.swift
//  freewrite
//
//  Created by Claude on 2/8/26.
//

import Foundation
import MLXLMCommon
import MLXLLM

@MainActor
class LocalLLMManager: ObservableObject {
    static let shared = LocalLLMManager()

    enum LoadingState: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published var loadingState: LoadingState = .idle
    @Published var loadingProgress: Double = 0.0

    struct AvailableModel: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String

        var displayName: String {
            // Try to extract model size and make it readable
            if name.contains("3B") {
                return name.replacingOccurrences(of: "-Instruct-4bit", with: "") + " (Fast)"
            } else if name.contains("8B") || name.contains("7B") {
                return name.replacingOccurrences(of: "-Instruct-4bit", with: "") + " (Better)"
            } else {
                return name.replacingOccurrences(of: "-Instruct-4bit", with: "")
            }
        }
    }

    private let modelsDirectory = "/Users/thorfinn/Library/Application Support/Freewrite/models"

    @Published var availableModels: [AvailableModel] = []
    @Published var selectedModel: AvailableModel?

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    private var currentLoadedModelPath: String?

    private init() {}

    func scanForModels() {
        availableModels.removeAll()

        let fileManager = FileManager.default
        let modelsURL = URL(fileURLWithPath: modelsDirectory)

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: modelsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for modelURL in contents {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }

                // Check if it has required model files
                let configPath = modelURL.appendingPathComponent("config.json").path
                let modelPath = modelURL.appendingPathComponent("model.safetensors").path

                if fileManager.fileExists(atPath: configPath) &&
                   fileManager.fileExists(atPath: modelPath) {
                    let modelName = modelURL.lastPathComponent
                    let model = AvailableModel(
                        id: modelName,
                        name: modelName,
                        path: modelURL.path
                    )
                    availableModels.append(model)
                }
            }

            // Sort by name (reverse so 8B comes before 3B)
            availableModels.sort { $0.name > $1.name }

            // Select first model if none selected (will be 8B due to reverse sort)
            if selectedModel == nil && !availableModels.isEmpty {
                selectedModel = availableModels[0]
            }

            print("Found \(availableModels.count) models: \(availableModels.map { $0.name }.joined(separator: ", "))")

        } catch {
            print("Error scanning for models: \(error)")
        }
    }

    func loadModelIfNeeded() async {
        // Check if we need to reload because model changed
        if let selectedPath = selectedModel?.path,
           currentLoadedModelPath != selectedPath && loadingState == .ready {
            unloadModel()
        }

        // Don't reload if already ready with the same model
        guard loadingState != .ready else { return }

        // Don't reload if currently loading
        guard loadingState != .loading else { return }

        guard let selectedModel = selectedModel else {
            loadingState = .error("No model selected")
            return
        }

        loadingState = .loading
        loadingProgress = 0.0
        let modelPath = selectedModel.path

        do {
            print("Loading model: \(selectedModel.displayName) from: \(modelPath)")

            // Create URL for local model path
            let modelURL = URL(fileURLWithPath: modelPath)

            // Create model configuration using the local directory URL
            let modelConfiguration = ModelConfiguration(
                directory: modelURL
            )

            // Load the model container with progress tracking
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: modelConfiguration
            ) { progress in
                Task { @MainActor in
                    self.loadingProgress = progress.fractionCompleted
                    print("Loading progress: \(Int(progress.fractionCompleted * 100))%")
                }
            }

            self.modelContainer = container

            // Create chat session - pass the container directly
            self.chatSession = ChatSession(container)

            currentLoadedModelPath = modelPath
            loadingState = .ready
            print("Model loaded successfully: \(selectedModel.displayName)")

        } catch {
            let errorMessage = "Failed to load model: \(error.localizedDescription)"
            print(errorMessage)
            loadingState = .error(errorMessage)
        }
    }

    func generateResponse(to prompt: String) async throws -> String {
        guard loadingState == .ready,
              let session = chatSession else {
            throw NSError(domain: "LocalLLM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not ready"])
        }

        let response = try await session.respond(to: prompt)
        return response
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error> {
        guard loadingState == .ready,
              let session = chatSession else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "LocalLLM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not ready"]))
            }
        }

        return session.streamResponse(to: prompt)
    }

    func resetConversation() {
        // Create a new chat session to clear history
        if let container = modelContainer {
            chatSession = ChatSession(container)
        }
    }

    func unloadModel() {
        chatSession = nil
        modelContainer = nil
        currentLoadedModelPath = nil
        loadingState = .idle
        loadingProgress = 0.0
    }
}
