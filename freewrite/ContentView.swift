import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String
    let filename: String
    let rawDate: Date
    var previewText: String
    var summary: String?
    var summaryGenerated: Date?

    static func createNew() -> HumanEntry {
        let id = UUID()
        let now = Date()

        let filenameFormatter = DateFormatter()
        filenameFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let filename = "[\(id)]-[\(filenameFormatter.string(from: now))].md"

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"

        return HumanEntry(
            id: id,
            date: displayFormatter.string(from: now),
            filename: filename,
            rawDate: now,
            previewText: "",
            summary: nil,
            summaryGenerated: nil
        )
    }
}

struct TimelinePoint: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let happiness: Double
    let description: String
    let scenario: TimelineScenario

    enum TimelineScenario: String, Codable {
        case actual
        case best
        case darkest
    }
}

struct TimelinePrediction: Codable {
    let bestTimeline: [TimelinePoint]
    let darkestTimeline: [TimelinePoint]
    let analysisDate: Date
    let monthsAhead: Int
}

class ClaudeAPIService: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var isTestingConnection = false
    @Published var connectionTestResult: String?

    private let baseURL = "https://api.anthropic.com/v1/messages"

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
                return "Claude API token is missing."
            case .invalidURL:
                return "Invalid API URL."
            case .invalidResponse:
                return "Invalid response from Claude API."
            case .httpError(let code, let message):
                if code == 401 { return "Invalid API token." }
                if code == 429 { return "Rate limit exceeded. Try again later." }
                return "HTTP error \(code): \(message)"
            case .encodingError(let message):
                return "Encoding error: \(message)"
            case .decodingError(let message):
                return "Decoding error: \(message)"
            case .networkError(let message):
                return "Network error: \(message)"
            }
        }
    }

    func generateTimelinePrediction(entries: [HumanEntry], apiToken: String, monthsAhead: Int) async throws -> TimelinePrediction {
        guard !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.missingToken
        }

        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let entriesData = try await prepareEntriesSummary(entries: entries)
            guard !entriesData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError.networkError("No journal entries to analyse.")
            }

            let prompt = createPrompt(entriesData: entriesData, monthsAhead: monthsAhead)
            let response = try await makeRequest(prompt: prompt, apiToken: apiToken)
            let prediction = try parseResponse(response: response, monthsAhead: monthsAhead)

            await MainActor.run {
                isLoading = false
            }

            return prediction
        } catch {
            let apiError = error as? APIError ?? APIError.networkError(error.localizedDescription)
            await MainActor.run {
                isLoading = false
                self.error = apiError.localizedDescription
            }
            throw apiError
        }
    }

    func testConnection(apiToken: String) async {
        await MainActor.run {
            isTestingConnection = true
            connectionTestResult = nil
        }

        do {
            let response = try await makeRequest(prompt: "Respond only with the word success.", apiToken: apiToken)
            if response.lowercased().contains("success") {
                await MainActor.run {
                    isTestingConnection = false
                    connectionTestResult = "✅ Connection successful"
                }
            } else {
                await MainActor.run {
                    isTestingConnection = false
                    connectionTestResult = "⚠️ Unexpected response"
                }
            }
        } catch {
            await MainActor.run {
                isTestingConnection = false
                connectionTestResult = "❌ Connection failed: \(error.localizedDescription)"
            }
        }
    }

    private func prepareEntriesSummary(entries: [HumanEntry]) async throws -> String {
        var combined = ""
        let documentsDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freewrite")

        for entry in entries.prefix(20) {
            let url = documentsDirectory.appendingPathComponent(entry.filename)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                combined += "Date: \(entry.date)\nEntry: \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            }
        }
        return combined
    }

    private func createPrompt(entriesData: String, monthsAhead: Int) -> String {
        """
        You are a thoughtful life coach analysing journal entries. Using the journal excerpts below, project two possible futures for the next \(monthsAhead) months:

        1. Best timeline: realistic but optimistic outcomes each month
        2. Darkest timeline: potential challenges to watch for

        For each month, provide a happiness score (1-10) and a short, vivid description. Respond in valid JSON matching this shape:
        {
          "bestTimeline": [{"month": 1, "happiness": 8.5, "description": "..."}],
          "darkestTimeline": [{"month": 1, "happiness": 4.2, "description": "..."}]
        }

        Journal entries:
        \(entriesData)
        """
    }

    private func makeRequest(prompt: String, apiToken: String) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiToken, forHTTPHeaderField: "x-api-key")

        let body = ClaudeAPIRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: 4000,
            messages: [ClaudeMessage(role: "user", content: prompt)]
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }

        let session = URLSession(configuration: .default)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, message)
        }

        do {
            let decoded = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
            guard let text = decoded.content.first?.text else {
                throw APIError.invalidResponse
            }
            return text
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw APIError.decodingError("\(error.localizedDescription)\nRaw: \(raw)")
        }
    }

    private func parseResponse(response: String, monthsAhead: Int) throws -> TimelinePrediction {
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd = response.lastIndex(of: "}") else {
            throw APIError.decodingError("Claude response did not include JSON block.")
        }

        let jsonString = String(response[jsonStart...jsonEnd])
        let data = Data(jsonString.utf8)
        let parsed = try JSONDecoder().decode(ClaudeTimelineResponse.self, from: data)

        let calendar = Calendar.current
        let today = Date()

        let bestTimeline = parsed.bestTimeline.enumerated().map { offset, item -> TimelinePoint in
            let target = calendar.date(byAdding: .month, value: item.month, to: today) ?? today
            return TimelinePoint(date: target, happiness: item.happiness, description: item.description, scenario: .best)
        }

        let darkestTimeline = parsed.darkestTimeline.enumerated().map { offset, item -> TimelinePoint in
            let target = calendar.date(byAdding: .month, value: item.month, to: today) ?? today
            return TimelinePoint(date: target, happiness: item.happiness, description: item.description, scenario: .darkest)
        }

        return TimelinePrediction(
            bestTimeline: bestTimeline,
            darkestTimeline: darkestTimeline,
            analysisDate: today,
            monthsAhead: monthsAhead
        )
    }
}

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

