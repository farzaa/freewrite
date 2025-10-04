import SwiftUI
import AppKit

struct ChatView: View {
    @Binding var showingChatView: Bool
    @State private var userMessage: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isWaitingForResponse = false
    @State private var fontSize: CGFloat = 16
    @State private var selectedFont: String = "Lato-Regular"
    @State private var isHoveringClose = false
    @State private var systemPrompt: String = ""
    @State private var totalTokens: Int = 0
    @State private var estimatedCost: Double = 0.0

    struct ChatMessage: Identifiable {
        let id = UUID()
        let text: String
        let isUser: Bool
    }

    private let apiKey = ""
    private let fileManager = FileManager.default

    var lineHeight: CGFloat {
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (fontSize * 1.5) - defaultLineHeight
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Chat messages area
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message.isUser ? "You" : "AI")
                                    .font(.custom(selectedFont, size: 12))
                                    .foregroundColor(.gray)
                                    .fontWeight(.semibold)

                                Text(message.text)
                                    .font(.custom(selectedFont, size: fontSize))
                                    .foregroundColor(.white)
                                    .lineSpacing(lineHeight)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: 650, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 20)
                        }

                        // Loading indicator
                        if isWaitingForResponse {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AI")
                                    .font(.custom(selectedFont, size: 12))
                                    .foregroundColor(.gray)
                                    .fontWeight(.semibold)

                                Text("Thinking...")
                                    .font(.custom(selectedFont, size: fontSize))
                                    .foregroundColor(.gray)
                                    .lineSpacing(lineHeight)
                            }
                            .frame(maxWidth: 650, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.never)

                // Input area
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        if userMessage.isEmpty {
                            Text("Message AI...")
                                .font(.custom(selectedFont, size: fontSize))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }

                        TextField("", text: $userMessage, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.custom(selectedFont, size: fontSize))
                            .foregroundColor(.white)
                            .lineLimit(1...6)
                            .padding(12)
                            .onSubmit {
                                sendMessage()
                            }
                            .disabled(isWaitingForResponse)
                    }
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                }
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            // Close button and token count (top right)
            VStack {
                HStack {
                    Spacer()

                    // Token count display
                    if totalTokens > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(totalTokens) tokens")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text("$\(String(format: "%.4f", estimatedCost))")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .padding(.trailing, 8)
                    }

                    Button("Close") {
                        showingChatView = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(isHoveringClose ? .white : .gray.opacity(0.8))
                    .onHover { hovering in
                        isHoveringClose = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sendMessage() {
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, !isWaitingForResponse else { return }

        // Add user message to chat
        messages.append(ChatMessage(text: trimmedMessage, isUser: true))
        userMessage = ""

        // Build system prompt on first message
        if systemPrompt.isEmpty {
            systemPrompt = buildSystemPrompt()
        }

        // Call Claude API
        Task {
            await getClaudeResponse()
        }
    }

    private func buildSystemPrompt() -> String {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freewrite")

        // Get today's date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let todayString = dateFormatter.string(from: Date())

        var prompt = "You are a thoughtful assistant that helps the user think deeper about their thoughts and feelings. Ask probing questions, make connections they might not see, challenge their assumptions gently, and help them explore their ideas more fully. Be casual and conversational, like a wise friend.\n\nToday the date is \(todayString) for the user.\n\n"

        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            let mdFiles = fileURLs.filter { $0.pathExtension == "md" }

            // Parse entries with dates
            var entries: [(date: Date, text: String)] = []

            for fileURL in mdFiles {
                let filename = fileURL.lastPathComponent

                // Extract date from filename - pattern [uuid]-[yyyy-MM-dd-HH-mm-ss].md
                if let dateMatch = filename.range(of: "\\[(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\]", options: .regularExpression) {
                    let dateString = String(filename[dateMatch].dropFirst().dropLast())
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"

                    if let date = dateFormatter.date(from: dateString),
                       let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanedContent.isEmpty {
                            entries.append((date: date, text: cleanedContent))
                        }
                    }
                }
            }

            // Sort by most recent first
            entries.sort { $0.date > $1.date }

            // Build prompt with entries
            if !entries.isEmpty {
                prompt += "Below are all the user's past journal entries along with dates and times:\n\n"

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMMM d, yyyy"
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"

                for entry in entries {
                    let dateStr = dateFormatter.string(from: entry.date)
                    let timeStr = timeFormatter.string(from: entry.date)
                    prompt += "*\(dateStr) at \(timeStr)*\n\(entry.text)\n\n"
                }
            }

        } catch {
            print("Error loading journal entries: \(error)")
        }

        return prompt
    }

    private func getClaudeResponse() async {
        isWaitingForResponse = true

        // Build messages array for API
        var apiMessages: [[String: String]] = []
        for message in messages {
            apiMessages.append([
                "role": message.isUser ? "user" : "assistant",
                "content": message.text
            ])
        }

        // Create request
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            isWaitingForResponse = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": apiMessages
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? String {

                await MainActor.run {
                    messages.append(ChatMessage(text: text, isUser: false))
                    isWaitingForResponse = false
                }

                // Count tokens after response
                await countTokens()
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(text: "Sorry, I couldn't process that response.", isUser: false))
                    isWaitingForResponse = false
                }
            }
        } catch {
            await MainActor.run {
                messages.append(ChatMessage(text: "Error: \(error.localizedDescription)", isUser: false))
                isWaitingForResponse = false
            }
        }
    }

    private func countTokens() async {
        // Build messages array for token counting
        var apiMessages: [[String: String]] = []
        for message in messages {
            apiMessages.append([
                "role": message.isUser ? "user" : "assistant",
                "content": message.text
            ])
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages/count_tokens") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-5",
            "system": systemPrompt,
            "messages": apiMessages
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let inputTokens = json["input_tokens"] as? Int {

                // Calculate cost (Claude Sonnet 4.5 pricing)
                // $3 per million tokens for both input and output
                // For simplicity, assuming output is ~30% of input
                let estimatedOutputTokens = Int(Double(inputTokens) * 0.3)
                let totalTokenCount = inputTokens + estimatedOutputTokens
                let cost = Double(totalTokenCount) / 1_000_000 * 3.0

                await MainActor.run {
                    totalTokens = totalTokenCount
                    estimatedCost = cost
                    print("📊 Total tokens: \(totalTokenCount)")
                    print("💰 Estimated cost: $\(String(format: "%.4f", cost))")
                }
            }
        } catch {
            print("Error counting tokens: \(error)")
        }
    }
}
