//
//  ColorsHelper.swift
//  freewrite
//
//  Created by Jonathan Taveras Vargas on 4/13/25.
//

import SwiftUI

func backgroundColor(for entry: HumanEntry, selectedEntryId: UUID?, hoveredEntryId: UUID?) -> Color {
    if entry.id == selectedEntryId {
        return Color.gray.opacity(0.1)  // More subtle selection highlight
    } else if entry.id == hoveredEntryId {
        return Color.gray.opacity(0.05)  // Even more subtle hover state
    } else {
        return Color.clear
    }
}
