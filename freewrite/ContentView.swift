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
import AVFoundation

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String
    let filename: String
    var previewText: String
    
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
            previewText: ""
        )
    }
}

enum SettingsTab: String, CaseIterable {
    case ai = "AI"
    case style = "Style"
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
    @State private var showingSettings = false // Add state for settings menu
    @State private var isHoveringSettings = false // Add state for settings hover
    @State private var selectedSettingsTab: SettingsTab = .ai // Add state for selected tab
    @State private var openAIAPIKey: String = ""
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let entryHeight: CGFloat = 40
    
    // 1. Add state for mic button
    @State private var isListening = false
    @State private var micDotAngle: Double = 0
    @State private var micDotTimer: Timer? = nil
    @State private var audioRecorder: AVAudioRecorder? = nil
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var transcriptionError: String? = nil
    
    // Toast notification states
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .error
    
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
                            previewText: truncated
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
                    ZStack {
                        // Bottom bar background
                        HStack {
                            // Font buttons (left)
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
                            // Utility buttons (right)
                            HStack(spacing: 8) {
                                // Button(timerButtonTitle) {
                                //     let now = Date()
                                //     if let lastClick = lastClickTime,
                                //        now.timeIntervalSince(lastClick) < 0.3 {
                                //         timeRemaining = 900
                                //         timerIsRunning = false
                                //         lastClickTime = nil
                                //     } else {
                                //         timerIsRunning.toggle()
                                //         lastClickTime = now
                                //     }
                                // }
                                // .buttonStyle(.plain)
                                // .foregroundColor(timerColor)
                                // .onHover { hovering in
                                //     isHoveringTimer = hovering
                                //     isHoveringBottomNav = hovering
                                //     if hovering {
                                //         NSCursor.pointingHand.push()
                                //     } else {
                                //         NSCursor.pop()
                                //     }
                                // }
                                // .onAppear {
                                //     NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                                //         if isHoveringTimer {
                                //             let scrollBuffer = event.deltaY * 0.25
                                        
                                //             if abs(scrollBuffer) >= 0.1 {
                                //                 let currentMinutes = timeRemaining / 60
                                //                 NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                //                 let direction = -scrollBuffer > 0 ? 5 : -5
                                //                 let newMinutes = currentMinutes + direction
                                //                 let roundedMinutes = (newMinutes / 5) * 5
                                //                 let newTime = roundedMinutes * 60
                                //                 timeRemaining = min(max(newTime, 0), 2700)
                                //             }
                                //         }
                                //         return event
                                //     }
                                // }
                                
                                // Text("•")
                                //     .foregroundColor(.gray)
                                
                                // Button("Chat") {
                                //     showingChatMenu = true
                                //     // Ensure didCopyPrompt is reset when opening the menu
                                //     didCopyPrompt = false
                                // }
                                // .buttonStyle(.plain)
                                // .foregroundColor(isHoveringChat ? textHoverColor : textColor)
                                // .onHover { hovering in
                                //     isHoveringChat = hovering
                                //     isHoveringBottomNav = hovering
                                //     if hovering {
                                //         NSCursor.pointingHand.push()
                                //     } else {
                                //         NSCursor.pop()
                                //     }
                                // }
                                // .popover(isPresented: $showingChatMenu, attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)), arrowEdge: .top) {
                                //     VStack(spacing: 0) { // Wrap everything in a VStack for consistent styling and onChange
                                //         let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                //         // Calculate potential URL lengths
                                //         let gptFullText = aiChatPrompt + "\n\n" + trimmedText
                                //         let claudeFullText = claudePrompt + "\n\n" + trimmedText
                                //         let encodedGptText = gptFullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                //         let encodedClaudeText = claudeFullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    
                                //         let gptUrlLength = "https://chat.openai.com/?m=".count + encodedGptText.count
                                //         let claudeUrlLength = "https://claude.ai/new?q=".count + encodedClaudeText.count
                                //         let isUrlTooLong = gptUrlLength > 6000 || claudeUrlLength > 6000
                                    
                                //         if isUrlTooLong {
                                //             // View for long text (URL too long)
                                //             Text("Hey, your entry is long. It'll break the URL. Instead, copy prompt by clicking below and paste into AI of your choice!")
                                //                 .font(.system(size: 14))
                                //                 .foregroundColor(popoverTextColor)
                                //                 .lineLimit(nil)
                                //                 .multilineTextAlignment(.leading)
                                //                 .frame(width: 200, alignment: .leading)
                                //                 .padding(.horizontal, 12)
                                //                 .padding(.vertical, 8)
                                        
                                //             Divider()
                                        
                                //             Button(action: {
                                //                 copyPromptToClipboard()
                                //                 didCopyPrompt = true
                                //             }) {
                                //                 Text(didCopyPrompt ? "Copied!" : "Copy Prompt")
                                //                     .frame(maxWidth: .infinity, alignment: .leading)
                                //                     .padding(.horizontal, 12)
                                //                     .padding(.vertical, 8)
                                //             }
                                //             .buttonStyle(.plain)
                                //             .foregroundColor(popoverTextColor)
                                //             .onHover { hovering in
                                //                 if hovering {
                                //                     NSCursor.pointingHand.push()
                                //                 } else {
                                //                     NSCursor.pop()
                                //                 }
                                //             }
                                        
                                //         } else if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("hi. my name is farza.") {
                                //             Text("Yo. Sorry, you can't chat with the guide lol. Please write your own entry.")
                                //                 .font(.system(size: 14))
                                //                 .foregroundColor(popoverTextColor)
                                //                 .frame(width: 250)
                                //                 .padding(.horizontal, 12)
                                //                 .padding(.vertical, 8)
                                //         } else if text.count < 350 {
                                //             Text("Please free write for at minimum 5 minutes first. Then click this. Trust.")
                                //                 .font(.system(size: 14))
                                //                 .foregroundColor(popoverTextColor)
                                //                 .frame(width: 250)
                                //                 .padding(.horizontal, 12)
                                //                 .padding(.vertical, 8)
                                //         } else {
                                //             // View for normal text length
                                //             Button(action: {
                                //                 showingChatMenu = false
                                //                 openChatGPT()
                                //             }) {
                                //                 Text("ChatGPT")
                                //                     .frame(maxWidth: .infinity, alignment: .leading)
                                //                     .padding(.horizontal, 12)
                                //                     .padding(.vertical, 8)
                                //             }
                                //             .buttonStyle(.plain)
                                //             .foregroundColor(popoverTextColor)
                                //             .onHover { hovering in
                                //                 if hovering {
                                //                     NSCursor.pointingHand.push()
                                //                 } else {
                                //                     NSCursor.pop()
                                //                 }
                                //             }
                                        
                                //             Divider()
                                        
                                //             Button(action: {
                                //                 showingChatMenu = false
                                //                 openClaude()
                                //             }) {
                                //                 Text("Claude")
                                //                     .frame(maxWidth: .infinity, alignment: .leading)
                                //                     .padding(.horizontal, 12)
                                //                     .padding(.vertical, 8)
                                //             }
                                //             .buttonStyle(.plain)
                                //             .foregroundColor(popoverTextColor)
                                //             .onHover { hovering in
                                //                 if hovering {
                                //                     NSCursor.pointingHand.push()
                                //                 } else {
                                //                     NSCursor.pop()
                                //                 }
                                //             }
                                        
                                //             Divider()
                                        
                                //             Button(action: {
                                //                 // Don't dismiss menu, just copy and update state
                                //                 copyPromptToClipboard()
                                //                 didCopyPrompt = true
                                //             }) {
                                //                 Text(didCopyPrompt ? "Copied!" : "Copy Prompt")
                                //                     .frame(maxWidth: .infinity, alignment: .leading)
                                //                     .padding(.horizontal, 12)
                                //                     .padding(.vertical, 8)
                                //             }
                                //             .buttonStyle(.plain)
                                //             .foregroundColor(popoverTextColor)
                                //             .onHover { hovering in
                                //                 if hovering {
                                //                     NSCursor.pointingHand.push()
                                //                 } else {
                                //                     NSCursor.pop()
                                //                 }
                                //             }
                                //         }
                                //     }
                                //     .frame(minWidth: 120, maxWidth: 250) // Allow width to adjust
                                //     .background(popoverBackgroundColor)
                                //     .cornerRadius(8)
                                //     .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                                //     // Reset copied state when popover dismisses
                                //     .onChange(of: showingChatMenu) { newValue in
                                //         if !newValue {
                                //             didCopyPrompt = false
                                //         }
                                //     }
                                // }
                                
                                // Text("•")
                                //     .foregroundColor(.gray)
                                
                                // Button(isFullscreen ? "Minimize" : "Fullscreen") {
                                //     if let window = NSApplication.shared.windows.first {
                                //         window.toggleFullScreen(nil)
                                //     }
                                // }
                                // .buttonStyle(.plain)
                                // .foregroundColor(isHoveringFullscreen ? textHoverColor : textColor)
                                // .onHover { hovering in
                                //     isHoveringFullscreen = hovering
                                //     isHoveringBottomNav = hovering
                                //     if hovering {
                                //         NSCursor.pointingHand.push()
                                //     } else {
                                //         NSCursor.pop()
                                //     }
                                // }
                                
                                // Text("•")
                                //     .foregroundColor(.gray)

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
                                
                                // Settings button
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingSettings = true
                                    }
                                }) {
                                    Image(systemName: "gearshape.fill")
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
                        // --- Microphone Button (centered absolutely) ---
                        GeometryReader { geo in
                            let barHeight: CGFloat = 68 // matches navHeight
                            let buttonSize: CGFloat = 40
                            let borderWidth: CGFloat = 1
                            let dotRadius: CGFloat = (buttonSize / 2) - (borderWidth / 2)
                            Button(action: {
                                toggleRecording()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(colorScheme == .light ? Color.white : Color.black)
                                        .frame(width: buttonSize, height: buttonSize)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.gray.opacity(0.45), lineWidth: borderWidth)
                                        )
                                        .shadow(color: isRecording ? Color.clear : Color.gray.opacity(0.32), radius: 12, y: 3)
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(colorScheme == .light ? .gray : .white.opacity(0.85))
                                    // Animated white dot on border
                                    if isRecording {
                                        let angle = Angle(degrees: micDotAngle)
                                        let x = dotRadius * cos(angle.radians - .pi/2)
                                        let y = dotRadius * sin(angle.radians - .pi/2)
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 9, height: 9)
                                            .offset(x: x, y: y)
                                            .shadow(color: Color.white.opacity(0.8), radius: 3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .animation(.linear(duration: 0.016), value: micDotAngle)
                            .onDisappear {
                                micDotTimer?.invalidate()
                                micDotTimer = nil
                            }
                            .position(x: geo.size.width / 2, y: barHeight / 2)
                        }
                        .frame(height: 68)
                        // --- End Microphone Button ---
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
        .overlay(
            // Settings Menu Overlay
            Group {
                if showingSettings {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingSettings = false
                            }
                        }
                    
                    SettingsModal(
                        showingSettings: $showingSettings,
                        selectedSettingsTab: $selectedSettingsTab,
                        apiKey: $openAIAPIKey
                    )
                }
            }
        )
        .overlay(
            // Toast Overlay
            toastOverlay
        )
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

