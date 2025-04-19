// Swift 5.0
//
//  ContentView.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct ContentView: View {
    private let headerString = "\n\n"
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: FreewriteViewModel
    
    private var colorScheme: ColorScheme {
        return settings.colorScheme
    }
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var lineHeight: CGFloat {
        let font = NSFont(name: viewModel.selectedFont, size: viewModel.fontSize) ?? .systemFont(ofSize: viewModel.fontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (viewModel.fontSize * 1.5) - defaultLineHeight
    }
    
    var placeholderOffset: CGFloat {
        // Instead of using calculated line height, use a simple offset
        return viewModel.fontSize / 2
    }
    
    
    var body: some View {
        
        HStack(spacing: 0) {
            // Main content
            ZStack {
                Color(colorScheme == .light ? .white : .black)
                    .ignoresSafeArea()
                
                TextEditor(text: Binding(
                    get: { viewModel.text },
                    set: { newValue in
                        if !newValue.hasPrefix("\n\n") {
                            viewModel.text = "\n\n" + newValue.trimmingCharacters(in: .newlines)
                        } else {
                            viewModel.text = newValue
                        }
                    }
                ))
                .background(Color(colorScheme == .light ? .white : .black))
                .font(.custom(viewModel.selectedFont, size: viewModel.fontSize))
                .foregroundColor(colorScheme == .light ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .lineSpacing(lineHeight)
                .frame(maxWidth: 650)
                .id("\(viewModel.selectedFont)-\(viewModel.fontSize)-\(colorScheme)")
                .padding(.bottom, viewModel.bottomNavOpacity > 0 ? 68 : 0)
                .ignoresSafeArea()
                .colorScheme(colorScheme)
                .overlay(
                    ZStack(alignment: .topLeading) {
                        if viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(viewModel.placeholderText)
                                .font(.custom(viewModel.selectedFont, size: viewModel.fontSize))
                                .foregroundColor(colorScheme == .light ? .gray.opacity(0.5) : .gray.opacity(0.6))
                                .offset(x: 5, y: placeholderOffset)
                        }
                    }, alignment: .topLeading
                )
                
                BottomNavBar(viewModel: viewModel)
                
            }
            
            // Right sidebar
            if viewModel.showingSidebar {
                Divider()
                
                SidebarView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showingSidebar)
        .preferredColorScheme(colorScheme)
        .onAppear {
            viewModel.showingSidebar = false  // Hide sidebar by default
            viewModel.loadExistingEntries()
        }
        .onChange(of: viewModel.text) { _ in
            // Save current entry when text changes
            if let currentId = viewModel.selectedEntryId,
               let currentEntry = viewModel.entries.first(where: { $0.id == currentId }) {
                viewModel.saveEntry(entry: currentEntry)
            }
        }
        .onReceive(timer) { _ in
            if viewModel.timerIsRunning && viewModel.timeRemaining > 0 {
                viewModel.timeRemaining -= 1
            } else if viewModel.timeRemaining == 0 {
                viewModel.timerIsRunning = false
                if !viewModel.isHoveringBottomNav {
                    withAnimation(.easeOut(duration: 1.0)) {
                        viewModel.bottomNavOpacity = 1.0
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            viewModel.isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            viewModel.isFullscreen = false
        }
    }
    
}

#Preview {
    ContentView(viewModel: FreewriteViewModel())
}
