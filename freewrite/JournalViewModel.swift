import SwiftUI
import AppKit
import CoreText

final class JournalViewModel: ObservableObject {
    @Published var entries: [HumanEntry] = []
    @Published var selectedEntryID: UUID?
    @Published var editorText: String = ""
    @Published var placeholderText: String
    @Published var timelinePrediction: TimelinePrediction?
    @Published var timelineError: String?

    private let placeholderOptions = [
        "Begin writing",
        "Pick a thought and go",
        "What's on your mind",
        "Just start",
        "Type your first thought",
        "Start with one sentence",
        "Let it flow"
    ]

    private let fileManager = FileManager.default
    private let documentsDirectory: URL

    init() {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freewrite")

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                print("Error creating Freewrite directory: \(error)")
            }
        }

        documentsDirectory = directory
        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"

        loadEntries()
    }

    var documentsPath: URL {
        documentsDirectory
    }

    var selectedEntry: HumanEntry? {
        guard let id = selectedEntryID else { return nil }
        return entries.first(where: { $0.id == id })
    }

    var wordCount: Int {
        editorText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    var actualTimelineData: [TimelinePoint] {
        guard !entries.isEmpty else { return [] }
        let calendar = Calendar.current
        var monthlyEntries: [Date: [HumanEntry]] = [:]

        for entry in entries {
            let entryDate = entry.rawDate
            let monthStart = calendar.dateInterval(of: .month, for: entryDate)?.start ?? entryDate
            monthlyEntries[monthStart, default: []].append(entry)
        }

        return monthlyEntries
            .sorted(by: { $0.key < $1.key })
            .map { monthDate, entries in
                TimelinePoint(
                    date: monthDate,
                    happiness: calculateHappinessScore(for: entries),
                    description: generateMonthDescription(for: entries),
                    scenario: .actual
                )
            }
    }

    func loadEntries() {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            let markdownFiles = fileURLs.filter { $0.pathExtension == "md" }

            let fileDateFormatter = DateFormatter()
            fileDateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d"

            let entriesWithDetails: [(entry: HumanEntry, date: Date, content: String)] = markdownFiles.compactMap { url in
                let filename = url.lastPathComponent

                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let preview = content
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let truncated = preview.isEmpty ? "" : (preview.count > 40 ? String(preview.prefix(40)) + "..." : preview)

                if let uuidMatch = filename.range(of: "\\[(.*?)\\]", options: .regularExpression),
                   let dateMatch = filename.range(of: "\\[(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\]", options: .regularExpression),
                   let uuid = UUID(uuidString: String(filename[uuidMatch].dropFirst().dropLast())) {
                    let dateString = String(filename[dateMatch].dropFirst().dropLast())
                    if let rawDate = fileDateFormatter.date(from: dateString) {
                        let entry = HumanEntry(
                            id: uuid,
                            date: displayFormatter.string(from: rawDate),
                            filename: filename,
                            rawDate: rawDate,
                            previewText: truncated,
                            summary: nil,
                            summaryGenerated: nil
                        )
                        return (entry, rawDate, content)
                    }
                }

                let attributes = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
                let fallbackDate = (attributes[.creationDate] as? Date)
                    ?? (attributes[.modificationDate] as? Date)
                    ?? Date()

                let entry = HumanEntry(
                    id: UUID(),
                    date: displayFormatter.string(from: fallbackDate),
                    filename: filename,
                    rawDate: fallbackDate,
                    previewText: truncated,
                    summary: nil,
                    summaryGenerated: nil
                )

                return (entry, fallbackDate, content)
            }

            let sorted = entriesWithDetails.sorted { $0.date > $1.date }
            entries = sorted.map { $0.entry }

            let contentLookup = Dictionary(uniqueKeysWithValues: sorted.map { ($0.entry.id, $0.content) })

            guard !entries.isEmpty else {
                createNewEntry()
                return
            }

            let calendar = Calendar.current
            let today = Date()
            let todayStart = calendar.startOfDay(for: today)

            let hasEmptyEntryToday = entries.contains { entry in
                let entryDayStart = calendar.startOfDay(for: entry.rawDate)
                return calendar.isDate(entryDayStart, inSameDayAs: todayStart) && entry.previewText.isEmpty
            }

            let hasOnlyWelcomeEntry = entries.count == 1 && sorted.first?.content.contains("Welcome to Freewrite.") == true

            if !hasEmptyEntryToday && !hasOnlyWelcomeEntry {
                createNewEntry()
                return
            }

            if let todaysEntry = entries.first(where: { entry in
                let entryDayStart = calendar.startOfDay(for: entry.rawDate)
                return calendar.isDate(entryDayStart, inSameDayAs: todayStart) && entry.previewText.isEmpty
            }) {
                selectEntry(todaysEntry, content: contentLookup[todaysEntry.id])
            } else if let first = entries.first {
                selectEntry(first, content: contentLookup[first.id])
            }

        } catch {
            print("Error loading entries: \(error)")
            createNewEntry()
        }
    }

    func selectEntry(_ entry: HumanEntry) {
        let content = try? String(contentsOf: documentsDirectory.appendingPathComponent(entry.filename), encoding: .utf8)
        selectEntry(entry, content: content)
    }

    private func selectEntry(_ entry: HumanEntry, content: String?) {
        selectedEntryID = entry.id
        let trimmed = content?.trimmingCharacters(in: .newlines) ?? ""
        editorText = trimmed
    }

    func createNewEntry() {
        let newEntry = HumanEntry.createNew()
        entries.insert(newEntry, at: 0)
        selectedEntryID = newEntry.id

        if entries.count == 1,
           let defaultMessageURL = Bundle.main.url(forResource: "default", withExtension: "md"),
           let defaultMessage = try? String(contentsOf: defaultMessageURL, encoding: .utf8) {
            editorText = defaultMessage
        } else {
            placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
            editorText = ""
        }

        saveCurrentEntry()
    }

    func updateEditorText(_ newValue: String) {
        editorText = newValue
        saveCurrentEntry()
    }

    func saveCurrentEntry() {
        guard let entry = selectedEntry else { return }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        do {
            try editorText.write(to: fileURL, atomically: true, encoding: .utf8)
            refreshPreview(for: entry)
        } catch {
            print("Error saving entry: \(error)")
        }
    }

    func deleteEntry(_ entry: HumanEntry) {
        let url = documentsDirectory.appendingPathComponent(entry.filename)
        do {
            try fileManager.removeItem(at: url)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: index)
            }

            if selectedEntryID == entry.id {
                if let first = entries.first {
                    selectEntry(first)
                } else {
                    createNewEntry()
                }
            }
        } catch {
            print("Error deleting entry: \(error)")
        }
    }

    func regeneratePlaceholder() {
        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
    }

    func contentURL(for entry: HumanEntry) -> URL {
        documentsDirectory.appendingPathComponent(entry.filename)
    }

    func exportCurrentEntryAsPDF(fontName: String, fontSize: CGFloat, lineHeight: CGFloat) -> Data? {
        guard let entry = selectedEntry else { return nil }
        return exportEntryAsPDF(entry: entry, fontName: fontName, fontSize: fontSize, lineHeight: lineHeight)
    }

    func exportEntryAsPDF(entry: HumanEntry, fontName: String, fontSize: CGFloat, lineHeight: CGFloat) -> Data? {
        let contentURL = documentsDirectory.appendingPathComponent(entry.filename)
        guard let text = try? String(contentsOf: contentURL, encoding: .utf8) else { return nil }
        return createPDF(text: text, fontName: fontName, fontSize: fontSize, lineHeight: lineHeight)
    }

    private func createPDF(text: String, fontName: String, fontSize: CGFloat, lineHeight: CGFloat) -> Data? {
        let pageWidth: CGFloat = 612.0
        let pageHeight: CGFloat = 792.0
        let margin: CGFloat = 72.0
        let contentRect = CGRect(x: margin, y: margin, width: pageWidth - margin * 2, height: pageHeight - margin * 2)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineHeight

        let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributed = NSAttributedString(string: trimmed, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        var currentRange = CFRange(location: 0, length: 0)
        var pageIndex = 0

        let path = CGMutablePath()
        path.addRect(contentRect)

        while currentRange.location < attributed.length {
            context.beginPage(mediaBox: nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentRange.location += visibleRange.length
            context.endPage()

            pageIndex += 1
            if pageIndex > 1000 { break }
        }

        context.closePDF()
        return pdfData as Data
    }

    private func refreshPreview(for entry: HumanEntry) {
        let url = documentsDirectory.appendingPathComponent(entry.filename)
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        let preview = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = preview.isEmpty ? "" : (preview.count > 40 ? String(preview.prefix(40)) + "..." : preview)
        entries[index].previewText = truncated
    }

    private func calculateHappinessScore(for entries: [HumanEntry]) -> Double {
        let positiveWords = ["happy", "good", "great", "amazing", "love", "excited", "wonderful", "fantastic", "awesome", "perfect", "beautiful", "successful", "accomplished", "grateful", "thankful", "blessed", "confident", "optimistic", "hopeful", "peaceful", "joyful", "content", "satisfied", "pleased", "delighted", "thrilled", "ecstatic", "proud", "inspired", "motivated", "energized"]
        let negativeWords = ["sad", "bad", "terrible", "awful", "hate", "worried", "horrible", "disgusting", "disappointed", "frustrated", "angry", "annoyed", "stressed", "anxious", "depressed", "upset", "miserable", "lonely", "tired", "exhausted", "overwhelmed", "confused", "lost", "hopeless", "scared", "afraid", "nervous", "uncomfortable", "embarrassed", "ashamed", "guilty", "regretful", "bitter", "resentful"]

        var positiveCount = 0
        var negativeCount = 0
        var totalWords = 0

        for entry in entries {
            let words = entry.previewText.lowercased().split(separator: " ")
            totalWords += words.count
            for word in words {
                if positiveWords.contains(String(word)) {
                    positiveCount += 1
                } else if negativeWords.contains(String(word)) {
                    negativeCount += 1
                }
            }
        }

        let sentiment = Double(positiveCount - negativeCount)
        let wordCount = max(Double(totalWords), 1)
        let normalizedSentiment = sentiment / wordCount * 100
        return max(1, min(10, 5 + normalizedSentiment))
    }

    private func generateMonthDescription(for entries: [HumanEntry]) -> String {
        let wordCount = entries.reduce(0) { count, entry in
            count + entry.previewText.split(separator: " ").count
        }

        switch entries.count {
        case 0:
            return "No entries this month"
        case 1:
            return "1 entry • \(wordCount) words"
        default:
            return "\(entries.count) entries • \(wordCount) words"
        }
    }
}
