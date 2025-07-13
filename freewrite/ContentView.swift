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
import Security

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String
    let filename: String
    var previewText: String
    
    static func createNew() -> HumanEntry {
        let id = UUID()
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd-yyyy-HH-mm-ss"
        let dateString = dateFormatter.string(from: now)
        
        // For display
        dateFormatter.dateFormat = "MMM d"
        let displayDate = dateFormatter.string(from: now)
        
        let dateParts = dateString.split(separator: "-")
        let dateComponent = "\(dateParts[0])-\(dateParts[1])-\(dateParts[2])"
        let timeComponent = "\(dateParts[3])-\(dateParts[4])-\(dateParts[5])"
        
        return HumanEntry(
            id: id,
            date: displayDate,
            filename: "[Daily]-[\(dateComponent)]-[\(timeComponent)].md",
            previewText: ""
        )
    }
}

enum SettingsTab: String, CaseIterable {
    case reflections = "Reflections"
    case ai = "AI"
    case style = "Style"
}

struct HeartEmoji: Identifiable {
    let id = UUID()
    var position: CGPoint
    var offset: CGFloat = 0
}

// MARK: - Keychain Helper for secure API key storage
// Using Keychain instead of UserDefaults for security - API keys are encrypted and protected
class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    private let service = "com.freewrite.apikeys"
    private let openAIKeyAccount = "openai_api_key"
    
    func saveAPIKey(_ key: String) {
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIKeyAccount,
            kSecValueData as String: data
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to save API key to Keychain: \(status)")
        }
    }
    
    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        
        return nil
    }
    
    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIKeyAccount
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

class ContentViewController: NSObject, URLSessionDataDelegate {
    // You can move the URLSession delegate methods here if you prefer
    // to keep ContentView cleaner. For now, we'll keep them in the extension.
}

struct ContentView: View {
    private let headerString = "\n\n"
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""  // Remove initial welcome text since we'll handle it in createNewEntry
    
    @State private var isFullscreen = false
    @State private var userSelectedFont: String = "Lato-Regular" // Renamed from selectedFont
    @State private var aiSelectedFont: String = "Lato-Regular" // For AI reflections
    @State private var currentRandomFont: String = ""
    @State private var currentAIRandomFont: String = ""
    @State private var timeRemaining: Int = 900  // Changed to 900 seconds (15 minutes)
    @State private var timerIsRunning = false
    @State private var isHoveringTimer = false
    @State private var isHoveringFullscreen = false
    @State private var userFontSize: CGFloat = 18 // Renamed from fontSize
    @State private var aiFontSize: CGFloat = 18 // For AI reflections
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

    @State private var isHoveringReflect = false
    @State private var isHoveringBrain = false // Add hover state for brain icon
    @State private var colorScheme: ColorScheme = .light // Add state for color scheme

    @State private var didCopyPrompt: Bool = false // Add state for copy prompt feedback
    @State private var showingSettings = false // Add state for settings menu
    @State private var isHoveringSettings = false // Add state for settings hover
    @State private var selectedSettingsTab: SettingsTab = .reflections // Add state for selected tab
    @State private var openAIAPIKey: String = ""
    @StateObject private var reflectionViewModel = ReflectionViewModel()
    
    // Hard-coded DeepGram API key for transcription
    private let deepgramAPIKey = "YOUR_DEEPGRAM_API_KEY_HERE"
    
    // Add state for reflection functionality
    @State private var showReflectionPanel: Bool = false
    @State private var isWeeklyReflection: Bool = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let entryHeight: CGFloat = 40
    
    // Updated audio recording states for streaming
    @State private var isListening = false
    @State private var micDotAngle: Double = 0
    @State private var micDotTimer: Timer? = nil
    @State private var audioRecorder: AVAudioRecorder? = nil
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var transcriptionError: String? = nil
    @State private var chunkTimer: Timer? = nil
    @State private var chunkCounter: Int = 0
    @State private var isVoiceInputMode = false // New state for voice input mode
    @State private var pendingTranscriptionText = "" // Buffer for incoming transcription
    
    // Toast notification states
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .error
    

    let availableFonts = NSFontManager.shared.availableFontFamilies
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
    
    // Initialize with saved theme preference if available
    init() {
        // Load saved color scheme preference
        let savedScheme = UserDefaults.standard.string(forKey: "colorScheme") ?? "light"
        _colorScheme = State(initialValue: savedScheme == "dark" ? .dark : .light)
        
        // Load saved OpenAI API key from Keychain (secure storage)
        let savedAPIKey = KeychainHelper.shared.loadAPIKey() ?? ""
        _openAIAPIKey = State(initialValue: savedAPIKey)
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
    
    // Function to run weekly reflection
    private func runWeeklyReflection() {
        // Calculate date range (7 days ago to today)
        let today = Date()
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        // Gather entries from the last 7 days
        let weeklyContent = gatherWeeklyEntries(from: sevenDaysAgo, to: today)
        
        // Check if there are any entries for the week
        if weeklyContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showToast(message: "No entries found for the past week", type: .error)
            return
        }
        
        // Format the date range for the title
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d"
        let startDateString = dateFormatter.string(from: sevenDaysAgo)
        let endDateString = dateFormatter.string(from: today)
        
        // Create title with date range
        let weeklyTitle = "Weekly: \(startDateString)-\(endDateString)"
        
        // Create new weekly entry
        let newEntry = createWeeklyEntry(title: weeklyTitle, startDate: sevenDaysAgo, endDate: today)
        
        // Start reflection with the gathered content
        reflectionViewModel.startWeeklyReflection(apiKey: openAIAPIKey, weeklyContent: weeklyContent) {
            // Save the entry after reflection is complete
            self.saveEntry(entry: newEntry)
        }
        
        // Show reflection panel as weekly reflection
        isWeeklyReflection = true
        showReflectionPanel = true
        showingSettings = false
    }
    
