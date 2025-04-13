// Swift 5.0
//
//  ContentView.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    private let headerString = "\n\n"
    @StateObject private var themeManager = ThemeManager()
    private let fileHelper = FileManagerHelper.shared
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""  // Remove initial welcome text since we'll handle it in createNewEntry
    
    @State private var isFullscreen = false
    @State private var selectedFont: String = "Lato-Regular"
    @State private var currentRandomFont: String = ""
    @State private var timeRemaining: Int = 900  // Changed to 900 seconds (15 minutes)
    @State private var timerIsRunning = false
    @State private var isHoveringTimer = false
    @State private var isHoveringToggleTheme = false
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
    @State private var showingTimerMenu = false
    @State private var isHoveringTimeOption = false
    @AppStorage("themeType") private var savedThemeType: String = ThemeType.light.rawValue
    @AppStorage("timerOptionSelected") private var timerOptionSelected = 900 // 1500secs (25 mins); 900secs (15 mins); 600secs (10 mins); 300secs (5 mins)
//    @AppStorage("startTimerOnWritting") private var startTimerOnWritting = false
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
    
    // documents directory
    var documentsDirectory: URL {
        return fileHelper.getDocumentsDirectory()
    }
    
    // Add file manager and save timer
    private let fileManager = FileManager.default
    private let saveTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
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
    
    // Add function to save text
    private func saveText() {
        let documentsDirectory = documentsDirectory
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
        let documentsDirectory = documentsDirectory
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
        fileHelper.loadExistingEntries(
            onSuccess: { loadedEntries, fullContents in
                entries = loadedEntries
                print("Successfully loaded \(entries.count) entries")
                
                let calendar = Calendar.current
                let today = Date()
                let todayStart = calendar.startOfDay(for: today)
                
                let hasEmptyEntryToday = entries.contains { entry in
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMM d"
                    if let date = formatter.date(from: entry.date) {
                        var components = calendar.dateComponents([.year, .month, .day], from: date)
                        components.year = calendar.component(.year, from: today)
                        if let fullDate = calendar.date(from: components) {
                            return calendar.isDate(fullDate, inSameDayAs: todayStart) && entry.previewText.isEmpty
                        }
                    }
                    return false
                }
                
                let hasOnlyWelcomeEntry = entries.count == 1 && fullContents[entries[0].id]?.contains("Welcome to Freewrite.") == true
                
                if entries.isEmpty {
                    fileHelper.createNewEntry(
                        isFirstEntry: true,
                        placeholderOptions: placeholderOptions,
                        onSuccess: { newEntry, entryText, placeholder in
                            entries.insert(newEntry, at: 0)
                            selectedEntryId = newEntry.id
                            text = entryText
                            placeholderText = placeholder ?? "\n\nBegin writing"
                            updatePreviewText(for: newEntry)
                        }
                    )
                } else if !hasEmptyEntryToday && !hasOnlyWelcomeEntry {
                    fileHelper.createNewEntry(
                        isFirstEntry: false,
                        placeholderOptions: placeholderOptions,
                        onSuccess: { newEntry, entryText, placeholder in
                            entries.insert(newEntry, at: 0)
                            selectedEntryId = newEntry.id
                            text = entryText
                            placeholderText = placeholder ?? "\n\nBegin writing"
                            updatePreviewText(for: newEntry)
                        }
                    )
                } else {
                    // Select the most relevant existing entry
                    if let todayEntry = entries.first(where: { entry in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMM d"
                        if let date = formatter.date(from: entry.date) {
                            var components = calendar.dateComponents([.year, .month, .day], from: date)
                            components.year = calendar.component(.year, from: today)
                            if let fullDate = calendar.date(from: components) {
                                return calendar.isDate(fullDate, inSameDayAs: todayStart) && entry.previewText.isEmpty
                            }
                        }
                        return false
                    }) {
                        selectedEntryId = todayEntry.id
                        fileHelper.loadEntry(todayEntry) { loadedText in
                            text = loadedText
                        }
                    } else if hasOnlyWelcomeEntry {
                        selectedEntryId = entries[0].id
                        fileHelper.loadEntry(entries[0]) { loadedText in
                            text = loadedText
                        }
                    }
                }
            },
            onError: { error in
                print("Error loading entries: \(error.localizedDescription)")
                fileHelper.createNewEntry(
                    isFirstEntry: true,
                    placeholderOptions: placeholderOptions,
                    onSuccess: { newEntry, entryText, placeholder in
                        entries.insert(newEntry, at: 0)
                        selectedEntryId = newEntry.id
                        text = entryText
                        placeholderText = placeholder ?? "\n\nBegin writing"
                        updatePreviewText(for: newEntry)
                    }
                )
            }
        )
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
        return isHoveringTimer ? .black : .gray
    }
    
    var timerOptionColor: Color {
        return isHoveringTimeOption ? .black  :  .gray
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
                themeManager.currentTheme.background
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
                .background(themeManager.currentTheme.background)
                    .font(.custom(selectedFont, size: fontSize))
                    .foregroundColor(themeManager.currentTheme is LightTheme ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .lineSpacing(lineHeight)
                    .frame(maxWidth: 650)
                    .id("\(selectedFont)-\(fontSize)")
                    .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                    .ignoresSafeArea()
                    .colorScheme(.dark)
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
                                    .foregroundColor(.gray.opacity(0.5))
                                    // .padding(.top, 8)
                                    // .padding(.leading, 8)
                                    .allowsHitTesting(false)
                                    .offset(x: 5, y: placeholderOffset)
                            }
                        }, alignment: .topLeading
                    )
                
                VStack {
                    Spacer()
                    BottomActionsView()
                }
            }
            
            // Right sidebar
            if showingSidebar {
                Divider()
                SidebarView(
                    isHoveringHistory: $isHoveringHistory,
                    entries: entries,
                    selectedEntryId: $selectedEntryId,
                    hoveredEntryId: $hoveredEntryId,
                    hoveredTrashId: $hoveredTrashId,
                    onSaveEntry: saveEntry,
                    onLoadEntry: loadEntry,
                    onDeleteEntry: deleteEntry
                )
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: showingSidebar)
        .preferredColorScheme(.light)
        .onAppear {
            showingSidebar = false  // Hide sidebar by default
            timeRemaining = timerOptionSelected
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
    
    @ViewBuilder
    func BottomActionsView () -> some View {
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
                .foregroundColor(isHoveringSize ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                .foregroundColor(hoveredFont == "Lato" ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                .foregroundColor(hoveredFont == "Arial" ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                .foregroundColor(hoveredFont == "System" ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                .foregroundColor(hoveredFont == "Serif" ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                .foregroundColor(hoveredFont == "Random" ?  themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                
                Button{
                    themeManager.switchTheme()
                } label: {
                    Image(systemName: themeManager.currentTheme is LightTheme ? "sun.max.fill" : "moon.fill")
                        .onHover { hovering in
                            isHoveringToggleTheme = hovering
                            isHoveringBottomNav = hovering
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .buttonStyle(.plain)
                .foregroundColor(
                    isHoveringToggleTheme ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary
                )
                
                Text("•")
                    .foregroundColor(.gray)
                
                HStack {
                    Button{
                        showingTimerMenu = true
                        timerIsRunning = false
                    } label: {
                        Image(systemName: "chevron.up")
                            .onHover { hovering in
                                isHoveringTimer = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                    }
                    .foregroundColor(isHoveringTimer ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingTimerMenu, attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)), arrowEdge: .top) {
                            VStack(spacing: 0) {
                                Button(action: {
                                    showingTimerMenu = false
                                    timerOptionSelected = 1500 // 25 mins
                                    timeRemaining = 1500
                                    timerIsRunning = false
                                }) {
                                    Text("25:00")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(
                                    timerOptionSelected == 1500 ? .black:timerOptionColor
                                )
                                .onHover { hovering in
                                    timerOptionSelected = 1500
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                        timerOptionSelected = timeRemaining
                                    }
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    showingTimerMenu = false
                                    timerOptionSelected = 900
                                    timeRemaining = 900
                                    timerIsRunning = false
                                }) {
                                    Text("15:00")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(
                                    timerOptionSelected == 900 ? .black:timerOptionColor
                                )
                                .onHover { hovering in
                                    timerOptionSelected = 900
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                        timerOptionSelected = timeRemaining
                                    }
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    showingTimerMenu = false
                                    timerOptionSelected = 600
                                    timeRemaining = 600
                                    timerIsRunning = false
                                }) {
                                    Text("10:00")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(
                                    timerOptionSelected == 600 ? .black:timerOptionColor
                                )
                                .onHover { hovering in
                                    timerOptionSelected = 600
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                        timerOptionSelected = timeRemaining
                                    }
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    showingTimerMenu = false
                                    timerOptionSelected = 300
                                    timeRemaining = 300
                                    timerIsRunning = false
                                }) {
                                    Text("05:00")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(
                                    timerOptionSelected == 300 ? .black:timerOptionColor
                                )
                                .onHover { hovering in
                                    timerOptionSelected = 300
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                        timerOptionSelected = timeRemaining
                                    }
                                }
                                
//                                maybe auto-start timer option on writting, future¿?
//                                Toggle(
//                                    "Auto-start timer",
//                                    isOn: $startTimerOnWritting
//                                )
//                                .padding(
//                                    .horizontal,
//                                    12
//                                )
//                                .padding(
//                                    .vertical,
//                                    8
//                                )
//                                .onHover { hovering in
//                                    if hovering {
//                                        NSCursor.pointingHand
//                                            .push()
//                                    } else {
//                                        NSCursor
//                                            .pop()
//                                                timerOptionSelected = timeRemaining
//                                            }
//                                        }
                            }
                            .frame(width: 120)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                        
                    }
                    
                   
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
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .buttonStyle(.plain)
                    .foregroundColor(isHoveringTimer ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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

                }
                
                Text("•")
                    .foregroundColor(.gray)
                
                Button("Chat") {
                    showingChatMenu = true
                }
                .buttonStyle(.plain)
                .foregroundColor(isHoveringChat ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .buttonStyle(.plain)
                .foregroundColor(isHoveringFullscreen ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .buttonStyle(.plain)
                .foregroundColor(isHoveringNewEntry ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
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
                        .foregroundColor(isHoveringClock ? themeManager.currentTheme.hoverColor: themeManager.currentTheme.textSecondary)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
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
        .background(themeManager.currentTheme.background)
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
    
    private func updatePreviewText(for entry: HumanEntry) {
        let documentsDirectory = documentsDirectory
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
        fileHelper.saveEntry(entry, withText: text, onSuccess: {
            updatePreviewText(for: entry)
        }, onError: { error in
            print("Save failed: \(error.localizedDescription)")
        })
    }
    
    private func loadEntry(entry: HumanEntry) {
        fileHelper.loadEntry(entry, onSuccess: { loadedText in
            text = loadedText
        }, onError: { error in
            print("Failed to load entry: \(error.localizedDescription)")
        })
    }
    
    private func createNewEntry() {
        fileHelper.createNewEntry(
            isFirstEntry: entries.isEmpty,
            placeholderOptions: placeholderOptions,
            onSuccess: { newEntry, entryText, placeholder in
                entries.insert(newEntry, at: 0)
                selectedEntryId = newEntry.id
                text = entryText
                placeholderText = placeholder ?? "\n\nBegin writing"
                updatePreviewText(for: newEntry)
            },
            onError: { error in
                print("Failed to create new entry: \(error.localizedDescription)")
            }
        )
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
        fileHelper.deleteEntry(entry, onSuccess: {
            // Remove from entries list
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: index)
                
                // Update selection
                if selectedEntryId == entry.id {
                    if let first = entries.first {
                        selectedEntryId = first.id
                        fileHelper.loadEntry(first, onSuccess: { loadedText in
                            text = loadedText
                        })
                    } else {
                        fileHelper.createNewEntry(
                            isFirstEntry: true,
                            placeholderOptions: placeholderOptions,
                            onSuccess: { newEntry, entryText, placeholder in
                                entries.insert(newEntry, at: 0)
                                selectedEntryId = newEntry.id
                                text = entryText
                                placeholderText = placeholder ?? "\n\nBegin writing"
                                updatePreviewText(for: newEntry)
                            }
                        )
                    }
                }
            }
        }, onError: { error in
            print("Failed to delete entry: \(error.localizedDescription)")
        })

    }
}

#Preview {
    ContentView()
}