struct TimelineChartView: View {
    let actualData: [TimelinePoint]
    let prediction: TimelinePrediction?
    @Binding var selectedPoint: TimelinePoint?
    var showsInlineSummary: Bool = true
    let onPointSelected: (TimelinePoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsInlineSummary, let selectedPoint {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedPoint.scenario.displayTitle)
                        .font(.headline)
                        .foregroundStyle(selectedPoint.scenario.accentColor)
                    Text(selectedPoint.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            CustomChartView(actualData: actualData, prediction: prediction, selectedPoint: $selectedPoint) { point in
                selectedPoint = point
                onPointSelected(point)
            }
            .frame(height: 220)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
        .animation(.easeInOut(duration: 0.25), value: selectedPoint?.id)
    }

}

struct CustomChartView: View {
    let actualData: [TimelinePoint]
    let prediction: TimelinePrediction?
    @Binding var selectedPoint: TimelinePoint?
    let onPointSelected: (TimelinePoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let padding: CGFloat = 32
            let chartWidth = width - padding * 2
            let chartHeight = height - padding * 2

            Canvas { context, size in
                let rect = CGRect(x: padding, y: padding, width: chartWidth, height: chartHeight)

                let background = Path(roundedRect: rect, cornerRadius: 16)
                context.fill(background, with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ))

                context.stroke(background, with: .color(Color.white.opacity(0.12)), lineWidth: 0.5)

                for i in 0...5 {
                    let fraction = Double(i) / 5.0
                    let y = rect.minY + rect.height * (1 - fraction)
                    var line = Path()
                    line.move(to: CGPoint(x: rect.minX, y: y))
                    line.addLine(to: CGPoint(x: rect.maxX, y: y))
                    context.stroke(line, with: .color(Color.white.opacity(0.08)), lineWidth: 0.5)
                }

                drawTimeline(points: actualData, in: rect, color: TimelinePoint.TimelineScenario.actual.accentColor, dashed: false, context: &context)

                if let prediction {
                    drawTimeline(points: prediction.bestTimeline, in: rect, color: TimelinePoint.TimelineScenario.best.accentColor, dashed: true, context: &context)
                    drawTimeline(points: prediction.darkestTimeline, in: rect, color: TimelinePoint.TimelineScenario.darkest.accentColor, dashed: true, context: &context)
                }
            }
            .overlay(
                timelinePointsOverlay(size: geometry.size, padding: padding, chartWidth: chartWidth, chartHeight: chartHeight)
            )
        }
    }

    private func timelinePointsOverlay(size: CGSize, padding: CGFloat, chartWidth: CGFloat, chartHeight: CGFloat) -> some View {
        let allPoints = combinedPoints()
        let labelPoints = uniqueAxisPoints(from: allPoints)

        return ZStack {
            ForEach(allPoints) { point in
                let index = pointIndex(point, in: allPoints)
                let x = padding + (chartWidth * CGFloat(index) / CGFloat(max(allPoints.count - 1, 1)))
                let y = padding + (chartHeight * CGFloat(10 - point.happiness) / 10)
                let isSelected = selectedPoint?.id == point.id

                Circle()
                    .fill(point.scenario.accentColor)
                    .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isSelected ? 0.8 : 0.0), lineWidth: 2)
                    )
                    .position(x: x, y: y)
                    .shadow(color: isSelected ? point.scenario.accentColor.opacity(0.35) : .clear, radius: 8, x: 0, y: 0)
                    .onTapGesture {
                        onPointSelected(point)
                    }
            }

            ForEach(labelPoints) { point in
                let index = pointIndex(point, in: allPoints)
                let x = padding + (chartWidth * CGFloat(index) / CGFloat(max(allPoints.count - 1, 1)))
                let labelY = padding + chartHeight + 16

                Text(monthYearString(point.date))
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .rotationEffect(.degrees(-25))
                    .position(x: x, y: labelY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func drawTimeline(points: [TimelinePoint], in rect: CGRect, color: Color, dashed: Bool, context: inout GraphicsContext) {
        guard points.count > 1 else { return }
        let sortedPoints = points.sorted { $0.date < $1.date }
        let allPoints = combinedPoints()

        var path = Path()
        for (index, point) in sortedPoints.enumerated() {
            let position = position(for: point, in: rect, allPoints: allPoints)
            if index == 0 {
                path.move(to: position)
            } else {
                path.addLine(to: position)
            }
        }

        context.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: dashed ? 2 : 3, lineCap: .round, dash: dashed ? [6, 6] : []))
    }

    private func position(for point: TimelinePoint, in rect: CGRect, allPoints: [TimelinePoint]) -> CGPoint {
        let index = pointIndex(point, in: allPoints)
        let fraction = CGFloat(index) / CGFloat(max(allPoints.count - 1, 1))
        let x = rect.minX + rect.width * fraction
        let clamped = max(1, min(10, point.happiness))
        let y = rect.maxY - rect.height * CGFloat((clamped - 1) / 9)
        return CGPoint(x: x, y: y)
    }

    private func combinedPoints() -> [TimelinePoint] {
        var points = actualData
        if let prediction {
            points.append(contentsOf: prediction.bestTimeline)
            points.append(contentsOf: prediction.darkestTimeline)
        }
        return points.sorted { $0.date < $1.date }
    }

    private func uniqueAxisPoints(from points: [TimelinePoint]) -> [TimelinePoint] {
        var seenDates: Set<Date> = []
        var result: [TimelinePoint] = []
        for point in points {
            if !seenDates.contains(point.date) {
                seenDates.insert(point.date)
                result.append(point)
            }
        }
        return result
    }

    private func pointIndex(_ point: TimelinePoint, in all: [TimelinePoint]) -> Int {
        all.firstIndex { $0.date == point.date && $0.scenario == point.scenario } ?? 0
    }

}

