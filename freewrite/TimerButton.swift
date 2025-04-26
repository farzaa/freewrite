//
//  TimerButton.swift
//  freewrite
//
//  Created by sa1l on 2025/4/26.
//

import SwiftUI

struct TimerButton: View {
    @Binding var timerIsRunning: Bool
    @Binding var timeRemaining: Int
    @Binding var isHoveringTimer: Bool
    @Binding var colorScheme: ColorScheme
    @Binding var lastClickTime: Date?
    @Binding var isHoveringBottomNav: Bool
    
    private var timerColor: Color {
        if timerIsRunning {
           return isHoveringTimer ? primaryColor : .gray.opacity(0.8) 
        }
        
        return isHoveringTimer ? primaryColor : secondaryColor
    }
    
    private var primaryColor: Color {
        colorScheme == .light ? .black : .white
    }
    
    private var secondaryColor: Color {
        colorScheme == .light ? .gray : .gray.opacity(0.8)
    }
    
    var body: some View {
        Button(action: handleTimerClick) {
            Text(timerTitle)
                .foregroundColor(timerColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHoveringTimer = hovering
            isHoveringBottomNav = hovering
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
    
    private var timerTitle: String {
        if !timerIsRunning && timeRemaining == 900 {
            return  "15:00"  
        }

        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func handleTimerClick() {
        let now = Date()
        guard let lastClick = lastClickTime else {
            lastClickTime = now
            timerIsRunning.toggle()
            return
        }
        
        if now.timeIntervalSince(lastClick) < 0.3 {
            resetTimer()
        } else {
            timerIsRunning.toggle()
        }
        lastClickTime = now
    }
    
    private func resetTimer() {
        withAnimation {
            timeRemaining = 900
            timerIsRunning = false
            lastClickTime = nil
        }
    }
}


