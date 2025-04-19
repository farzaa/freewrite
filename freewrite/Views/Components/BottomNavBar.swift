//
//  BottomNavBar.swift
//  freewrite
//
//  Created by Gaspar Dolcemascolo on 17-04-25.
//

import SwiftUI

struct BottomNavBar: View {
    @ObservedObject var viewModel: FreewriteViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @State private var isHoveringThemeToggle = false
    @State private var isHoveringTimer = false
    @State private var isHoveringClock = false
    
    private let availableFonts = NSFontManager.shared.availableFontFamilies
    private let fontSizes: [CGFloat] = [16, 18, 20, 22, 24, 26]
    
    private var fontSizeButtonTitle: String {
        return "\(Int(viewModel.fontSize))px"
    }
    private var randomButtonTitle: String {
        return viewModel.currentRandomFont.isEmpty ? "Random" : "Random [\(viewModel.currentRandomFont)]"
    }
    
    private var timerButtonTitle: String {
        if !viewModel.timerIsRunning && viewModel.timeRemaining == 900 {
            return "15:00"
        }
        let minutes = viewModel.timeRemaining / 60
        let seconds = viewModel.timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var timerColor: Color {
        if viewModel.timerIsRunning {
            return isHoveringTimer ? (appSettings.colorScheme == .light ? .black : .white) : .gray.opacity(0.8)
        } else {
            return isHoveringTimer ? (appSettings.colorScheme == .light ? .black : .white) : (appSettings.colorScheme == .light ? .gray : .gray.opacity(0.8))
        }
    }
    
    var body: some View {
        let textColor = appSettings.colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
        let textHoverColor = appSettings.colorScheme == .light ? Color.black : Color.white
        
        VStack {
            Spacer()
            HStack {
                // Font buttons (moved to left)
                HStack(spacing: 8) {
                    OptionButton(title: fontSizeButtonTitle) {
                        if let currentIndex = fontSizes.firstIndex(of: viewModel.fontSize) {
                            let nextIndex = (currentIndex + 1) % fontSizes.count
                            viewModel.fontSize = fontSizes[nextIndex]
                        }
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    OptionButton(title: "Lato") {
                        viewModel.selectedFont = "Lato-Regular"
                        viewModel.currentRandomFont = ""
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    OptionButton(title: "Arial") {
                        viewModel.selectedFont = "Arial"
                        viewModel.currentRandomFont = ""
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    OptionButton(title: "System") {
                        viewModel.selectedFont = ".AppleSystemUIFont"
                        viewModel.currentRandomFont = ""
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    OptionButton(title: "Serif") {
                        viewModel.selectedFont = "Times New Roman"
                        viewModel.currentRandomFont = ""
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    OptionButton(title: randomButtonTitle) {
                        if let randomFont = availableFonts.randomElement() {
                            viewModel.selectedFont = randomFont
                            viewModel.currentRandomFont = randomFont
                        }
                    }
                }
                .padding(8)
                .cornerRadius(6)
                
                Spacer()
                
                // Utility buttons (moved to right)
                HStack(spacing: 8) {
                    Button(timerButtonTitle) {
                        let now = Date()
                        if let lastClick = viewModel.lastClickTime,
                           now.timeIntervalSince(lastClick) < 0.3 {
                            viewModel.timeRemaining = 900
                            viewModel.timerIsRunning = false
                            viewModel.lastClickTime = nil
                        } else {
                            viewModel.timerIsRunning.toggle()
                            viewModel.lastClickTime = now
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(timerColor)
                    .onHover { hovering in
                        isHoveringTimer = hovering
                        viewModel.isHoveringBottomNav = hovering
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
                                    let currentMinutes = viewModel.timeRemaining / 60
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                    let direction = -scrollBuffer > 0 ? 5 : -5
                                    let newMinutes = currentMinutes + direction
                                    let roundedMinutes = (newMinutes / 5) * 5
                                    let newTime = roundedMinutes * 60
                                    viewModel.timeRemaining = min(max(newTime, 0), 2700)
                                }
                            }
                            return event
                        }
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    OptionButton(title: "Chat") {
                        viewModel.showingChatMenu = true
                    }.popover(isPresented: $viewModel.showingChatMenu, attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)), arrowEdge: .top) {
                        ChatPopOverView(text: $viewModel.text) { text in
                            if text == Chat.chatGTP {
                                viewModel.openChatGPT()
                            } else {
                                viewModel.openClaude()
                            }
                            
                        }
                        
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    OptionButton(title: viewModel.isFullscreen ? "Minimize" : "Fullscreen") {
                        if let window = NSApplication.shared.windows.first {
                            window.toggleFullScreen(nil)
                        }
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    OptionButton(title: "New Entry") {
                        viewModel.createNewEntry()
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    // Theme toggle button
                    Button(action: {
                        appSettings.updateColorScheme(appSettings.colorScheme == .light ? .dark : .light)
                    }) {
                        Image(systemName: appSettings.colorScheme == .light ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(isHoveringThemeToggle ? textHoverColor : textColor)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringThemeToggle = hovering
                        viewModel.isHoveringBottomNav = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
                    // Version history button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showingSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(isHoveringClock ? textHoverColor : textColor)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringClock = hovering
                        viewModel.isHoveringBottomNav = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .padding(8)
                .cornerRadius(6)
            }
            .padding()
            .background(Color(appSettings.colorScheme == .light ? .white : .black))
            .opacity(viewModel.bottomNavOpacity)
            .onHover { hovering in
                viewModel.isHoveringBottomNav = hovering
                if hovering {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.bottomNavOpacity = 1.0
                    }
                } else if viewModel.timerIsRunning {
                    withAnimation(.easeIn(duration: 1.0)) {
                        viewModel.bottomNavOpacity = 0.0
                    }
                }
            }
        }
    }
}
