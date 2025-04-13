//
//  SidebarView.swift
//  freewrite
//
//  Created by JTV on 4/13/25.
//

import SwiftUI

struct SidebarView: View {
    private let fileHelper = FileManagerHelper.shared
    @Binding var isHoveringHistory: Bool
    let entries: [HumanEntry]
    @Binding var selectedEntryId: UUID?
    @Binding var hoveredEntryId: UUID?
    @Binding var hoveredTrashId: UUID?
    
//    handlers
    var onSaveEntry: (_ entry: HumanEntry) -> Void
    var onLoadEntry: (_ entry: HumanEntry) -> Void
    var onDeleteEntry: (_ entry: HumanEntry) -> Void
    
    var documentsDirectory: URL {
        return fileHelper.getDocumentsDirectory()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: documentsDirectory.path)
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
                        Text(documentsDirectory.path)
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
            EntryListView()
        }
        .frame(width: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    func EntryListView() -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    EntryRowView(
                        entry: entry,
                        selectedEntryId: $selectedEntryId,
                        hoveredEntryId: $hoveredEntryId,
                        hoveredTrashId: $hoveredTrashId,
                        entries: entries,
                        onSaveEntry: onSaveEntry,
                        onLoadEntry: onLoadEntry,
                        onDeleteEntry: onDeleteEntry
                    )
                    if entry.id != entries.last?.id {
                        Divider()
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }
}

struct EntryRowView: View {
    private let fileHelper = FileManagerHelper.shared
    let entry: HumanEntry
    @Binding var selectedEntryId: UUID?
    @Binding var hoveredEntryId: UUID?
    @Binding var hoveredTrashId: UUID?
    let entries: [HumanEntry]
    let onSaveEntry: (HumanEntry) -> Void
    let onLoadEntry: (HumanEntry) -> Void
    let onDeleteEntry: (HumanEntry) -> Void

    var body: some View {
        Button(action: {
            if selectedEntryId != entry.id {
                if let currentId = selectedEntryId ?? nil,
                   let currentEntry = entries.first(where: { $0.id == currentId }) {
                    onSaveEntry(currentEntry)
                }
                selectedEntryId = entry.id
                onLoadEntry(entry)
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

                if hoveredEntryId == entry.id {
                    Button(action: {
                        onDeleteEntry(entry)
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
                    .fill(
                        backgroundColor(
                            for: entry,
                            selectedEntryId: selectedEntryId,
                            hoveredEntryId: hoveredEntryId
                        )
                    )

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
            NSCursor.pop()
        }
        .help("Click to select this entry")
    }
}
