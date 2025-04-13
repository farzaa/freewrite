//
//  HumanEntry.swift
//  freewrite
//
//  Created by JTV on 4/13/25.
//
//  Represents a single journal entry, including date, filename, and preview text.
//

import SwiftUI

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


