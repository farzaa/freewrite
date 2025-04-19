//
//  freewriteApp.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI

@main
struct freewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"
    @StateObject private var settings = AppSettings()
    @StateObject private var viewModel: FreewriteViewModel = FreewriteViewModel()
    
    init() {
        // Register Lato font
        if let fontURL = Bundle.main.url(forResource: "Lato-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }
     
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .toolbar(.hidden, for: .windowToolbar)
                .preferredColorScheme(colorSchemeString == "dark" ? .dark : .light)
                .environmentObject(settings)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 600)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
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


class AppSettings: ObservableObject {
    @Published var colorScheme: ColorScheme = .light
    
    init() {
        // Load saved color scheme preference
        let savedScheme = UserDefaults.standard.string(forKey: "colorScheme") ?? "light"
        colorScheme = savedScheme == "dark" ? .dark : .light
    }
    
    func updateColorScheme(_ scheme: ColorScheme) {
        UserDefaults.standard.set(scheme == .dark ? "dark" : "light", forKey: "colorScheme")
        colorScheme = scheme
    }
}
