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
    case apiKeys = "API Keys"
    case transcription = "Transcription"
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
    
    enum KeyType: String {
        case openAI = "openai_api_key"
        case deepgram = "deepgram_api_key"
    }
    
    func saveAPIKey(_ key: String, for type: KeyType) {
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: type.rawValue,
            kSecValueData as String: data
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to save API key to Keychain for account \(type.rawValue): \(status)")
        }
    }
    
    func loadAPIKey(for type: KeyType) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: type.rawValue,
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
    
    func deleteAPIKey(for type: KeyType) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: type.rawValue
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

class ContentViewController: NSObject, URLSessionDataDelegate {
    // You can move the URLSession delegate methods here if you prefer
    // to keep ContentView cleaner. For now, we'll keep them in the extension.
}

// Section type for alternating user/reflection
enum EntrySectionType {
    case user
    case reflection
}

struct EntrySection: Identifiable, Equatable {
    let id = UUID()
    var type: EntrySectionType
    var text: String
    static func == (lhs: EntrySection, rhs: EntrySection) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.text == rhs.text
    }
}

struct ContentView: View {
    // Global navigation height constant
    private let navHeight: CGFloat = 59
    
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""  // Initialize as empty string without "\n\n"
    
    @State private var isFullscreen = false
    @State private var userSelectedFont: String = "Lato-Regular" // Renamed from selectedFont
    @State private var currentRandomFont: String = "" 
    @State private var currentAIRandomFont: String = ""
    @State private var timeRemaining: Int = 600  // Changed to 600 seconds (10 minutes)
    @State private var timerIsRunning = false
    @State private var isHoveringTimer = false
    @State private var isHoveringTheme = false
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
    @State private var showingChatMenu = false
    @State private var chatMenuAnchor: CGPoint = .zero
    @State private var showingSidebar = false  // Add this state variable
    @State private var hoveredTrashId: UUID? = nil
    @State private var hoveredExportId: UUID? = nil
    @State private var placeholderText: String = ""  // Add this line
    @State private var isHoveringNewEntry = false
    @State private var isHoveringFullscreen = false
    @State private var isHoveringClock = false
    @State private var isHoveringHistory = false
    @State private var isHoveringHistoryText = false
    @State private var isHoveringHistoryPath = false
    @State private var isHoveringHistoryArrow = false

    @State private var isHoveringReflect = false
    @State private var isHoveringSidebar = false
    @State private var colorScheme: ColorScheme = .light // Add state for color scheme

    @State private var didCopyPrompt: Bool = false // Add state for copy prompt feedback
    @State private var showingSettings = false // Add state for settings menu
    @State private var isHoveringSettings = false // Add state for settings hover
    @State private var selectedSettingsTab: SettingsTab = .reflections // Add state for selected tab
    @State private var openAIAPIKey: String = ""
    @State private var deepgramAPIKey: String = ""
    @StateObject private var reflectionViewModel = ReflectionViewModel()
    @State private var followUpText: String = ""
    @State private var showMicrophone: Bool = true
    
    // Add state for reflection functionality
    @State private var showReflectionPanel: Bool = false
    @State private var isWeeklyReflection: Bool = false
    @State private var hasInitiatedReflection: Bool = false
    
    @State private var sections: [EntrySection] = [] // All USER and REFLECTION sections
    @State private var editingText: String = "" // Current text being edited (always the latest USER section)
    @State private var isStreamingReflection: Bool = false // Freeze text editor during streaming
    
    @State private var shouldScrollToBottom: Bool = false
    
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
    
    // Focus states for text editors
    @FocusState private var isFollowUpFocused: Bool
    @FocusState private var isUserEditorFocused: Bool

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
        let savedAPIKey = KeychainHelper.shared.loadAPIKey(for: .openAI) ?? ""
        _openAIAPIKey = State(initialValue: savedAPIKey)
        
        // Load saved Deepgram API key from Keychain (secure storage)
        let savedDeepgramKey = KeychainHelper.shared.loadAPIKey(for: .deepgram) ?? ""
        _deepgramAPIKey = State(initialValue: savedDeepgramKey)
        
