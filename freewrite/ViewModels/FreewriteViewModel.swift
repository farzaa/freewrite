//
//  FreewriteViewModel.swift
//  freewrite
//
//  Created by Gaspar Dolcemascolo on 17-04-25.
//

import SwiftUI

class FreewriteViewModel: ObservableObject {
    private let fileManager = FreewriterFileManager.shared
    private let aiChatManager = AIChatManager.shared
    @Published var entries: [HumanEntry] = []
    @Published var text: String = ""  // Remove initial welcome text since we'll handle it in createNewEntry
    
    @Published var isFullscreen = false
    @Published var selectedFont: String = "Lato-Regular"
    @Published var currentRandomFont: String = ""
    @Published var timeRemaining: Int = 900  // Changed to 900 seconds (15 minutes)
    @Published var timerIsRunning = false
    @Published var isHoveringTimer = false
    @Published var fontSize: CGFloat = 18
    @Published var blinkCount = 0
    @Published var isBlinking = false
    @Published var opacity: Double = 1.0
    @Published var shouldShowGray = true // New state to control color
    @Published var lastClickTime: Date? = nil
    @Published var bottomNavOpacity: Double = 1.0
    @Published var isHoveringBottomNav = false
    @Published var selectedEntryIndex: Int = 0
    @Published var scrollOffset: CGFloat = 0
    @Published var selectedEntryId: UUID? = nil
    @Published var hoveredEntryId: UUID? = nil
    @Published var isHoveringChat = false  // Add this state variable
    @Published var showingChatMenu = false
    @Published var chatMenuAnchor: CGPoint = .zero
    @Published var showingSidebar = false  // Add this state variable
    @Published var placeholderText: String = ""  // Add this line
    
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
    
    
    
    // MARK: - FILES MANAGE
    
    // Add function to load existing entries
    func loadExistingEntries() {
        let entryList = fileManager.loadExistingEntries()
        
        guard let entriesWithDates = entryList else {
            print("Creating default entry after error")
            createNewEntry()
            return
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
    }
    
    
    func getDocumentsDirectory() -> URL {
        return fileManager.getDocumentsDirectory()
    }
    
    func updatePreviewText(for entry: HumanEntry) {
        let fileURL = fileManager.updatePreviewText(for: entry)
        
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
    
    func saveEntry(entry: HumanEntry) {
        let fileURL = fileManager.saveEntry(entry: entry)
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved entry: \(entry.filename)")
            updatePreviewText(for: entry)  // Update preview after saving
        } catch {
            print("Error saving entry: \(error)")
        }
    }
    
    func createNewEntry() {
        let newEntry = fileManager.createNewEntry()
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
    
    func loadEntry(entry: HumanEntry) {
        let fileURL = fileManager.loadEntry(entry: entry)
        
        guard let fileURL else { return }
        
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
            print("Successfully loaded entry: \(entry.filename)")
        } catch {
            print("Error loading entry: \(error)")
        }
    }
    
    func deleteEntry(entry: HumanEntry) {
        let deletedEntryId = fileManager.deleteEntry(entry: entry)
        
        if let index = entries.firstIndex(where: { $0.id == deletedEntryId }) {
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
    }
    
    func exportEntryAsPDF(entry: HumanEntry) {
        // First make sure the current entry is saved
        if selectedEntryId == entry.id {
            saveEntry(entry: entry)
        }
        
        fileManager.exportEntryAsPDF(entry: entry, font: selectedFont, fontSize: fontSize)
    }
    
    
    // MARK: / AI CHAT
    
    func openChatGPT() {
        showingChatMenu = false
        aiChatManager.openChatGPT(text: text)
    }
    
    func openClaude() {
        showingChatMenu = false
        aiChatManager.openClaude(text: text)
    }
    
}
