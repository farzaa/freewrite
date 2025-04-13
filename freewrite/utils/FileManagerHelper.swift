//
//  FileManagerHelper.swift
//  freewrite
//
//  Created by JTV on 4/13/25.
//
//  Handles reading, writing, and organizing journal entry files.
//

import SwiftUI
import Foundation

struct FileManagerHelper {
    static let shared = FileManagerHelper()
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freewrite")
        
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func saveEntry(_ entry: HumanEntry, withText text: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved entry: \(entry.filename)")
            onSuccess?()
        } catch {
            print("Error saving entry: \(error)")
            onError?(error)
        }
    }
    
    func loadEntry(_ entry: HumanEntry, onSuccess: ((String) -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                print("Successfully loaded entry: \(entry.filename)")
                onSuccess?(content)
            } else {
                print("File does not exist: \(entry.filename)")
                onSuccess?("") // Optional: treat non-existent file as empty
            }
        } catch {
            print("Error loading entry: \(error)")
            onError?(error)
        }
    }
    
    func createNewEntry(
        isFirstEntry: Bool,
        placeholderOptions: [String],
        onSuccess: @escaping (_ newEntry: HumanEntry, _ entryText: String, _ placeholder: String?) -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        let newEntry = HumanEntry.createNew()
        
        var entryText = "\n\n"
        var placeholder: String? = nil
        
        if isFirstEntry {
            // Load welcome message from bundled file
            if let defaultMessageURL = Bundle.main.url(forResource: "default", withExtension: "md"),
               let defaultMessage = try? String(contentsOf: defaultMessageURL, encoding: .utf8) {
                entryText = "\n\n" + defaultMessage
            }
        } else {
            // Not first entry: assign a random placeholder for UI use
            placeholder = placeholderOptions.randomElement()
        }

        // Save the entry to disk
        saveEntry(newEntry, withText: entryText, onSuccess: {
            onSuccess(newEntry, entryText, placeholder)
        }, onError: onError)
    }
    
    // Delete the file from the filesystem
    func deleteEntry(
        _ entry: HumanEntry,
        onSuccess: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            try fileManager.removeItem(at: fileURL)
            print("Successfully deleted file: \(entry.filename)")
            onSuccess?()
        } catch {
            print("Error deleting file: \(error)")
            onError?(error)
        }
    }
    
    func loadExistingEntries(
        onSuccess: @escaping (_ entries: [HumanEntry], _ fullContents: [UUID: String]) -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        let directory = documentsDirectory
        print("Looking for entries in: \(directory.path)")
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let mdFiles = fileURLs.filter { $0.pathExtension == "md" }
            
            print("Found \(mdFiles.count) .md files")
            
            var loadedEntries: [(entry: HumanEntry, date: Date, content: String)] = []
            var contentMap: [UUID: String] = [:]
            
            for fileURL in mdFiles {
                let filename = fileURL.lastPathComponent
                print("Processing: \(filename)")
                
                guard let uuidMatch = filename.range(of: "\\[(.*?)\\]", options: .regularExpression),
                      let dateMatch = filename.range(of: "\\[(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\]", options: .regularExpression),
                      let uuid = UUID(uuidString: String(filename[uuidMatch].dropFirst().dropLast())) else {
                    print("Failed to parse UUID or date: \(filename)")
                    continue
                }
                
                let dateString = String(filename[dateMatch].dropFirst().dropLast())
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
                guard let fileDate = formatter.date(from: dateString) else {
                    print("Invalid date format in: \(filename)")
                    continue
                }
                
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    let preview = content
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let truncated = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)
                    
                    formatter.dateFormat = "MMM d"
                    let displayDate = formatter.string(from: fileDate)
                    
                    let entry = HumanEntry(
                        id: uuid,
                        date: displayDate,
                        filename: filename,
                        previewText: truncated
                    )
                    
                    loadedEntries.append((entry: entry, date: fileDate, content: content))
                    contentMap[uuid] = content
                    
                } catch {
                    print("Failed to read content for file: \(filename)")
                }
            }
            
            let sorted = loadedEntries.sorted { $0.date > $1.date }
            let finalEntries = sorted.map { $0.entry }
            
            print("Loaded \(finalEntries.count) entries")
            onSuccess(finalEntries, contentMap)
            
        } catch {
            print("Error reading from directory: \(error)")
            onError?(error)
        }
    }


    // Optionally, add this for reuse
    func getDocumentsDirectory() -> URL {
        return documentsDirectory
    }
}
