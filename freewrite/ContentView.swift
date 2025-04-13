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

struct HeartEmoji: Identifiable {
    let id = UUID()
    var position: CGPoint
    var offset: CGFloat = 0
}

struct ContentView: View {
    private let headerString = "\n\n"
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""  // Remove initial welcome text since we'll handle it in createNewEntry
    @AppStorage("customDirectoryPath") private var customDirectoryPath: String?
    
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
    @State private var isZenMode = false
    @State private var currentLine = ""
    @State private var previousLines: [String] = []
    @State private var isHoveringZen = false
    @State private var isHoveringRandomFont = false // Add state for random font button hover
    @State private var fontSearchText: String = "" // State for font search field
    @State private var showingTimerPopover = false // State for timer popover
    @State private var customTimeInput: String = "" // State for custom timer input
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let entryHeight: CGFloat = 40

    // Get all available font families from the system
    let availableFonts = NSFontManager.shared.availableFontFamilies
    // Keep standardFonts for the dropdown
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
    
    // Update cached documents directory to handle custom path
    private var documentsDirectory: URL {
        if let customPath = customDirectoryPath {
            return URL(fileURLWithPath: customPath)
        }
        
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
    }
    
    // AI Prompts
    private let aiChatPrompt = "You are an AI assistant. The user has provided the following text. Please analyze it and provide helpful feedback, suggestions, or insights. Focus on clarity, flow, and potential areas for expansion or refinement."
    private let claudePrompt = "Analyze the following text and provide constructive feedback. Consider the writing style, clarity, potential improvements, and interesting themes or ideas present."
    
    // Computed property for formatted time
    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // Function to load existing entries
    private func loadExistingEntries() {
        guard let directory = getDocumentsDirectory() else {
            // This case handles when a custom path was set but invalid.
            // getDocumentsDirectory already printed an error and reset the path.
            // We should attempt to load again using the now-reset default path.
            print("Invalid custom directory detected. Attempting to load from default directory.")
            // Directly call getDocumentsDirectory again, which will now return the default path
            guard let defaultDirectory = getDocumentsDirectory() else {
                 // If even the default directory fails (highly unlikely but possible), bail out.
                 print("FATAL: Could not access default documents directory.")
                 // Optionally show an alert to the user here.
                 entries = [] // Ensure entries is empty
                 createNewEntry() // Create a fallback entry
                 return
            }
            // Proceed with loading from the default directory
            loadEntries(from: defaultDirectory)
            return // Exit after handling the invalid custom path case
        }

        // Proceed with loading from the valid directory (custom or default)
        loadEntries(from: directory)
    }

    // Helper function to perform the actual loading from a given directory
    private func loadEntries(from directory: URL) {
         do {
            let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)

            // Filter out directories, just in case
            let filteredFileURLs = fileURLs.filter { !$0.hasDirectoryPath }

            let sortedFileURLs = try filteredFileURLs.sorted {
                let date1 = try $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 > date2 // Sort descending by creation date
            }

            entries = sortedFileURLs.compactMap { url -> HumanEntry? in // Explicit return type
                let filename = url.lastPathComponent

                // Extract UUID and Date from filename
                // Example: "[UUID]-[YYYY-MM-DD-HH-MM-SS].md"
                let baseName = filename.replacingOccurrences(of: ".md", with: "")
                let components = baseName.components(separatedBy: "]-[") // Split between the brackets

                guard components.count == 2 else {
                    // print("Could not split filename into 2 components: \(filename)")
                    return nil
                }

                let idString = components[0].replacingOccurrences(of: "[", with: "") // Remove leading '['
                let dateString = components[1].replacingOccurrences(of: "]", with: "") // Remove trailing ']'

                guard !idString.isEmpty,
                      !dateString.isEmpty,
                      let id = UUID(uuidString: idString)
                      else {
                    // print("Could not parse UUID ('\(idString)') or date ('\(dateString)') from filename: \(filename)")
                    return nil
                }

                // Format date for display
                let inputFormatter = DateFormatter()
                inputFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
                guard let date = inputFormatter.date(from: dateString) else {
                    // print("Could not parse date string '\(dateString)' for: \(filename)")
                    return nil
                }

                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MMM d"
                let displayDate = outputFormatter.string(from: date)

                // Generate initial preview text (will be updated)
                var preview = ""
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    preview = content
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    preview = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)
                } catch {
                    // print("Error reading file for preview: \(error)")
                }

