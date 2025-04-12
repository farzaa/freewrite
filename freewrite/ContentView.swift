// Swift 5.0
//
//  ContentView.swift
//  freewrite
//i
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit

// MARK: - Data Models
struct HumanEntry: Identifiable {
    let id: UUID
    let date: String // Display date (e.g., "Apr 11")
    let filename: String
    var previewText: String

    static func createNew() -> HumanEntry {
        let id = UUID()
        let now = Date()
        let dateFormatter = DateFormatter()

        // For filename (precise timestamp)
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let filenameDateString = dateFormatter.string(from: now)

        // For display
        dateFormatter.dateFormat = "MMM d"
        let displayDate = dateFormatter.string(from: now)

        return HumanEntry(
            id: id,
            date: displayDate,
            filename: "[\(id)]-[\(filenameDateString)].md",
            previewText: ""
        )
    }
}

struct HeartEmoji: Identifiable {
    let id = UUID()
    var position: CGPoint
    var offset: CGFloat = 0
}

// MARK: - Main Content View
struct ContentView: View {
    // MARK: - State Variables
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""
    @State private var selectedEntryId: UUID? = nil

    // UI State
    @State private var isDarkMode = false // Dark Mode Toggle State
    @State private var isFullscreen = false
    @State private var selectedFont: String = "Lato-Regular"
    @State private var currentRandomFont: String = ""
    @State private var fontSize: CGFloat = 18
    @State private var bottomNavOpacity: Double = 1.0
    @State private var showingSidebar = false
    @State private var placeholderText: String = ""

    // Timer State
    @State private var timeRemaining: Int = 900 // 15 minutes
    @State private var timerIsRunning = false
    @State private var lastClickTime: Date? = nil

    // Hover States
    @State private var isHoveringTimer = false
    @State private var isHoveringFullscreen = false
    @State private var hoveredFont: String? = nil
    @State private var isHoveringSize = false
    @State private var isHoveringBottomNav = false
    @State private var hoveredEntryId: UUID? = nil
    @State private var isHoveringChat = false
    @State private var hoveredTrashId: UUID? = nil
    @State private var isHoveringNewEntry = false
    @State private var isHoveringClock = false
    @State private var isHoveringHistory = false
    @State private var isHoveringDarkModeToggle = false

    // Popover State
    @State private var showingChatMenu = false

    // Timers & Constants
    private let headerString = "\n\n"
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let saveTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect() // Auto-save
    let entryHeight: CGFloat = 40
    let availableFonts = NSFontManager.shared.availableFontFamilies
    let standardFonts = ["Lato-Regular", "Arial", ".AppleSystemUIFont", "Times New Roman"]
    let fontSizes: [CGFloat] = [16, 18, 20, 22, 24, 26]
    let placeholderOptions = [
        "\n\nBegin writing", "\n\nPick a thought and go", "\n\nStart typing",
        "\n\nWhat's on your mind", "\n\nJust start", "\n\nType your first thought",
        "\n\nStart with one sentence", "\n\nJust say it"
    ]

    // File Management
    private let fileManager = FileManager.default
    private let documentsDirectory: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Freewrite")
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

    // AI Prompts
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

    // MARK: - Dynamic Colors (Dark Mode Support)
    var backgroundColor: Color { isDarkMode ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color.white }
    var textColor: Color { isDarkMode ? Color.white.opacity(0.9) : Color(red: 0.20, green: 0.20, blue: 0.20) }
    var secondaryTextColor: Color { .secondary } // Adapts automatically
    var buttonIdleColor: Color { .gray } // Often works well in both modes
    var buttonHoverColor: Color { isDarkMode ? .white : .black }
    var placeholderColor: Color { isDarkMode ? Color.gray.opacity(0.6) : Color.gray.opacity(0.5) }
    var sidebarBackgroundColor: Color { Color(NSColor.windowBackgroundColor) } // Adapts
    var popoverBackgroundColor: Color { Color(NSColor.controlBackgroundColor) } // Adapts
    var dividerColor: Color { Color(NSColor.separatorColor) } // Adapts

