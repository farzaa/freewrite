//
//  ThemeManager.swift
//  freewrite
//
//  Created by JTV on 4/13/25.
//

import SwiftUI

// MARK: - ThemeType Enum with String Raw Values

enum ThemeType: String {
    case light
    case dark
}

// MARK: - Theme Protocol and Implementations

protocol Theme {
    var hoverColor: Color { get }
    var selectedColor: Color { get }
    var background: Color { get }
    var textPrimary: Color { get }
    var textSecondary: Color { get }
}

struct LightTheme: Theme {
    let hoverColor: Color = .black
    let selectedColor: Color = .black
    let background: Color = .white
    let textPrimary: Color = .black
    let textSecondary: Color = .gray
}

struct DarkTheme: Theme {
    let hoverColor: Color = .white
    let selectedColor: Color = .white
    let background: Color = .black
    let textPrimary: Color = .white
    let textSecondary: Color = .gray
}

// MARK: - Theme Manager with @AppStorage

class ThemeManager: ObservableObject {
    @AppStorage("themeType") private var savedThemeType: String = ThemeType.light.rawValue
    
    @Published var currentTheme: Theme = LightTheme()  // Default so it's initialized
    
    init() {
        let storedTheme = ThemeType(rawValue: savedThemeType) ?? .light
        currentTheme = (storedTheme == .light) ? LightTheme() : DarkTheme()
    }
    
    func switchTheme() {
        if currentTheme is LightTheme {
            currentTheme = DarkTheme()
            savedThemeType = ThemeType.dark.rawValue
        } else {
            currentTheme = LightTheme()
            savedThemeType = ThemeType.light.rawValue
        }
    }
}

// MARK: - Environment Key (Optional)

struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = LightTheme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
