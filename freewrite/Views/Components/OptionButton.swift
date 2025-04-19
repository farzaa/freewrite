//
//  OptionButton.swift
//  freewrite
//
//  Created by Gaspar Dolcemascolo on 17-04-25.
//

import SwiftUI


struct OptionButton: View {
    
    @EnvironmentObject private var settings: AppSettings
    @State private var isHover: Bool = false
    
    private var textColor: Color {
        return settings.colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
    }
    private var textHoverColor: Color {
        return settings.colorScheme == .light ? Color.black : Color.white
    }
    
    private let action: () -> Void
    private let title: String
    
    init(title: String, action: @escaping () -> Void)  {
        self.title = title
        self.action = action
    }
    
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundColor(isHover ? textHoverColor : textColor)
            .onHover { hovering in
                isHover = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

#Preview {
    OptionButton(title: "This is a button", action: {
        print("Hello, World!")
    })
}
