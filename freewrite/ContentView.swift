// Swift 5.0
//
//  ContentView.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PDFKit
import NaturalLanguage

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String
    let filename: String
    var previewText: String
    var summary: String?
    var summaryGenerated: Date?
    
    static func createNew() -> HumanEntry {
        let id = UUID()
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: now)
        
        // For display
        dateFormatter.dateFormat = "MMM d"
        let displayDate = dateFormatter.string(from: now)
        
        return HumanEntry(
            id: id,
            date: displayDate,
            filename: "[\(id)]-[\(dateString)].md",
            previewText: "",
            summary: nil,
            summaryGenerated: nil
        )
    }
}

class SummaryService: ObservableObject {
    func generateSummary(for text: String) -> String {
        let cleanText = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanText.isEmpty {
            return "Empty entry"
        }
        
        if cleanText.count < 50 {
            return cleanText
        }
        
        // Extract first few meaningful sentences for summary
        let sentences = cleanText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 3 }
        
        if sentences.isEmpty {
            return String(cleanText.prefix(100)) + "..."
        }
        
        // Take first 1-2 sentences up to 150 characters
        var summary = ""
        for sentence in sentences.prefix(2) {
            if summary.count + sentence.count < 150 {
                summary += sentence + ". "
            } else {
                break
            }
        }
        
        return summary.isEmpty ? String(cleanText.prefix(100)) + "..." : summary.trimmingCharacters(in: .whitespaces)
    }
}

// Timeline Prediction Data Models
struct TimelinePoint: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let happiness: Double
    let description: String
    let scenario: TimelineScenario
    
    enum TimelineScenario: String, Codable {
        case actual = "actual"
        case best = "best"
        case darkest = "darkest"
    }
}

struct TimelinePrediction: Codable {
    let bestTimeline: [TimelinePoint]
    let darkestTimeline: [TimelinePoint]
    let analysisDate: Date
    let monthsAhead: Int
}

// Claude API Service
class ClaudeAPIService: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var isTestingConnection = false
    @Published var connectionTestResult: String?
    
    private let baseURL = "https://api.anthropic.com/v1/messages"
    
    func generateTimelinePrediction(entries: [HumanEntry], apiToken: String, monthsAhead: Int) async throws -> TimelinePrediction {
        guard !apiToken.isEmpty else {
            throw APIError.missingToken
        }
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            // Prepare entries data for analysis
            let entriesData = try await prepareEntriesData(entries: entries)
            
            // Validate we have enough data
            guard !entriesData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError.networkError("No journal entries found to analyze")
            }
            
            // Create the prompt for Claude
            let prompt = createTimelinePredictionPrompt(entriesData: entriesData, monthsAhead: monthsAhead)
            
            // Make API call to Claude
            let response = try await makeClaudeAPICall(prompt: prompt, apiToken: apiToken)
            
            // Parse the response into timeline prediction
            let prediction = try parseTimelinePrediction(response: response, monthsAhead: monthsAhead)
            
            await MainActor.run {
                isLoading = false
            }
            
            return prediction
            
        } catch let urlError as URLError {
            let networkError = APIError.networkError(urlError.localizedDescription)
            await MainActor.run {
                isLoading = false
                self.error = networkError.localizedDescription
            }
            throw networkError
        } catch let apiError as APIError {
            await MainActor.run {
                isLoading = false
                self.error = apiError.localizedDescription
            }
            throw apiError
        } catch {
            let genericError = APIError.networkError(error.localizedDescription)
            await MainActor.run {
                isLoading = false
                self.error = genericError.localizedDescription
            }
            throw genericError
        }
    }
    
    private func prepareEntriesData(entries: [HumanEntry]) async throws -> String {
        var entriesText = ""
        
        for entry in entries.prefix(20) { // Limit to recent 20 entries
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Freewrite")
            let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
            
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                entriesText += "Date: \(entry.date)\n"
                entriesText += "Entry: \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            } catch {
                continue
            }
        }
        
        return entriesText
    }
    
    private func createTimelinePredictionPrompt(entriesData: String, monthsAhead: Int) -> String {
        return """
        You are a skilled life coach and pattern analyst. Based on the following journal entries, I need you to create two timeline predictions for the next \(monthsAhead) months:

        1. **Best Timeline**: What would likely happen if things go really well
        2. **Darkest Timeline**: What might happen if things go poorly

        For each timeline, provide monthly predictions with:
        - A happiness score (1-10, where 10 is most happy)
        - A brief story description of what happens that month

        Please respond in this exact JSON format:
        {
          "bestTimeline": [
            {
              "month": 1,
              "happiness": 8.5,
              "description": "Description of what happens in month 1"
            }
          ],
          "darkestTimeline": [
            {
              "month": 1,
              "happiness": 4.2,
              "description": "Description of what happens in month 1"
            }
          ]
        }

        Journal Entries:
        \(entriesData)

        Base your predictions on patterns, concerns, hopes, and themes you see in the entries. Make the stories feel personal and specific to this person's life situation.
        """
    }
    
    private func makeClaudeAPICall(prompt: String, apiToken: String) async throws -> String {
        // Validate API token format
        guard !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.missingToken
        }
        
        let cleanToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(cleanToken, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 60.0
        
        let requestBody = ClaudeAPIRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: 4000,
            messages: [
                ClaudeMessage(role: "user", content: prompt)
            ]
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }
        
        print("Making API request to: \(url)")
        print("Request headers: \(request.allHTTPHeaderFields ?? [:])")
        print("Request body model: \(requestBody.model)")
        print("Request body max_tokens: \(requestBody.max_tokens)")
        
        // Create custom URL session with better configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 120.0
        config.waitsForConnectivity = true
        
        let session = URLSession(configuration: config)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        print("HTTP Status Code: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Error response body: \(errorBody)")
            throw APIError.httpError(httpResponse.statusCode, errorBody)
        }
        
        do {
            let apiResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
            guard let content = apiResponse.content.first?.text else {
                throw APIError.invalidResponse
            }
            return content
        } catch {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("Decoding error: \(error)")
            print("Response body: \(responseString)")
            throw APIError.decodingError(error.localizedDescription)
        }
    }
    
    private func parseTimelinePrediction(response: String, monthsAhead: Int) throws -> TimelinePrediction {
        // Extract JSON from response (Claude sometimes adds explanatory text)
        let jsonStart = response.firstIndex(of: "{") ?? response.startIndex
        let jsonEnd = response.lastIndex(of: "}") ?? response.endIndex
        let jsonString = String(response[jsonStart...jsonEnd])
        
        let data = jsonString.data(using: .utf8)!
        let parsedResponse = try JSONDecoder().decode(ClaudeTimelineResponse.self, from: data)
        
        let calendar = Calendar.current
        let today = Date()
        
        let bestTimeline = parsedResponse.bestTimeline.map { item in
            let futureDate = calendar.date(byAdding: .month, value: item.month, to: today)!
            return TimelinePoint(
                date: futureDate,
                happiness: item.happiness,
                description: item.description,
                scenario: .best
            )
        }
        
        let darkestTimeline = parsedResponse.darkestTimeline.map { item in
            let futureDate = calendar.date(byAdding: .month, value: item.month, to: today)!
            return TimelinePoint(
                date: futureDate,
                happiness: item.happiness,
                description: item.description,
                scenario: .darkest
            )
        }
        
        return TimelinePrediction(
            bestTimeline: bestTimeline,
            darkestTimeline: darkestTimeline,
            analysisDate: today,
            monthsAhead: monthsAhead
        )
    }
    
    enum APIError: Error {
        case missingToken
        case invalidURL
        case invalidResponse
        case httpError(Int, String)
        case encodingError(String)
        case decodingError(String)
        case networkError(String)
        
        var localizedDescription: String {
            switch self {
            case .missingToken:
                return "Claude API token is missing. Please add it in Settings."
            case .invalidURL:
                return "Invalid API URL"
            case .invalidResponse:
                return "Invalid response from Claude API"
            case .httpError(let code, let message):
                if code == 401 {
                    return "Invalid API token. Please check your token in Settings."
                } else if code == 429 {
                    return "Rate limit exceeded. Please try again later."
                } else {
                    return "HTTP error \(code): \(message)"
                }
            case .encodingError(let message):
                return "Request encoding error: \(message)"
            case .decodingError(let message):
                return "Response decoding error: \(message)"
            case .networkError(let message):
                return "Network error: \(message). Check your internet connection."
            }
        }
    }
    
    func testConnection(apiToken: String) async {
        await MainActor.run {
            isTestingConnection = true
            connectionTestResult = nil
        }
        
        do {
            let testPrompt = "Hello, please respond with just the word 'success' to test the API connection."
            let response = try await makeClaudeAPICall(prompt: testPrompt, apiToken: apiToken)
            
            await MainActor.run {
                isTestingConnection = false
                connectionTestResult = "✅ Connection successful! API token is valid."
            }
        } catch {
            await MainActor.run {
                isTestingConnection = false
                connectionTestResult = "❌ Connection failed: \(error.localizedDescription)"
            }
        }
    }
}

