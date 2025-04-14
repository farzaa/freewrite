// Swift 5.0
//
//  ContentView.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String
    let filename: String
    var previewText: String
    var tags: [String]
    
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
            tags: []
        )
    }
}

struct HeartEmoji: Identifiable {
    let id = UUID()
    var position: CGPoint
    var offset: CGFloat = 0
}

struct TagView: View {
    let tag: String
    let isSelected: Bool
    let onDelete: () -> Void
    @State private var isHovering: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 12))
                .padding(.leading, 6)
                .padding(.trailing, isHovering ? 2 : 6)
                .padding(.vertical, 2)
            
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .padding(.vertical, 2)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.gray.opacity(0.2) : (isHovering ? Color.gray.opacity(0.15) : Color.gray.opacity(0.1)))
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .foregroundColor(isHovering ? .primary : .secondary)
        .onHover { hovering in
            isHovering = hovering
        }
    }
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
    @State private var placeholderText: String = ""  // Add this line
    @State private var isHoveringNewEntry = false
    @State private var isHoveringClock = false
    @State private var isHoveringHistory = false
    @State private var isHoveringHistoryText = false
    @State private var isHoveringHistoryPath = false
    @State private var isHoveringHistoryArrow = false
    @State private var newTagText: String = ""
    @State private var isAddingTag: Bool = false
    @State private var selectedTags: Set<String> = []
    @State private var showTagControls: Bool = false
    @State private var availableTags: Set<String> = []
    @State private var isHoveringTagButton: Bool = false

    @State private var entryToDelete: HumanEntry? = nil
    @State private var showingDeleteConfirmation = false
    @State private var isDarkMode: Bool = false // Add dark mode state
    @State private var isHoveringDarkMode: Bool = false // Add state for dark mode button hover
    @State private var isHoveringWordCount: Bool = false // Add state for word count hover
    @State private var isHoveringClose: Bool = false // Add state for close button hover

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
    
    // Metadata structure for entries
    struct EntryMetadata: Codable {
        var tags: [String]
        
        static func defaultMetadata() -> EntryMetadata {
            return EntryMetadata(tags: [])
        }
    }
    
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
    
    // Modify getDocumentsDirectory to use cached value
    private func getDocumentsDirectory() -> URL {
        return documentsDirectory
    }
    
    // Add function to get metadata file URL for an entry
    private func getMetadataURL(for filename: String) -> URL {
        return getDocumentsDirectory().appendingPathComponent(filename + ".metadata.json")
    }
    
    // Add function to load metadata for an entry
    private func loadMetadata(for entry: HumanEntry) -> EntryMetadata {
        let metadataURL = getMetadataURL(for: entry.filename)
        
        do {
            if fileManager.fileExists(atPath: metadataURL.path) {
                let data = try Data(contentsOf: metadataURL)
                let metadata = try JSONDecoder().decode(EntryMetadata.self, from: data)
                return metadata
            }
        } catch {
            print("Error loading metadata: \(error)")
        }
        
        return EntryMetadata.defaultMetadata()
    }
    
    // Add function to save metadata for an entry
    private func saveMetadata(for entry: HumanEntry, metadata: EntryMetadata) {
        let metadataURL = getMetadataURL(for: entry.filename)
        
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
            print("Successfully saved metadata for: \(entry.filename)")
        } catch {
            print("Error saving metadata: \(error)")
        }
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
    
    // Update loadExistingEntries to include tags
    private func loadExistingEntries() {
        let documentsDirectory = getDocumentsDirectory()
        print("Looking for entries in: \(documentsDirectory.path)")
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            let mdFiles = fileURLs.filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasSuffix(".metadata.json") }
            
            print("Found \(mdFiles.count) .md files")
            
            // Collect all available tags
            var allTags = Set<String>()
            
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
                    
                    // Load metadata and tags
                    let metadata = loadMetadata(for: HumanEntry(id: uuid, date: displayDate, filename: filename, previewText: "", tags: []))
                    
                    // Add tags to available tags
                    metadata.tags.forEach { allTags.insert($0) }
                    
                    return (
                        entry: HumanEntry(
                            id: uuid,
                            date: displayDate,
                            filename: filename,
                            previewText: truncated,
                            tags: metadata.tags
                        ),
                        date: fileDate,
                        content: content  // Store the full content to check for welcome message
                    )
                } catch {
                    print("Error reading file: \(error)")
                    return nil
                }
            }
            
            // Update available tags
            availableTags = allTags
            
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
        if timerIsRunning && !isHoveringTimer {
            return .gray
        }
        return isHoveringTimer ? (isDarkMode ? .white : .black) : .gray
    }
    
    var wordCount: String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return "\(words.count) words"
    }
    
    var lineHeight: CGFloat {
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let defaultLineHeight = font.defaultLineHeight()
        return (fontSize * 1.5) - defaultLineHeight
    }
    
    var fontSizeButtonTitle: String {
        return "\(Int(fontSize))px"
    }
    
    var placeholderOffset: CGFloat {
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let defaultLineHeight = font.defaultLineHeight()
        // Account for two newlines plus a small adjustment for visual alignment
        // return (defaultLineHeight * 2) + 2
        return fontSize / 2 
    }
    
    var body: some View {
        let buttonBackground = Color.white
        let navHeight: CGFloat = 68
        
        HStack(spacing: 0) {
            // Main content
            ZStack {
                // Background color based on dark mode
                (isDarkMode ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.white)
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
                    .background(isDarkMode ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.white)
                    .font(.custom(selectedFont, size: fontSize))
                    .foregroundColor(isDarkMode ? Color(red: 0.9, green: 0.9, blue: 0.9) : Color(red: 0.20, green: 0.20, blue: 0.20))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .lineSpacing(lineHeight)
                    .frame(maxWidth: 650)
                    .id("\(selectedFont)-\(fontSize)-\(isDarkMode)")
                    .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                    .ignoresSafeArea()
                    .colorScheme(isDarkMode ? .dark : .light)
                    .onAppear {
                        placeholderText = placeholderOptions.randomElement() ?? "\n\nBegin writing"
                        DispatchQueue.main.async {
                            if let scrollView = NSApp.keyWindow?.contentView?.findSubview(ofType: NSScrollView.self) {
                                scrollView.hasVerticalScroller = false
                                scrollView.hasHorizontalScroller = false
                            }
                        }
                    }
                    .overlay(
                        ZStack(alignment: .topLeading) {
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(placeholderText)
                                    .font(.custom(selectedFont, size: fontSize))
                                    .foregroundColor(isDarkMode ? .gray.opacity(0.6) : .gray.opacity(0.5))
                                    .allowsHitTesting(false)
                                    .offset(x: 5, y: placeholderOffset)
                            }
                        }, alignment: .topLeading
                    )
                
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
                            .foregroundColor(isHoveringSize ? (isDarkMode ? .white : .black) : .gray)
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
                            .foregroundColor(hoveredFont == "Lato" ? (isDarkMode ? .white : .black) : .gray)
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
                            .foregroundColor(hoveredFont == "Arial" ? (isDarkMode ? .white : .black) : .gray)
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
                            .foregroundColor(hoveredFont == "System" ? (isDarkMode ? .white : .black) : .gray)
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
                            .foregroundColor(hoveredFont == "Serif" ? (isDarkMode ? .white : .black) : .gray)
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
                            .foregroundColor(hoveredFont == "Random" ? (isDarkMode ? .white : .black) : .gray)
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
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringChat ? (isDarkMode ? .white : .black) : .gray)
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
                                if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("hi. my name is farza.") {
                                    Text("Yo. Sorry, you can't chat with the guide lol. Please write your own entry.")
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .frame(width: 250)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                                } else if text.count < 350 {
                                    Text("Please free write for at minimum 5 minutes first. Then click this. Trust.")
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .frame(width: 250)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                                } else {
                                    VStack(spacing: 0) {
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
                                        .foregroundColor(.primary)
                                        
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
                                        .foregroundColor(.primary)
                                    }
                                    .frame(width: 120)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
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
                            .foregroundColor(isHoveringFullscreen ? (isDarkMode ? .white : .black) : .gray)
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
                            .foregroundColor(isHoveringNewEntry ? (isDarkMode ? .white : .black) : .gray)
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
                            
                            // Version history button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingSidebar.toggle()
                                }
                            }) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(isHoveringClock ? (isDarkMode ? .white : .black) : .gray)
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
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            // Tags button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingSidebar.toggle()
                                    if showingSidebar {
                                        showTagControls = true
                                    }
                                }
                            }) {
                                Image(systemName: "tag")
                                    .foregroundColor(isHoveringTagButton ? (isDarkMode ? .white : .black) : .gray)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringTagButton = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            // Add Dark Mode Toggle button
                            Button(action: {
                                isDarkMode.toggle()
                            }) {
                                Image(systemName: isDarkMode ? "sun.max" : "moon")
                                    .foregroundColor(isHoveringDarkMode ? (isDarkMode ? .white : .black) : .gray)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringDarkMode = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                                
                            // Word count
                            Text(wordCount)
                                .font(.system(size: 13))
                                .foregroundColor(isHoveringWordCount ? (isDarkMode ? .white : .black) : .gray)
                                .onHover { hovering in
                                    isHoveringWordCount = hovering
                                    isHoveringBottomNav = hovering
                                    if hovering {
                                        NSCursor.arrow.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                
                            Text("•")
                                .foregroundColor(.gray)
                                
                            // Close button
                            Button(action: {
                                NSApplication.shared.terminate(nil)
                            }) {
                                Text("Close")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringClose ? (isDarkMode ? .white : .black) : .gray)
                            .onHover { hovering in
                                isHoveringClose = hovering
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
                    .background(isDarkMode ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color.white)
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
                                        .foregroundColor(isHoveringHistory ? (isDarkMode ? .white : .black) : .secondary)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(isHoveringHistory ? (isDarkMode ? .white : .black) : .secondary)
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
                    
                    // Tags filtering section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tags")
                                .font(.system(size: 13, weight: .medium))
                            
                            Spacer()
                            
                            Button(action: {
                                showTagControls.toggle()
                            }) {
                                Image(systemName: showTagControls ? "minus" : "plus")
                                    .font(.system(size: 10))
                                    .foregroundColor(isHoveringTagButton ? .black : .gray)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringTagButton = hovering
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        
                        // Tag filter buttons - Replace ScrollView with FlowLayout
                        FlowLayout(spacing: 6) {
                            ForEach(Array(availableTags).sorted(), id: \.self) { tag in
                                Button(action: {
                                    if selectedTags.contains(tag) {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                }) {
                                    Text(tag)
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(selectedTags.contains(tag) ? 
                                                    (isDarkMode ? Color.gray.opacity(0.4) : Color.gray.opacity(0.3)) : 
                                                    (isDarkMode ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)))
                                        )
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        
                        // Tag controls for current entry
                        if showTagControls, let currentId = selectedEntryId, let index = entries.firstIndex(where: { $0.id == currentId }) {
                            VStack(spacing: 6) {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                // Title for tags section
                                Text("Tags for this entry")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Current entry tags
                                FlowLayout(spacing: 6) {
                                    ForEach(entries[index].tags.sorted(), id: \.self) { tag in
                                        TagView(tag: tag, isSelected: false) {
                                            removeTagFromCurrentEntry(tag)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                
                                // Add new tag
                                HStack {
                                    TextField("New tag", text: $newTagText)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.system(size: 12))
                                        .onSubmit {
                                            if !newTagText.isEmpty {
                                                addTagToCurrentEntry(newTagText)
                                                newTagText = ""
                                            }
                                        }
                                    
                                    Button(action: {
                                        if !newTagText.isEmpty {
                                            addTagToCurrentEntry(newTagText)
                                            newTagText = ""
                                        }
                                    }) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(newTagText.isEmpty)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                    
                    Divider()
                    
                    // Entries List
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filterEntriesByTags()) { entry in
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
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.previewText)
                                                    .font(.system(size: 13))
                                                    .lineLimit(1)
                                                    .foregroundColor(.primary)
                                                Text(entry.date)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            
                                            // Trash icon that appears on hover
                                            if hoveredEntryId == entry.id {
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
                                        
                                        // Tags for the entry
                                        if !entry.tags.isEmpty {
                                            FlowLayout(spacing: 4) {
                                                ForEach(entry.tags.sorted().prefix(3), id: \.self) { tag in
                                                    Text(tag)
                                                        .font(.system(size: 10))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 2)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 2)
                                                                .fill(Color.gray.opacity(0.1))
                                                        )
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                if entry.tags.count > 3 {
                                                    Text("+\(entry.tags.count - 3)")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
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
                                
                                if entry.id != filterEntriesByTags().last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .frame(width: 200)
                .background(isDarkMode ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: showingSidebar)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .confirmationDialog(
            "Are you sure you want to delete this entry?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    performDeleteEntry(entry: entry)
                    entryToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
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
    
    private func backgroundColor(for entry: HumanEntry) -> Color {
        if entry.id == selectedEntryId {
            return isDarkMode ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)  // Adjust for dark mode
        } else if entry.id == hoveredEntryId {
            return isDarkMode ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05)  // Adjust for dark mode
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
            
            // Save metadata
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                let metadata = EntryMetadata(tags: entries[index].tags)
                saveMetadata(for: entry, metadata: metadata)
            }
            
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
                
                // Load metadata for the entry
                let metadata = loadMetadata(for: entry)
                
                // Update entry tags in the entries array
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index].tags = metadata.tags
                }
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
    
    private func deleteEntry(entry: HumanEntry) {
        entryToDelete = entry
        showingDeleteConfirmation = true
    }
    
    private func performDeleteEntry(entry: HumanEntry) {
        // Delete the file from the filesystem
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        let metadataURL = getMetadataURL(for: entry.filename)
        
        do {
            try fileManager.removeItem(at: fileURL)
            print("Successfully deleted file: \(entry.filename)")
            
            // Delete metadata file if it exists
            if fileManager.fileExists(atPath: metadataURL.path) {
                try fileManager.removeItem(at: metadataURL)
                print("Successfully deleted metadata file for: \(entry.filename)")
            }
            
            // Remove the entry from the entries array
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                // Remove tags from available tags if they're not used in other entries
                for tag in entries[index].tags {
                    let isTagUsedElsewhere = entries.filter { $0.id != entry.id }.contains { $0.tags.contains(tag) }
                    if !isTagUsedElsewhere {
                        availableTags.remove(tag)
                    }
                }
                
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
    
    private func addTagToCurrentEntry(_ tag: String) {
        guard let currentId = selectedEntryId,
              let index = entries.firstIndex(where: { $0.id == currentId }),
              !tag.isEmpty,
              !entries[index].tags.contains(tag) else {
            return
        }
        
        // Add tag to entry
        entries[index].tags.append(tag)
        
        // Add to available tags if not present
        availableTags.insert(tag)
        
        // Save metadata
        let metadata = EntryMetadata(tags: entries[index].tags)
        saveMetadata(for: entries[index], metadata: metadata)
    }
    
    private func removeTagFromCurrentEntry(_ tag: String) {
        guard let currentId = selectedEntryId,
              let index = entries.firstIndex(where: { $0.id == currentId }) else {
            return
        }
        
        // Remove tag from entry
        entries[index].tags.removeAll { $0 == tag }
        
        // Save metadata
        let metadata = EntryMetadata(tags: entries[index].tags)
        saveMetadata(for: entries[index], metadata: metadata)
    }
    
    private func filterEntriesByTags() -> [HumanEntry] {
        guard !selectedTags.isEmpty else {
            return entries
        }
        
        return entries.filter { entry in
            !Set(entry.tags).isDisjoint(with: selectedTags)
        }
    }
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

// Helper extension to get default line height
extension NSFont {
    func defaultLineHeight() -> CGFloat {
        return self.ascender - self.descender + self.leading
    }
}

// Add helper extension at the bottom of the file
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

// Add FlowLayout for wrapping tags
struct FlowLayout: Layout {
    var spacing: CGFloat
    var alignment: HorizontalAlignment = .leading
    
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        
        var rowWidths: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        var currentRow = 0
        
        // Calculate rows and their dimensions
        for size in sizes {
            if rowWidths[currentRow] + size.width + (rowWidths[currentRow] > 0 ? spacing : 0) <= maxWidth {
                // Add to current row
                rowWidths[currentRow] += size.width + (rowWidths[currentRow] > 0 ? spacing : 0)
                rowHeights[currentRow] = max(rowHeights[currentRow], size.height)
            } else {
                // Start new row
                currentRow += 1
                rowWidths.append(size.width)
                rowHeights.append(size.height)
            }
        }
        
        // Calculate total height with spacing between rows
        let totalHeight = rowHeights.reduce(0, +) + CGFloat(max(0, rowHeights.count - 1)) * spacing
        
        return CGSize(width: maxWidth, height: totalHeight)
    }
    
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = bounds.width
        
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        
        // Place each subview
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            
            // Check if we need to move to next row
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            
            // Place the view
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            
            // Update position and row height
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    ContentView()
}