struct ContentView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var claudeService = ClaudeAPIService()

    @AppStorage("colorScheme") private var colorSchemeString: String = "light"
    @AppStorage("claudeApiToken") private var claudeApiToken: String = ""
    @AppStorage("predictionMonths") private var predictionMonths: Int = 6

    @State private var selectedFont: String = "Lato-Regular"
    @State private var fontSize: CGFloat = 18
    @State private var timeRemaining: Int = 900
    @State private var timerIsRunning = false
    @State private var isSettingsPresented = false
    @State private var showApiToken = false
    @State private var isGeneratingPrediction = false
    @State private var isFocusMode = true
    @State private var isSidebarVisible = false
    @State private var selectedTimelinePoint: TimelinePoint?
    @State private var isTimelineDrawerVisible = false
    @State private var timerShakeTrigger = 0

    private enum Tab: String, CaseIterable {
        case editor = "Editor"
        case timeline = "Timeline"
    }
    @State private var activeTab: Tab = .editor

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let availableFonts = NSFontManager.shared.availableFontFamilies
    private let fontSizes: [CGFloat] = [16, 18, 20, 22, 24, 26]
    private let focusSessionDuration: Int = 900

    private let aiChatPrompt = """
    below is my journal entry. wyt? talk through it with me like a friend. don't therpaize me and give me a whole breakdown, don't repeat my thoughts with headings. really take all of this, and tell me back stuff truly as if you're an old homie.

    Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with markdown headings if needed.

    do not just go through every single thing i say, and say it back to me. you need to proccess everythikng i say, make connections i don't see it, and deliver it all back to me as a story that makes me feel what you think i wanna feel. thats what the best therapists do.

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
    Start with "hey, thanks for showing me this. my thoughts:" and then use markdown headings to structure your response.

    Here's my journal entry:
    """

    var body: some View {
        ZStack {
            LiquidGlassBackground()
            VStack(spacing: 24) {
                if !isFocusMode {
                    headerSection
                        .transition(.opacity)

                    tabSwitcher
                        .transition(.opacity)
                }

                Group {
                    switch activeTab {
                    case .editor:
                        if isFocusMode {
                            JournalEditorView(
                                text: viewModel.editorText,
                                placeholder: viewModel.placeholderText,
                                selectedFont: selectedFont,
                                fontSize: fontSize,
                                lineSpacing: lineSpacing,
                                colorScheme: currentColorScheme,
                                wordCount: viewModel.wordCount,
                                onTextChange: viewModel.updateEditorText,
                                showsContext: false
                            )
                            .transition(.opacity.combined(with: .scale))
                        } else {
                            HStack(alignment: .top, spacing: 24) {
                                if isSidebarVisible {
                                    JournalSidebar(
                                        entries: viewModel.entries,
                                        selectedEntryID: viewModel.selectedEntryID,
                                        onCreate: viewModel.createNewEntry,
                                        onSelect: { viewModel.selectEntry($0) },
                                        onReveal: { revealInFinder(entry: $0) },
                                        onExport: { export(entry: $0) },
                                        onDelete: { viewModel.deleteEntry($0) }
                                    )
                                    .frame(width: 260)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                }

                                LiquidGlassPanel {
                                    JournalEditorView(
                                        text: viewModel.editorText,
                                        placeholder: viewModel.placeholderText,
                                        selectedFont: selectedFont,
                                        fontSize: fontSize,
                                        lineSpacing: lineSpacing,
                                        colorScheme: currentColorScheme,
                                        wordCount: viewModel.wordCount,
                                        onTextChange: viewModel.updateEditorText,
                                        showsContext: true
                                    )
                                }
                                .frame(maxWidth: .infinity, minHeight: 520)
                            }
                            .animation(.easeInOut(duration: 0.3), value: isSidebarVisible)
                            .transition(.opacity)
                        }

                    case .timeline:
                        if isFocusMode {
                            EmptyView()
                                .transition(.opacity)
                        } else {
                            TimelinePage(
                                entries: viewModel.entries,
                                actualData: viewModel.actualTimelineData,
                                prediction: viewModel.timelinePrediction,
                                timelineError: viewModel.timelineError,
                                isGeneratingPrediction: isGeneratingPrediction || claudeService.isLoading,
                                predictionMonths: $predictionMonths,
                                onGeneratePrediction: generateTimelinePrediction,
                                onSelectEntry: {
                                    viewModel.selectEntry($0)
                                    handleTabSelection(.editor)
                                },
                                onOpenSettings: { isSettingsPresented = true },
                                selectedPoint: $selectedTimelinePoint,
                                isDrawerVisible: $isTimelineDrawerVisible
                            )
                            .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, isFocusMode ? 16 : 32)
            .padding(.top, isFocusMode ? 16 : 28)
            .padding(.bottom, isFocusMode ? 16 : 140)
            .animation(.easeInOut(duration: 0.35), value: isFocusMode)
        }
        .preferredColorScheme(currentColorScheme)
        .overlay(alignment: .bottom) {
            if !isFocusMode {
                bottomUtilityBar
            }
        }
        .overlay(alignment: .topTrailing) {
            if shouldShowFocusTimer {
                focusTimerBadge
                    .padding(.top, isFocusMode ? 24 : 20)
                    .padding(.trailing, isFocusMode ? 28 : 32)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isFocusMode {
                focusRevealButton
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet(
                claudeApiToken: $claudeApiToken,
                predictionMonths: $predictionMonths,
                showApiToken: $showApiToken,
                claudeService: claudeService,
                onDismiss: { isSettingsPresented = false }
            )
            .frame(minWidth: 480, minHeight: 420)
        }
        .onReceive(timer) { _ in
            guard timerIsRunning else { return }
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timerIsRunning = false
                timeRemaining = 0
                withAnimation(.easeInOut(duration: 0.6)) {
                    timerShakeTrigger += 1
                }
            }
        }
    }

    private var currentColorScheme: ColorScheme {
        colorSchemeString == "dark" ? .dark : .light
    }

    private var lineSpacing: CGFloat {
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let base = getLineHeight(font: font)
        return max(4, (fontSize * 1.5) - base)
    }

    private var formattedTimer: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var focusToggleButton: some View {
        Button(action: toggleFocusMode) {
            Label(isFocusMode ? "Exit Focus" : "Focus Mode", systemImage: isFocusMode ? "eye" : "eye.slash")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(GlassControlStyle())
        .animation(.easeInOut(duration: 0.35), value: isFocusMode)
    }

    private var entriesToggleButton: some View {
        Button(action: toggleSidebar) {
            Label(isSidebarVisible ? "Hide Entries" : "Show Entries", systemImage: "sidebar.left")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(GlassControlStyle())
        .animation(.easeInOut(duration: 0.3), value: isSidebarVisible)
    }

    private var focusRevealButton: some View {
        Button(action: toggleFocusMode) {
            Image(systemName: "slider.horizontal.3")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.9)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 12)
                )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 40)
        .padding(.bottom, 40)
        .transition(.scale.combined(with: .opacity))
    }

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Freewrite Journal")
                    .font(.title3.weight(.semibold))
                if let date = viewModel.selectedEntry?.date {
                    Text("Entry for \(date)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Start a fresh entry and let it pour out.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isFocusMode {
                focusToggleButton
            }
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button(action: { handleTabSelection(tab) }) {
                    Text(tab.rawValue)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .frame(minWidth: 110)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tab == activeTab ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(tab == activeTab ? 0.28 : 0.1), lineWidth: 0.8)
                        )
                        .foregroundStyle(tab == activeTab ? Color.white : .secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    private var shouldShowFocusTimer: Bool {
        isFocusMode && (timerIsRunning || timeRemaining != focusSessionDuration)
    }

    private var focusTimerBadge: some View {
        Button(action: toggleTimer) {
            Label(formattedTimer, systemImage: "timer")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.9)
                        )
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .modifier(ShakeEffect(animatableData: CGFloat(timerShakeTrigger)))
        .animation(.easeInOut(duration: 0.6), value: timerShakeTrigger)
    }

    private var bottomUtilityBar: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 12) {
                Button(action: toggleTimer) {
                    Label(formattedTimer, systemImage: timerIsRunning ? "pause.circle.fill" : "play.circle.fill")
                }
                .buttonStyle(GlassControlStyle())
                .contextMenu {
                    Button("Reset Timer", role: .destructive, action: resetTimer)
                }

                Label("\(viewModel.wordCount) words", systemImage: "character.cursor.ibeam")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .backgroundCapsule()
            }

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Menu {
                    Picker("Writing Font", selection: $selectedFont) {
                        Text("Lato").tag("Lato-Regular")
                        Text("Arial").tag("Arial")
                        Text("System").tag(".AppleSystemUIFont")
                        Text("Serif").tag("Times New Roman")
                    }
                    Divider()
                    Button("Randomize") {
                        if let random = availableFonts.randomElement() {
                            selectedFont = random
                        }
                    }
                } label: {
                    Label(fontDisplayName, systemImage: "textformat")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(GlassControlStyle())

                Menu {
                    ForEach(fontSizes, id: \.self) { size in
                        Button(action: { fontSize = size }) {
                            if fontSize == size {
                                Label("\(Int(size)) pt", systemImage: "checkmark")
                            } else {
                                Text("\(Int(size)) pt")
                            }
                        }
                    }
                } label: {
                    Label("\(Int(fontSize)) pt", systemImage: "textformat.size")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(GlassControlStyle())

                Button(action: toggleColorScheme) {
                    Image(systemName: currentColorScheme == .dark ? "sun.max.fill" : "moon.fill")
                }
                .buttonStyle(GlassControlStyle())
            }

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Menu("AI Tools") {
                    Button("Copy prompt to clipboard", action: copyPromptToClipboard)
                    Button("Open in ChatGPT", action: openChatGPT)
                    Button("Open in Claude", action: openClaude)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(GlassControlStyle())

                Menu("More") {
                    Button("Reveal in Finder", action: revealJournalFolder)
                    Divider()
                    Button("Export current entry as PDF", action: exportCurrentEntry)
                    Divider()
                    Button("Toggle Full Screen") {
                        toggleFullScreen()
                    }
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(GlassControlStyle())

                Button(action: { isSettingsPresented = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(GlassControlStyle())

                if activeTab == .editor {
                    entriesToggleButton
                }

                focusToggleButton
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.7)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 30, x: 0, y: 20)
        )
        .padding(.horizontal, 42)
        .padding(.bottom, 24)
    }

    private var fontDisplayName: String {
        switch selectedFont {
        case "Lato-Regular": return "Lato"
        case "Arial": return "Arial"
        case ".AppleSystemUIFont": return "System"
        case "Times New Roman": return "Serif"
        default: return selectedFont
        }
    }

    private func toggleTimer() {
        if timerIsRunning {
            timerIsRunning = false
        } else {
            if timeRemaining == 0 {
                timeRemaining = focusSessionDuration
            }
            timerShakeTrigger = 0
            withAnimation(.easeInOut(duration: 0.35)) {
                activeTab = .editor
                isSidebarVisible = false
                isTimelineDrawerVisible = false
                selectedTimelinePoint = nil
                isFocusMode = true
            }
            timerIsRunning = true
        }
    }

    private func resetTimer() {
        timerIsRunning = false
        timeRemaining = focusSessionDuration
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSidebarVisible.toggle()
        }
    }

    private func toggleFocusMode() {
        withAnimation(.easeInOut(duration: 0.35)) {
            if isFocusMode {
                isFocusMode = false
            } else {
                activeTab = .editor
                isSidebarVisible = false
                isTimelineDrawerVisible = false
                selectedTimelinePoint = nil
                isFocusMode = true
            }
        }
    }

    private func handleTabSelection(_ tab: Tab) {
        withAnimation(.easeInOut(duration: 0.25)) {
            activeTab = tab
            if tab != .editor {
                isSidebarVisible = false
            }
            if tab != .timeline {
                isTimelineDrawerVisible = false
                selectedTimelinePoint = nil
            }
        }
    }

    private func toggleColorScheme() {
        colorSchemeString = colorSchemeString == "dark" ? "light" : "dark"
    }

    private func toggleFullScreen() {
        if let window = NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
    }

    private func revealJournalFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: viewModel.documentsPath.path)
    }

    private func copyPromptToClipboard() {
        let text = viewModel.editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        let slot = aiChatPrompt + "\n\n" + text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(slot, forType: .string)
    }

    private func openChatGPT() {
        let trimmed = viewModel.editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText = aiChatPrompt + "\n\n" + trimmed
        guard let encoded = fullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://chat.openai.com/?m=" + encoded) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openClaude() {
        let trimmed = viewModel.editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText = claudePrompt + "\n\n" + trimmed
        guard let encoded = fullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://claude.ai/new?q=" + encoded) else { return }
        NSWorkspace.shared.open(url)
    }

    private func export(entry: HumanEntry) {
        guard let data = viewModel.exportEntryAsPDF(entry: entry, fontName: selectedFont, fontSize: fontSize, lineHeight: lineSpacing) else { return }
        presentSavePanel(data: data, suggestedName: suggestedFilename(for: entry))
    }

    private func exportCurrentEntry() {
        guard let entry = viewModel.selectedEntry,
              let data = viewModel.exportCurrentEntryAsPDF(fontName: selectedFont, fontSize: fontSize, lineHeight: lineSpacing) else { return }
        presentSavePanel(data: data, suggestedName: suggestedFilename(for: entry))
    }

    private func revealInFinder(entry: HumanEntry) {
        let url = viewModel.contentURL(for: entry)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func presentSavePanel(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.nameFieldStringValue = suggestedName
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func suggestedFilename(for entry: HumanEntry) -> String {
        let url = viewModel.contentURL(for: entry)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Entry-\(entry.date).pdf"
        }

        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = cleaned
            .split { $0.isWhitespace || ",.!?;:".contains($0) }
            .map(String.init)

        if words.count >= 4 {
            return words.prefix(4).joined(separator: "-").lowercased() + ".pdf"
        }

        if let first = words.first {
            return first.lowercased() + "-entry.pdf"
        }

        return "Entry-\(entry.date).pdf"
    }

    private func generateTimelinePrediction() {
        Task {
            guard !claudeApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                viewModel.timelineError = "Add a Claude API token in Settings to generate predictions."
                isSettingsPresented = true
                return
            }

            guard !viewModel.entries.isEmpty else {
                viewModel.timelineError = "Add some journal entries to generate a timeline."
                return
            }

            viewModel.timelineError = nil
            isGeneratingPrediction = true

            do {
                let prediction = try await claudeService.generateTimelinePrediction(entries: viewModel.entries, apiToken: claudeApiToken, monthsAhead: predictionMonths)
                await MainActor.run {
                    viewModel.timelinePrediction = prediction
                }
            } catch {
                await MainActor.run {
                    viewModel.timelineError = error.localizedDescription
                }
            }

            await MainActor.run {
                isGeneratingPrediction = false
            }
        }
    }
}

struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.12, green: 0.14, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.30, green: 0.55, blue: 0.95).opacity(0.35))
                .frame(width: 420)
                .blur(radius: 160)
                .offset(x: -260, y: -200)

            Circle()
                .fill(Color(red: 0.95, green: 0.55, blue: 0.85).opacity(0.25))
                .frame(width: 420)
                .blur(radius: 180)
                .offset(x: 220, y: 240)

            RoundedRectangle(cornerRadius: 100)
                .fill(Color.white.opacity(0.08))
                .frame(width: 520, height: 520)
                .blur(radius: 200)
        }
    }
}

struct JournalSidebar: View {
    let entries: [HumanEntry]
    let selectedEntryID: UUID?
    let onCreate: () -> Void
    let onSelect: (HumanEntry) -> Void
    let onReveal: (HumanEntry) -> Void
    let onExport: (HumanEntry) -> Void
    let onDelete: (HumanEntry) -> Void

    var body: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Entries")
                        .font(.headline)
                    Spacer()
                    Button(action: onCreate) {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(GlassControlStyle())
                }

                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No entries yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Click New to capture your first thoughts.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(entries) { entry in
                                SidebarEntryRow(
                                    entry: entry,
                                    isSelected: entry.id == selectedEntryID,
                                    onSelect: { onSelect(entry) },
                                    onReveal: { onReveal(entry) },
                                    onExport: { onExport(entry) },
                                    onDelete: { onDelete(entry) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SidebarEntryRow: View {
    let entry: HumanEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onReveal: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Menu {
                    Button("Reveal in Finder", action: onReveal)
                    Button("Export as PDF", action: onExport)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .imageScale(.small)
                }
                .menuStyle(.borderlessButton)
            }

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.previewText.isEmpty ? "Untitled entry" : entry.previewText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
    }
}

struct JournalEditorView: View {
    let text: String
    let placeholder: String
    let selectedFont: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let colorScheme: ColorScheme
    let wordCount: Int
    let onTextChange: (String) -> Void
    var showsContext: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: showsContext ? 18 : 0) {
            if showsContext {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today")
                        .font(.headline)
                    Text("Focus on the detail in front of you and let everything else happen later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { text },
                    set: { onTextChange($0) }
                ))
                .font(.custom(selectedFont, size: fontSize))
                .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.20, green: 0.20, blue: 0.20))
                .scrollContentBackground(.hidden)
                .lineSpacing(lineSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, showsContext ? 0 : 0)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.custom(selectedFont, size: fontSize))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.top, 2)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }

            if showsContext {
                HStack(spacing: 12) {
                    Label("\(wordCount) words", systemImage: "character.cursor.ibeam")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Auto-saved")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(editorPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var editorPadding: EdgeInsets {
        if showsContext {
            return EdgeInsets(top: 20, leading: 26, bottom: 26, trailing: 26)
        } else {
            return EdgeInsets(top: 28, leading: 38, bottom: 32, trailing: 38)
        }
    }
}

