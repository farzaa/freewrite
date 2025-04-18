//
//  freewriteApp.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit

@main
struct freewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("colorScheme") private var colorSchemeString: String = "auto"
    @StateObject private var appearanceManager = AppearanceManager()
    
    init() {
        // Register Lato font
        if let fontURL = Bundle.main.url(forResource: "Lato-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .toolbar(.hidden, for: .windowToolbar)
                .preferredColorScheme(getPreferredColorScheme())
                .environmentObject(appearanceManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 600)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
    }
    
    // Return desired appearance from user setting
    private func getPreferredColorScheme() -> ColorScheme? {
        switch colorSchemeString {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return appearanceManager.colorScheme
        }
    }
}

@MainActor
class AppearanceManager: ObservableObject {
    @Published var colorScheme: ColorScheme = .light
    private var appearanceObserver: Any?
    
    init() {
        setupAppearanceObserver()
        updateColorScheme()
    }
    
    private func setupAppearanceObserver() {
        // Observe system appearance changes
        appearanceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateColorScheme()
        }
    }
    
    func updateColorScheme() {
        let isDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        colorScheme = isDarkMode ? .dark : .light
        
        // Update app's appearance
        DispatchQueue.main.async {
            NSApp.appearance = isDarkMode ?
                NSAppearance(named: .darkAqua) :
                NSAppearance(named: .aqua)
        }
    }
    
    deinit {
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default.removeObserver(observer)
        }
    }
}

// Add AppDelegate to handle window configuration
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            // Ensure window starts in windowed mode
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            
            // Center the window on the screen
            window.center()
        }
    }
}

// Names and icons of the three appearance options
enum AppColorScheme: String {
    case light = "light"
    case dark = "dark"
    case auto = "auto"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .auto: return "Auto"
        }
    }
    
    var systemImage: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .auto: return "sun.dust.fill"
        }
    }
}