    // MARK: - Computed Properties
    var randomButtonTitle: String {
        currentRandomFont.isEmpty ? "Random" : "Random [\(currentRandomFont)]"
    }

    var timerButtonTitle: String {
        if !timerIsRunning && timeRemaining == 900 { return "15:00" }
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var timerColor: Color {
        if timerIsRunning && !isHoveringTimer { return buttonIdleColor }
        return isHoveringTimer ? buttonHoverColor : buttonIdleColor
    }

    var lineHeight: CGFloat {
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let defaultLineHeight = font.defaultLineHeight()
        return (fontSize * 1.5) - defaultLineHeight // Adjust line spacing relative to font size
    }

    var fontSizeButtonTitle: String { "\(Int(fontSize))px" }

    var placeholderOffset: CGFloat { fontSize / 2 } // Simplified offset calculation

    // MARK: - Body
    var body: some View {
        let navHeight: CGFloat = 68

        HStack(spacing: 0) {
            // Main content
            ZStack {
                backgroundColor // Use dynamic background color
                    .ignoresSafeArea()

                TextEditor(text: Binding(
                    get: { text },
                    set: { newValue in
                        // Ensure the text always starts with two newlines
                        if !newValue.hasPrefix(headerString) {
                            text = headerString + newValue.trimmingCharacters(in: .newlines)
                        } else {
                            text = newValue
                        }
                    }
                ))
                    .background(backgroundColor) // Use dynamic background color
                    .font(.custom(selectedFont, size: fontSize))
                    .foregroundColor(textColor) // Use dynamic text color
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .lineSpacing(lineHeight)
                    .frame(maxWidth: 650) // Limit width for readability
                    .id("\(selectedFont)-\(fontSize)") // Force redraw on font/size change
                    .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                    .ignoresSafeArea(.container, edges: .bottom) // Ignore safe area only at the bottom for nav overlap
                    .colorScheme(isDarkMode ? .dark : .light) // Hint for system components within TextEditor
                    .onAppear {
                        placeholderText = placeholderOptions.randomElement() ?? "\n\nBegin writing"
                        // Remove scrollbars (might need adjustment depending on macOS version)
                        DispatchQueue.main.async {
                            if let scrollView = NSApp.keyWindow?.contentView?.findSubview(ofType: NSScrollView.self) {
                                scrollView.hasVerticalScroller = false
                                scrollView.hasHorizontalScroller = false
                            }
                        }
                    }
                    .overlay( // Placeholder Text
                        ZStack(alignment: .topLeading) {
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(placeholderText)
                                    .font(.custom(selectedFont, size: fontSize))
                                    .foregroundColor(placeholderColor) // Use dynamic placeholder color
                                    .allowsHitTesting(false)
                                    .offset(x: 5, y: placeholderOffset) // Position placeholder accurately
                            }
                        }, alignment: .topLeading
                    )

                // Bottom Navigation Bar
                VStack {
                    Spacer()
                    HStack {
                        // Font Controls (Left)
                        HStack(spacing: 8) {
                            // Font Size Cycle Button
                            Button(fontSizeButtonTitle) { cycleFontSize() }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringSize ? buttonHoverColor : buttonIdleColor)
                                .onHover { hovering in handleHover(&isHoveringSize, hovering) }

                            Text("•").foregroundColor(secondaryTextColor)

                            // Standard Font Buttons
                            fontButton("Lato", fontName: "Lato-Regular")
                            Text("•").foregroundColor(secondaryTextColor)
                            fontButton("Arial", fontName: "Arial")
                            Text("•").foregroundColor(secondaryTextColor)
                            fontButton("System", fontName: ".AppleSystemUIFont")
                            Text("•").foregroundColor(secondaryTextColor)
                            fontButton("Serif", fontName: "Times New Roman")
                            Text("•").foregroundColor(secondaryTextColor)

                            // Random Font Button
                            Button(randomButtonTitle) { setRandomFont() }
                                .buttonStyle(.plain)
                                .foregroundColor(hoveredFont == "Random" ? buttonHoverColor : buttonIdleColor)
                                .onHover { hovering in handleHover(&hoveredFont, "Random", hovering) }
                        }
                        .padding(8)
                        .cornerRadius(6)
                        .onHover { hovering in isHoveringBottomNav = hovering }

                        Spacer()

                        // Utility Controls (Right)
                        HStack(spacing: 8) {
                            // Timer Button
                            Button(timerButtonTitle) { toggleTimer() }
                                .buttonStyle(.plain)
                                .foregroundColor(timerColor) // Dynamic timer color
                                .onHover { hovering in handleHover(&isHoveringTimer, hovering) }
                                .onAppear { setupScrollWheelMonitor() } // Monitor scroll wheel for timer adjust

                            Text("•").foregroundColor(secondaryTextColor)

                            // Chat Button
                            Button("Chat") { showingChatMenu = true }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringChat ? buttonHoverColor : buttonIdleColor)
                                .onHover { hovering in handleHover(&isHoveringChat, hovering) }
                                .popover(isPresented: $showingChatMenu, attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)), arrowEdge: .top) {
                                    chatPopoverContent() // Extracted popover view logic
                                }

                            Text("•").foregroundColor(secondaryTextColor)

                            // Fullscreen Button
                            Button(isFullscreen ? "Minimize" : "Fullscreen") { toggleFullscreen() }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringFullscreen ? buttonHoverColor : buttonIdleColor)
                                .onHover { hovering in handleHover(&isHoveringFullscreen, hovering) }

                            Text("•").foregroundColor(secondaryTextColor)
                            
                            // Dark Mode Toggle
                            Toggle(isOn: $isDarkMode) {
                                // Empty label, icon implies function
                            }
                            .toggleStyle(.switch)
                            .scaleEffect(0.7) // Make the switch smaller
                            .padding(.trailing, -8) // Adjust spacing if needed
                            .foregroundColor(isHoveringDarkModeToggle ? buttonHoverColor : buttonIdleColor) // Use appropriate colors
                            .onHover { hovering in handleHover(&isHoveringDarkModeToggle, hovering) }


                            Text("•").foregroundColor(secondaryTextColor)

                            // New Entry Button
                            Button("New Entry") { createNewEntry() }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringNewEntry ? buttonHoverColor : buttonIdleColor)
                                .onHover { hovering in handleHover(&isHoveringNewEntry, hovering) }