        // Load saved show microphone preference
        _showMicrophone = State(initialValue: UserDefaults.standard.object(forKey: "showMicrophone") as? Bool ?? true)
    }
    
    private func buildFullConversationContext() -> String {
        var context = ""
        
        // Add all previous sections chronologically
        for section in sections {
            if section.type == .user {
                if !context.isEmpty {
                    context += "\n\n--- PREVIOUS USER ENTRY ---\n\n"
                } else {
                    context += "--- PREVIOUS USER ENTRY ---\n\n"
                }
                context += section.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                context += "\n\n--- PREVIOUS REFLECTION ---\n\n"
                context += section.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Add current editing text as the new entry to reflect on
        if !context.isEmpty {
            context += "\n\n--- CURRENT NEW ENTRY ---\n\n"
        } else {
            context += "--- CURRENT NEW ENTRY ---\n\n"
        }
        context += editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return context
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
                    // Remove separators from preview
                    let cleanedPreview = removeReflectionSeparators(from: contentForPreview)
                    
                    let preview = cleanedPreview
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
            
            // Ensure previewText is always cleaned of section headers
            for entry in entries {
                updatePreviewText(for: entry)
            }
            
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
        if isHoveringTimer {
            return colorScheme == .light ? .black : .white
        } else {
            return colorScheme == .light ? .gray : .gray.opacity(0.8)
        }
    }
    
    var userLineHeight: CGFloat {
        let font = NSFont(name: userSelectedFont, size: userFontSize) ?? .systemFont(ofSize: userFontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (userFontSize * 1.5) - defaultLineHeight
    }
    
    var placeholderOffset: CGFloat {
        // Instead of using calculated line height, use a simple offset
        // Add extra offset to account for line spacing and positioning differences
        return userFontSize * 2.2
    }
    
    var aiLineHeight: CGFloat {
        return userFontSize * 1.5
    }
    
    // Add a color utility computed property
    var popoverBackgroundColor: Color {
        return colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(NSColor.darkGray)
    }
    
    var popoverTextColor: Color {
        return colorScheme == .light ? Color.primary : Color.white
    }
    
    // Add missing computed properties from reference file
    var fontSizeButtonTitle: String {
        return "\(Int(userFontSize))px"
    }
    
    var randomButtonTitle: String {
        return currentRandomFont.isEmpty ? "Random" : "Random [\(currentRandomFont)]"
    }
    
    // Add state variables for font hover states
    @State private var isHoveringSize = false
    @State private var hoveredFont: String? = nil
    
    @ViewBuilder
    private var bottomNavigationView: some View {
        let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
        let textHoverColor = colorScheme == .light ? Color.black : Color.white
        
        VStack(spacing: 0) {
            
            // Main navigation bar
            ZStack(alignment: .center) {
                HStack(alignment: .center) {
                    // Left side - Navigation Controls: Sidebar, New Entry, Timer
                    HStack(spacing: 8) {
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
                        
                        Button("Fullscreen") {
                            if !isFullscreen {
                                if let window = NSApplication.shared.windows.first {
                                    window.toggleFullScreen(nil)
                                }
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
                        
                        // Timer button
                        if !isWeeklyReflection {
                            Text("•")
                                .foregroundColor(.gray)
                            
                            Button(timerButtonTitle) {
                                if timerIsRunning {
                                    timerIsRunning = false
                                    if !isHoveringBottomNav {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            bottomNavOpacity = 1.0
                                        }
                                    }
                                } else {
                                    timerIsRunning = true
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        bottomNavOpacity = 0.0
                                    }
                                }
                                
                                // Force reset hover state after clicking
                                isHoveringTimer = false
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
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        // This ensures we're actually over the button when scrolling
                                    }
                            )
                            .onAppear {
                                NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                                    // Only process scroll if we're actually hovering AND the button is visible
                                    if isHoveringTimer && !isWeeklyReflection {
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
                    }
                    .padding(8)
                    .cornerRadius(6)
                    .onHover { hovering in
                        isHoveringBottomNav = hovering
                    }
                    Spacer()
                    // Right side - Style Controls: Reflect, Dark Mode, Size, Fonts
                    HStack(spacing: 8) {
                        // Only show Reflect button for non-weekly entries
                        if !isWeeklyReflection {
                            // Toggle reflection panel button (only show if reflection has been initiated)
                            if hasInitiatedReflection {
                                
                                Button(action: {
                                    showReflectionPanel.toggle()
                                }) {
                                    Image(systemName: showReflectionPanel ? "sidebar.right" : "sidebar.left")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringSidebar ? textHoverColor : textColor)
                                .onHover { hovering in
                                    isHoveringSidebar = hovering
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }

                                Text("•")
                                    .foregroundColor(.gray)
                            }
                            
                            Button(action: {
                                if editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    showToast(message: "Empty! Write something and try again.", type: .error)
                                    return
                                }
                                
                                // Update the latest USER section with current editing text
                                if let lastIndex = sections.lastIndex(where: { $0.type == .user }) {
                                    sections[lastIndex].text = editingText
                                }
                                
                                // Add new REFLECTION section (will be filled during streaming)
                                sections.append(EntrySection(type: .reflection, text: ""))
                                
                                // Show reflection panel and freeze text editor
                                showReflectionPanel = true
                                hasInitiatedReflection = true
                                isStreamingReflection = true
                                
                                // Build full conversation context including all previous sections
                                let fullContext = buildFullConversationContext()
                                
                                // Start reflection with streaming to file
                                reflectionViewModel.start(apiKey: openAIAPIKey, entryText: fullContext) {
                                    // On complete: add new empty USER section (not copying previous text), unfreeze editor, and save
                                    sections.append(EntrySection(type: .user, text: "\n\n"))
                                    editingText = "\n\n"
                                    isStreamingReflection = false
                                    if let currentId = selectedEntryId,
                                       let entry = entries.first(where: { $0.id == currentId }) {
                                        saveEntry(entry: entry)
                                    }
                                } onStream: { streamedText in
                                    // Update the latest REFLECTION section as it streams
                                    if let lastReflectionIndex = sections.lastIndex(where: { $0.type == .reflection }) {
                                        sections[lastReflectionIndex].text = streamedText
                                    }
                                    // Save to file during streaming
                                    if let currentId = selectedEntryId,
                                       let entry = entries.first(where: { $0.id == currentId }) {
                                        saveEntry(entry: entry)
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
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                        }
                        
                        // Theme toggle
                        Button(action: {
                            colorScheme = colorScheme == .light ? .dark : .light
                            UserDefaults.standard.set(colorScheme == .light ? "light" : "dark", forKey: "colorScheme")
                        }) {
                            Image(systemName: colorScheme == .light ? "moon.fill" : "sun.max.fill")
                                .foregroundColor(isHoveringTheme ? textHoverColor : textColor)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isHoveringTheme = hovering
                            isHoveringBottomNav = hovering
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        
                        Text("•")
                            .foregroundColor(.gray)
                        
                        // Font size button
                        Button(fontSizeButtonTitle) {
                            let fontSizes: [CGFloat] = [16, 18, 20, 22, 24, 26]
                            if let currentIndex = fontSizes.firstIndex(of: userFontSize) {
                                let nextIndex = (currentIndex + 1) % fontSizes.count
                                let newSize = fontSizes[nextIndex]
                                userFontSize = newSize
                                aiFontSize = newSize
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
                            userSelectedFont = "Lato-Regular"
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
                            userSelectedFont = "Arial"
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
                            userSelectedFont = ".AppleSystemUIFont"
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
                            userSelectedFont = "Times New Roman"
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
                                userSelectedFont = randomFont
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
                }
                
                // Microphone Button (centered in navbar)
                if showMicrophone {
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
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .background(Color(colorScheme == .light ? .white : .black))
                .opacity(bottomNavOpacity)
                .onHover { hovering in
                    isHoveringBottomNav = hovering
                    if hovering {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            bottomNavOpacity = 1.0
                        }
                    } else if timerIsRunning || isRecording {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            bottomNavOpacity = 0.0
                        }
                    }
                }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            if showingSidebar {
                sidebar
            }
            
            ZStack {
                // Main content area
                Group {
                    if isWeeklyReflection {
                        centeredReflectionView
                    } else {
                        mainContent
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showReflectionPanel)
                
                // Navigation is an overlay within each of those views
            }
            .background(Color(colorScheme == .light ? .white : .black))
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
        .onChange(of: userFontSize) { newValue in
            aiFontSize = newValue
        }
        .onReceive(timer) { _ in
            if timerIsRunning && timeRemaining > 0 {
                timeRemaining -= 1
            } else if timeRemaining == 0 {
                timerIsRunning = false
                if !isHoveringBottomNav {
                    withAnimation(.easeInOut(duration: 1.0)) {
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
                        openAIapiKey: $openAIAPIKey,
                        deepgramApiKey: $deepgramAPIKey,
                        showMicrophone: $showMicrophone,
                        onRunWeekly: runWeeklyReflection
                    )
                }
            }
        )
        .overlay(
            // Toast Overlay
            toastOverlay
        )
        .onChange(of: reflectionViewModel.isLoading) { isLoading in
            if isLoading {
                isUserEditorFocused = false
            }
        }
    }
    
    private var mainContent: some View {
        ZStack {
            Color(colorScheme == .light ? .white : .black)
                .ignoresSafeArea()
            
            HStack(alignment: .top, spacing: 0) {
                // Left side - Text Editor
                VStack(spacing: 0) {
                    TextEditor(text: Binding(
                        get: { editingText },
                        set: { newValue in
                            // Ensure the text starts with two newlines for proper spacing
                            if !newValue.hasPrefix("\n\n") && !newValue.isEmpty {
                                editingText = "\n\n" + newValue.trimmingCharacters(in: .newlines)
                            } else {
                                editingText = newValue
                            }
                            // Update the last user section
                            if let lastUserIdx = sections.lastIndex(where: { $0.type == .user }) {
                                sections[lastUserIdx].text = editingText
                            }
                            if let currentId = selectedEntryId,
                               let currentEntry = entries.first(where: { $0.id == currentId }) {
                                saveEntry(entry: currentEntry)
                            }
                        }
                    ))
                    .font(.custom(userSelectedFont, size: userFontSize))
                    .foregroundColor(colorScheme == .light ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.90, green: 0.90, blue: 0.90))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .lineSpacing(userLineHeight)
                    .frame(maxWidth: showReflectionPanel ? .infinity : 650)
                    .padding(.horizontal, showReflectionPanel ? 24 : 16)
                    .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                    .background(Color.clear)
                    .textSelection(.enabled)
                    .disabled(reflectionViewModel.isLoading || isStreamingReflection)
                    .focused($isUserEditorFocused)
                    .overlay(
                        ZStack(alignment: .topLeading) {
                            if editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(placeholderText)
                                    .font(.custom(userSelectedFont, size: userFontSize))
                                    .foregroundColor(colorScheme == .light ? .gray.opacity(0.5) : .gray.opacity(0.6))
                                    .allowsHitTesting(false)
                                    .offset(x: showReflectionPanel ? 29 : 21, y: placeholderOffset)
                            }
                        }, alignment: .topLeading
                    )
                    .ignoresSafeArea()
                }
                
                // Divider (only show when reflection panel is visible)
                if showReflectionPanel {
                    Divider()
                        .opacity(showReflectionPanel ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.3), value: showReflectionPanel)
                }
                
                // Right side - Reflection Panel
                if showReflectionPanel {
                    VStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    // Show all sections except the latest USER section
                                    let sectionsToShow = sections.dropLast(sections.last?.type == .user ? 1 : 0)
                                    
                                    ForEach(Array(sectionsToShow.enumerated()), id: \.element.id) { index, section in
                                        VStack(alignment: .leading, spacing: 0) {
                                            if section.type == .user {
                                                // Show user text (no background, gray color) with padding to match reflection text
                                                Text(section.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                                    .font(.custom(userSelectedFont, size: userFontSize))
                                                    .foregroundColor(colorScheme == .light ? Color.gray : Color.gray.opacity(0.8))
                                                    .lineSpacing(userLineHeight)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.horizontal, 16) // Add horizontal padding to match reflection text
                                                    .padding(.top, 16) // Add top padding to match bottom
                                                    .padding(.bottom, 16)
                                            } else {
                                                // Show reflection content with proper styling
                                                VStack(alignment: .leading, spacing: 0) {
                                                    if section.text.isEmpty && reflectionViewModel.isLoading {
                                                        // Show loading for empty reflection being streamed
                                                        HStack(alignment: .top, spacing: 0) {
                                                            OscillatingDotView(colorScheme: colorScheme)
                                                            Spacer()
                                                        }
                                                    } else if !section.text.isEmpty {
                                                        // Show reflection content with user's line height (not AI line height)
                                                        MarkdownTextView(
                                                            content: section.text,
                                                            font: userSelectedFont,
                                                            fontSize: userFontSize,
                                                            colorScheme: colorScheme,
                                                            lineHeight: userLineHeight  // Use user line height for proper spacing
                                                        )
                                                        .id(userFontSize)
                                                        .id(userSelectedFont)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .frame(minHeight: userFontSize * 1.5 + 32)
                                                    }
                                                }
                                                .padding()
                                                .frame(minHeight: userFontSize * 1.5 + 32)
                                                .background(Color.gray.opacity(0.1))
                                                .cornerRadius(12)
                                            }
                                        }
                                    }
                                    
                                    VStack(spacing: 0) { EmptyView() }.id("reflectionBottomAnchor")
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 38)
                                .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
                            }
                            .scrollIndicators(.never)
                            .onChange(of: sections) { _ in
                                // Only scroll when we're actively streaming a reflection
                                if isStreamingReflection || reflectionViewModel.isLoading {
                                    withAnimation {
                                        // If navbar is visible, scroll to top of anchor (content above navbar)
                                        // If navbar is hidden, scroll to bottom of anchor (bottom of page)
                                        let anchor: UnitPoint = bottomNavOpacity > 0 ? .top : .bottom
                                        proxy.scrollTo("reflectionBottomAnchor", anchor: anchor)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(showReflectionPanel ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.3), value: showReflectionPanel)
                }
            }
            
            VStack {
                Spacer()
                bottomNavigationView
            }
            .animation(nil, value: showReflectionPanel)
            .ignoresSafeArea(.keyboard)
        }
    }
    
    @ViewBuilder
    private var sidebar: some View {
        if showingSidebar {
            let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
            let textHoverColor = colorScheme == .light ? Color.black : Color.white
            
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    // Header with settings button
                    HStack(alignment: .firstTextBaseline) {
                        Button(action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: getDocumentsDirectory().path)
                        }) {
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
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isHoveringHistory = hovering
                        }
                        
                        Spacer()
                        
                        // Settings button moved to sidebar - aligned with journal title
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
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    
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
                                            updatePreviewText(for: currentEntry)
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
                // Add right border
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1)
                    .edgesIgnoringSafeArea(.vertical)
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
            let fullContent = try String(contentsOf: fileURL, encoding: .utf8)
            let userSeparator = "--- USER ---"
            let reflectionSeparator = "--- REFLECTION ---"
            let userRange = (fullContent as NSString).range(of: userSeparator)
            let reflectionRange = (fullContent as NSString).range(of: reflectionSeparator)
            var preview = ""
            if userRange.location != NSNotFound {
                if reflectionRange.location != NSNotFound {
                    let userStart = userRange.location + userRange.length
                    let userEnd = reflectionRange.location
                    if userEnd > userStart {
                        let userText = (fullContent as NSString).substring(with: NSRange(location: userStart, length: userEnd - userStart)).trimmingCharacters(in: .whitespacesAndNewlines)
                        preview = userText
                    } else {
                        // If reflection comes before user, or range is invalid, just take from user start to end of string.
                        let userStart = userRange.location + userRange.length
                        preview = (fullContent as NSString).substring(from: userStart)
                    }
                } else {
                    let userStart = userRange.location + userRange.length
                    let userText = (fullContent as NSString).substring(from: userStart).trimmingCharacters(in: .whitespacesAndNewlines)
                    preview = userText
                }
            } else {
                preview = fullContent.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Remove --- USER --- and --- REFLECTION --- from preview, and trim whitespace/newlines
            preview = preview.replacingOccurrences(of: userSeparator, with: "")
            preview = preview.replacingOccurrences(of: reflectionSeparator, with: "")
            preview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            preview = preview.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let truncated = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)
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
        
        var contentToSave = ""
        
        // Ensure the latest USER section is updated with current editing text
        if let lastUserIndex = sections.lastIndex(where: { $0.type == .user }) {
            sections[lastUserIndex].text = editingText
        }
        
        // Add all sections in order with proper markers
        for (index, section) in sections.enumerated() {
            if index > 0 {
                contentToSave += "\n\n"
            }
            
            if section.type == .user {
                contentToSave += "--- USER ---\n\n"
            } else {
                contentToSave += "--- REFLECTION ---\n\n"
            }
            contentToSave += section.text
            
            if section.type == .user {
                contentToSave += "\n"
            }
        }
        
        do {
            try contentToSave.trimmingCharacters(in: .whitespacesAndNewlines).write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved entry: \(entry.filename)")
        } catch {
            print("Error saving entry: \(error)")
        }
    }
    
    private func loadEntry(entry: HumanEntry) {
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        // Reset reflection state
        hasInitiatedReflection = false
        showReflectionPanel = false
        reflectionViewModel.reflectionResponse = ""
        isStreamingReflection = false
        sections.removeAll()
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                let fullContent = try String(contentsOf: fileURL, encoding: .utf8)
                
                // Parse new section-based format
                if fullContent.contains("--- USER ---") || fullContent.contains("--- REFLECTION ---") {
                    // Split content by section markers
                    let sectionPattern = "(--- USER ---|--- REFLECTION ---)"
                    let parts = fullContent.components(separatedBy: .newlines)
                    
                    var currentSectionType: EntrySectionType? = nil
                    var currentSectionText = ""
                    
                    for line in parts {
                        if line == "--- USER ---" {
                            // Save previous section if it exists
                            if let sectionType = currentSectionType, !currentSectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                sections.append(EntrySection(type: sectionType, text: currentSectionText.trimmingCharacters(in: .whitespacesAndNewlines)))
                            }
                            currentSectionType = .user
                            currentSectionText = ""
                        } else if line == "--- REFLECTION ---" {
                            // Save previous section if it exists
                            if let sectionType = currentSectionType, !currentSectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                sections.append(EntrySection(type: sectionType, text: currentSectionText.trimmingCharacters(in: .whitespacesAndNewlines)))
                            }
                            currentSectionType = .reflection
                            currentSectionText = ""
                            hasInitiatedReflection = true
                        } else if currentSectionType != nil {
                            // Add line to current section
                            if !currentSectionText.isEmpty {
                                currentSectionText += "\n"
                            }
                            currentSectionText += line
                        }
                    }
                    
                    // Add the final section (including empty ones)
                    if let sectionType = currentSectionType {
                        sections.append(EntrySection(type: sectionType, text: currentSectionText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                    
                    // Find the latest USER section for editing (must be the last section)
                    if let lastSection = sections.last, lastSection.type == .user {
                        editingText = lastSection.text.isEmpty ? "\n\n" : lastSection.text
                    } else {
                        // If last section is not USER or no sections exist, create new USER section
                        editingText = "\n\n"
                        sections.append(EntrySection(type: .user, text: "\n\n"))
                    }
                    
                    // Show reflection panel if we have reflections
                    if hasInitiatedReflection {
                        showReflectionPanel = true
                    }
                    
                } else {
                    // Legacy format or new entry
                    editingText = fullContent.hasPrefix("\n\n") ? fullContent : "\n\n" + fullContent
                    sections = [EntrySection(type: .user, text: editingText)]
                }
                
                print("Successfully loaded entry: \(entry.filename)")
            } else {
                // New entry
                editingText = "\n\n"
                sections = [EntrySection(type: .user, text: "\n\n")]
            }
        } catch {
            print("Error loading entry: \(error)")
            // Fallback: start with empty entry
            editingText = "\n\n"
            sections = [EntrySection(type: .user, text: "\n\n")]
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
        hasInitiatedReflection = false
        isStreamingReflection = false
        followUpText = ""

        // Always start with a user section
        sections = [EntrySection(type: .user, text: "\n\n")]
        editingText = "\n\n"

        // If this is the first entry (entries was empty before adding this one)
        if entries.count == 1 {
            // Read welcome message from default.md
            if let defaultMessageURL = Bundle.main.url(forResource: "default", withExtension: "md"),
               let defaultMessage = try? String(contentsOf: defaultMessageURL, encoding: .utf8) {
                editingText = "\n\n" + defaultMessage
                sections[0].text = "\n\n" + defaultMessage
            }
            // Save the welcome message immediately
            saveEntry(entry: newEntry)
            // Update the preview text
            updatePreviewText(for: newEntry)
        } else {
            // Regular new entry starts with newlines
            editingText = "\n\n"
            sections[0].text = "\n\n"
            // Randomize placeholder text for new entry
            placeholderText = placeholderOptions.randomElement() ?? "\n\nBegin writing"
            // Save the empty entry
            saveEntry(entry: newEntry)
        }
        // Focus the text editor for the new entry with a slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isUserEditorFocused = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isUserEditorFocused = true
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
        guard !deepgramAPIKey.isEmpty else {
            showToast(message: "DeepGram API key not configured in Settings", type: .error)
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
        
        // Hide bottom navigation bar when recording starts
        withAnimation(.easeInOut(duration: 0.3)) {
            bottomNavOpacity = 0.0
        }
        
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
            // Show bottom navigation bar again if recording failed
            withAnimation(.easeInOut(duration: 0.3)) {
                bottomNavOpacity = 1.0
            }
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
        
        // Show bottom navigation bar when recording stops
        if !isHoveringBottomNav && !timerIsRunning {
            withAnimation(.easeInOut(duration: 0.3)) {
                bottomNavOpacity = 1.0
            }
        }
    }
    
    func transcribeAudioChunk(url: URL, chunkIndex: Int) {
        guard !deepgramAPIKey.isEmpty else {
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
        guard !deepgramAPIKey.isEmpty else {
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
        private var onStream: ((String) -> Void)?

        func start(apiKey: String, entryText: String, onComplete: @escaping () -> Void, onStream: ((String) -> Void)? = nil) {
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
            self.onStream = onStream

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
            below is my journal entry for the day as well as my reflections on them. wyt? talk through it with me like a friend. don't therapize me and give me a whole breakdown, don't repeat my thoughts with headings. really take all of this, and tell me back stuff truly as if you're an old homie.

            Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with headings if needed. use new paragrahs to make what you say more readable. don't use markdown or any other formatting. just use text.

            do not just go through every single thing i say, and say it back to me. you need to process everything i say, make connections i don't see it, and deliver it all back to me as a story that makes me feel what you think i wanna feel. thats what the best therapists do.

            the length should match the intensity of thought. if it's a light entry, be more concise. if it's a heavy entry, really dive in.
            
            ideally, you're style/tone should sound like the user themselves. it's as if the user is hearing their own tone but it should still feel different, because you have different things to say and don't just repeat back what i say.

            else, start by saying, "hey, thanks for showing me this :) my thoughts:" or "more thoughts:"
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

            Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with headings if needed. use new paragrahs to make what you say more readable. don't use markdown or any other formatting. just use text.

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
                                    self.reflectionResponse += content
                                    self.onStream?(self.reflectionResponse)
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
                    fontSize: 18,
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
                .padding()
            } else if let error = reflectionViewModel.error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            } else {
                MarkdownTextView(
                    content: reflectionViewModel.reflectionResponse, // Already just the reflection
                    font: userSelectedFont, // Use the same font as the user editor
                    fontSize: userFontSize,
                    colorScheme: colorScheme,
                    lineHeight: aiLineHeight
                )
                .id(userFontSize)
                .id(userSelectedFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: userFontSize * 1.5 + 32)
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private var centeredReflectionView: some View {
        ZStack {
            Color(colorScheme == .light ? .white : .black)
                .ignoresSafeArea()

            ScrollView {
                VStack {
                    reflectionContent
                        .frame(maxWidth: 650)
                        .padding(.horizontal, 16)
                        .padding(.top, 32)
                        
                    Spacer()
                }
                .frame(minHeight: (NSScreen.main?.visibleFrame.height ?? 800) - navHeight)
            }
            .scrollIndicators(.never)
            .padding(.bottom, bottomNavOpacity > 0 ? navHeight : 0)
            
            VStack {
                Spacer()
                bottomNavigationView
            }
            .animation(nil, value: showReflectionPanel)
            .ignoresSafeArea(.keyboard)
        }
    }
}

// Add these view structs before the main ContentView struct
struct SettingsModal: View {
    @Binding var showingSettings: Bool
    @Binding var selectedSettingsTab: SettingsTab
    @Binding var openAIapiKey: String
    @Binding var deepgramApiKey: String
    @Binding var showMicrophone: Bool
    let onRunWeekly: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedTab: $selectedSettingsTab)
            SettingsContent(
                selectedTab: selectedSettingsTab,
                openAIapiKey: $openAIapiKey,
                deepgramApiKey: $deepgramApiKey,
                showMicrophone: $showMicrophone,
                onRunWeekly: onRunWeekly
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
                    title: "API Keys",
                    icon: "key.fill",
                    isSelected: selectedTab == .apiKeys,
                    action: { selectedTab = .apiKeys }
                )
                
                SettingsSidebarItem(
                    title: "Transcription",
                    icon: "waveform",
                    isSelected: selectedTab == .transcription,
                    action: { selectedTab = .transcription }
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
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16, height: 16)
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .white : .white) : .primary)
                
                Text(title)
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .white : .white) : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? (colorScheme == .dark ? Color.black : Color.primary) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsContent: View {
    let selectedTab: SettingsTab
    @Binding var openAIapiKey: String
    @Binding var deepgramApiKey: String
    @Binding var showMicrophone: Bool
    let onRunWeekly: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selectedTab {
            case .apiKeys:
                APIKeysSettingsView(openAIapiKey: $openAIapiKey, deepgramApiKey: $deepgramApiKey)
            case .reflections:
                ReflectionsSettingsView(onRunNow: onRunWeekly)
            case .transcription:
                TranscriptionSettingsView(showMicrophone: $showMicrophone)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

struct APIKeysSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var openAIapiKey: String
    @Binding var deepgramApiKey: String
    
    @State private var tempOpenAIApiKey: String = ""
    @State private var tempDeepgramApiKey: String = ""
    @State private var hasUnsavedOpenAI: Bool = false
    @State private var hasUnsavedDeepgram: Bool = false
    @State private var showOpenAISaveConfirmation: Bool = false
    @State private var showDeepgramSaveConfirmation: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // OpenAI API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                SecureField("Enter your OpenAI API key", text: $tempOpenAIApiKey)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                    .onChange(of: tempOpenAIApiKey) { newValue in
                        hasUnsavedOpenAI = (newValue != openAIapiKey)
                    }
                
                Text("Used for reflections.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Button(action: {
                        if !tempOpenAIApiKey.isEmpty {
                            KeychainHelper.shared.saveAPIKey(tempOpenAIApiKey, for: .openAI)
                            openAIapiKey = tempOpenAIApiKey
                        } else {
                            KeychainHelper.shared.deleteAPIKey(for: .openAI)
                            openAIapiKey = ""
                        }
                        hasUnsavedOpenAI = false
                        showOpenAISaveConfirmation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showOpenAISaveConfirmation = false
                        }
                    }) {
                        Text("Save")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(colorScheme == .dark ? Color.black : (hasUnsavedOpenAI ? .primary : .secondary))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!hasUnsavedOpenAI)
                    
                    if showOpenAISaveConfirmation {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("Saved")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showOpenAISaveConfirmation)
            }
            // Deepgram API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Deepgram API Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                SecureField("Enter your Deepgram API key", text: $tempDeepgramApiKey)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                    .onChange(of: tempDeepgramApiKey) { newValue in
                        hasUnsavedDeepgram = (newValue != deepgramApiKey)
                    }
                
                Text("Used for speech-to-text transcription.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Button(action: {
                        if !tempDeepgramApiKey.isEmpty {
                            KeychainHelper.shared.saveAPIKey(tempDeepgramApiKey, for: .deepgram)
                            deepgramApiKey = tempDeepgramApiKey
                        } else {
                            KeychainHelper.shared.deleteAPIKey(for: .deepgram)
                            deepgramApiKey = ""
                        }
                        hasUnsavedDeepgram = false
                        showDeepgramSaveConfirmation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showDeepgramSaveConfirmation = false
                        }
                    }) {
                        Text("Save")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(colorScheme == .dark ? Color.black : (hasUnsavedDeepgram ? .primary : .secondary))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!hasUnsavedDeepgram)
                    
                    if showDeepgramSaveConfirmation {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("Saved")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showDeepgramSaveConfirmation)
            }
            Spacer()
        }
        .padding(.top, 8)
        .onAppear {
            tempOpenAIApiKey = openAIapiKey
            tempDeepgramApiKey = deepgramApiKey
            hasUnsavedOpenAI = false
            hasUnsavedDeepgram = false
        }
    }
}

struct ReflectionsSettingsView: View {
    // Weekly
    @State private var isWeeklyEnabled: Bool = true
    @State private var selectedDay: String = "Sunday"
    @State private var weeklyReflectionTime: Date = Calendar.current.date(from: DateComponents(hour: 10, minute: 0)) ?? Date()
    let daysOfWeek = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    // Monthly
    @State private var isMonthlyEnabled: Bool = false
    @State private var selectedMonthDay: Int = 1
    @State private var monthlyReflectionTime: Date = Calendar.current.date(from: DateComponents(hour: 10, minute: 0)) ?? Date()
    let daysOfMonth = Array(1...30)
    
    // Quarterly
    @State private var isQuarterlyEnabled: Bool = false
    @State private var q1Month: Int = 0
    @State private var q1Day: Int = 1
    @State private var q2Month: Int = 3
    @State private var q2Day: Int = 1
    @State private var q3Month: Int = 6
    @State private var q3Day: Int = 1
    @State private var q4Month: Int = 9
    @State private var q4Day: Int = 1
    @State private var quarterlyReflectionTime: Date = Calendar.current.date(from: DateComponents(hour: 10, minute: 0)) ?? Date()
    
    // Annually
    @State private var isAnnuallyEnabled: Bool = false
    @State private var annualMonth: Int = 0 // 0 = January
    @State private var annualDay: Int = 1   // 1 = first day
    @State private var annualReflectionTime: Date = Calendar.current.date(from: DateComponents(hour: 10, minute: 0)) ?? Date()

    let onRunNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Weekly Section
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $isWeeklyEnabled) {
                        Text("Weekly")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    HStack(spacing: 12) {
                        Picker("Reflect every", selection: $selectedDay) {
                            ForEach(daysOfWeek, id: \.self) { day in Text(day) }
                        }
                        .pickerStyle(MenuPickerStyle())
                        
                        DatePicker("at", selection: $weeklyReflectionTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(CompactDatePickerStyle())
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Button("Run now") {
                            onRunNow()
                        }
                    }
                    .foregroundColor(.secondary)
                    .disabled(!isWeeklyEnabled)
                }
                
                Divider()
                
                // Monthly Section
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $isMonthlyEnabled) {
                        Text("Monthly")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    HStack(spacing: 8) {
                        Text("Reflect every")
                        Picker("Day", selection: $selectedMonthDay) {
                            ForEach(daysOfMonth, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .labelsHidden()
                        Text("at")
                            .foregroundColor(.secondary)
                        DatePicker("", selection: $monthlyReflectionTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(CompactDatePickerStyle())
                        Text("•")
                            .foregroundColor(.secondary)
                        Button("Run now") {
                            // No action for now
                        }
                    }
                    .foregroundColor(.secondary)
                    .disabled(!isMonthlyEnabled)
                }
                
                Divider()

                // Quarterly Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $isQuarterlyEnabled) {
                        Text("Quarterly")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    // Quarterly pickers: Month and Day dropdowns for each quarter
                    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                    let days = Array(1...30)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q1")
                            HStack(spacing: 4) {
                                Picker("", selection: $q1Month) {
                                    ForEach(0..<months.count, id: \ .self) { idx in
                                        Text(months[idx]).tag(idx)
                                    }
                                }
                                .frame(width: 70)
                                .labelsHidden()
                                .disabled(!isQuarterlyEnabled)
                                Picker("", selection: $q1Day) {
                                    ForEach(days, id: \ .self) { day in
                                        Text("\(day)").tag(day)
                                    }
                                }
                                .frame(width: 50)
                                .labelsHidden()
                                .disabled(!isQuarterlyEnabled)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q2")
                            HStack(spacing: 4) {
                                Picker("", selection: $q2Month) {
                                    ForEach(0..<months.count, id: \ .self) { idx in
                                        Text(months[idx]).tag(idx)
                                    }
                                }
                                .frame(width: 70)
                                .labelsHidden()
                                .disabled(!isQuarterlyEnabled)
                                Picker("", selection: $q2Day) {
                                    ForEach(days, id: \ .self) { day in
                                        Text("\(day)").tag(day)
                                    }
                                }
                                .frame(width: 50)
                                .labelsHidden()
                                .disabled(!isQuarterlyEnabled)
                            }
                        }
                    }
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q3")
                            HStack(spacing: 4) {
                                Picker("", selection: $q3Month) {
                                    ForEach(0..<months.count, id: \ .self) { idx in
                                        Text(months[idx]).tag(idx)
                                    }
                                }
                                .frame(width: 70)
                                .labelsHidden()
                                .disabled(!isQuarterlyEnabled)
                                Picker("", selection: $q3Day) {
                                    ForEach(days, id: \ .self) { day in
                                        Text("\(day)").tag(day)
                                    }
                                }
                                .frame(width: 50)
                                .labelsHidden()
                                .disabled(!isQuarterlyEnabled)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q4")
                            HStack(spacing: 4) {
                                Picker("", selection: $q4Month) {
                                    ForEach(0..<months.count, id: \ .self) { idx in
                                        Text(months[idx]).tag(idx)
                                    }
                                }
                                .frame(width: 70)
                                .labelsHidden()
                                .disabled(!isQuarterlyEnabled)
                                Picker("", selection: $q4Day) {
                                    ForEach(days, id: \ .self) { day in
                                        Text("\(day)").tag(day)
                                    }
                                }
                                .frame(width: 50)
                                .labelsHidden()
                                .disabled(!isQuarterlyEnabled)
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                    
                        DatePicker("at", selection: $quarterlyReflectionTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(CompactDatePickerStyle())
                        
                        Spacer()

                        Text("•")
                            .foregroundColor(.secondary)
                        Button("Run now") {
                            // No action for now
                        }
                    }
                    .foregroundColor(.secondary)
                    .disabled(!isQuarterlyEnabled)
                }
                
                Divider()
                
                // Annually Section
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $isAnnuallyEnabled) {
                        Text("Annually")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                    let days = Array(1...30)
                    HStack(spacing: 8) {
                        Picker("", selection: $annualMonth) {
                            ForEach(0..<months.count, id: \ .self) { idx in
                                Text(months[idx]).tag(idx)
                            }
                        }
                        .frame(width: 70)
                        .labelsHidden()
                        .disabled(!isAnnuallyEnabled)
                        Picker("", selection: $annualDay) {
                            ForEach(days, id: \ .self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                        .frame(width: 50)
                        .labelsHidden()
                        .disabled(!isAnnuallyEnabled)
                        DatePicker("at", selection: $annualReflectionTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(CompactDatePickerStyle())
                            .disabled(!isAnnuallyEnabled)
                        Text("•")
                            .foregroundColor(.secondary)
                        Button("Run now") {
                            // No action for now
                        }
                    }
                    .foregroundColor(.secondary)
                    .disabled(!isAnnuallyEnabled)
                }
            }
            .padding(.vertical, 20)
        }
        .onAppear(perform: setQuarterDates)
        .scrollIndicators(.never)
    }

    private func setQuarterDates() {
        q1Month = 3
        q1Day = 1
        q2Month = 6
        q2Day = 1
        q3Month = 9
        q3Day = 1
        q4Month = 0
        q4Day = 1
    }
}

struct TranscriptionSettingsView: View {
    @Binding var showMicrophone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Toggle("Show microphone button", isOn: $showMicrophone)
                .onChange(of: showMicrophone) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "showMicrophone")
                }

            Text("Disable if you prefer using another speech-to-text app (Wispr Flow, Superwhisper, etc.).")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.top, 8)
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
                NSColor(calibratedWhite: 0.90, alpha: 1.0)
            
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
                NSColor(calibratedWhite: 0.90, alpha: 1.0)
            self.attributedString = fallback
        }
    }
}

#Preview {
    ContentView()
}

// Helper to remove reflection/follow-up separators from text
func removeReflectionSeparators(from text: String) -> String {
    let lines = text.components(separatedBy: .newlines)
    let filtered = lines.filter { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed != "--- REFLECTION ---" && trimmed != "--- USER ---"
    }
    return filtered.joined(separator: "\n")
}

// Add this helper view at the end of the file:
import AppKit
struct TextEditorCursorColorView: NSViewRepresentable {
    let colorScheme: ColorScheme
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window, let textView = window.firstResponder as? NSTextView {
                textView.insertionPointColor = (colorScheme == .dark) ? .white : .black
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window, let textView = window.firstResponder as? NSTextView {
                textView.insertionPointColor = (colorScheme == .dark) ? .white : .black
            }
        }
    }
}