                return HumanEntry(id: id, date: displayDate, filename: filename, previewText: preview)
            }

            // Select the first entry if available, otherwise create a new one
            if let firstEntry = entries.first {
                selectedEntryId = firstEntry.id
                loadEntry(entry: firstEntry)
            } else {
                createNewEntry() // Creates the first entry with welcome message
            }

            // Randomize placeholder for subsequent new entries
            placeholderText = placeholderOptions.randomElement() ?? "\n\nBegin writing"
            
        } catch {
            print("Error loading entries: \(error)")
            // If loading fails (e.g., first run, directory error), create a new entry
            if entries.isEmpty {
                createNewEntry()
            }
        }
    }

    // Function to get documents directory (handles custom path). Returns nil if custom path is set but invalid.
    private func getDocumentsDirectory() -> URL? {
        if let customPath = customDirectoryPath {
            // Validate the custom path
            let url = URL(fileURLWithPath: customPath) // Use fileURLWithPath for robustness
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                // Custom path is valid and is a directory
                return url
            } else {
                // Custom path is invalid (doesn't exist or isn't a directory)
                print("Custom directory path is invalid or not a directory: \(customPath). Resetting to default.")
                // Reset the stored path immediately
                customDirectoryPath = nil
                // Return nil to signal the caller that the custom path failed validation
                return nil
            }
        }

        // No custom path set, use the default directory logic
        let defaultDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Freewrite")
        
        // Create Freewrite directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: defaultDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
                print("Successfully created default Freewrite directory")
            } catch {
                print("Error creating default directory: \(error)")
                // Handle error appropriately, maybe return a temporary directory or show an alert
                // For now, just print the error and return the (potentially non-existent) path
            }
        }
        return defaultDirectory
    }
    
    // Function to select a custom directory
    private func selectCustomDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Freewrite Folder"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                customDirectoryPath = url.path // Store the path
                print("Custom directory selected: \(url.path)")
                // Reload entries from the new directory
                loadExistingEntries()
            }
        }
    }
    
    // Function to reset to the default directory
    private func resetToDefaultDirectory() {
        customDirectoryPath = nil
        print("Reset to default directory.")
        // Reload entries from the default directory AFTER resetting the path
        // This avoids the potential recursion/double-load issue
        // Use DispatchQueue.main.async to ensure UI updates happen on the main thread
        // and avoid potential issues if called during view updates.
        DispatchQueue.main.async {
            self.loadExistingEntries()
        }
    }

    var body: some View {
        ZStack { // Removed alignment: .leading
            // Main Content Area (Standard View or Zen Mode)
            if !isZenMode {
                HStack(spacing: 0) {
                    // Main Editor Area
                    ZStack(alignment: .bottom) {
                        // Text Editor
                        SmoothTextEditorView(
                            text: $text,
                            selectedFont: $selectedFont,
                            fontSize: $fontSize,
                            placeholder: placeholderText // Pass the placeholder
                        )
                        .padding(.horizontal, 80) // Add horizontal padding
                        .padding(.top, 40)       // Add top padding
                        .padding(.bottom, 80)    // Add bottom padding for the nav bar
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white) // Ensure background is white
                        .onChange(of: text) { _ in
                            // Reset timer only if it's not running (prevents reset on every keystroke)
                            if !timerIsRunning {
                                // timeRemaining = 900 // Reset timer on text change if needed
                            }
                            // Handle bottom nav fade-out logic if needed here or keep in .onHover
                        }

                        // Bottom Navigation Bar (Conditional Opacity)
                        HStack {
                            // Timer display and control (Play/Pause Button + Time Display Button)
                            HStack(spacing: 10) { // Group Play/Pause and Time
                                // Play/Pause Button
                                Button(action: {
                                    timerIsRunning.toggle()
                                    if timerIsRunning {
                                        // Start timer
                                        withAnimation(.easeIn(duration: 1.0)) {
                                            bottomNavOpacity = 0.0 // Fade out when timer starts
                                        }
                                    } else {
                                        // Stop timer
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            bottomNavOpacity = 1.0 // Fade in when timer stops
                                        }
                                    }
                                }) {
                                    Image(systemName: timerIsRunning ? "pause.fill" : "play.fill")
                                        .font(.system(size: 13))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringTimer ? .black : .gray)
                                .onHover { hovering in
                                    isHoveringTimer = hovering // Track hover specifically for play/pause
                                    isHoveringBottomNav = hovering // Indicate bottom nav hover
                                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }

                                // Time Display Button (triggers popover)
                                Button(action: {
                                    showingTimerPopover = true
                                }) {
                                    Text(formattedTime)
                                        .font(.system(size: 13))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringClock ? .black : .gray) // Use isHoveringClock for time display hover
                                .onHover { hovering in
                                    isHoveringClock = hovering // Use separate state for time display hover
                                    isHoveringBottomNav = hovering // Indicate bottom nav hover
                                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                                .popover(isPresented: $showingTimerPopover, arrowEdge: .bottom) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Set Timer (minutes)").font(.caption).foregroundColor(.secondary)
                                        Divider()
                                        // Preset Buttons
                                        HStack {
                                            ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                                                Button("\(minutes)") {
                                                    setTimer(minutes: minutes)
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                        // Custom Input
                                        HStack {
                                            TextField("Custom", text: $customTimeInput)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                                .frame(width: 60)
                                                .onChange(of: customTimeInput) { newValue in
                                                    // Allow only digits
                                                    let filtered = newValue.filter { "0123456789".contains($0) }
                                                    if filtered != newValue {
                                                        customTimeInput = filtered
                                                    }
                                                }

                                            Button("Set") {
                                                if let minutes = Int(customTimeInput), minutes > 0 {
                                                    setTimer(minutes: minutes)
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(customTimeInput.isEmpty || Int(customTimeInput) == nil || Int(customTimeInput)! <= 0)
                                        }
                                    }
                                    .padding()
                                } // End popover
                            } // End HStack for Play/Pause + Time

                            Text("•")
                                .foregroundColor(.gray)

                            // Font Selector Dropdown with Search
                            Menu {
                                // Search Field
                                TextField("Search Fonts", text: $fontSearchText)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(4)
                                    .padding(.bottom, 4) // Add some space below search

                                Divider() // Separate search from list

                                // Filtered Font List
                                ScrollView { // Make the list scrollable if long
                                    ForEach(filteredFonts, id: \.self) { font in
                                        Button(action: {
                                            selectedFont = font
                                            fontSearchText = "" // Clear search on selection
                                        }) {
                                            Text(font)
                                                .font(.custom(font, size: 14)) // Preview font in menu
                                                .frame(maxWidth: .infinity, alignment: .leading) // Ensure text aligns left
                                        }
                                        .buttonStyle(.plain) // Use plain style for menu items
                                    }
                                }
                                .frame(maxHeight: 200) // Limit the height of the scrollable list

                            } label: {
                                Text(selectedFont)
                                    .font(.system(size: 13))
                                    .foregroundColor(hoveredFont == selectedFont ? .black : .gray) // Use hoveredFont state
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize() // Prevent layout shifts
                            .onHover { hovering in
                                hoveredFont = hovering ? selectedFont : nil // Update hoveredFont
                                isHoveringBottomNav = hovering // Indicate bottom nav hover
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }

                            Text("•")
                                .foregroundColor(.gray)

                            // Font Size Selector Dropdown
                            Menu {
                                ForEach(fontSizes, id: \.self) { size in
                                    Button(action: { fontSize = size }) {
                                        Text("\(Int(size)) pt")
                                    }
                                }
                            } label: {
                                Text("\(Int(fontSize)) pt")
                                    .font(.system(size: 13))
                                    .foregroundColor(isHoveringSize ? .black : .gray)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .onHover { hovering in
                                isHoveringSize = hovering
                                isHoveringBottomNav = hovering // Indicate bottom nav hover
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }

                            Text("•") // Separator before Random Font
                                .foregroundColor(.gray)

                            // Random Font Button
                            Button(action: {
                                // Select a random font from all available system fonts
                                selectedFont = availableFonts.randomElement() ?? ".AppleSystemUIFont" // Default to system font if random fails
                            }) {
                                Image(systemName: "shuffle") // Use shuffle icon
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringRandomFont ? .black : .gray)
                            .onHover { hovering in
                                isHoveringRandomFont = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .help("Select Random Font") // Add tooltip

                            Spacer() // Pushes elements left and right

                            // AI Chat Button
                            Button(action: {
                                showingChatMenu = true
                            }) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringChat ? .black : .gray)
                            .popover(isPresented: $showingChatMenu, arrowEdge: .bottom) {
                                VStack {
                                    Button("Open in ChatGPT") {
                                        openChatGPT()
                                        showingChatMenu = false
                                    }
                                    Button("Open in Claude") {
                                        openClaude()
                                        showingChatMenu = false
                                    }
                                }
                                .padding()
                            }
                            .onHover { hovering in
                                isHoveringChat = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }

                            Text("•")
                                .foregroundColor(.gray)

                            // Zen Mode Button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isZenMode.toggle()
                                }
                            }) {
                                Image(systemName: "infinity") // Changed Zen mode icon to infinity
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringZen ? .black : .gray)
                            .onHover { hovering in
                                isHoveringZen = hovering
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
                            .foregroundColor(isHoveringNewEntry ? .black : .gray)
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
                                    .foregroundColor(isHoveringClock ? .black : .gray)
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
                        .background(Color.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure editor fills space
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
                            } // End VStack for bottom bar content
                        } // End ZStack for main content area

                    // Sidebar (moved back to the right)
                    if showingSidebar {
                        // Divider() // Removed this divider which appeared between content and sidebar

                        VStack(spacing: 0) {
                            // Header with folder selection
                            Button(action: {
                                // Safely unwrap the directory URL before using its path
                                if let directoryURL = getDocumentsDirectory() {
                                    if customDirectoryPath != nil {
                                        // If a custom path is set (and valid), open it in Finder
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directoryURL.path)
                                    } else {
                                        // If using the default path, allow selecting a custom one
                                        selectCustomDirectory()
                                    }
                                } else {
                                     // This case should ideally not happen if logic is correct,
                                     // but as a fallback, allow selecting a custom directory.
                                     print("Error: Could not get directory URL for Finder action.")
                                     selectCustomDirectory()
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Text("History")
                                                .font(.system(size: 13))
                                                .foregroundColor(isHoveringHistory ? .black : .secondary)
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 10))
                                                .foregroundColor(isHoveringHistory ? .black : .secondary)
                                        }
                                        // Display the current directory path, handling potential nil from initial load failure
                                        Text(getDocumentsDirectory()?.path ?? "Default Location")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()

                                    // Add folder icon button
                                    if customDirectoryPath != nil {
                                        Button(action: resetToDefaultDirectory) {
                                            Image(systemName: "folder.badge.minus")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Reset to default location")
                                    } else {
                                        Button(action: selectCustomDirectory) {
                                            Image(systemName: "folder.badge.plus")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Choose custom folder location")
                                    }
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
                                            .frame(maxWidth: .infinity)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(backgroundColor(for: entry))
                                            )
                                            .padding(.horizontal, 4) // Add slight horizontal padding for the background highlight
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .contentShape(Rectangle()) // Ensure the whole area is clickable
                                        .onHover { hovering in
                                            withAnimation(.easeInOut(duration: 0.1)) { // Faster hover animation
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
                        .background(Color(NSColor.controlBackgroundColor))
                        .transition(.move(edge: .trailing)) // Ensure transition is from the right
                    } // End if showingSidebar
                } // End HStack for standard view content + sidebar
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Make HStack fill the space
            } // End if !isZenMode

            // Zen Mode View Overlay
            if isZenMode {
                ZenModeView(
                    currentLine: $currentLine,
                    previousLines: $previousLines,
                    text: $text, // Pass the main text binding
                    selectedFont: $selectedFont,
                    fontSize: $fontSize,
                    timeRemaining: $timeRemaining,
                    timerIsRunning: $timerIsRunning,
                    isZenMode: $isZenMode
                )
                .transition(.opacity.combined(with: .scale(scale: 1.05))) // Transition for Zen view
            }
        } // End Top level ZStack
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure ZStack fills the window
        .frame(minWidth: 1100, minHeight: 600)
        .animation(.easeInOut(duration: 0.3), value: isZenMode) // Animate Zen Mode changes
        .animation(.easeInOut(duration: 0.2), value: showingSidebar) // Keep sidebar animation separate
        .preferredColorScheme(.light)
        .onAppear {
            showingSidebar = false  // Hide sidebar by default
            loadExistingEntries()
        }
        .onChange(of: text) { _ in
            // Save current entry when text changes, only if NOT in Zen Mode
            // ZenModeView handles updating 'text' internally via binding
            if !isZenMode, let currentId = selectedEntryId,
               let currentEntry = entries.first(where: { $0.id == currentId }) {
                saveEntry(entry: currentEntry)
            }
        }
        .onChange(of: isZenMode) { newValue in
             // Use the new value directly
            if newValue {
                // Entering Zen Mode
                showingSidebar = false // Ensure sidebar is hidden
                // Parse current text into lines, preserving initial newlines and structure
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

                // Find the last non-empty line to be the current line
                if let lastNonEmptyIndex = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    currentLine = lines[lastNonEmptyIndex]
                    // Previous lines are everything before the last non-empty one, preserving empty lines between them
                    previousLines = Array(lines.prefix(lastNonEmptyIndex))
                } else {
                    // Text is empty or only whitespace/newlines
                    currentLine = ""
                    // Preserve leading newlines if they exist
                    previousLines = lines.filter { $0.isEmpty }
                }
                // Update the main text state immediately to reflect the split (important for consistency if saved)
                 text = (previousLines + [currentLine]).joined(separator: "\n")

            } else {
                // Exiting Zen Mode
                // Reconstruct the text from previousLines and the potentially modified currentLine
                // Add current line back only if it's not just whitespace
                let trimmedCurrentLine = currentLine.trimmingCharacters(in: .whitespaces)
                let finalLines = previousLines + (trimmedCurrentLine.isEmpty ? [] : [currentLine])

                // Reconstruct, ensuring at least the initial \n\n are present if the result isn't empty
                var reconstructedText = finalLines.joined(separator: "\n")
                if !reconstructedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // If there's content, ensure it starts with \n\n
                    if !reconstructedText.hasPrefix("\n\n") {
                         if reconstructedText.hasPrefix("\n") {
                             reconstructedText = "\n" + reconstructedText // Add one more \n
                         } else {
                             reconstructedText = "\n\n" + reconstructedText // Add both \n\n
                         }
                    }
                } else {
                    // If the result is effectively empty, reset to just \n\n
                    reconstructedText = "\n\n"
                }
                 text = reconstructedText // Update the main state

                // Save the reconstructed text immediately
                if let currentId = selectedEntryId,
                   let currentEntry = entries.first(where: { $0.id == currentId }) {
                    saveEntry(entry: currentEntry)
                }
            }
        }
        .onReceive(timer) { _ in
            if timerIsRunning && timeRemaining > 0 {
                timeRemaining -= 1
            } else if timeRemaining == 0 {
                timerIsRunning = false
                // Exit Zen Mode automatically if timer runs out
                if isZenMode {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isZenMode = false
                    }
                }
                // Show bottom bar if not hovering
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
    } // End body var

    // Function to set the timer
    private func setTimer(minutes: Int) {
        timeRemaining = minutes * 60
        timerIsRunning = false // Stop timer when setting a new time
        customTimeInput = "" // Clear custom input field
        showingTimerPopover = false // Close popover
        // Ensure bottom bar is visible when timer is reset/stopped
        withAnimation(.easeOut(duration: 0.2)) {
            bottomNavOpacity = 1.0
        }
    }

    // Computed property for filtered fonts
    private var filteredFonts: [String] {
        if fontSearchText.isEmpty {
            return availableFonts.sorted() // Show all available fonts sorted if search is empty
        } else {
            // Filter available fonts based on search text (case-insensitive)
            return availableFonts.filter { $0.localizedCaseInsensitiveContains(fontSearchText) }.sorted()
        }
    }

    // MARK: - Helper Functions

    private func backgroundColor(for entry: HumanEntry) -> Color {
        if entry.id == selectedEntryId {
            return Color.gray.opacity(0.15) // Slightly stronger selection highlight
        } else if entry.id == hoveredEntryId {
            return Color.gray.opacity(0.08) // Slightly stronger hover state
        } else {
            return Color.clear
        }
    }

    private func updatePreviewText(for entry: HumanEntry) {
        // Use the currently determined valid directory
        guard let documentsDirectory = getDocumentsDirectory() else {
             print("Cannot update preview text: Invalid directory.")
             return
        }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        do {
            // Check if file exists before trying to read
            guard fileManager.fileExists(atPath: fileURL.path) else {
                print("Preview update skipped: File does not exist at \(fileURL.path)")
                // Optionally remove the entry from the list if the file is gone
                // if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                //     entries.remove(at: index)
                // }
                return
            }
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
        // Use the currently determined valid directory
        guard let documentsDirectory = getDocumentsDirectory() else {
             print("Cannot save entry: Invalid directory.")
             return // Or handle error appropriately
        }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        // Ensure text always has the leading newlines before saving
        var textToSave = text
        if !textToSave.hasPrefix("\n\n") {
             if textToSave.hasPrefix("\n") {
                 textToSave = "\n" + textToSave
             } else if !textToSave.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                 // Only add prefix if there's actual content
                 textToSave = "\n\n" + textToSave
             } else {
                 // If it's effectively empty, save just the newlines
                 textToSave = "\n\n"
             }
        }

        do {
            try textToSave.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved entry: \(entry.filename)")
            updatePreviewText(for: entry)  // Update preview after saving
        } catch {
            print("Error saving entry: \(error)")
        }
    }

    private func loadEntry(entry: HumanEntry) {
        // Use the currently determined valid directory
        guard let documentsDirectory = getDocumentsDirectory() else {
             print("Cannot load entry: Invalid directory.")
             text = "\n\nError: Could not access storage location." // Provide feedback
             return
        }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                var loadedText = try String(contentsOf: fileURL, encoding: .utf8)
                // Ensure loaded text starts correctly
                if !loadedText.hasPrefix("\n\n") {
                     if loadedText.hasPrefix("\n") {
                         loadedText = "\n" + loadedText
                     } else if !loadedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                         loadedText = "\n\n" + loadedText
                     } else {
                         loadedText = "\n\n"
                     }
                }
                text = loadedText
                print("Successfully loaded entry: \(entry.filename)")
            }
        } catch {
            print("Error loading entry: \(error)")
        }
    }

    private func createNewEntry() {
        // Save the current entry first if one is selected
        if let currentId = selectedEntryId, let currentEntry = entries.first(where: { $0.id == currentId }) {
             saveEntry(entry: currentEntry)
        }

        let newEntry = HumanEntry.createNew()
        entries.insert(newEntry, at: 0) // Add to the beginning
        selectedEntryId = newEntry.id

        // If this is the first entry (entries was empty before adding this one)
        if entries.count == 1 {
            // Read welcome message from default.md
            if let defaultMessageURL = Bundle.main.url(forResource: "default", withExtension: "md"),
               let defaultMessage = try? String(contentsOf: defaultMessageURL, encoding: .utf8) {
                text = "\n\n" + defaultMessage
            } else {
                 text = "\n\n" // Fallback if default.md is missing
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
        // Use the currently determined valid directory
        guard let documentsDirectory = getDocumentsDirectory() else {
             print("Cannot delete entry: Invalid directory.")
             // Optionally show an alert to the user
             return
        }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        do {
            // Check if file exists before trying to delete
            guard fileManager.fileExists(atPath: fileURL.path) else {
                 print("Deletion skipped: File does not exist at \(fileURL.path)")
                 // Remove the entry from the list anyway if it's somehow still there
                 if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                     entries.remove(at: index)
                     // Handle selection change if needed
                     if selectedEntryId == entry.id {
                         if let firstEntry = entries.first {
                             selectedEntryId = firstEntry.id
                             loadEntry(entry: firstEntry)
                         } else {
                             createNewEntry()
                         }
                     }
                 }
                 return
            }

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
                        // If no entries left, create a new one
                        createNewEntry()
                    }
                }
            }
        } catch {
            print("Error deleting file: \(error)")
        }
    }
} // End ContentView struct

// MARK: - Extensions

// Add helper extension to find NSView subviews
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

    // findSubview needs to be here too
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

// Helper extension to get default line height
extension NSFont {
    func defaultLineHeight() -> CGFloat {
        // Use layoutManager to calculate line height for the font
        let layoutManager = NSLayoutManager()
        return layoutManager.defaultLineHeight(for: self)
    }
}

#Preview {
    ContentView()
}