    // Function to gather entries from the last 7 days
    private func gatherWeeklyEntries(from startDate: Date, to endDate: Date) -> String {
        let documentsDirectory = getDocumentsDirectory()
        var weeklyContent = ""
        var processedFiles: [String] = []
        
        print("=== GATHERING WEEKLY ENTRIES ===")
        print("Target date range: \(startDate) to \(endDate)")
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            let mdFiles = fileURLs.filter { $0.pathExtension == "md" }
            
            print("Found \(mdFiles.count) .md files to process")
            
            let calendar = Calendar.current
            let startOfStartDate = calendar.startOfDay(for: startDate)
            let startOfEndDate = calendar.startOfDay(for: endDate)
            
            for fileURL in mdFiles {
                let filename = fileURL.lastPathComponent
                var shouldInclude = false
                var displayDate = ""
                
                // Handle Daily entries: [Daily]-[MM-dd-yyyy]-[HH-mm-ss].md
                if filename.hasPrefix("[Daily]-") {
                    if let dateMatch = filename.range(of: "\\[(\\d{2}-\\d{2}-\\d{4})\\]-\\[(\\d{2}-\\d{2}-\\d{2})\\]", options: .regularExpression) {
                        let matchString = String(filename[dateMatch])
                        let components = matchString.components(separatedBy: "]-[")
                        
                        if components.count >= 2 {
                            let dateComponent = components[0].replacingOccurrences(of: "[", with: "")
                            let timeComponent = components[1].replacingOccurrences(of: "]", with: "")
                            
                            let dateTimeString = "\(dateComponent)-\(timeComponent)"
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "MM-dd-yyyy-HH-mm-ss"
                            
                            if let fileDate = dateFormatter.date(from: dateTimeString) {
                                let startOfFileDate = calendar.startOfDay(for: fileDate)
                                
                                // Check if file date is within our 7-day range
                                if startOfFileDate >= startOfStartDate && startOfFileDate <= startOfEndDate {
                                    shouldInclude = true
                                    dateFormatter.dateFormat = "MMMM d"
                                    displayDate = dateFormatter.string(from: fileDate)
                                }
                            }
                        }
                    }
                }
                // Handle Weekly entries: [Weekly]-[MM-dd-yyyy]-[MM-dd-yyyy]-[HH-mm-ss].md
                else if filename.hasPrefix("[Weekly]-") {
                    let pattern = "\\[Weekly\\]-\\[(\\d{2}-\\d{2}-\\d{4})\\]-\\[(\\d{2}-\\d{2}-\\d{4})\\]-\\[(\\d{2}-\\d{2}-\\d{2})\\]"
                    if let match = filename.range(of: pattern, options: .regularExpression) {
                        let matchString = String(filename[match])
                        let components = matchString.components(separatedBy: "]-[")
                        
                        if components.count >= 4 {
                            let weeklyStartDateString = components[1]
                            let weeklyEndDateString = components[2]
                            
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "MM-dd-yyyy"
                            
                            if let weeklyStartDate = dateFormatter.date(from: weeklyStartDateString),
                               let weeklyEndDate = dateFormatter.date(from: weeklyEndDateString) {
                                
                                let startOfWeeklyStart = calendar.startOfDay(for: weeklyStartDate)
                                let startOfWeeklyEnd = calendar.startOfDay(for: weeklyEndDate)
                                
                                // Check if weekly entry's date range overlaps with our target 7-day range
                                // Overlap exists if: weeklyStart <= targetEnd AND weeklyEnd >= targetStart
                                if startOfWeeklyStart <= startOfEndDate && startOfWeeklyEnd >= startOfStartDate {
                                    shouldInclude = true
                                    dateFormatter.dateFormat = "MMMM d"
                                    let startDisplay = dateFormatter.string(from: weeklyStartDate)
                                    let endDisplay = dateFormatter.string(from: weeklyEndDate)
                                    displayDate = "Weekly: \(startDisplay) - \(endDisplay)"
                                }
                            }
                        }
                    }
                }
                
                if shouldInclude {
                    do {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !cleanContent.isEmpty {
                            print("✓ Including file: \(filename)")
                            print("  Display date: \(displayDate)")
                            print("  Content length: \(cleanContent.count) characters")
                            print("  Content preview: \(String(cleanContent.prefix(100)))...")
                            
                            weeklyContent += "\n\n--- \(displayDate) ---\n\n"
                            weeklyContent += cleanContent
                            processedFiles.append(filename)
                        } else {
                            print("⚠ Skipping empty file: \(filename)")
                        }
                    } catch {
                        print("❌ Error reading file \(filename): \(error)")
                    }
                } else {
                    print("⏭ Skipping file (outside date range): \(filename)")
                }
            }
        } catch {
            print("❌ Error gathering weekly entries: \(error)")
        }
        
        print("\n=== WEEKLY REFLECTION SUMMARY ===")
        print("Processed \(processedFiles.count) files:")
        for file in processedFiles {
            print("  - \(file)")
        }
        print("Total content length: \(weeklyContent.count) characters")
        