// Claude API Request/Response Models
struct ClaudeAPIRequest: Codable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeAPIResponse: Codable {
    let content: [ClaudeContent]
}

struct ClaudeContent: Codable {
    let text: String
    let type: String
}

struct ClaudeTimelineResponse: Codable {
    let bestTimeline: [ClaudeTimelineItem]
    let darkestTimeline: [ClaudeTimelineItem]
}

struct ClaudeTimelineItem: Codable {
    let month: Int
    let happiness: Double
    let description: String
}

struct TimelineDot: View {
    let isFirst: Bool
    let isLast: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if !isFirst {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 2, height: 20)
            }
            
            Circle()
                .fill(Color.blue)
                .frame(width: 12, height: 12)
            
            if !isLast {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 2, height: 20)
            }
        }
    }
}

struct TimelineEntryView: View {
    let entry: HumanEntry
    let summary: String
    let isFirst: Bool
    let isLast: Bool
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            TimelineDot(isFirst: isFirst, isLast: isLast)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(summary)
                    .font(.body)
                    .foregroundColor(isHovered ? .primary : .secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

struct TimelineView: View {
    let entries: [HumanEntry]
    let onEntrySelected: (HumanEntry) -> Void
    let onClose: () -> Void
    
    @StateObject private var summaryService = SummaryService()
    @State private var summaries: [UUID: String] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        TimelineEntryView(
                            entry: entry,
                            summary: summaries[entry.id] ?? "Generating summary...",
                            isFirst: index == 0,
                            isLast: index == entries.count - 1,
                            onTap: {
                                onEntrySelected(entry)
                                onClose()
                            }
                        )
                        .onAppear {
                            generateSummaryIfNeeded(for: entry)
                        }
                    }
                }
                .padding(.top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func generateSummaryIfNeeded(for entry: HumanEntry) {
        guard summaries[entry.id] == nil else { return }
        
        Task {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Freewrite")
            let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
            
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let summary = summaryService.generateSummary(for: content)
                
                await MainActor.run {
                    summaries[entry.id] = summary
                }
            } catch {
                await MainActor.run {
                    summaries[entry.id] = entry.previewText.isEmpty ? "Unable to load content" : entry.previewText
                }
            }
        }
    }
}

struct TimelineChartView: View {
    let entries: [HumanEntry]
    let prediction: TimelinePrediction?
    let onEntrySelected: (HumanEntry) -> Void
    
    @State private var selectedPoint: TimelinePoint?
    @State private var hoveredDate: Date?
    @StateObject private var summaryService = SummaryService()
    @State private var actualTimelineData: [TimelinePoint] = []
    
