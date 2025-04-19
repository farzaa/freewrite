//
//  EntryCard.swift
//  freewrite
//
//  Created by Gaspar Dolcemascolo on 18-04-25.
//

import SwiftUI

struct EntryCard: View {
    @ObservedObject var viewModel: FreewriteViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var hoveredExportId: UUID?
    @State private var hoveredTrashId: UUID?
    
    var entry: HumanEntry
    
    private var imageHoverColor: Color {
        return settings.colorScheme == .light ? .black : .white
    }
    
    private var imageColor: Color {
        return settings.colorScheme == .light ? .gray : .gray.opacity(0.8)
    }
    
    private func backgroundColor(for entry: HumanEntry) -> Color {
        if entry.id == viewModel.selectedEntryId {
            return Color.gray.opacity(0.1)  // More subtle selection highlight
        } else if entry.id == viewModel.hoveredEntryId {
            return Color.gray.opacity(0.05)  // Even more subtle hover state
        } else {
            return Color.clear
        }
    }
    
    @ViewBuilder
    var EntryActionButtons: some View {
        HStack(spacing: 8) {
            // Export PDF button
            Button(action: {
                viewModel.exportEntryAsPDF(entry: entry)
            }) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundColor(hoveredExportId == entry.id ? imageHoverColor : imageColor)
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
                viewModel.deleteEntry(entry: entry)
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
    
    var body: some View {
        Button(action: {
            if viewModel.selectedEntryId != entry.id {
                // Save current entry before switching
                if let currentId = viewModel.selectedEntryId,
                   let currentEntry = viewModel.entries.first(where: { $0.id == currentId }) {
                    viewModel.saveEntry(entry: currentEntry)
                }
                
                viewModel.selectedEntryId = entry.id
                viewModel.loadEntry(entry: entry)
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
                        if viewModel.hoveredEntryId == entry.id {
                            EntryActionButtons
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
                viewModel.hoveredEntryId = hovering ? entry.id : nil
            }
        }
        .onAppear {
            NSCursor.pop()  // Reset cursor when button appears
        }
        .help("Click to select this entry")
        
        if entry.id != viewModel.entries.last?.id {
            Divider()
        }
    }
}

