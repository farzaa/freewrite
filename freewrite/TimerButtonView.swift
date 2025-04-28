//
//  TimerButtonView.swift
//  freewrite
//
//  Created by sa1l on 2025/4/28.
//

import SwiftUI

struct TimerButtonView: View {
    @Binding var timerIsRunning: Bool
    @Binding var isHoveringTimer: Bool
    @Binding var colorScheme: ColorScheme
    @Binding var timeRemaining: Int
    
    var body: some View {
        let timerColor: Color = {
            if timerIsRunning {
                return isHoveringTimer ? (colorScheme == .light ? .black : .white) : .gray.opacity(0.8)
            } else {
                return isHoveringTimer ? (colorScheme == .light ? .black : .white) : (colorScheme == .light ? .gray : .gray.opacity(0.8))
            }
        }()
        
        let timerButtonTitle: String = {
            if !timerIsRunning && timeRemaining == 900 {
                return "15:00"
            }
            let minutes = timeRemaining / 60
            let seconds = timeRemaining % 60
            return String(format: "%d:%02d", minutes, seconds)
        }()
        
        Text(timerButtonTitle)
            .foregroundColor(timerColor)
    }
}