    // --- Audio Recording and Whisper API ---
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        // Check API key first
        guard !openAIAPIKey.isEmpty else {
            showToast(message: "Please enter your OpenAI API key in Settings", type: .error)
            return
        }
        
        // Debug: Print the current authorization status
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        // For macOS, directly check microphone permission
        switch status {
        case .authorized:
            setupRecorder()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupRecorder()
                    } else {
                        self.showToast(message: "Microphone access denied. Please enable in System Settings.", type: .error)
                    }
                }
            }
        case .denied:
            showToast(message: "Microphone access denied. Please enable in System Settings.", type: .error)
        case .restricted:
            showToast(message: "Microphone access denied. Please enable in System Settings.", type: .error)
        @unknown default:
            showToast(message: "Unknown microphone permission status", type: .error)
        }
    }
    
    func setupRecorder() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsPath.appendingPathComponent("recording.m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            
            isRecording = true
            isListening = true
            startMicAnimation()
            // showToast(message: "Recording started", type: .success)
        } catch {
            showToast(message: "Failed to start recording: \(error.localizedDescription)", type: .error)
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isListening = false
        stopMicAnimation()
        
        if let url = audioRecorder?.url {
            showToast(message: "Processing audio...", type: .info)
            transcribeAudio(url: url)
        }
    }
    
    func transcribeAudio(url: URL) {
        guard !openAIAPIKey.isEmpty else {
            showToast(message: "Please enter your OpenAI API key in Settings", type: .error)
            return
        }
        
        isTranscribing = true
        
        // Prepare request to OpenAI Whisper
        let apiKey = openAIAPIKey
        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Prepare multipart body
        var body = Data()
        
        // Add file
        if let audioData = try? Data(contentsOf: url) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add model param
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        // Send request
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isTranscribing = false
                
                if let error = error {
                    self.showToast(message: "Network error: \(error.localizedDescription)", type: .error)
                    print("Transcription error: \(error)")
                    return
                }
                
                guard let data = data else {
                    self.showToast(message: "No response from OpenAI", type: .error)
                    print("No data returned from Whisper API")
                    return
                }
                
                // Check for API errors
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorJson["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            self.showToast(message: "OpenAI API Error: \(message)", type: .error)
                        } else {
                            self.showToast(message: "API Error: Status \(httpResponse.statusCode)", type: .error)
                        }
                        return
                    }
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], 
                   let textResult = json["text"] as? String {
                    // Insert the transcribed text at the end of current text
                    self.text += (self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " ") + textResult
                    self.showToast(message: "Text transcribed successfully", type: .success)
                } else {
                    self.showToast(message: "Failed to parse transcription response", type: .error)
                    print("Failed to parse Whisper response: \(String(data: data, encoding: .utf8) ?? "")")
                }
            }
        }.resume()
        
        // Clean up audio file
        try? FileManager.default.removeItem(at: url)
    }
    
    func showToast(message: String, type: ToastType) {
        toastMessage = message
        toastType = type
        withAnimation(.easeInOut(duration: 0.6)) {
            showToast = true
        }
        
        // Auto-hide after 3 seconds for success/info, 5 seconds for errors
        let duration: Double = type == .error ? 5.0 : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeInOut(duration: 0.6)) {
                showToast = false
            }
        }
    }
    
    func startMicAnimation() {
        micDotTimer?.invalidate()
        micDotTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            micDotAngle += 1.2
            if micDotAngle > 360 { micDotAngle -= 360 }
        }
    }
    
    func stopMicAnimation() {
        micDotTimer?.invalidate()
        micDotTimer = nil
    }
    
    // --- End Audio Recording and Whisper API ---
    
    // Computed property for toast overlay to avoid type-checking complexity
    private var toastOverlay: some View {
        Group {
            if showToast {
                ToastView(
                    message: toastMessage, 
                    type: toastType,
                    selectedFont: selectedFont,
                    fontSize: fontSize,
                    colorScheme: colorScheme
                )
                .transition(.move(edge: .top))
            }
        }
    }
}