                            Text("•").foregroundColor(secondaryTextColor)

                            // History Sidebar Button
                            Button { withAnimation(.easeInOut(duration: 0.2)) { showingSidebar.toggle() } } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(isHoveringClock ? buttonHoverColor : buttonIdleColor)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in handleHover(&isHoveringClock, hovering) }
                        }
                        .padding(8)
                        .cornerRadius(6)
                        .onHover { hovering in isHoveringBottomNav = hovering }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8) // Slightly reduce vertical padding
                    .frame(height: navHeight)
                    .background(backgroundColor.shadow(radius: isDarkMode ? 5 : 3)) // Add subtle shadow, darker in dark mode
                    .opacity(bottomNavOpacity)
                    .onHover { hovering in
                        isHoveringBottomNav = hovering
                        updateBottomNavOpacity(hovering: hovering)
                    }
                }
            } // End Main ZStack

            // Right Sidebar (History)
            if showingSidebar {
                sidebarView() // Extracted sidebar view
            }
        } // End Main HStack
        .frame(minWidth: 1100, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: showingSidebar) // Animate sidebar
        // .preferredColorScheme(isDarkMode ? .dark : .light) // Apply color scheme preference to the whole window
        .onAppear {
            setupInitialState() // Load entries and set initial dark mode state
        }
        .onChange(of: text) { _ in autoSaveCurrentEntry() } // Auto-save on text change
        .onReceive(timer) { _ in handleTimerTick() } // Update timer countdown
        .onReceive(saveTimer) { _ in autoSaveCurrentEntry() } // Auto-save periodically
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in isFullscreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in isFullscreen = false }
    }

    // MARK: - View Builders & Helper Views

    // Creates a standard font selection button
    @ViewBuilder
    private func fontButton(_ label: String, fontName: String) -> some View {
        Button(label) {
            selectedFont = fontName
            currentRandomFont = "" // Clear random font selection
        }
        .buttonStyle(.plain)
        .foregroundColor(hoveredFont == label ? buttonHoverColor : buttonIdleColor)
        .onHover { hovering in handleHover(&hoveredFont, label, hovering) }
    }

    // Builds the content for the chat popover
    @ViewBuilder
    private func chatPopoverContent() -> some View {
        // Check conditions for showing options vs messages
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("hi. my name is farza.") {
            popoverMessage("Yo. Sorry, you can't chat with the guide lol. Please write your own entry.")
        } else if text.count < 350 {
            popoverMessage("Please free write for at minimum 5 minutes first. Then click this. Trust.")
        } else {
            VStack(spacing: 0) {
                popoverButton("ChatGPT") { openChatGPT() }
                Divider().background(dividerColor) // Use dynamic divider color
                popoverButton("Claude") { openClaude() }
            }
            .frame(width: 120)
            .background(popoverBackgroundColor) // Use dynamic popover background
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(isDarkMode ? 0.3 : 0.1), radius: 4, y: 2)
        }
    }

    // Helper for simple popover messages
    @ViewBuilder
    private func popoverMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundColor(.primary) // Adapts automatically
            .frame(width: 250)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(popoverBackgroundColor) // Use dynamic popover background
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(isDarkMode ? 0.3 : 0.1), radius: 4, y: 2)
    }

    // Helper for popover action buttons
    @ViewBuilder
    private func popoverButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            showingChatMenu = false // Close popover on action
            action()
        }) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary) // Adapts automatically
    }

    // Builds the history sidebar view
    @ViewBuilder
    private func sidebarView() -> some View {
        Divider().background(dividerColor) // Use dynamic divider color
        VStack(spacing: 0) {
            // Header Button to reveal folder
            Button(action: openDocumentsFolder) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("History")
                                .font(.system(size: 13))
                                .foregroundColor(isHoveringHistory ? buttonHoverColor : secondaryTextColor)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundColor(isHoveringHistory ? buttonHoverColor : secondaryTextColor)
                        }
                        Text(getDocumentsDirectory().path)
                            .font(.system(size: 10))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                            .truncationMode(.middle) // Truncate path in the middle
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onHover { hovering in isHoveringHistory = hovering }

            Divider().background(dividerColor) // Use dynamic divider color

            // Entries List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        sidebarEntryButton(entry: entry) // Extracted entry button
                        if entry.id != entries.last?.id {
                           Divider().background(dividerColor.opacity(0.5)) // Make internal dividers subtler
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(width: 220) // Slightly wider sidebar
        .background(sidebarBackgroundColor) // Use dynamic sidebar background
    }

    // Builds a single entry button for the sidebar
    @ViewBuilder
    private func sidebarEntryButton(entry: HumanEntry) -> some View {
        Button(action: { selectEntry(entry) }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.previewText.isEmpty ? "Empty Entry" : entry.previewText) // Show placeholder if empty
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundColor(.primary) // Adapts
                    Text(entry.date)
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor) // Adapts
                }
                Spacer()

                // Trash icon that appears on hover
                if hoveredEntryId == entry.id {
                    Button(action: { deleteEntry(entry: entry) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(hoveredTrashId == entry.id ? .red : .gray) // Red only on direct hover
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.1)) { // Faster animation
                            hoveredTrashId = hovering ? entry.id : nil
                        }
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .padding(.leading, 4) // Add some space before trash icon
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 10) // Adjust padding
            .background(sidebarEntryBackgroundColor(for: entry)) // Use dynamic background
            .cornerRadius(4) // Apply corner radius to the background
            .padding(.horizontal, 4) // Add padding around the background for spacing
            .padding(.vertical, 2)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { // Faster animation
                hoveredEntryId = hovering ? entry.id : nil
            }
             if !hovering { hoveredTrashId = nil } // Ensure trash hover resets when leaving row
        }
        .help("Select Entry: \(entry.date)") // Add tooltip
    }

    // MARK: - Action & Helper Functions

    // Sets up initial state on appear
    private func setupInitialState() {
        showingSidebar = false
        // Respect system appearance on first launch only
        let systemAppearance = NSApp.effectiveAppearance
        isDarkMode = systemAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        loadExistingEntries()
    }

    // Cycles through available font sizes
    private func cycleFontSize() {
        if let currentIndex = fontSizes.firstIndex(of: fontSize) {
            let nextIndex = (currentIndex + 1) % fontSizes.count
            fontSize = fontSizes[nextIndex]
        } else {
            fontSize = fontSizes.first ?? 18 // Default if current size isn't in list
        }
    }

    // Sets a random font from the available system fonts
    private func setRandomFont() {
        if let randomFont = availableFonts.randomElement() {
            selectedFont = randomFont
            currentRandomFont = randomFont // Display the random font name
        }
    }

    // Toggles the timer state or resets on double-click
    private func toggleTimer() {
        let now = Date()
        // Double-click detection (within 0.3 seconds)
        if let lastClick = lastClickTime, now.timeIntervalSince(lastClick) < 0.3 {
            timeRemaining = 900 // Reset to 15 mins
            timerIsRunning = false
            lastClickTime = nil // Reset click time
             updateBottomNavOpacity(hovering: isHoveringBottomNav) // Update opacity after reset
        } else {
            timerIsRunning.toggle()
            lastClickTime = now // Record click time
             updateBottomNavOpacity(hovering: isHoveringBottomNav) // Update opacity after toggle
        }
    }

    // Handles the timer tick event
    private func handleTimerTick() {
        if timerIsRunning && timeRemaining > 0 {
            timeRemaining -= 1
        } else if timeRemaining == 0 {
            if timerIsRunning { // Ensure this only runs once when timer hits 0
                 timerIsRunning = false
                 // Make nav reappear explicitly when timer finishes
                 withAnimation(.easeOut(duration: 1.0)) {
                     bottomNavOpacity = 1.0
                 }
                 // Optional: Add a sound or visual notification
                 NSSound.beep()
            }
        }
    }

    // Toggles fullscreen mode for the window
    private func toggleFullscreen() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.toggleFullScreen(nil)
    }

    // Opens the documents folder in Finder
    private func openDocumentsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: getDocumentsDirectory().path)
    }

    // Handles hover state changes for buttons and controls
    private func handleHover(_ state: inout Bool, _ hovering: Bool) {
        state = hovering
        isHoveringBottomNav = hovering // Any hover on controls counts as nav hover
        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    // Overload for font buttons using String?
    private func handleHover(_ state: inout String?, _ label: String, _ hovering: Bool) {
        state = hovering ? label : nil
        isHoveringBottomNav = hovering
        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
    
    // Updates the opacity of the bottom navigation bar based on hover and timer state
    private func updateBottomNavOpacity(hovering: Bool) {
        if hovering {
            // Instantly reappear or stay visible on hover
            withAnimation(.easeOut(duration: 0.2)) { bottomNavOpacity = 1.0 }
        } else if timerIsRunning {
            // Fade out only if timer is running and not hovering
            withAnimation(.easeIn(duration: 1.0)) { bottomNavOpacity = 0.0 }
        } else {
             // Stay visible if timer is not running and not hovering
             withAnimation(.easeOut(duration: 0.2)) { bottomNavOpacity = 1.0 }
        }
    }

    // Sets up the scroll wheel listener for the timer adjust feature
    private func setupScrollWheelMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            if self.isHoveringTimer {
                let scrollAmount = event.deltaY * 0.25 // Sensitivity adjustment

                if abs(scrollAmount) >= 0.1 { // Threshold to avoid tiny scrolls
                    let currentMinutes = self.timeRemaining / 60
                    // Use haptic feedback for scroll adjustment
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

                    // Increment/decrement by 5 minutes based on scroll direction
                    let direction = -scrollAmount > 0 ? 5 : -5
                    let newMinutes = currentMinutes + direction
                    let roundedMinutes = max(0, (newMinutes / 5) * 5) // Ensure multiple of 5, non-negative
                    let newTime = roundedMinutes * 60

                    // Clamp time between 0 and 45 minutes (2700 seconds)
                    self.timeRemaining = min(max(newTime, 0), 2700)
                }
            }
            return event // Pass event along
        }
    }

    // Gets the background color for a sidebar entry based on state
    private func sidebarEntryBackgroundColor(for entry: HumanEntry) -> Color {
        if entry.id == selectedEntryId {
            // Use system accent color for selection, adapting opacity
            return Color.accentColor.opacity(isDarkMode ? 0.4 : 0.25)
        } else if entry.id == hoveredEntryId {
            // Subtle gray for hover, adapting opacity
            return Color.gray.opacity(isDarkMode ? 0.15 : 0.1)
        } else {
            return Color.clear // No background otherwise
        }
    }

    // Selects an entry from the sidebar
    private func selectEntry(_ entry: HumanEntry) {
         guard selectedEntryId != entry.id else { return } // Do nothing if already selected

         // Save current entry before switching
         autoSaveCurrentEntry()

         // Load new entry
         selectedEntryId = entry.id
         loadEntry(entry: entry)
    }


    // MARK: - File Operations & Entry Management

    // Returns the cached documents directory URL
    private func getDocumentsDirectory() -> URL {
        return documentsDirectory
    }

    // Auto-saves the currently selected entry if valid
    private func autoSaveCurrentEntry() {
        guard let currentId = selectedEntryId,
              let currentEntry = entries.first(where: { $0.id == currentId }) else {
            // This can happen if no entry is selected yet or during deletion
            // print("Auto-save skipped: No valid entry selected.")
            return
        }
        saveEntry(entry: currentEntry)
    }

    // Saves the content of a specific entry to its file
    private func saveEntry(entry: HumanEntry) {
        let fileURL = getDocumentsDirectory().appendingPathComponent(entry.filename)
        do {
            // Use current `text` state for saving
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            // print("Successfully saved entry: \(entry.filename)")
            updatePreviewText(for: entry) // Update preview in the sidebar
        } catch {
            print("Error saving entry \(entry.filename): \(error)")
        }
    }

    // Loads the content of a specific entry into the editor
    private func loadEntry(entry: HumanEntry) {
        let fileURL = getDocumentsDirectory().appendingPathComponent(entry.filename)
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                text = try String(contentsOf: fileURL, encoding: .utf8)
                print("Successfully loaded entry: \(entry.filename)")
                 // Ensure text starts with newlines after loading
                 if !text.hasPrefix(headerString) {
                     text = headerString + text
                 }
                // Reset placeholder when loading an entry
                placeholderText = placeholderOptions.randomElement() ?? "\n\nBegin writing"
            } else {
                 print("File not found for entry: \(entry.filename). Creating empty.")
                 text = headerString // Start with newlines if file was missing
                 saveEntry(entry: entry) // Save the empty state
            }
        } catch {
            print("Error loading entry \(entry.filename): \(error)")
            text = headerString // Fallback to empty text on error
        }
    }

    // Updates the preview text shown in the sidebar for a given entry
    private func updatePreviewText(for entry: HumanEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }

        // Generate preview from the current `text` state if this is the selected entry
        let contentToPreview = (entry.id == selectedEntryId) ? text : nil

        if let content = contentToPreview {
            let preview = content
                .replacingOccurrences(of: "\n", with: " ") // Replace newlines with spaces for preview
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let truncated = preview.isEmpty ? "" : (preview.count > 50 ? String(preview.prefix(50)) + "..." : preview) // Longer preview
            // Ensure update happens on the main thread if needed
            DispatchQueue.main.async {
                 if index < self.entries.count { // Check index validity
                     self.entries[index].previewText = truncated
                 }
            }
        } else {
            // If not the selected entry, read from file (less frequent update)
            let fileURL = getDocumentsDirectory().appendingPathComponent(entry.filename)
            DispatchQueue.global(qos: .background).async {
                 do {
                     let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                     let preview = fileContent
                         .replacingOccurrences(of: "\n", with: " ")
                         .trimmingCharacters(in: .whitespacesAndNewlines)
                     let truncated = preview.isEmpty ? "" : (preview.count > 50 ? String(preview.prefix(50)) + "..." : preview)
                     DispatchQueue.main.async {
                          if index < self.entries.count { // Check index validity again
                              self.entries[index].previewText = truncated
                          }
                     }
                 } catch {
                     print("Error updating preview text from file for \(entry.filename): \(error)")
                 }
            }
        }
    }

    // Loads all existing .md entries from the documents directory
    // Loads all existing .md entries from the documents directory
        private func loadExistingEntries() {
            let documentsDir = getDocumentsDirectory()
            print("Looking for entries in: \(documentsDir.path)")

            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
                let mdFiles = fileURLs.filter { $0.pathExtension == "md" }
                print("Found \(mdFiles.count) .md files")

                var loadedEntries: [(entry: HumanEntry, modDate: Date)] = []

                for fileURL in mdFiles {
                    let filename = fileURL.lastPathComponent
                    // print("Processing: \(filename)")

                    // Improved filename parsing
                    let components = filename.dropLast(3).components(separatedBy: "]-[" ) // Drop ".md" and split

                    // --- CORRECTION START ---

                    // 1. Guard for the correct number of components first.
                    guard components.count == 2 else {
                        print("Skipping malformed filename (wrong component count): \(filename)")
                        continue
                    }

                    // 2. Extract the strings (these are NOT optional at this point).
                    //    Explicitly convert Substring to String for clarity and safety.
                    let uuidString = String(components[0].dropFirst().trimmingCharacters(in: .whitespaces)) // Remove '['
                    let dateString = String(components[1].dropLast().trimmingCharacters(in: .whitespaces)) // Remove ']'

                    // 3. Guard for the UUID creation, which *IS* optional.
                    guard let uuid = UUID(uuidString: uuidString) else {
                         print("Skipping malformed filename (invalid UUID string): \(filename)")
                         continue
                    }

                    // --- CORRECTION END ---


                    // Parse date from filename for sorting/display consistency
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss" // Filename format
                    guard let fileDate = dateFormatter.date(from: dateString) else {
                         print("Failed to parse date from filename: \(filename)")
                         continue
                    }

                    // Get modification date for accurate sorting
                    // Use try? to make attribute fetching optional without crashing
                    let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                    let modDate = attributes?[.modificationDate] as? Date ?? fileDate // Fallback to filename date


                     // Format display date
                     dateFormatter.dateFormat = "MMM d" // Display format
                     let displayDate = dateFormatter.string(from: fileDate)


                    // Read initial preview text (can be updated later)
                     var preview = ""
                     do {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        let previewContent = content
                            .replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                         preview = previewContent.isEmpty ? "" : (previewContent.count > 50 ? String(previewContent.prefix(50)) + "..." : previewContent)
                     } catch {
                        print("Error reading initial preview for \(filename): \(error)")
                     }


                    loadedEntries.append((
                        entry: HumanEntry(
                            id: uuid,
                            date: displayDate,
                            filename: filename,
                            previewText: preview
                        ),
                        modDate: modDate
                    ))
                }

                // Sort entries by modification date, newest first
                loadedEntries.sort { $0.modDate > $1.modDate }
                self.entries = loadedEntries.map { $0.entry }

                print("Successfully loaded and sorted \(entries.count) entries")

                // Decide which entry to select or if a new one is needed
                if let mostRecentEntry = entries.first {
                    selectedEntryId = mostRecentEntry.id
                    loadEntry(entry: mostRecentEntry)
                } else {
                    // No entries found, create the initial welcome entry
                    print("No existing entries found. Creating initial entry.")
                    createNewEntry(isInitial: true) // Pass flag for welcome message
                }

            } catch {
                print("Error loading directory contents: \(error)")
                print("Creating default entry after error.")
                createNewEntry(isInitial: true) // Create welcome entry on error
            }
        }


    // Creates a new entry, optionally with a welcome message
    private func createNewEntry(isInitial: Bool = false) {
         // Save the current entry *before* creating the new one
         autoSaveCurrentEntry()

         let newEntry = HumanEntry.createNew()
         entries.insert(newEntry, at: 0) // Add to the beginning of the list
         selectedEntryId = newEntry.id    // Select the new entry

         if isInitial {
             // Load welcome message from default.md in the bundle
             if let defaultMessageURL = Bundle.main.url(forResource: "default", withExtension: "md"),
                let defaultMessage = try? String(contentsOf: defaultMessageURL, encoding: .utf8) {
                 text = headerString + defaultMessage
             } else {
                 print("Warning: default.md not found in bundle. Creating empty initial entry.")
                 text = headerString // Fallback to empty
             }
         } else {
             // Regular new entry starts empty (with header)
             text = headerString
         }

         // Randomize placeholder text for the new entry
         placeholderText = placeholderOptions.randomElement() ?? "\n\nBegin writing"

         // Save the new entry immediately (whether welcome or empty)
         saveEntry(entry: newEntry)
         print("Created and selected new entry: \(newEntry.filename)")
    }


    // Opens ChatGPT with the current text and predefined prompt
    private func openChatGPT() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText = aiChatPrompt + "\n\n" + trimmedText
        openURL(base: "https://chat.openai.com/?m=", text: fullText)
    }

    // Opens Claude with the current text and predefined prompt
    private func openClaude() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText = claudePrompt + "\n\n" + trimmedText
        openURL(base: "https://claude.ai/new?q=", text: fullText)
    }

    // Helper to URL encode text and open a URL
    private func openURL(base: String, text: String) {
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: base + encodedText) else {
            print("Error creating URL for AI chat")
            return
        }
        NSWorkspace.shared.open(url)
    }

    // Deletes a specific entry from the list and filesystem
    private func deleteEntry(entry: HumanEntry) {
        print("Attempting to delete entry: \(entry.filename)")
        let fileURL = getDocumentsDirectory().appendingPathComponent(entry.filename)

        do {
            // 1. Remove from filesystem
            try fileManager.removeItem(at: fileURL)
            print("Successfully deleted file: \(entry.filename)")

            // 2. Remove from the entries array
            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
                 print("Error: Could not find deleted entry in the array.")
                 return // Should not happen if deletion is triggered from the list
            }
            entries.remove(at: index)
            print("Removed entry from list.")

            // 3. Handle selection change
            if selectedEntryId == entry.id {
                print("Deleted entry was selected. Selecting next or creating new.")
                if let firstEntry = entries.first {
                    // Select the new first entry (most recent)
                    selectedEntryId = firstEntry.id
                    loadEntry(entry: firstEntry)
                } else {
                    // No entries left, create a new one
                    print("No entries remaining after deletion. Creating new initial entry.")
                    createNewEntry(isInitial: true)
                }
            } else {
                 print("Deleted entry was not selected. Selection remains.")
            }
            // Reset hover states related to the deleted entry
            if hoveredEntryId == entry.id { hoveredEntryId = nil }
            if hoveredTrashId == entry.id { hoveredTrashId = nil }

        } catch {
            print("Error deleting file \(entry.filename): \(error)")
            // Optionally show an alert to the user here
        }
    }
}

// MARK: - Helper Extensions

extension NSView {
    // Recursively find the first subview of a specific type
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

extension NSFont {
    // Calculate the default line height for the font
    func defaultLineHeight() -> CGFloat {
        //ascender: The maximum distance glyphs extend above the baseline.
        //descender: The maximum distance glyphs extend below the baseline (typically negative).
        //leading: The recommended extra vertical space between lines.
        return self.ascender - self.descender + self.leading
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