struct TimelinePage: View {
    let entries: [HumanEntry]
    let actualData: [TimelinePoint]
    let prediction: TimelinePrediction?
    let timelineError: String?
    let isGeneratingPrediction: Bool
    @Binding var predictionMonths: Int
    let onGeneratePrediction: () -> Void
    let onSelectEntry: (HumanEntry) -> Void
    let onOpenSettings: () -> Void
    @Binding var selectedPoint: TimelinePoint?
    @Binding var isDrawerVisible: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let timelineError {
                    errorBanner(for: timelineError)
                }

                chartSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isDrawerVisible, let selectedPoint {
                TimelineDetailDrawer(
                    point: selectedPoint,
                    entries: entriesFor(point: selectedPoint),
                    onSelectEntry: { entry in
                        onSelectEntry(entry)
                        closeDrawer()
                    },
                    onClose: closeDrawer
                )
                .frame(width: 360)
                .padding(.trailing, 36)
                .padding(.top, 96)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isDrawerVisible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Timeline")
                    .font(.title3.weight(.semibold))
                Text("Scan your story and where it could go next.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            Picker("Months ahead", selection: $predictionMonths) {
                Text("3m").tag(3)
                Text("6m").tag(6)
                Text("12m").tag(12)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button(action: onGeneratePrediction) {
                HStack(spacing: 8) {
                    if isGeneratingPrediction {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isGeneratingPrediction ? "Projecting" : "Project timelines")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(GlassControlStyle())
            .disabled(isGeneratingPrediction)
        }
    }

    private var chartSection: some View {
        Group {
            if hasChartData {
                TimelineChartView(
                    actualData: actualData,
                    prediction: prediction,
                    selectedPoint: $selectedPoint,
                    showsInlineSummary: false
                ) { point in
                    selectedPoint = point
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isDrawerVisible = true
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 360)
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No timeline yet")
                        .font(.headline)
                    Text("Write a few entries and generate a forecast to see your story unfold here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(action: onOpenSettings) {
                        Text("Open settings")
                    }
                    .buttonStyle(GlassControlStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func errorBanner(for message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Settings", action: onOpenSettings)
                .buttonStyle(GlassControlStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 0.8)
                )
        )
    }

    private func entriesFor(point: TimelinePoint) -> [TimelineEntryDetail] {
        let calendar = Calendar.current
        let documentsDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freewrite")

        return entries
            .filter { calendar.isDate($0.rawDate, equalTo: point.date, toGranularity: .month) }
            .compactMap { entry in
                let url = documentsDirectory.appendingPathComponent(entry.filename)
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? entry.previewText
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                return TimelineEntryDetail(entry: entry, content: trimmed)
            }
            .sorted { $0.entry.rawDate > $1.entry.rawDate }
    }

    private var hasChartData: Bool {
        if !actualData.isEmpty { return true }
        guard let prediction else { return false }
        return !prediction.bestTimeline.isEmpty || !prediction.darkestTimeline.isEmpty
    }

    private func closeDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerVisible = false
            selectedPoint = nil
        }
    }
}

struct TimelineDetailDrawer: View {
    let point: TimelinePoint
    let entries: [TimelineEntryDetail]
    let onSelectEntry: (HumanEntry) -> Void
    let onClose: () -> Void

    var body: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(monthYearString(point.date))
                            .font(.title3.weight(.semibold))
                        Text(point.scenario.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(point.scenario.accentColor)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(GlassControlStyle())
                }

                HStack(spacing: 12) {
                    Label(String(format: "%.1f", point.happiness), systemImage: "waveform.path.ecg")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .backgroundCapsule()
                        .foregroundStyle(point.scenario.accentColor)
                }

                Text(point.description)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Divider()

                if point.scenario == .actual {
                    Text(entries.isEmpty ? "No entries captured for this month." : "Entries from this month")
                        .font(.subheadline.weight(.semibold))

                    if entries.isEmpty {
                        Text("Capture more reflections to build your story here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(entries) { detail in
                                    Button(action: {
                                        onSelectEntry(detail.entry)
                                    }) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(longDateString(detail.entry.rawDate))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(detail.content.isEmpty ? "Tap to open entry" : detail.content)
                                                .font(.footnote)
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(nil)
                                        }
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(Color.white.opacity(0.05))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                    }
                } else {
                    Text("This forecast is generated by Claude based on your recent writing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TimelineEntryDetail: Identifiable {
    let entry: HumanEntry
    let content: String

    var id: UUID { entry.id }
}

struct SettingsSheet: View {
    @Binding var claudeApiToken: String
    @Binding var predictionMonths: Int
    @Binding var showApiToken: Bool
    @ObservedObject var claudeService: ClaudeAPIService
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Claude API") {
                    HStack {
                        Group {
                            if showApiToken {
                                TextField("Claude API Token", text: $claudeApiToken)
                            } else {
                                SecureField("Claude API Token", text: $claudeApiToken)
                            }
                        }
                        Button(action: { showApiToken.toggle() }) {
                            Image(systemName: showApiToken ? "eye.slash" : "eye")
                        }
                    }

                    Button {
                        Task { await claudeService.testConnection(apiToken: claudeApiToken) }
                    } label: {
                        if claudeService.isTestingConnection {
                            ProgressView()
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(claudeApiToken.isEmpty || claudeService.isTestingConnection)

                    if let result = claudeService.connectionTestResult {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(result.contains("✅") ? Color.green : Color.red)
                    }
                }

                Section("Timeline Horizon") {
                    Picker("Months ahead", selection: $predictionMonths) {
                        Text("3 months").tag(3)
                        Text("6 months").tag(6)
                        Text("12 months").tag(12)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}

struct LiquidGlassPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 40, x: 0, y: 30)
            )
    }
}

private extension TimelinePoint.TimelineScenario {
    var displayTitle: String {
        switch self {
        case .actual: return "Current Story"
        case .best: return "Best Timeline"
        case .darkest: return "Darkest Timeline"
        }
    }

    var accentColor: Color {
        switch self {
        case .actual: return Color.cyan
        case .best: return Color.green
        case .darkest: return Color.red
        }
    }
}

struct GlassControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .backgroundCapsule(active: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.7 : 0.9))
            )
            .foregroundStyle(.white)
    }
}

struct ShakeEffect: GeometryEffect {
    var amplitude: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amplitude * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

extension View {
    func backgroundCapsule(active: Bool = false) -> some View {
        self
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(active ? 0.35 : 0.18), lineWidth: active ? 1.2 : 0.8)
                    )
            )
    }
}

#Preview {
    ContentView()
}

func getLineHeight(font: NSFont) -> CGFloat {
    font.ascender - font.descender + font.leading
}

fileprivate let monthYearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"
    return formatter
}()

fileprivate let longDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
}()

fileprivate func monthYearString(_ date: Date) -> String {
    monthYearFormatter.string(from: date)
}

fileprivate func longDateString(_ date: Date) -> String {
    longDateFormatter.string(from: date)
}
    