    var body: some View {
        VStack(spacing: 16) {
            // Chart Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Future Timeline Projection")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Historical happiness data with best and darkest possible futures")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Legend
                HStack(spacing: 20) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                        Text("Actual Journey")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                        Text("Best Timeline")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("Darkest Timeline")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Custom Chart Implementation
            CustomChartView(
                actualData: actualTimelineData,
                prediction: prediction,
                onPointSelected: { point in
                    selectedPoint = point
                }
            )
            .frame(height: 300)
            .onAppear {
                generateActualTimelineData()
            }
            
            // Selected point details
            if let selectedPoint = selectedPoint {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(getTimelineTitle(for: selectedPoint.scenario))
                            .font(.headline)
                            .foregroundColor(getTimelineColor(for: selectedPoint.scenario))
                        
                        Spacer()
                        
                        Text(formatDate(selectedPoint.date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Happiness: \(selectedPoint.happiness, specifier: "%.1f")/10")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(selectedPoint.description)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private func getTimelineTitle(for scenario: TimelinePoint.TimelineScenario) -> String {
        switch scenario {
        case .actual:
            return "Current State"
        case .best:
            return "Best Timeline"
        case .darkest:
            return "Darkest Timeline"
        }
    }
    
    private func getTimelineColor(for scenario: TimelinePoint.TimelineScenario) -> Color {
        switch scenario {
        case .actual:
            return .blue
        case .best:
            return .green
        case .darkest:
            return .red
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
    
    private func generateActualTimelineData() {
        // Generate actual timeline data from entries
        let calendar = Calendar.current
        
        // Group entries by month
        var monthlyEntries: [Date: [HumanEntry]] = [:]
        
        for entry in entries {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            
            if let entryDate = dateFormatter.date(from: entry.date) {
                // Set current year
                var components = calendar.dateComponents([.month, .day], from: entryDate)
                components.year = calendar.component(.year, from: Date())
                
                if let dateWithYear = calendar.date(from: components) {
                    let monthStart = calendar.dateInterval(of: .month, for: dateWithYear)?.start ?? dateWithYear
                    
                    if monthlyEntries[monthStart] == nil {
                        monthlyEntries[monthStart] = []
                    }
                    monthlyEntries[monthStart]?.append(entry)
                }
            }
        }
        
        // Calculate happiness scores for each month
        var points: [TimelinePoint] = []
        
        for (monthDate, monthEntries) in monthlyEntries.sorted(by: { $0.key < $1.key }) {
            let happiness = calculateHappinessScore(for: monthEntries)
            let description = generateMonthDescription(for: monthEntries)
            
            let point = TimelinePoint(
                date: monthDate,
                happiness: happiness,
                description: description,
                scenario: .actual
            )
            points.append(point)
        }
        
        actualTimelineData = points
    }
    
    private func calculateHappinessScore(for entries: [HumanEntry]) -> Double {
        // Simple happiness calculation based on text sentiment
        // In a real app, you might use NaturalLanguage framework or more sophisticated analysis
        
        let totalWords = entries.reduce(0) { count, entry in
            count + entry.previewText.split(separator: " ").count
        }
        
        let positiveWords = ["happy", "good", "great", "amazing", "love", "excited", "wonderful", "fantastic", "awesome", "perfect", "beautiful", "successful", "accomplished", "grateful", "thankful", "blessed", "confident", "optimistic", "hopeful", "peaceful", "joyful", "content", "satisfied", "pleased", "delighted", "thrilled", "ecstatic", "proud", "inspired", "motivated", "energized"]
        
        let negativeWords = ["sad", "bad", "terrible", "awful", "hate", "worried", "horrible", "disgusting", "disappointed", "frustrated", "angry", "annoyed", "stressed", "anxious", "depressed", "upset", "miserable", "lonely", "tired", "exhausted", "overwhelmed", "confused", "lost", "hopeless", "scared", "afraid", "nervous", "uncomfortable", "embarrassed", "ashamed", "guilty", "regretful", "bitter", "resentful"]
        
        var positiveCount = 0
        var negativeCount = 0
        
        for entry in entries {
            let words = entry.previewText.lowercased().split(separator: " ")
            for word in words {
                if positiveWords.contains(String(word)) {
                    positiveCount += 1
                } else if negativeWords.contains(String(word)) {
                    negativeCount += 1
                }
            }
        }
        
        // Calculate happiness score (1-10)
        let sentiment = Double(positiveCount - negativeCount)
        let wordCount = max(Double(totalWords), 1)
        let normalizedSentiment = sentiment / wordCount * 100
        
        // Map to 1-10 scale with 5 as neutral
        let happiness = max(1, min(10, 5 + normalizedSentiment))
        
        return happiness
    }
    
    private func generateMonthDescription(for entries: [HumanEntry]) -> String {
        let wordCount = entries.reduce(0) { count, entry in
            count + entry.previewText.split(separator: " ").count
        }
        
        let entryCount = entries.count
        
        if entryCount == 0 {
            return "No entries this month"
        } else if entryCount == 1 {
            return "1 entry with \(wordCount) words"
        } else {
            return "\(entryCount) entries with \(wordCount) words total"
        }
    }
}

struct CustomChartView: View {
    let actualData: [TimelinePoint]
    let prediction: TimelinePrediction?
    let onPointSelected: (TimelinePoint) -> Void
    
    @State private var hoveredDate: Date?
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let padding: CGFloat = 40
            let chartWidth = width - padding * 2
            let chartHeight = height - padding * 2
            
            ZStack {
                // Chart background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                
                // Grid lines
                Path { path in
                    // Horizontal grid lines
                    for i in 0...10 {
                        let y = padding + (chartHeight * CGFloat(10 - i) / 10)
                        path.move(to: CGPoint(x: padding, y: y))
                        path.addLine(to: CGPoint(x: padding + chartWidth, y: y))
                    }
                    
                    // Vertical grid lines (months)
                    let allPoints = getAllPoints()
                    if !allPoints.isEmpty {
                        let monthCount = allPoints.count > 1 ? allPoints.count - 1 : 1
                        for i in 0...monthCount {
                            let x = padding + (chartWidth * CGFloat(i) / CGFloat(monthCount))
                            path.move(to: CGPoint(x: x, y: padding))
                            path.addLine(to: CGPoint(x: x, y: padding + chartHeight))
                        }
                    }
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                
                // Plot actual timeline
                if !actualData.isEmpty {
                    drawTimeline(points: actualData, color: .blue, isDashed: false, width: chartWidth, height: chartHeight, padding: padding)
                }
                
                // Plot prediction timelines
                if let prediction = prediction {
                    drawTimeline(points: prediction.bestTimeline, color: .green, isDashed: true, width: chartWidth, height: chartHeight, padding: padding)
                    drawTimeline(points: prediction.darkestTimeline, color: .red, isDashed: true, width: chartWidth, height: chartHeight, padding: padding)
                }
                
                // Y-axis labels
                VStack {
                    ForEach(0..<11) { i in
                        HStack {
                            Text("\(10 - i)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        if i < 10 {
                            Spacer()
                        }
                    }
                }
                .frame(width: 20, height: chartHeight)
                .offset(x: -width/2 + 20, y: 0)
                
                // X-axis labels
                HStack {
                    ForEach(getAllPoints().indices, id: \.self) { index in
                        Text(formatDateForAxis(getAllPoints()[index].date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if index < getAllPoints().count - 1 {
                            Spacer()
                        }
                    }
                }
                .frame(width: chartWidth, height: 20)
                .offset(x: 0, y: height/2 - 30)
                
                // Invisible hover zones for each month
                ForEach(getUniqueDates(), id: \.self) { date in
                    let allPoints = getAllPoints()
                    let pointIndex = allPoints.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: date) } ?? 0
                    let xPosition = padding + (chartWidth * CGFloat(pointIndex) / CGFloat(max(allPoints.count - 1, 1)))
                    let zoneWidth = chartWidth / CGFloat(max(allPoints.count, 1))
                    
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: zoneWidth, height: chartHeight)
                        .position(x: xPosition, y: padding + chartHeight/2)
                        .onHover { isHovering in
                            hoveredDate = isHovering ? date : nil
                        }
                }
                
                // Tooltip overlay
                if let hoveredDate = hoveredDate {
                    tooltipView(for: hoveredDate, width: width, height: height, padding: padding, chartWidth: chartWidth, chartHeight: chartHeight)
                }
            }
        }
    }
    
    private func tooltipView(for date: Date, width: CGFloat, height: CGFloat, padding: CGFloat, chartWidth: CGFloat, chartHeight: CGFloat) -> some View {
        let allPoints = getAllPoints()
        let pointsAtDate = getPointsAtDate(date: date)
        
        // Get the x position for this date - use same logic as chart points
        let pointIndex = allPoints.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: date) } ?? 0
        let pointX = padding + (chartWidth * CGFloat(pointIndex) / CGFloat(max(allPoints.count - 1, 1)))
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(formatDateForTooltip(date))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Show tooltips for each scenario at this date
            ForEach(pointsAtDate.sorted { $0.scenario.rawValue < $1.scenario.rawValue }) { point in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(point.scenario == .best ? .green : point.scenario == .darkest ? .red : .blue)
                            .frame(width: 8, height: 8)
                        
                        Text(point.scenario.rawValue.capitalized + " Timeline")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(point.scenario == .best ? .green : point.scenario == .darkest ? .red : .blue)
                    }
                    
                    Text("Happiness: \(String(format: "%.1f", point.happiness))/10")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if !point.description.isEmpty {
                        Text(point.description)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        )
        .frame(maxWidth: 280)
        .position(
            x: min(max(pointX, 140), width - 140),
            y: max(height * 0.2, 60)
        )
    }
    
    private func getPointsAtDate(date: Date) -> [TimelinePoint] {
        var pointsAtDate: [TimelinePoint] = []
        
        // Check actual data
        pointsAtDate.append(contentsOf: actualData.filter { Calendar.current.isDate($0.date, inSameDayAs: date) })
        
        // Check prediction data
        if let prediction = prediction {
            pointsAtDate.append(contentsOf: prediction.bestTimeline.filter { Calendar.current.isDate($0.date, inSameDayAs: date) })
            pointsAtDate.append(contentsOf: prediction.darkestTimeline.filter { Calendar.current.isDate($0.date, inSameDayAs: date) })
        }
        
        return pointsAtDate
    }
    
    private func formatDateForTooltip(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
    
    private func getUniqueDates() -> [Date] {
        var allDates: [Date] = []
        
        // Collect dates from actual data
        allDates.append(contentsOf: actualData.map { $0.date })
        
        // Collect dates from prediction data
        if let prediction = prediction {
            allDates.append(contentsOf: prediction.bestTimeline.map { $0.date })
            allDates.append(contentsOf: prediction.darkestTimeline.map { $0.date })
        }
        
        // Remove duplicates and sort
        let uniqueDates = Array(Set(allDates)).sorted()
        return uniqueDates
    }
    
    
    private func getAllPoints() -> [TimelinePoint] {
        var allPoints = actualData
        
        if let prediction = prediction {
            allPoints.append(contentsOf: prediction.bestTimeline)
            allPoints.append(contentsOf: prediction.darkestTimeline)
        }
        
        return allPoints.sorted { $0.date < $1.date }
    }
    
    private func drawTimeline(points: [TimelinePoint], color: Color, isDashed: Bool, width: CGFloat, height: CGFloat, padding: CGFloat) -> some View {
        let sortedPoints = points.sorted { $0.date < $1.date }
        let allPoints = getAllPoints()
        
        return ZStack {
            // Draw line
            if sortedPoints.count > 1 {
                Path { path in
                    for (index, point) in sortedPoints.enumerated() {
                        let x = padding + (width * CGFloat(getPointIndex(point: point, in: allPoints)) / CGFloat(max(allPoints.count - 1, 1)))
                        let y = padding + (height * CGFloat(10 - point.happiness) / 10)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: isDashed ? 2 : 3, lineCap: .round, dash: isDashed ? [5, 5] : []))
            }
            
            // Draw points
            ForEach(sortedPoints) { point in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .position(
                        x: padding + (width * CGFloat(getPointIndex(point: point, in: allPoints)) / CGFloat(max(allPoints.count - 1, 1))),
                        y: padding + (height * CGFloat(10 - point.happiness) / 10)
                    )
                    .onTapGesture {
                        onPointSelected(point)
                    }
            }
        }
    }
    
    private func getPointIndex(point: TimelinePoint, in allPoints: [TimelinePoint]) -> Int {
        return allPoints.firstIndex { $0.date == point.date } ?? 0
    }
    
    private func formatDateForAxis(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
}

struct HeartEmoji: Identifiable {
    let id = UUID()
    var position: CGPoint
    var offset: CGFloat = 0
}

struct ContentView: View {
    private let headerString = "\n\n"
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""  // Remove initial welcome text since we'll handle it in createNewEntry
    
    @State private var isFullscreen = false
    @State private var selectedFont: String = "Lato-Regular"
    @State private var currentRandomFont: String = ""
    @State private var timeRemaining: Int = 900  // Changed to 900 seconds (15 minutes)
    @State private var timerIsRunning = false
    @State private var isHoveringTimer = false
    @State private var isHoveringFullscreen = false
    @State private var hoveredFont: String? = nil
    @State private var isHoveringSize = false
    @State private var fontSize: CGFloat = 18
    @State private var blinkCount = 0
    @State private var isBlinking = false
    @State private var opacity: Double = 1.0
    @State private var shouldShowGray = true // New state to control color
    @State private var lastClickTime: Date? = nil
    @State private var bottomNavOpacity: Double = 1.0
    @State private var isHoveringBottomNav = false
    @State private var selectedEntryIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedEntryId: UUID? = nil
    @State private var hoveredEntryId: UUID? = nil
    @State private var isHoveringChat = false  // Add this state variable
    @State private var showingChatMenu = false
    @State private var chatMenuAnchor: CGPoint = .zero
    @State private var showingSidebar = false  // Add this state variable
    @State private var hoveredTrashId: UUID? = nil
    @State private var hoveredExportId: UUID? = nil
    @State private var placeholderText: String = ""  // Add this line
    @State private var isHoveringNewEntry = false
    @State private var isHoveringClock = false
    @State private var isHoveringHistory = false
    @State private var isHoveringHistoryText = false
    @State private var isHoveringHistoryPath = false
    @State private var isHoveringHistoryArrow = false
    @State private var colorScheme: ColorScheme = .light // Add state for color scheme
    @State private var isHoveringThemeToggle = false // Add state for theme toggle hover
    @State private var didCopyPrompt: Bool = false // Add state for copy prompt feedback
    @State private var currentView: AppView = .writing // Add state for current view
    @State private var isHoveringTimeline = false // Add state for timeline button hover
    @State private var showingTimeline = false // Keep for backwards compatibility
    @State private var isHoveringSettings = false // Add state for settings button hover
    @AppStorage("claudeApiToken") private var claudeApiToken: String = ""
    @AppStorage("predictionMonths") private var predictionMonths: Int = 6
    @StateObject private var claudeService = ClaudeAPIService()
    @State private var timelinePrediction: TimelinePrediction?
    @State private var isGeneratingPrediction = false
    @State private var showApiToken = false
    
    enum AppView {
        case writing
        case timeline
        case settings
    }
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let entryHeight: CGFloat = 40
    
    let availableFonts = NSFontManager.shared.availableFontFamilies
    let standardFonts = ["Lato-Regular", "Arial", ".AppleSystemUIFont", "Times New Roman"]
    let fontSizes: [CGFloat] = [16, 18, 20, 22, 24, 26]
    let placeholderOptions = [
        "\n\nBegin writing",
        "\n\nPick a thought and go",
        "\n\nStart typing",
        "\n\nWhat's on your mind",
        "\n\nJust start",
        "\n\nType your first thought",
        "\n\nStart with one sentence",
        "\n\nJust say it"
    ]
    
    // Add file manager and save timer
    private let fileManager = FileManager.default
    private let saveTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    // Add cached documents directory
    private let documentsDirectory: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Freewrite")
        
        // Create Freewrite directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                print("Successfully created Freewrite directory")
            } catch {
                print("Error creating directory: \(error)")
            }
        }
        
        return directory
    }()
    
    // Add shared prompt constant
    private let aiChatPrompt = """
    below is my journal entry. wyt? talk through it with me like a friend. don't therpaize me and give me a whole breakdown, don't repeat my thoughts with headings. really take all of this, and tell me back stuff truly as if you're an old homie.
    
    Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with markdown headings if needed.

    do not just go through every single thing i say, and say it back to me. you need to proccess everythikng is say, make connections i don't see it, and deliver it all back to me as a story that makes me feel what you think i wanna feel. thats what the best therapists do.

    ideally, you're style/tone should sound like the user themselves. it's as if the user is hearing their own tone but it should still feel different, because you have different things to say and don't just repeat back they say.

    else, start by saying, "hey, thanks for showing me this. my thoughts:"
        
    my entry:
    """
    
    private let claudePrompt = """
    Take a look at my journal entry below. I'd like you to analyze it and respond with deep insight that feels personal, not clinical.
    Imagine you're not just a friend, but a mentor who truly gets both my tech background and my psychological patterns. I want you to uncover the deeper meaning and emotional undercurrents behind my scattered thoughts.
    Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with markdown headings if needed.
    Use vivid metaphors and powerful imagery to help me see what I'm really building. Organize your thoughts with meaningful headings that create a narrative journey through my ideas.
    Don't just validate my thoughts - reframe them in a way that shows me what I'm really seeking beneath the surface. Go beyond the product concepts to the emotional core of what I'm trying to solve.
    Be willing to be profound and philosophical without sounding like you're giving therapy. I want someone who can see the patterns I can't see myself and articulate them in a way that feels like an epiphany.
    Start with 'hey, thanks for showing me this. my thoughts:' and then use markdown headings to structure your response.

    Here's my journal entry:
    """
    
    // Initialize with saved theme preference if available
    init() {
        // Load saved color scheme preference
        let savedScheme = UserDefaults.standard.string(forKey: "colorScheme") ?? "light"
        _colorScheme = State(initialValue: savedScheme == "dark" ? .dark : .light)
    }
    
    // Modify getDocumentsDirectory to use cached value
    private func getDocumentsDirectory() -> URL {
        return documentsDirectory
    }
    
    // Add function to save text
    private func saveText() {
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent("entry.md")
        
        print("Attempting to save file to: \(fileURL.path)")
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved file")
        } catch {
            print("Error saving file: \(error)")
            print("Error details: \(error.localizedDescription)")
        }
    }
    
    // Add function to load text
    private func loadText() {
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent("entry.md")
        
        print("Attempting to load file from: \(fileURL.path)")
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                text = try String(contentsOf: fileURL, encoding: .utf8)
                print("Successfully loaded file")
            } else {
                print("File does not exist yet")
            }
        } catch {
            print("Error loading file: \(error)")
            print("Error details: \(error.localizedDescription)")
        }
    }
    
    // Add function to load existing entries
    private func loadExistingEntries() {
        let documentsDirectory = getDocumentsDirectory()
        print("Looking for entries in: \(documentsDirectory.path)")
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            let mdFiles = fileURLs.filter { $0.pathExtension == "md" }
            
            print("Found \(mdFiles.count) .md files")
            
            // Process each file
            let entriesWithDates = mdFiles.compactMap { fileURL -> (entry: HumanEntry, date: Date, content: String)? in
                let filename = fileURL.lastPathComponent
                print("Processing: \(filename)")
                
                // Extract UUID and date from filename - pattern [uuid]-[yyyy-MM-dd-HH-mm-ss].md
                guard let uuidMatch = filename.range(of: "\\[(.*?)\\]", options: .regularExpression),
                      let dateMatch = filename.range(of: "\\[(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\]", options: .regularExpression),
                      let uuid = UUID(uuidString: String(filename[uuidMatch].dropFirst().dropLast())) else {
                    print("Failed to extract UUID or date from filename: \(filename)")
                    return nil
                }
                
                // Parse the date string
                let dateString = String(filename[dateMatch].dropFirst().dropLast())
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
                
                guard let fileDate = dateFormatter.date(from: dateString) else {
                    print("Failed to parse date from filename: \(filename)")
                    return nil
                }
                
                // Read file contents for preview
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    let preview = content
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let truncated = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)
                    
                    // Format display date
                    dateFormatter.dateFormat = "MMM d"
                    let displayDate = dateFormatter.string(from: fileDate)
                    
                    return (
                        entry: HumanEntry(
                            id: uuid,
                            date: displayDate,
                            filename: filename,
                            previewText: truncated,
                            summary: nil,
                            summaryGenerated: nil
                        ),
                        date: fileDate,
                        content: content  // Store the full content to check for welcome message
                    )
                } catch {
                    print("Error reading file: \(error)")
                    return nil
                }
            }
            
            // Sort and extract entries
            entries = entriesWithDates
                .sorted { $0.date > $1.date }  // Sort by actual date from filename
                .map { $0.entry }
            
            print("Successfully loaded and sorted \(entries.count) entries")
            
            // Check if we need to create a new entry
            let calendar = Calendar.current
            let today = Date()
            let todayStart = calendar.startOfDay(for: today)
            
            // Check if there's an empty entry from today
            let hasEmptyEntryToday = entries.contains { entry in
                // Convert the display date (e.g. "Mar 14") to a Date object
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                if let entryDate = dateFormatter.date(from: entry.date) {
                    // Set year component to current year since our stored dates don't include year
                    var components = calendar.dateComponents([.year, .month, .day], from: entryDate)
                    components.year = calendar.component(.year, from: today)
                    
                    // Get start of day for the entry date
                    if let entryDateWithYear = calendar.date(from: components) {
                        let entryDayStart = calendar.startOfDay(for: entryDateWithYear)
                        return calendar.isDate(entryDayStart, inSameDayAs: todayStart) && entry.previewText.isEmpty
                    }
                }
                return false
            }
            
            // Check if we have only one entry and it's the welcome message
            let hasOnlyWelcomeEntry = entries.count == 1 && entriesWithDates.first?.content.contains("Welcome to Freewrite.") == true
            
            if entries.isEmpty {
                // First time user - create entry with welcome message
                print("First time user, creating welcome entry")
                createNewEntry()
            } else if !hasEmptyEntryToday && !hasOnlyWelcomeEntry {
                // No empty entry for today and not just the welcome entry - create new entry
                print("No empty entry for today, creating new entry")
                createNewEntry()
            } else {
                // Select the most recent empty entry from today or the welcome entry
                if let todayEntry = entries.first(where: { entry in
                    // Convert the display date (e.g. "Mar 14") to a Date object
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MMM d"
                    if let entryDate = dateFormatter.date(from: entry.date) {
                        // Set year component to current year since our stored dates don't include year
                        var components = calendar.dateComponents([.year, .month, .day], from: entryDate)
                        components.year = calendar.component(.year, from: today)
                        
                        // Get start of day for the entry date
                        if let entryDateWithYear = calendar.date(from: components) {
                            let entryDayStart = calendar.startOfDay(for: entryDateWithYear)
                            return calendar.isDate(entryDayStart, inSameDayAs: todayStart) && entry.previewText.isEmpty
                        }
                    }
                    return false
                }) {
                    selectedEntryId = todayEntry.id
                    loadEntry(entry: todayEntry)
                } else if hasOnlyWelcomeEntry {
                    // If we only have the welcome entry, select it
                    selectedEntryId = entries[0].id
                    loadEntry(entry: entries[0])
                }
            }
            
        } catch {
            print("Error loading directory contents: \(error)")
            print("Creating default entry after error")
            createNewEntry()
        }
    }
    
    var randomButtonTitle: String {
        return currentRandomFont.isEmpty ? "Random" : "Random [\(currentRandomFont)]"
    }
    
    var timerButtonTitle: String {
        if !timerIsRunning && timeRemaining == 900 {
            return "15:00"
        }
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var timerColor: Color {
        if timerIsRunning {
            return isHoveringTimer ? (colorScheme == .light ? .black : .white) : .gray.opacity(0.8)
        } else {
            return isHoveringTimer ? (colorScheme == .light ? .black : .white) : (colorScheme == .light ? .gray : .gray.opacity(0.8))
        }
    }
    
    var lineHeight: CGFloat {
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (fontSize * 1.5) - defaultLineHeight
    }
    
    var fontSizeButtonTitle: String {
        return "\(Int(fontSize))px"
    }
    
    var placeholderOffset: CGFloat {
        // Instead of using calculated line height, use a simple offset
        return fontSize / 2
    }
    
    // Add a color utility computed property
    var popoverBackgroundColor: Color {
        return colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(NSColor.darkGray)
    }
    
    var popoverTextColor: Color {
        return colorScheme == .light ? Color.primary : Color.white
    }
    
    @State private var viewHeight: CGFloat = 0
    
    var body: some View {
        let buttonBackground = colorScheme == .light ? Color.white : Color.black
        let navHeight: CGFloat = 68
        let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
        let textHoverColor = colorScheme == .light ? Color.black : Color.white
        
        Group {
            if currentView == .timeline {
                timelinePageView
            } else if currentView == .settings {
                settingsPageView
            } else {
                writingPageView(buttonBackground: buttonBackground, navHeight: navHeight, textColor: textColor, textHoverColor: textHoverColor)
            }
        }
    }
    
    private func writingPageView(buttonBackground: Color, navHeight: CGFloat, textColor: Color, textHoverColor: Color) -> some View {
        HStack(spacing: 0) {
            // Main content
            ZStack {
                Color(colorScheme == .light ? .white : .black)
                    .ignoresSafeArea()
                
              
                    TextEditor(text: Binding(
                        get: { text },
                        set: { newValue in
                            // Ensure the text always starts with two newlines
                            if !newValue.hasPrefix("\n\n") {
                                text = "\n\n" + newValue.trimmingCharacters(in: .newlines)
                            } else {
                                text = newValue
                            }
                        }
                    ))
                    .background(Color(colorScheme == .light ? .white : .black))
                    .font(.custom(selectedFont, size: fontSize))
                    .foregroundColor(colorScheme == .light ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .lineSpacing(lineHeight)
                    .frame(maxWidth: 650)
                    
          
                    .id("\(selectedFont)-\(fontSize)-\(colorScheme)")
                    .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                    .ignoresSafeArea()
                    .colorScheme(colorScheme)
                    .onAppear {
                        placeholderText = placeholderOptions.randomElement() ?? "\n\nBegin writing"
                        // Removed findSubview code which was causing errors
                    }
                    .overlay(
                        ZStack(alignment: .topLeading) {
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(placeholderText)
                                    .font(.custom(selectedFont, size: fontSize))
                                    .foregroundColor(colorScheme == .light ? .gray.opacity(0.5) : .gray.opacity(0.6))
                                // .padding(.top, 8)
                                // .padding(.leading, 8)
                                    .allowsHitTesting(false)
                                    .offset(x: 5, y: placeholderOffset)
                            }
                        }, alignment: .topLeading
                    )
                    .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { height in
                                    viewHeight = height
                                }
                                .contentMargins(.bottom, viewHeight / 4)
                    
                
                VStack {
                    Spacer()
                    HStack {
                        // Font buttons (moved to left)
                        HStack(spacing: 8) {
                            Button(fontSizeButtonTitle) {
                                if let currentIndex = fontSizes.firstIndex(of: fontSize) {
                                    let nextIndex = (currentIndex + 1) % fontSizes.count
                                    fontSize = fontSizes[nextIndex]
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringSize ? textHoverColor : textColor)
                            .onHover { hovering in
                                isHoveringSize = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button("Lato") {
                                selectedFont = "Lato-Regular"
                                currentRandomFont = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(hoveredFont == "Lato" ? textHoverColor : textColor)
                            .onHover { hovering in
                                hoveredFont = hovering ? "Lato" : nil
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button("Arial") {
                                selectedFont = "Arial"
                                currentRandomFont = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(hoveredFont == "Arial" ? textHoverColor : textColor)
                            .onHover { hovering in
                                hoveredFont = hovering ? "Arial" : nil
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button("System") {
                                selectedFont = ".AppleSystemUIFont"
                                currentRandomFont = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(hoveredFont == "System" ? textHoverColor : textColor)
                            .onHover { hovering in
                                hoveredFont = hovering ? "System" : nil
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button("Serif") {
                                selectedFont = "Times New Roman"
                                currentRandomFont = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(hoveredFont == "Serif" ? textHoverColor : textColor)
                            .onHover { hovering in
                                hoveredFont = hovering ? "Serif" : nil
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button(randomButtonTitle) {
                                if let randomFont = availableFonts.randomElement() {
                                    selectedFont = randomFont
                                    currentRandomFont = randomFont
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(hoveredFont == "Random" ? textHoverColor : textColor)
                            .onHover { hovering in
                                hoveredFont = hovering ? "Random" : nil
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                        .padding(8)
                        .cornerRadius(6)
                        .onHover { hovering in
                            isHoveringBottomNav = hovering
                        }
                        
                        Spacer()
                        
                        // Utility buttons (moved to right)
                        HStack(spacing: 8) {
                            Button(timerButtonTitle) {
                                let now = Date()
                                if let lastClick = lastClickTime,
                                   now.timeIntervalSince(lastClick) < 0.3 {
                                    timeRemaining = 900
                                    timerIsRunning = false
                                    lastClickTime = nil
                                } else {
                                    timerIsRunning.toggle()
                                    lastClickTime = now
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(timerColor)
                            .onHover { hovering in
                                isHoveringTimer = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .onAppear {
                                NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                                    if isHoveringTimer {
                                        let scrollBuffer = event.deltaY * 0.25
                                        
                                        if abs(scrollBuffer) >= 0.1 {
                                            let currentMinutes = timeRemaining / 60
                                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                            let direction = -scrollBuffer > 0 ? 5 : -5
                                            let newMinutes = currentMinutes + direction
                                            let roundedMinutes = (newMinutes / 5) * 5
                                            let newTime = roundedMinutes * 60
                                            timeRemaining = min(max(newTime, 0), 2700)
                                        }
                                    }
                                    return event
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button("Chat") {
                                showingChatMenu = true
                                // Ensure didCopyPrompt is reset when opening the menu
                                didCopyPrompt = false
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringChat ? textHoverColor : textColor)
                            .onHover { hovering in
                                isHoveringChat = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .popover(isPresented: $showingChatMenu, attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)), arrowEdge: .top) {
                                VStack(spacing: 0) { // Wrap everything in a VStack for consistent styling and onChange
                                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    // Calculate potential URL lengths
                                    let gptFullText = aiChatPrompt + "\n\n" + trimmedText
                                    let claudeFullText = claudePrompt + "\n\n" + trimmedText
                                    let encodedGptText = gptFullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    let encodedClaudeText = claudeFullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    
                                    let gptUrlLength = "https://chat.openai.com/?m=".count + encodedGptText.count
                                    let claudeUrlLength = "https://claude.ai/new?q=".count + encodedClaudeText.count
                                    let isUrlTooLong = gptUrlLength > 6000 || claudeUrlLength > 6000
                                    
                                    if isUrlTooLong {
                                        // View for long text (URL too long)
                                        Text("Hey, your entry is long. It'll break the URL. Instead, copy prompt by clicking below and paste into AI of your choice!")
                                            .font(.system(size: 14))
                                            .foregroundColor(popoverTextColor)
                                            .lineLimit(nil)
                                            .multilineTextAlignment(.leading)
                                            .frame(width: 200, alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                        
                                        Divider()
                                        
                                        Button(action: {
                                            copyPromptToClipboard()
                                            didCopyPrompt = true
                                        }) {
                                            Text(didCopyPrompt ? "Copied!" : "Copy Prompt")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(popoverTextColor)
                                        .onHover { hovering in
                                            if hovering {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                        
                                    } else if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("hi. my name is farza.") {
                                        Text("Yo. Sorry, you can't chat with the guide lol. Please write your own entry.")
                                            .font(.system(size: 14))
                                            .foregroundColor(popoverTextColor)
                                            .frame(width: 250)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                    } else if text.count < 350 {
                                        Text("Please free write for at minimum 5 minutes first. Then click this. Trust.")
                                            .font(.system(size: 14))
                                            .foregroundColor(popoverTextColor)
                                            .frame(width: 250)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                    } else {
                                        // View for normal text length
                                        Button(action: {
                                            showingChatMenu = false
                                            openChatGPT()
                                        }) {
                                            Text("ChatGPT")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(popoverTextColor)
                                        .onHover { hovering in
                                            if hovering {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                        
                                        Divider()
                                        
                                        Button(action: {
                                            showingChatMenu = false
                                            openClaude()
                                        }) {
                                            Text("Claude")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(popoverTextColor)
                                        .onHover { hovering in
                                            if hovering {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                        
                                        Divider()
                                        
                                        Button(action: {
                                            // Don't dismiss menu, just copy and update state
                                            copyPromptToClipboard()
                                            didCopyPrompt = true
                                        }) {
                                            Text(didCopyPrompt ? "Copied!" : "Copy Prompt")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(popoverTextColor)
                                        .onHover { hovering in
                                            if hovering {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                    }
                                }
                                .frame(minWidth: 120, maxWidth: 250) // Allow width to adjust
                                .background(popoverBackgroundColor)
                                .cornerRadius(8)
                                .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                                // Reset copied state when popover dismisses
                                .onChange(of: showingChatMenu) { newValue in
                                    if !newValue {
                                        didCopyPrompt = false
                                    }
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button(isFullscreen ? "Minimize" : "Fullscreen") {
                                if let window = NSApplication.shared.windows.first {
                                    window.toggleFullScreen(nil)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringFullscreen ? textHoverColor : textColor)
                            .onHover { hovering in
                                isHoveringFullscreen = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button(action: {
                                createNewEntry()
                            }) {
                                Text("New Entry")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringNewEntry ? textHoverColor : textColor)
                            .onHover { hovering in
                                isHoveringNewEntry = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            // Theme toggle button
                            Button(action: {
                                colorScheme = colorScheme == .light ? .dark : .light
                                // Save preference
                                UserDefaults.standard.set(colorScheme == .light ? "light" : "dark", forKey: "colorScheme")
                            }) {
                                Image(systemName: colorScheme == .light ? "moon.fill" : "sun.max.fill")
                                    .foregroundColor(isHoveringThemeToggle ? textHoverColor : textColor)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringThemeToggle = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }

                            Text("•")
                                .foregroundColor(.gray)
                            
                            // Timeline button
                            Button(action: {
                                currentView = .timeline
                            }) {
                                Image(systemName: "timeline.selection")
                                    .foregroundColor(isHoveringTimeline ? textHoverColor : textColor)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringTimeline = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            // Settings button
                            Button(action: {
                                currentView = .settings
                            }) {
                                Image(systemName: "gear")
                                    .foregroundColor(isHoveringSettings ? textHoverColor : textColor)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringSettings = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            // Version history button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingSidebar.toggle()
                                }
                            }) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(isHoveringClock ? textHoverColor : textColor)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringClock = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                        .padding(8)
                        .cornerRadius(6)
                        .onHover { hovering in
                            isHoveringBottomNav = hovering
                        }
                    }
                    .padding()
                    .background(Color(colorScheme == .light ? .white : .black))
                    .opacity(bottomNavOpacity)
                    .onHover { hovering in
                        isHoveringBottomNav = hovering
                        if hovering {
                            withAnimation(.easeOut(duration: 0.2)) {
                                bottomNavOpacity = 1.0
                            }
                        } else if timerIsRunning {
                            withAnimation(.easeIn(duration: 1.0)) {
                                bottomNavOpacity = 0.0
                            }
                        }
                    }
                }
            }
            
            // Right sidebar
            if showingSidebar {
                Divider()
                
                VStack(spacing: 0) {
                    // Header
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: getDocumentsDirectory().path)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("History")
                                        .font(.system(size: 13))
                                        .foregroundColor(isHoveringHistory ? textHoverColor : textColor)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(isHoveringHistory ? textHoverColor : textColor)
                                }
                                Text(getDocumentsDirectory().path)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onHover { hovering in
                        isHoveringHistory = hovering
                    }
                    
                    Divider()
                    
                    // Entries List
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                Button(action: {
                                    if selectedEntryId != entry.id {
                                        // Save current entry before switching
                                        if let currentId = selectedEntryId,
                                           let currentEntry = entries.first(where: { $0.id == currentId }) {
                                            saveEntry(entry: currentEntry)
                                        }
                                        
                                        selectedEntryId = entry.id
                                        loadEntry(entry: entry)
                                    }
                                }) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(entry.previewText)
                                                    .font(.system(size: 13))
                                                    .lineLimit(1)
                                                    .foregroundColor(.primary)
                                                
                                                Spacer()
                                                
                                                // Export/Trash icons that appear on hover
                                                if hoveredEntryId == entry.id {
                                                    HStack(spacing: 8) {
                                                        // Export PDF button
                                                        Button(action: {
                                                            exportEntryAsPDF(entry: entry)
                                                        }) {
                                                            Image(systemName: "arrow.down.circle")
                                                                .font(.system(size: 11))
                                                                .foregroundColor(hoveredExportId == entry.id ? 
                                                                    (colorScheme == .light ? .black : .white) : 
                                                                    (colorScheme == .light ? .gray : .gray.opacity(0.8)))
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Export entry as PDF")
                                                        .onHover { hovering in
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                hoveredExportId = hovering ? entry.id : nil
                                                            }
                                                            if hovering {
                                                                NSCursor.pointingHand.push()
                                                            } else {
                                                                NSCursor.pop()
                                                            }
                                                        }
                                                        
                                                        // Trash icon
                                                        Button(action: {
                                                            deleteEntry(entry: entry)
                                                        }) {
                                                            Image(systemName: "trash")
                                                                .font(.system(size: 11))
                                                                .foregroundColor(hoveredTrashId == entry.id ? .red : .gray)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .onHover { hovering in
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                hoveredTrashId = hovering ? entry.id : nil
                                                            }
                                                            if hovering {
                                                                NSCursor.pointingHand.push()
                                                            } else {
                                                                NSCursor.pop()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            Text(entry.date)
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(backgroundColor(for: entry))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        hoveredEntryId = hovering ? entry.id : nil
                                    }
                                }
                                .onAppear {
                                    NSCursor.pop()  // Reset cursor when button appears
                                }
                                .help("Click to select this entry")  // Add tooltip
                                
                                if entry.id != entries.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .frame(width: 200)
                .background(Color(colorScheme == .light ? .white : NSColor.black))
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: showingSidebar)
        .preferredColorScheme(colorScheme)
        .onAppear {
            showingSidebar = false  // Hide sidebar by default
            loadExistingEntries()
        }
        .onChange(of: text) { _ in
            // Save current entry when text changes
            if let currentId = selectedEntryId,
               let currentEntry = entries.first(where: { $0.id == currentId }) {
                saveEntry(entry: currentEntry)
            }
        }
        .onReceive(timer) { _ in
            if timerIsRunning && timeRemaining > 0 {
                timeRemaining -= 1
            } else if timeRemaining == 0 {
                timerIsRunning = false
                if !isHoveringBottomNav {
                    withAnimation(.easeOut(duration: 1.0)) {
                        bottomNavOpacity = 1.0
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
    }
    
    private var timelinePageView: some View {
        VStack(spacing: 0) {
            // Navigation header
            HStack {
                Button(action: {
                    currentView = .writing
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("Back to Writing")
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Timeline")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Empty space for visual balance
                HStack(spacing: 8) {
                    Text("Back to Writing")
                        .opacity(0)
                    Image(systemName: "chevron.left")
                        .opacity(0)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            // Timeline content
            ScrollView {
                VStack(spacing: 24) {
                    // Generate Predictions Button
                    HStack {
                        Button(action: {
                            generateTimelinePredictions()
                        }) {
                            HStack {
                                if isGeneratingPrediction {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else {
                                    Image(systemName: "wand.and.stars")
                                }
                                Text(isGeneratingPrediction ? "Generating Predictions..." : "Generate Timeline Predictions")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(claudeApiToken.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(claudeApiToken.isEmpty || isGeneratingPrediction)
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        if claudeApiToken.isEmpty {
                            Button(action: {
                                currentView = .settings
                            }) {
                                HStack {
                                    Image(systemName: "gear")
                                    Text("Add API Token")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Error message
                    if let error = claudeService.error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                    
                    // Timeline Chart
                    TimelineChartView(
                        entries: entries,
                        prediction: timelinePrediction,
                        onEntrySelected: { entry in
                            selectedEntryId = entry.id
                            loadEntry(entry: entry)
                            currentView = .writing
                        }
                    )
                    
                    // Original Timeline View (for entry selection)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Journal Entries")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.horizontal)
                        
                        TimelineView(
                            entries: entries,
                            onEntrySelected: { entry in
                                selectedEntryId = entry.id
                                loadEntry(entry: entry)
                                currentView = .writing
                            },
                            onClose: {
                                currentView = .writing
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(colorScheme)
    }
    
    private var settingsPageView: some View {
        VStack(spacing: 0) {
            // Navigation header
            HStack {
                Button(action: {
                    currentView = .writing
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("Back to Writing")
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Empty space for visual balance
                HStack(spacing: 8) {
                    Text("Back to Writing")
                        .opacity(0)
                    Image(systemName: "chevron.left")
                        .opacity(0)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Claude AI API Token Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Claude AI Integration")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Token")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Enter your Claude AI API token to enable timeline predictions and advanced analysis.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            HStack {
                                Group {
                                    if showApiToken {
                                        TextField("Enter Claude AI API Token", text: $claudeApiToken)
                                    } else {
                                        SecureField("Enter Claude AI API Token", text: $claudeApiToken)
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                
                                Button(action: {
                                    showApiToken.toggle()
                                }) {
                                    Image(systemName: showApiToken ? "eye.slash" : "eye")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                                .help(showApiToken ? "Hide API token" : "Show API token")
                            }
                            .frame(maxWidth: 400)
                            
                            HStack {
                                Button(action: {
                                    Task {
                                        await claudeService.testConnection(apiToken: claudeApiToken)
                                    }
                                }) {
                                    HStack {
                                        if claudeService.isTestingConnection {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .progressViewStyle(CircularProgressViewStyle())
                                        } else {
                                            Image(systemName: "antenna.radiowaves.left.and.right")
                                        }
                                        Text(claudeService.isTestingConnection ? "Testing..." : "Test Connection")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(claudeApiToken.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                                .disabled(claudeApiToken.isEmpty || claudeService.isTestingConnection)
                                .buttonStyle(.plain)
                                
                                Spacer()
                            }
                            
                            if let result = claudeService.connectionTestResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(result.contains("✅") ? .green : .red)
                                    .padding(.top, 4)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How to get your API token:")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text("1. Go to console.anthropic.com\n2. Create an account or sign in\n3. Navigate to API Keys\n4. Create a new API key\n5. Copy and paste it above")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Troubleshooting:")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text("• Ensure you have an active internet connection\n• Check that your firewall isn't blocking api.anthropic.com\n• Verify your API token is correct and has sufficient credits\n• Try the 'Test Connection' button above")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Divider()
                    
                    // Timeline Prediction Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Timeline Predictions")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prediction Range")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("How many months ahead would you like to predict?")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Prediction Range", selection: $predictionMonths) {
                                Text("3 months").tag(3)
                                Text("6 months").tag(6)
                                Text("12 months").tag(12)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(colorScheme)
    }
    
    private func generateTimelinePredictions() {
        guard !claudeApiToken.isEmpty else { return }
        
        isGeneratingPrediction = true
        
        Task {
            do {
                let prediction = try await claudeService.generateTimelinePrediction(
                    entries: entries,
                    apiToken: claudeApiToken,
                    monthsAhead: predictionMonths
                )
                
                await MainActor.run {
                    timelinePrediction = prediction
                    isGeneratingPrediction = false
                }
            } catch {
                await MainActor.run {
                    isGeneratingPrediction = false
                    print("Error generating predictions: \(error)")
                }
            }
        }
    }
    
    private func backgroundColor(for entry: HumanEntry) -> Color {
        if entry.id == selectedEntryId {
            return Color.gray.opacity(0.1)  // More subtle selection highlight
        } else if entry.id == hoveredEntryId {
            return Color.gray.opacity(0.05)  // Even more subtle hover state
        } else {
            return Color.clear
        }
    }
    
    private func updatePreviewText(for entry: HumanEntry) {
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let preview = content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let truncated = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)
            
            // Find and update the entry in the entries array
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index].previewText = truncated
            }
        } catch {
            print("Error updating preview text: \(error)")
        }
    }
    
    private func saveEntry(entry: HumanEntry) {
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved entry: \(entry.filename)")
            updatePreviewText(for: entry)  // Update preview after saving
        } catch {
            print("Error saving entry: \(error)")
        }
    }
    
    private func loadEntry(entry: HumanEntry) {
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                text = try String(contentsOf: fileURL, encoding: .utf8)
                print("Successfully loaded entry: \(entry.filename)")
            }
        } catch {
            print("Error loading entry: \(error)")
        }
    }
    
    private func createNewEntry() {
        let newEntry = HumanEntry.createNew()
        entries.insert(newEntry, at: 0) // Add to the beginning
        selectedEntryId = newEntry.id
        
        // If this is the first entry (entries was empty before adding this one)
        if entries.count == 1 {
            // Read welcome message from default.md
            if let defaultMessageURL = Bundle.main.url(forResource: "default", withExtension: "md"),
               let defaultMessage = try? String(contentsOf: defaultMessageURL, encoding: .utf8) {
                text = "\n\n" + defaultMessage
            }
            // Save the welcome message immediately
            saveEntry(entry: newEntry)
            // Update the preview text
            updatePreviewText(for: newEntry)
        } else {
            // Regular new entry starts with newlines
            text = "\n\n"
            // Randomize placeholder text for new entry
            placeholderText = placeholderOptions.randomElement() ?? "\n\nBegin writing"
            // Save the empty entry
            saveEntry(entry: newEntry)
        }
    }
    
    private func openChatGPT() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText = aiChatPrompt + "\n\n" + trimmedText
        
        if let encodedText = fullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://chat.openai.com/?m=" + encodedText) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openClaude() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText = claudePrompt + "\n\n" + trimmedText
        
        if let encodedText = fullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://claude.ai/new?q=" + encodedText) {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyPromptToClipboard() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText = aiChatPrompt + "\n\n" + trimmedText

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullText, forType: .string)
        print("Prompt copied to clipboard")
    }
    
    private func deleteEntry(entry: HumanEntry) {
        // Delete the file from the filesystem
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            try fileManager.removeItem(at: fileURL)
            print("Successfully deleted file: \(entry.filename)")
            
            // Remove the entry from the entries array
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: index)
                
                // If the deleted entry was selected, select the first entry or create a new one
                if selectedEntryId == entry.id {
                    if let firstEntry = entries.first {
                        selectedEntryId = firstEntry.id
                        loadEntry(entry: firstEntry)
                    } else {
                        createNewEntry()
                    }
                }
            }
        } catch {
            print("Error deleting file: \(error)")
        }
    }
    
    // Extract a title from entry content for PDF export
    private func extractTitleFromContent(_ content: String, date: String) -> String {
        // Clean up content by removing leading/trailing whitespace and newlines
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If content is empty, just use the date
        if trimmedContent.isEmpty {
            return "Entry \(date)"
        }
        
        // Split content into words, ignoring newlines and removing punctuation
        let words = trimmedContent
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { word in
                word.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}<>"))
                    .lowercased()
            }
            .filter { !$0.isEmpty }
        
        // If we have at least 4 words, use them
        if words.count >= 4 {
            return "\(words[0])-\(words[1])-\(words[2])-\(words[3])"
        }
        
        // If we have fewer than 4 words, use what we have
        if !words.isEmpty {
            return words.joined(separator: "-")
        }
        
        // Fallback to date if no words found
        return "Entry \(date)"
    }
    
    private func exportEntryAsPDF(entry: HumanEntry) {
        // First make sure the current entry is saved
        if selectedEntryId == entry.id {
            saveEntry(entry: entry)
        }
        
        // Get entry content
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            // Read the content of the entry
            let entryContent = try String(contentsOf: fileURL, encoding: .utf8)
            
            // Extract a title from the entry content and add .pdf extension
            let suggestedFilename = extractTitleFromContent(entryContent, date: entry.date) + ".pdf"
            
            // Create save panel
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.pdf]
            savePanel.nameFieldStringValue = suggestedFilename
            savePanel.isExtensionHidden = false  // Make sure extension is visible
            
            // Show save dialog
            if savePanel.runModal() == .OK, let url = savePanel.url {
                // Create PDF data
                if let pdfData = createPDFFromText(text: entryContent) {
                    try pdfData.write(to: url)
                    print("Successfully exported PDF to: \(url.path)")
                }
            }
        } catch {
            print("Error in PDF export: \(error)")
        }
    }
    
    private func createPDFFromText(text: String) -> Data? {
        // Letter size page dimensions
        let pageWidth: CGFloat = 612.0  // 8.5 x 72
        let pageHeight: CGFloat = 792.0 // 11 x 72
        let margin: CGFloat = 72.0      // 1-inch margins
        
        // Calculate content area
        let contentRect = CGRect(
            x: margin,
            y: margin,
            width: pageWidth - (margin * 2),
            height: pageHeight - (margin * 2)
        )
        
        // Create PDF data container
        let pdfData = NSMutableData()
        
        // Configure text formatting attributes
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineHeight
        
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        
        // Trim the initial newlines before creating the PDF
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create the attributed string with formatting
        let attributedString = NSAttributedString(string: trimmedText, attributes: textAttributes)
        
        // Create a Core Text framesetter for text layout
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        // Create a PDF context with the data consumer
        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!, mediaBox: nil, nil) else {
            print("Failed to create PDF context")
            return nil
        }
        
        // Track position within text
        var currentRange = CFRange(location: 0, length: 0)
        var pageIndex = 0
        
        // Create a path for the text frame
        let framePath = CGMutablePath()
        framePath.addRect(contentRect)
        
        // Continue creating pages until all text is processed
        while currentRange.location < attributedString.length {
            // Begin a new PDF page
            pdfContext.beginPage(mediaBox: nil)
            
            // Fill the page with white background
            pdfContext.setFillColor(NSColor.white.cgColor)
            pdfContext.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            
            // Create a frame for this page's text
            let frame = CTFramesetterCreateFrame(
                framesetter, 
                currentRange, 
                framePath, 
                nil
            )
            
            // Draw the text frame
            CTFrameDraw(frame, pdfContext)
            
            // Get the range of text that was actually displayed in this frame
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            
            // Move to the next block of text for the next page
            currentRange.location += visibleRange.length
            
            // Finish the page
            pdfContext.endPage()
            pageIndex += 1
            
            // Safety check - don't allow infinite loops
            if pageIndex > 1000 {
                print("Safety limit reached - stopping PDF generation")
                break
            }
        }
        
        // Finalize the PDF document
        pdfContext.closePDF()
        
        return pdfData as Data
    }
}

// Helper function to calculate line height
func getLineHeight(font: NSFont) -> CGFloat {
    return font.ascender - font.descender + font.leading
}

// Add helper extension to find NSTextView
extension NSView {
    func findTextView() -> NSView? {
        if self is NSTextView {
            return self
        }
        for subview in subviews {
            if let textView = subview.findTextView() {
                return textView
            }
        }
        return nil
    }
}

// Add helper extension for finding subviews of a specific type
extension NSView {
    func findSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let typedSelf = self as? T {
            return typedSelf
        }
        for subview in subviews {
            if let found = subview.findSubview(ofType: type) {
                return found
            }
        }
        return nil
    }
}

#Preview {
    ContentView()
}
