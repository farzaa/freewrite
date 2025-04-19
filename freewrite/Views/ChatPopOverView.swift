//
//  ChatPopOverView.swift
//  freewrite
//
//  Created by Gaspar Dolcemascolo on 17-04-25.
//

import SwiftUI

struct ChatPopOverView: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var text: String
    
    var action: (_: Chat) -> Void
    
    var popoverTextColor: Color {
        return settings.colorScheme == .light ? Color.primary : Color.white
    }
    
    var popoverBackgroundColor: Color {
        return settings.colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(NSColor.darkGray)
    }
    
    
    var body: some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("hi. my name is farza.") {
            Text("Yo. Sorry, you can't chat with the guide lol. Please write your own entry.")
                .font(.system(size: 14))
                .foregroundColor(popoverTextColor)
                .frame(width: 250)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(popoverBackgroundColor)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
        } else if text.count < 350 {
            Text("Please free write for at minimum 5 minutes first. Then click this. Trust.")
                .font(.system(size: 14))
                .foregroundColor(popoverTextColor)
                .frame(width: 250)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(popoverBackgroundColor)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
        } else {
            VStack(spacing: 0) {
                Button(action: {
                    action(.chatGTP)
                }) {
                    Text(Chat.chatGTP.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundColor(popoverTextColor)
                
                Divider()
                
                Button(action: {
                    action(.claude)
                }) {
                    Text("Claude")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundColor(popoverTextColor)
            }
            .frame(width: 120)
            .background(popoverBackgroundColor)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
        }
    }
}