        return weeklyContent
    }
    
    // Function to create a new weekly entry
    private func createWeeklyEntry(title: String, startDate: Date, endDate: Date) -> HumanEntry {
        let id = UUID()
        let now = Date()
        let dateFormatter = DateFormatter()
        
        // Create filename with new format [Weekly]-[start-date]-[end-date]-[time]
        dateFormatter.dateFormat = "MM-dd-yyyy"
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)
        
        dateFormatter.dateFormat = "HH-mm-ss"
        let timeString = dateFormatter.string(from: now)
        
        let filename = "[Weekly]-[\(startDateString)]-[\(endDateString)]-[\(timeString)].md"
        
        // For display date
        dateFormatter.dateFormat = "MMM d"
        let startDisplayDate = dateFormatter.string(from: startDate)
        let endDisplayDate = dateFormatter.string(from: endDate)
        let displayDate = "\(startDisplayDate) - \(endDisplayDate)"
        
        let newEntry = HumanEntry(
            id: id,
            date: displayDate,
            filename: filename,
            previewText: title
        )
        
        // Add to entries and select it
        entries.insert(newEntry, at: 0)
        selectedEntryId = newEntry.id
        
        return newEntry
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
                
                var fileDate: Date?
                var displayDate: String = ""
                let uuid = UUID() // Generate new UUID for each entry
                
                // Handle Daily entries: [Daily]-[MM-dd-yyyy]-[HH-mm-ss].md
                if filename.hasPrefix("[Daily]-") {
                    if let dateMatch = filename.range(of: "\\[(\\d{2}-\\d{2}-\\d{4})\\]-\\[(\\d{2}-\\d{2}-\\d{2})\\]", options: .regularExpression) {
                        let matchString = String(filename[dateMatch])
                        let components = matchString.components(separatedBy: "]-[")
                        
                        if components.count >= 2 {
                            let dateComponent = components[0].replacingOccurrences(of: "[", with: "")
                            let timeComponent = components[1].replacingOccurrences(of: "]", with: "")
                            
                            let dateTimeString = "\(dateComponent)-\(timeComponent)"
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "MM-dd-yyyy-HH-mm-ss"
                            
                            if let parsedDate = dateFormatter.date(from: dateTimeString) {
                                fileDate = parsedDate
                                dateFormatter.dateFormat = "MMM d"
                                displayDate = dateFormatter.string(from: parsedDate)
                            }
                        }
                    }
                }
                // Handle Weekly entries: [Weekly]-[MM-dd-yyyy]-[MM-dd-yyyy]-[HH-mm-ss].md
                else if filename.hasPrefix("[Weekly]-") {
                    let pattern = "\\[Weekly\\]-\\[(\\d{2}-\\d{2}-\\d{4})\\]-\\[(\\d{2}-\\d{2}-\\d{4})\\]-\\[(\\d{2}-\\d{2}-\\d{2})\\]"
                    if let match = filename.range(of: pattern, options: .regularExpression) {
                        let matchString = String(filename[match])
                        let components = matchString.components(separatedBy: "]-[")
                        
                        if components.count >= 4 {
                            let startDateString = components[1]
                            let endDateString = components[2]
                            let timeString = components[3].replacingOccurrences(of: "]", with: "")
                            
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "MM-dd-yyyy"
                            
                            if let startDate = dateFormatter.date(from: startDateString),
                               let endDate = dateFormatter.date(from: endDateString) {
                                // Combine end date with time for proper sorting
                                dateFormatter.dateFormat = "MM-dd-yyyy-HH-mm-ss"
                                let endDateWithTime = "\(endDateString)-\(timeString)"
                                fileDate = dateFormatter.date(from: endDateWithTime)
                                
                                // Format display date as range
                                dateFormatter.dateFormat = "MMM d"
                                let startDisplay = dateFormatter.string(from: startDate)
                                let endDisplay = dateFormatter.string(from: endDate)
                                displayDate = "\(startDisplay) - \(endDisplay)"
                            }
                        }
                    }
                }
                
                guard let validFileDate = fileDate else {
                    print("Failed to parse date from filename: \(filename)")
                    return nil
                }
                
                // Read file contents for preview
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    
                    let separator = "\n\n--- REFLECTION ---\n\n"
                    let contentForPreview = content.replacingOccurrences(of: separator, with: " ")
                    
                    let preview = contentForPreview
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let truncated = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)
                    
                    return (
                        entry: HumanEntry(
                            id: uuid,
                            date: displayDate,
                            filename: filename,
                            previewText: truncated
                        ),
                        date: validFileDate,
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
    
    var userLineHeight: CGFloat {
        let font = NSFont(name: userSelectedFont, size: userFontSize) ?? .systemFont(ofSize: userFontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (userFontSize * 1.5) - defaultLineHeight
    }
    
    var aiLineHeight: CGFloat {
        let font = NSFont(name: aiSelectedFont, size: aiFontSize) ?? .systemFont(ofSize: aiFontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (aiFontSize * 1.5) - defaultLineHeight
    }
    
    var placeholderOffset: CGFloat {
        // Instead of using calculated line height, use a simple offset
        return (userFontSize / 2) + 1.5
    }
    
    // Add a color utility computed property
    var popoverBackgroundColor: Color {
        return colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(NSColor.darkGray)
    }
    
    var popoverTextColor: Color {
        return colorScheme == .light ? Color.primary : Color.white
    }
    
    @State private var viewHeight: CGFloat = 0
    
    @ViewBuilder
    private var bottomNavigationView: some View {
        let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
        let textHoverColor = colorScheme == .light ? Color.black : Color.white
        
        VStack(spacing: 0) {
            
            // Main navigation bar
            ZStack {
                HStack {
                    // Left side - Settings and Reflect (with brain icon)
                    HStack(spacing: 8) {
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
                        
                        // Only show Reflect button for non-weekly entries
                        if !isWeeklyReflection {
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button(action: {
                                isWeeklyReflection = false
                                showReflectionPanel = true
                                reflectionViewModel.start(apiKey: openAIAPIKey, entryText: text) {
                                    if let currentId = self.selectedEntryId,
                                       let entry = self.entries.first(where: { $0.id == currentId }) {
                                        self.saveEntry(entry: entry)
                                    }
                                }
                            }) {
                                Text("Reflect")
                                    .font(.system(size: 13))
                            } 
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringReflect ? textHoverColor : textColor)
                            .onHover { hovering in
                                isHoveringReflect = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            // Brain icon appears right after Reflect button when reflection has been run
                            if reflectionViewModel.hasBeenRun {
                                Text("•")
                                    .foregroundColor(.gray)
                                
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showReflectionPanel.toggle()
                                    }
                                    if !showReflectionPanel {
                                        isWeeklyReflection = false
                                    }
                                }) {
                                    Image(systemName: "brain.head.profile.fill")
                                        .foregroundColor(isHoveringBrain ? textHoverColor : textColor)
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    isHoveringBrain = hovering
                                    isHoveringBottomNav = hovering
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                    .cornerRadius(6)
                    .onHover { hovering in
                        isHoveringBottomNav = hovering
                    }
                    Spacer()
                    // Right side buttons - Timer, New Entry, History
                    HStack(spacing: 8) {
                        // Timer button (moved to right side)
                        if !isWeeklyReflection {
                            Button(timerButtonTitle) {
                                if timerIsRunning {
                                    timerIsRunning = false
                                    if !isHoveringBottomNav {
                                        withAnimation(.easeOut(duration: 1.0)) {
                                            bottomNavOpacity = 1.0
                                        }
                                    }
                                } else {
                                    timerIsRunning = true
                                    withAnimation(.easeIn(duration: 1.0)) {
                                        bottomNavOpacity = 0.0
                                    }
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
                        }
                        
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
                        
                        // History/sidebar button with new icon
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingSidebar.toggle()
                            }
                        }) {
                            Image(systemName: "book.fill")
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
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .padding(.top, 8)
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
                                .shadow(
                                    color: isRecording
                                        ? (colorScheme == .dark ? Color.clear : Color.clear)
                                        : (colorScheme == .dark ? Color.white.opacity(0.32) : Color.gray.opacity(0.32)),
                                    radius: 12,
                                    y: 3
                                )
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .light ? .gray : .white.opacity(0.85))
                            // Animated white dot on border
                            if isRecording {
                                let angle = Angle(degrees: micDotAngle)
                                let x = dotRadius * cos(angle.radians - .pi/2)
                                let y = dotRadius * sin(angle.radians - .pi/2)
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 5, height: 5)
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
    
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                // Main content area
                Group {
                    if showReflectionPanel {
                        if isWeeklyReflection {
                            centeredReflectionView
                        } else {
                            mainContentWithReflection
                        }
                    } else {
                        mainContent
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showReflectionPanel)
                
                // Navigation is an overlay within each of those views
            }
            .background(Color(colorScheme == .light ? .white : .black))


            // Sidebar
            if showingSidebar {
                sidebar
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: showingSidebar)
        .preferredColorScheme(colorScheme)
        .onAppear {
            showingSidebar = false  // Hide sidebar by default
            loadExistingEntries()
        }
        .onDisappear {
            cleanupRecording()
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
                        apiKey: $openAIAPIKey,
                        onRunWeekly: runWeeklyReflection,
                        colorScheme: $colorScheme,
                        userFontSize: $userFontSize,
                        userSelectedFont: $userSelectedFont,
                        aiFontSize: $aiFontSize,
                        aiSelectedFont: $aiSelectedFont
                    )
                }
            }
        )
        .overlay(
            // Toast Overlay
            toastOverlay
        )
    }
    
    private var mainContent: some View {
        let navHeight: CGFloat = 68
        
        return ZStack {
                Color(colorScheme == .light ? .white : .black)
                    .ignoresSafeArea()
              
                    TextEditor(text: Binding(
                        get: { text },
                        set: { newValue in
                    // Don't allow text changes when voice input is active
                    guard !isVoiceInputMode else { return }
                    
                            // Ensure the text always starts with two newlines
                            if !newValue.hasPrefix("\n\n") {
                                text = "\n\n" + newValue.trimmingCharacters(in: .newlines)
                            } else {
                                text = newValue
                            }
                        }
                    ))
                    .background(Color(colorScheme == .light ? .white : .black))
                    .font(.custom(userSelectedFont, size: userFontSize))
                    .foregroundColor(colorScheme == .light ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .lineSpacing(userLineHeight)
                    .frame(maxWidth: 650)
                    .allowsHitTesting(!isVoiceInputMode && !showingSettings) // Disable interactions during voice input or settings modal
                    
          
                    .id("\(userSelectedFont)-\(userFontSize)-\(colorScheme)")
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
                                    .font(.custom(userSelectedFont, size: userFontSize))
                                    .foregroundColor(colorScheme == .light ? .gray.opacity(0.5) : .gray.opacity(0.6))
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
                    bottomNavigationView
                }
                .ignoresSafeArea(.keyboard) // Prevent keyboard from pushing nav up
            }
    }
    
    @ViewBuilder
    private var sidebar: some View {
            if showingSidebar {
            let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
            let textHoverColor = colorScheme == .light ? Color.black : Color.white
            
                Divider()
                
                VStack(spacing: 0) {
                    // Header
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: getDocumentsDirectory().path)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                Text("Journal")
                                        .font(.system(size: 16))
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
                                                Text(entry.date)
                                                    .font(.system(size: 14))
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
                                            
                                            Text(entry.previewText)
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
            let fullContent = try String(contentsOf: fileURL, encoding: .utf8)
            let separator = "\n\n--- REFLECTION ---\n\n"
            let contentForPreview = fullContent.replacingOccurrences(of: separator, with: " ")
            
            let preview = contentForPreview
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
        
        var contentToSave = text
        if reflectionViewModel.hasBeenRun && !reflectionViewModel.reflectionResponse.isEmpty {
            contentToSave += "\n\n--- REFLECTION ---\n\n" + reflectionViewModel.reflectionResponse
        }
        
        do {
            try contentToSave.write(to: fileURL, atomically: true, encoding: .utf8)
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
                let fullContent = try String(contentsOf: fileURL, encoding: .utf8)
                let separator = "\n\n--- REFLECTION ---\n\n"
                
                if let range = fullContent.range(of: separator) {
                    text = String(fullContent[..<range.lowerBound])
                    reflectionViewModel.reflectionResponse = String(fullContent[range.upperBound...])
                    reflectionViewModel.hasBeenRun = true
                    showReflectionPanel = true // Or false, depending on desired default state
                } else {
                    text = fullContent
                    reflectionViewModel.reflectionResponse = ""
                    reflectionViewModel.hasBeenRun = false
                    showReflectionPanel = false
                }
                
                if entry.filename.hasPrefix("[Weekly]-") {
                    isWeeklyReflection = true
                } else {
                    isWeeklyReflection = false
                }
                
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
        
        // Reset all reflection-related state for a clean slate
        reflectionViewModel.reflectionResponse = ""
        reflectionViewModel.isLoading = false
        reflectionViewModel.error = nil
        reflectionViewModel.hasBeenRun = false
        showReflectionPanel = false
        isWeeklyReflection = false
        
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
        paragraphStyle.lineSpacing = userLineHeight
        
        let font = NSFont(name: userSelectedFont, size: userFontSize) ?? .systemFont(ofSize: userFontSize)
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
        guard !deepgramAPIKey.isEmpty && deepgramAPIKey != "YOUR_DEEPGRAM_API_KEY_HERE" else {
            showToast(message: "DeepGram API key not configured", type: .error)
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
        // Enter voice input mode - remove cursor focus and prepare for voice input
        isVoiceInputMode = true
        
        // Remove focus from text editor by hiding the keyboard/cursor
        DispatchQueue.main.async {
            NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        }
        
        // Reset chunk counter and start initial recording
        chunkCounter = 0
        
        // Start the first recording chunk
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsPath.appendingPathComponent("recording_chunk_0.m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            
            // Start chunked recording timer
            startChunkedRecording()
            
            isRecording = true
            isListening = true
            startMicAnimation()
            // showToast(message: "Recording started", type: .success)
        } catch {
            showToast(message: "Failed to start recording: \(error.localizedDescription)", type: .error)
            isVoiceInputMode = false
        }
    }
    
    func startChunkedRecording() {
        // Start a timer to process audio chunks every 3 seconds
        chunkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.processAudioChunk()
        }
    }
    
    func processAudioChunk() {
        guard isRecording else { return }
        
        // Stop current recording and start a new one
        audioRecorder?.stop()
        
        // Process the current chunk
        if let url = audioRecorder?.url {
            transcribeAudioChunk(url: url, chunkIndex: chunkCounter)
            chunkCounter += 1
        }
        
        // Start recording the next chunk
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsPath.appendingPathComponent("recording_chunk_\(chunkCounter).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
        } catch {
            showToast(message: "Failed to continue recording: \(error.localizedDescription)", type: .error)
            stopRecording()
        }
    }
    
    func stopRecording() {
        // Stop the chunk timer
        chunkTimer?.invalidate()
        chunkTimer = nil
        
        // Stop current recording
        audioRecorder?.stop()
        
        // Process the final chunk if it exists
        if let url = audioRecorder?.url {
            transcribeAudioChunk(url: url, chunkIndex: chunkCounter)
        }
        
        // Exit voice input mode
        isVoiceInputMode = false
        isRecording = false
        isListening = false
        stopMicAnimation()
        
    }
    
    func transcribeAudioChunk(url: URL, chunkIndex: Int) {
        guard !deepgramAPIKey.isEmpty && deepgramAPIKey != "YOUR_DEEPGRAM_API_KEY_HERE" else {
            showToast(message: "DeepGram API key not configured", type: .error)
            return
        }
        
        // Check if the audio file has content (avoid transcribing empty chunks)
        guard let audioData = try? Data(contentsOf: url), audioData.count > 1000 else {
            // Clean up small/empty audio file
            try? FileManager.default.removeItem(at: url)
            return
        }
        
        // Prepare request to DeepGram API
        let apiKey = deepgramAPIKey
        let endpoint = URL(string: "https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        
        // Send request
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Transcription error for chunk \(chunkIndex): \(error)")
                    // Don't show error toast for individual chunks to avoid spam
                    return
                }
                
                guard let data = data else {
                    print("No data returned from DeepGram API for chunk \(chunkIndex)")
                    return
                }
                
                // Check for API errors
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorJson["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            print("DeepGram API Error for chunk \(chunkIndex): \(message)")
                        } else {
                            print("API Error for chunk \(chunkIndex): Status \(httpResponse.statusCode)")
                        }
                        return
                    }
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [String: Any],
                   let channels = results["channels"] as? [[String: Any]],
                   let firstChannel = channels.first,
                   let alternatives = firstChannel["alternatives"] as? [[String: Any]],
                   let firstAlternative = alternatives.first,
                   let textResult = firstAlternative["transcript"] as? String {
                    
                    // Filter out empty or very short transcriptions
                    let cleanedText = textResult.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanedText.isEmpty && cleanedText.count > 2 {
                        // Insert the transcribed text at the end of current text
                        let separator = self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " "
                        self.text += separator + cleanedText.prefix(1).capitalized + cleanedText.dropFirst()
                    }
                } else {
                    print("Failed to parse DeepGram response for chunk \(chunkIndex)")
                }
            }
        }.resume()
        
        // Clean up audio file
        try? FileManager.default.removeItem(at: url)
    }
    
    func transcribeAudio(url: URL) {
        guard !deepgramAPIKey.isEmpty && deepgramAPIKey != "YOUR_DEEPGRAM_API_KEY_HERE" else {
            showToast(message: "DeepGram API key not configured", type: .error)
            return
        }
        
        isTranscribing = true
        
        // Prepare request to DeepGram API
        let apiKey = deepgramAPIKey
        let endpoint = URL(string: "https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        
        // Set request body with audio data
        if let audioData = try? Data(contentsOf: url) {
            request.httpBody = audioData
        }
        
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
                    self.showToast(message: "No response from DeepGram", type: .error)
                    print("No data returned from DeepGram API")
                    return
                }
                
                // Check for API errors
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorJson["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            self.showToast(message: "DeepGram API Error: \(message)", type: .error)
                        } else {
                            self.showToast(message: "API Error: Status \(httpResponse.statusCode)", type: .error)
                        }
                        return
                    }
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [String: Any],
                   let channels = results["channels"] as? [[String: Any]],
                   let firstChannel = channels.first,
                   let alternatives = firstChannel["alternatives"] as? [[String: Any]],
                   let firstAlternative = alternatives.first,
                   let textResult = firstAlternative["transcript"] as? String {
                    // Insert the transcribed text at the end of current text
                    self.text += (self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " ") + textResult.prefix(1).capitalized + textResult.dropFirst()
                    self.showToast(message: "Text transcribed successfully", type: .success)
                } else {
                    self.showToast(message: "Failed to parse transcription response", type: .error)
                    print("Failed to parse DeepGram response: \(String(data: data, encoding: .utf8) ?? "")")
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
    
    func cleanupRecording() {
        // Stop all timers and recording
        chunkTimer?.invalidate()
        chunkTimer = nil
        micDotTimer?.invalidate()
        micDotTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        
        // Reset states
        isRecording = false
        isListening = false
        isVoiceInputMode = false
        isTranscribing = false
    }
    
    // --- End Audio Recording and Whisper API ---
    
    // --- Reflection Functionality ---
    
    class ReflectionViewModel: NSObject, ObservableObject, URLSessionDataDelegate {
        @Published var reflectionResponse: String = ""
        @Published var isLoading: Bool = false
        @Published var error: String? = nil
        @Published var hasBeenRun: Bool = false
        
        private var streamingTask: URLSessionDataTask?
        private var onComplete: (() -> Void)?

        func start(apiKey: String, entryText: String, onComplete: @escaping () -> Void) {
            guard !apiKey.isEmpty else {
                self.error = "Please enter your OpenAI API key in Settings"
                return
            }
            
            guard !entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.error = "Cannot reflect on an empty entry."
                return
            }

            self.reflectionResponse = ""
            self.isLoading = true
            self.error = nil
            self.hasBeenRun = true
            self.onComplete = onComplete

            streamOpenAIResponse(apiKey: apiKey, entryText: entryText)
        }
        
        func startWeeklyReflection(apiKey: String, weeklyContent: String, onComplete: @escaping () -> Void) {
            guard !apiKey.isEmpty else {
                self.error = "Please enter your OpenAI API key in Settings"
                return
            }
            
            guard !weeklyContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.error = "No entries found for the past week."
                return
            }

            self.reflectionResponse = ""
            self.isLoading = true
            self.error = nil
            self.hasBeenRun = true
            self.onComplete = onComplete

            streamWeeklyOpenAIResponse(apiKey: apiKey, weeklyContent: weeklyContent)
        }

        private func streamOpenAIResponse(apiKey: String, entryText: String) {
            let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
            
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let systemPrompt = """
            below is my journal entry for the day. wyt? talk through it with me like a friend. don't therapize me and give me a whole breakdown, don't repeat my thoughts with headings. really take all of this, and tell me back stuff truly as if you're an old homie.

            Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with markdown headings if needed. use new paragrahs to make what you say more readable.

            do not just go through every single thing i say, and say it back to me. you need to process everything i say, make connections i don't see it, and deliver it all back to me as a story that makes me feel what you think i wanna feel. thats what the best therapists do.

            ideally, you're style/tone should sound like the user themselves. it's as if the user is hearing their own tone but it should still feel different, because you have different things to say and don't just repeat back they say.

            else, start by saying, "hey, thanks for showing me this. my thoughts:"

            then after, extract what you think are my wins and losses for the day and put them in a list formatted:

            **Wins:**

            - win #1
            - …

            **Losses:**

            - loss #1
            - …

            then after that pull out the single most important improvement you think I could make (one sentence), and a compliment for me that you would give having observed my thoughts :)

            my raw thoughts:
            """
            
            let payload: [String: Any] = [
                "model": "gpt-4o",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": entryText]
                ],
                "stream": true
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.error = "Failed to prepare request."
                }
                return
            }
            
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            streamingTask = session.dataTask(with: request)
            streamingTask?.resume()
        }
        
        private func streamWeeklyOpenAIResponse(apiKey: String, weeklyContent: String) {
            let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
            
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let systemPrompt = """
            below are my journal entries for the week. sometimes with reflections from a friend. wyt? talk through it with me like a friend. don't therapize me and give me a whole breakdown, don't repeat my thoughts with headings. really take all of this, and tell me back stuff truly as if you're an old homie.

            Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with markdown headings if needed. use new paragrahs to make what you say more readable.

            do not just go through every single thing i say, and say it back to me. you need to process everything i say, make connections i don't see it, and deliver it all back to me as a story that makes me feel what you think i wanna feel. thats what the best therapists do.

            ideally, you're style/tone should sound like the user themselves. it's as if the user is hearing their own tone but it should still feel different, because you have different things to say and don't just repeat back they say.

            else, start by saying, "hey, thanks for showing me this. my thoughts:"

            my entries:

            """
            
            let payload: [String: Any] = [
                "model": "gpt-4o",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": weeklyContent]
                ],
                "stream": true
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.error = "Failed to prepare request."
                }
                return
            }
            
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            streamingTask = session.dataTask(with: request)
            streamingTask?.resume()
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let stringData = String(data: data, encoding: .utf8) ?? ""
            let lines = stringData.split(separator: "\n")
            
            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    
                    if jsonString == "[DONE]" {
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.onComplete?()
                        }
                        return
                    }
                    
                    if let jsonData = jsonString.data(using: .utf8) {
                        do {
                            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                DispatchQueue.main.async {
                                    if self.reflectionResponse.isEmpty {
                                        self.reflectionResponse = "\n\n"
                                    }
                                    self.reflectionResponse += content
                                }
                            }
                        } catch {
                            // JSON parsing error
                        }
                    }
                }
            }
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    // Computed property for toast overlay to avoid type-checking complexity
    private var toastOverlay: some View {
        Group {
            if showToast {
                ToastView(
                    message: toastMessage, 
                    type: toastType,
                    selectedFont: userSelectedFont,
                    fontSize: userFontSize,
                    colorScheme: colorScheme
                )
                .transition(.move(edge: .top))
            }
        }
    }

    // Add this after the mainContent and sidebar view definitions

    @ViewBuilder
    private var reflectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if reflectionViewModel.isLoading && reflectionViewModel.reflectionResponse.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    OscillatingDotView(colorScheme: colorScheme)
                    Spacer()
                }
                .padding(.top, (userFontSize + userLineHeight) * 2)
                .padding(.horizontal, 24)
            } else if let error = reflectionViewModel.error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .padding(.top, 16) // Match vertical padding
            } else {
                let navHeight: CGFloat = 68
                ScrollViewReader { proxy in
                    ScrollView {
                        MarkdownTextView(
                            content: reflectionViewModel.reflectionResponse,
                            font: aiSelectedFont,
                            fontSize: aiFontSize,
                            colorScheme: colorScheme,
                            lineHeight: aiLineHeight
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)

                        Color.white
                            .frame(height: 1)
                            .id("bottomAnchor")
                    }
                    .scrollIndicators(.never)
                    .onChange(of: reflectionViewModel.reflectionResponse) { _ in
                        // Only auto-scroll to bottom when AI is actively streaming
                        if reflectionViewModel.isLoading {
                            withAnimation {
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(colorScheme == .light ? .white : .black))
    }

    @ViewBuilder
    private var centeredReflectionView: some View {
        let navHeight: CGFloat = 68
        
        ZStack {
            Color(colorScheme == .light ? .white : .black)
                .ignoresSafeArea()
            
            if reflectionViewModel.isLoading && reflectionViewModel.reflectionResponse.isEmpty {
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        OscillatingDotView(colorScheme: colorScheme)
                        Spacer()
                    }
                    .frame(maxWidth: 650, alignment: .leading)
                    .padding(.top, ((userFontSize + userLineHeight) * 2) + 1.5)
                    .padding(.horizontal, 24)
                    .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        viewHeight = height
                    }
                    .contentMargins(.bottom, viewHeight / 4)
                }
                .scrollIndicators(.never)
            } else if let error = reflectionViewModel.error {
                VStack {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .frame(maxWidth: 650)
                    Spacer()
                }
                .padding(.top, 16)
            } else {
                ZStack {
                    Color(colorScheme == .light ? .white : .black)
                        .ignoresSafeArea()
                    
                    VStack {
                        ScrollViewReader { proxy in
                            ScrollView {
                                MarkdownTextView(
                                    content: reflectionViewModel.reflectionResponse,
                                    font: aiSelectedFont,
                                    fontSize: aiFontSize,
                                    colorScheme: colorScheme,
                                    lineHeight: aiLineHeight
                                )
                                .frame(maxWidth: 650, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { height in
                                    viewHeight = height
                                }
                                .contentMargins(.bottom, viewHeight / 4)

                                Color.white
                                    .frame(height: 1)
                                    .id("bottomAnchor")
                            }
                            .scrollIndicators(.never)
                            .onChange(of: reflectionViewModel.reflectionResponse) { _ in
                                // Only auto-scroll to bottom when AI is actively streaming
                                if reflectionViewModel.isLoading {
                                    withAnimation {
                                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    
                    VStack {
                        Spacer()
                        ZStack {
                            // Always-visible background to prevent text bleed-through
                            Rectangle()
                                .fill(Color(colorScheme == .light ? .white : .black))
                                .frame(height: 68)
                            
                            bottomNavigationView
                        }
                    }
                    .ignoresSafeArea(.keyboard)
                }
            }
        }
    }

    @ViewBuilder
    private var mainContentWithReflection: some View {
        let navHeight: CGFloat = 68
        ZStack {
            // Split content view (behind navigation)
            HStack(spacing: 0) {
                // Left side - User's text (50% of screen width)
                ZStack {
                    Color(colorScheme == .light ? .white : .black)
                        .ignoresSafeArea()
                    
                    TextEditor(text: Binding(
                        get: { text },
                        set: { newValue in
                            guard !isVoiceInputMode else { return }
                            
                            if !newValue.hasPrefix("\n\n") {
                                text = "\n\n" + newValue.trimmingCharacters(in: .newlines)
                            } else {
                                text = newValue
                            }
                        }
                    ))
                    .background(Color(colorScheme == .light ? .white : .black))
                    .font(.custom(userSelectedFont, size: userFontSize))
                    .foregroundColor(colorScheme == .light ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .lineSpacing(userLineHeight)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(!isVoiceInputMode && !showingSettings)
                    .padding(.horizontal, 24)
                    .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                    .ignoresSafeArea()
                    .colorScheme(colorScheme)
                    .overlay(
                        ZStack(alignment: .topLeading) {
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(placeholderText)
                                    .font(.custom(userSelectedFont, size: userFontSize))
                                    .foregroundColor(colorScheme == .light ? .gray.opacity(0.5) : .gray.opacity(0.6))
                                    .allowsHitTesting(false)
                                    .offset(x: 29, y: placeholderOffset)
                            }
                        }, alignment: .topLeading
                    )
                }
                
                // Center divider
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                    .frame(width: 1)
                
                // Right side - Reflection content (50% of screen width)
                reflectionContent
                    .background(Color(colorScheme == .light ? .white : .black))
            }
            
            // Navigation overlay (stays on top)
            VStack {
                Spacer()
                bottomNavigationView
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}

// Add these view structs before the main ContentView struct
struct SettingsModal: View {
    @Binding var showingSettings: Bool
    @Binding var selectedSettingsTab: SettingsTab
    @Binding var apiKey: String
    let onRunWeekly: () -> Void
    
    // Style bindings
    @Binding var colorScheme: ColorScheme
    @Binding var userFontSize: CGFloat
    @Binding var userSelectedFont: String
    @Binding var aiFontSize: CGFloat
    @Binding var aiSelectedFont: String
    
    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedTab: $selectedSettingsTab)
            SettingsContent(
                selectedTab: selectedSettingsTab,
                apiKey: $apiKey,
                onRunWeekly: onRunWeekly,
                colorScheme: $colorScheme,
                userFontSize: $userFontSize,
                userSelectedFont: $userSelectedFont,
                aiFontSize: $aiFontSize,
                aiSelectedFont: $aiSelectedFont
            )
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
                    title: "Reflections",
                    icon: "calendar",
                    isSelected: selectedTab == .reflections,
                    action: { selectedTab = .reflections }
                )
                
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
                    .fill(isSelected ? .primary : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsContent: View {
    let selectedTab: SettingsTab
    @Binding var apiKey: String
    let onRunWeekly: () -> Void
    
    // Style bindings
    @Binding var colorScheme: ColorScheme
    @Binding var userFontSize: CGFloat
    @Binding var userSelectedFont: String
    @Binding var aiFontSize: CGFloat
    @Binding var aiSelectedFont: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selectedTab {
            case .ai:
                AISettingsView(apiKey: $apiKey)
            case .style:
                StyleSettingsView(
                    colorScheme: $colorScheme,
                    userFontSize: $userFontSize,
                    userSelectedFont: $userSelectedFont,
                    aiFontSize: $aiFontSize,
                    aiSelectedFont: $aiSelectedFont
                )
            case .reflections:
                ReflectionsSettingsView(onRunNow: onRunWeekly)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

struct AISettingsView: View {
    @Binding var apiKey: String
    @State private var tempApiKey: String = ""
    @State private var hasUnsavedChanges: Bool = false
    @State private var showSaveConfirmation: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // OpenAI API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                SecureField("Enter your OpenAI API key", text: $tempApiKey)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary, lineWidth: 1)
                    )
                    .frame(maxWidth: 300)
                    .onChange(of: tempApiKey) { newValue in
                        hasUnsavedChanges = (newValue != apiKey)
                    }
                
                Text("Your API key is stored locally and only used for reflection.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Save button
                HStack(spacing: 12) {
                    Button(action: {
                        // Save API key to Keychain when save button is clicked
                        if !tempApiKey.isEmpty {
                            KeychainHelper.shared.saveAPIKey(tempApiKey)
                            apiKey = tempApiKey
                        } else {
                            KeychainHelper.shared.deleteAPIKey()
                            apiKey = ""
                        }
                        hasUnsavedChanges = false
                        showSaveConfirmation = true
                        
                        // Hide confirmation after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showSaveConfirmation = false
                        }
                    }) {
                        Text("Save")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(hasUnsavedChanges ? .primary : .secondary)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!hasUnsavedChanges)
                    
                    if showSaveConfirmation {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.primary)
                                .font(.system(size: 12))
                            Text("Saved")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showSaveConfirmation)
            }
            .padding(.top, 8)
        }
        .onAppear {
            // Load the current API key when the view appears
            tempApiKey = apiKey
        }
    }
}

struct StyleSettingsView: View {
    @Binding var colorScheme: ColorScheme
    @Binding var userFontSize: CGFloat
    @Binding var userSelectedFont: String
    @Binding var aiFontSize: CGFloat
    @Binding var aiSelectedFont: String
    
    let fontSizes: [CGFloat] = [16, 18, 20, 22, 24, 26]
    let standardFonts = ["Lato-Regular", "Arial", ".AppleSystemUIFont", "Times New Roman"]
    let availableFonts = NSFontManager.shared.availableFontFamilies
    
    @State private var userHoveredFont: String? = nil
    @State private var aiHoveredFont: String? = nil
    @State private var currentRandomFont: String = ""
    @State private var currentAIRandomFont: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Theme Toggle
            HStack {
                Text("Theme")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button(action: {
                    colorScheme = colorScheme == .light ? .dark : .light
                    UserDefaults.standard.set(colorScheme == .light ? "light" : "dark", forKey: "colorScheme")
                }) {
                    Image(systemName: colorScheme == .light ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // My Writing Style
            VStack(alignment: .leading, spacing: 12) {
                Text("My Writing Style")
                    .font(.system(size: 14, weight: .medium))
                
                HStack {
                    Text("Font Size")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("Font Size", selection: $userFontSize) {
                        ForEach(fontSizes, id: \.self) { size in
                            Text("\(Int(size))px").tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 100)
                }
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Text("Font Family")
                            .font(.system(size: 13))
                        Spacer()
                        FontButton(title: "Lato", selectedFont: $userSelectedFont, hoveredFont: $userHoveredFont, fontName: "Lato-Regular")
                        FontButton(title: "Arial", selectedFont: $userSelectedFont, hoveredFont: $userHoveredFont, fontName: "Arial")
                        FontButton(title: "System", selectedFont: $userSelectedFont, hoveredFont: $userHoveredFont, fontName: ".AppleSystemUIFont")
                        FontButton(title: "Serif", selectedFont: $userSelectedFont, hoveredFont: $userHoveredFont, fontName: "Times New Roman")
                    }
                    
                    HStack {
                        Spacer()
                        Button(currentRandomFont.isEmpty ? "Random" : "Random [\(currentRandomFont)]") {
                            if let randomFont = availableFonts.randomElement() {
                                userSelectedFont = randomFont
                                currentRandomFont = randomFont
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(userHoveredFont == "Random" ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(userHoveredFont == "Random" ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                userHoveredFont = hovering ? "Random" : nil
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // AI Writing Style
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Writing Style")
                    .font(.system(size: 14, weight: .medium))
                
                HStack {
                    Text("Font Size")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("Font Size", selection: $aiFontSize) {
                        ForEach(fontSizes, id: \.self) { size in
                            Text("\(Int(size))px").tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 100)
                }
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Text("Font Family")
                            .font(.system(size: 13))
                        Spacer()
                        FontButton(title: "Lato", selectedFont: $aiSelectedFont, hoveredFont: $aiHoveredFont, fontName: "Lato-Regular")
                        FontButton(title: "Arial", selectedFont: $aiSelectedFont, hoveredFont: $aiHoveredFont, fontName: "Arial")
                        FontButton(title: "System", selectedFont: $aiSelectedFont, hoveredFont: $aiHoveredFont, fontName: ".AppleSystemUIFont")
                        FontButton(title: "Serif", selectedFont: $aiSelectedFont, hoveredFont: $aiHoveredFont, fontName: "Times New Roman")
                    }
                    
                    HStack {
                        Spacer()
                        Button(currentAIRandomFont.isEmpty ? "Random" : "Random [\(currentAIRandomFont)]") {
                            if let randomFont = availableFonts.randomElement() {
                                aiSelectedFont = randomFont
                                currentAIRandomFont = randomFont
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(aiHoveredFont == "Random" ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(aiHoveredFont == "Random" ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                aiHoveredFont = hovering ? "Random" : nil
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }
}

struct FontButton: View {
    let title: String
    @Binding var selectedFont: String
    @Binding var hoveredFont: String?
    let fontName: String
    
    @Environment(\.colorScheme) var colorScheme
    
    private var isSelected: Bool {
        selectedFont == fontName
    }
    
    private var isHovered: Bool {
        hoveredFont == title
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        }
        if isHovered {
            return colorScheme == .light ? .black : .white
        }
        return .secondary
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .primary
        }
        if isHovered {
            return Color.primary.opacity(0.1)
        }
        return .clear
    }
    
    var body: some View {
        Button(title) {
            selectedFont = fontName
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundColor(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredFont = hovering ? title : nil
            }
        }
    }
}

struct ReflectionsSettingsView: View {
    @State private var selectedDay: String = "Sunday"
    @State private var reflectionTime: Date = Calendar.current.date(from: DateComponents(hour: 10, minute: 0)) ?? Date()
    let daysOfWeek = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    let onRunNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 8) {
                Picker("Reflect every", selection: $selectedDay) {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                    }
                }
                .font(.system(size: 14))
                .pickerStyle(MenuPickerStyle())
                
                DatePicker("at", selection: $reflectionTime, displayedComponents: .hourAndMinute)
                    .font(.system(size: 14))
                    .datePickerStyle(CompactDatePickerStyle())
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Button("Run now") {
                    onRunNow()
                }
            }
            .foregroundColor(.secondary)
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

// OscillatingDotView: Animated loading dot for reflection loading state
struct OscillatingDotView: View {
    @State private var scale: CGFloat = 1.0
    let colorScheme: ColorScheme
    
    var body: some View {
        Circle()
            .fill(colorScheme == .light ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9))
            .frame(width: 16, height: 16)
            .scaleEffect(scale)
            .onAppear {
                let animation = Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                withAnimation(animation) {
                    self.scale = 1.2
                }
            }
    }
}

// MarkdownTextView: Renders markdown content with proper styling
struct MarkdownTextView: View {
    let content: String
    let font: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme
    let lineHeight: CGFloat
    
    @State private var attributedString: AttributedString = AttributedString()
    
    var body: some View {
        Text(attributedString)
            .textSelection(.enabled)
            .lineSpacing(lineHeight)
            .onAppear {
                updateAttributedString()
            }
            .onChange(of: content) { _ in
                updateAttributedString()
            }
            .onChange(of: font) { _ in
                updateAttributedString()
            }
            .onChange(of: fontSize) { _ in
                updateAttributedString()
            }
            .onChange(of: colorScheme) { _ in
                updateAttributedString()
            }
    }
    
    private func updateAttributedString() {
        do {
            // Parse markdown content
            var parsed = try AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            
            // Apply base font and color
            let baseFont = NSFont(name: font, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let textColor = colorScheme == .light ? 
                NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0) : 
                NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
            
            // Apply base styling to entire string
            parsed.font = baseFont
            parsed.foregroundColor = textColor
            
            // Apply custom styling for markdown elements
            for run in parsed.runs {
                let range = run.range
                
                // Handle bold text
                if let intent = run.inlinePresentationIntent, intent.contains(.stronglyEmphasized) {
                    let boldFont = NSFont(name: font.replacingOccurrences(of: "Regular", with: "Bold"), size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
                    parsed[range].font = boldFont
                }
                
                // Handle italic text
                if let intent = run.inlinePresentationIntent, intent.contains(.emphasized) {
                    let italicFont = NSFont(name: font.replacingOccurrences(of: "Regular", with: "Italic"), size: fontSize) ?? {
                        // Fallback to system italic if custom font doesn't have italic variant
                        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
                        return NSFont(descriptor: descriptor, size: fontSize) ?? baseFont
                    }()
                    parsed[range].font = italicFont
                }
                
                // Handle code spans
                if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                    let codeFont = NSFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: .regular)
                    parsed[range].font = codeFont
                    parsed[range].backgroundColor = colorScheme == .light ? 
                        NSColor.lightGray.withAlphaComponent(0.2) : 
                        NSColor.darkGray.withAlphaComponent(0.3)
                }
                
                // Handle headers by checking presentation intent
                if let intent = run.presentationIntent {
                    let intentString = "\(intent)"
                    if intentString.contains("header(level: 1)") {
                        let headerFont = NSFont(name: font.replacingOccurrences(of: "Regular", with: "Bold"), size: fontSize * 1.5) ?? NSFont.boldSystemFont(ofSize: fontSize * 1.5)
                        parsed[range].font = headerFont
                    } else if intentString.contains("header(level: 2)") {
                        let headerFont = NSFont(name: font.replacingOccurrences(of: "Regular", with: "Bold"), size: fontSize * 1.3) ?? NSFont.boldSystemFont(ofSize: fontSize * 1.3)
                        parsed[range].font = headerFont
                    } else if intentString.contains("header(level: 3)") {
                        let headerFont = NSFont(name: font.replacingOccurrences(of: "Regular", with: "Bold"), size: fontSize * 1.1) ?? NSFont.boldSystemFont(ofSize: fontSize * 1.1)
                        parsed[range].font = headerFont
                    }
                }
            }
            
            self.attributedString = parsed
            
        } catch {
            // If markdown parsing fails, fall back to plain text
            print("Markdown parsing failed: \(error)")
            var fallback = AttributedString(content)
            fallback.font = NSFont(name: font, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            fallback.foregroundColor = colorScheme == .light ? 
                NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0) : 
                NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
            self.attributedString = fallback
        }
    }
}

#Preview {
    ContentView()
}