// Add these view structs before the main ContentView struct
struct SettingsModal: View {
    @Binding var showingSettings: Bool
    @Binding var selectedSettingsTab: SettingsTab
    @Binding var apiKey: String
    
    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedTab: $selectedSettingsTab)
            SettingsContent(selectedTab: selectedSettingsTab, apiKey: $apiKey)
        }
        .frame(width: 600, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}

struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Sidebar Items
            VStack(alignment: .leading, spacing: 2) {
                SettingsSidebarItem(
                    title: "AI",
                    icon: "brain.head.profile.fill",
                    isSelected: selectedTab == .ai,
                    action: { selectedTab = .ai }
                )
                
                SettingsSidebarItem(
                    title: "Style",
                    icon: "paintpalette.fill",
                    isSelected: selectedTab == .style,
                    action: { selectedTab = .style }
                )
            }
            .padding(.horizontal, 8)
            
            Spacer()
        }
        .frame(width: 180)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct SettingsSidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16, height: 16)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(title)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsContent: View {
    let selectedTab: SettingsTab
    @Binding var apiKey: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selectedTab {
            case .ai:
                AISettingsView(apiKey: $apiKey)
            case .style:
                StyleSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

struct AISettingsView: View {
    @Binding var apiKey: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // OpenAI API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI Whisper API Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                SecureField("Enter your OpenAI API key", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: 300)
                
                Text("Your API key is stored locally and only used for transcription.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }
}

struct StyleSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Add style-specific settings here in the future
        }
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

// Add enum for toast types before ContentView struct
enum ToastType {
    case success, error, info
    
    var color: Color {
        switch self {
        case .success:
            return .green
        case .error:
            return .red
        case .info:
            return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
}



// Add ToastView component after the other view structs
struct ToastView: View {
    let message: String
    let type: ToastType
    let selectedFont: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme
    
    private var iconColor: Color {
        colorScheme == .light ? .gray : .white.opacity(0.85)
    }
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 14))
                
                Text(message)
                    .font(.custom(selectedFont, size: fontSize * 0.8)) // Slightly smaller than editor font
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            )
            .frame(maxWidth: 400) // Max width constraint
            .padding(.top, 20) // Position from top
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
