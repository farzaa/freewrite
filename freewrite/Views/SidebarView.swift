//
//  SidebarView.swift
//  freewrite
//
//  Created by Gaspar Dolcemascolo on 18-04-25.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: FreewriteViewModel
    @State private var isHoveringHistory = false
    @State private var isHoveringHistoryText = false
    @State private var isHoveringHistoryPath = false
    
    private var textColor: Color {
        return settings.colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
    }
    
    private var textHoverColor: Color {
        return settings.colorScheme == .light ? Color.black : Color.white
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
    
    // MARK: - HEADER
    
    @ViewBuilder
    private var Header: some View {
        Button(action: {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: viewModel.getDocumentsDirectory().path)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("History")
                            .font(.system(size: 13))
                            .foregroundColor(isHoveringHistory ? textHoverColor : textColor)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                            .foregroundColor(isHoveringHistory ? textHoverColor : textColor)
                    }
                    Text(viewModel.getDocumentsDirectory().path)
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
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            Header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.entries) { entry in
                          // Add tooltip
                        
                        EntryCard(viewModel: viewModel, entry: entry)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(width: 200)
        .background(Color(settings.colorScheme == .light ? .white : NSColor.black))
    }
}

#Preview {
    SidebarView(viewModel: FreewriteViewModel())
}
