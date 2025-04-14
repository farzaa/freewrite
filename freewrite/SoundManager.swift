import Foundation
import AVFoundation
import AudioToolbox
#if os(macOS)
import AppKit
#endif

class SoundManager {
    static let shared = SoundManager()
    
    // Sound types
    enum SoundType {
        case keyPress
        case spaceBar
        case backspace
        case carriageReturn
    }
    
    private var players: [SoundType: AVAudioPlayer] = [:]
    
    // Control whether sounds are enabled
    var soundEnabled = true
    
    private init() {
        setupAudioSession()
        prepareAllSounds()
    }
    
    private func setupAudioSession() {
        // AVAudioSession is iOS-specific, skip on macOS
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default)
            try audioSession.setActive(true)
            print("Audio session set up successfully")
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        #else
        print("Audio session setup skipped (not needed on macOS)")
        #endif
    }
    
    private func prepareAllSounds() {
        // Load all the different sound types
        prepareSound(type: .keyPress, filename: "typewriter-key-1")
        prepareSound(type: .spaceBar, filename: "typewriter-space-bar-1")
        prepareSound(type: .backspace, filename: "typewriter-backspace-1")
        prepareSound(type: .carriageReturn, filename: "typewriter-return-1")
    }
    
    private func prepareSound(type: SoundType, filename: String) {
        // First try bundle approach
        if let soundURL = Bundle.main.url(forResource: filename, withExtension: "mp3", subdirectory: "Sounds") {
            print("Found sound URL in bundle: \(soundURL)")
            loadSound(from: soundURL, for: type)
        } else if let soundURL = Bundle.main.url(forResource: filename, withExtension: "mp3") {
            // Try without subdirectory
            print("Found sound URL in main bundle: \(soundURL)")
            loadSound(from: soundURL, for: type)
        } else {
            // Try direct file path as last resort
            let directPath = "/Users/shrivardhangoenka/Documents/Projects/freewrite/freewrite/Sounds/\(filename).mp3"
            print("Sound not found in bundle, trying direct path: \(directPath)")
            let fileURL = URL(fileURLWithPath: directPath)
            if FileManager.default.fileExists(atPath: directPath) {
                print("File exists at direct path")
                loadSound(from: fileURL, for: type)
            } else {
                print("ERROR: Sound file \(filename) not found at any location!")
            }
        }
    }
    
    private func loadSound(from url: URL, for type: SoundType) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.volume = 0.5
            players[type] = player
            print("Successfully loaded audio player for \(type)")
        } catch {
            print("Failed to create audio player for \(type): \(error)")
        }
    }
    
    func playSound(type: SoundType) {
        guard soundEnabled else { return }
        
        // If AVAudioPlayer is available for this type, use it
        if let player = players[type] {
            // Create a slight variation in pitch for natural typing sound (except for return sound)
            if type != .carriageReturn {
                player.rate = Float.random(in: 0.95...1.05)
            }
            player.currentTime = 0
            player.play()
        } else {
            // If still not available, use system sound as fallback
            #if os(macOS)
            print("Using macOS system sound fallback")
            NSSound.beep()
            #else
            // Use iOS system sound
            print("Using iOS system sound fallback")
            AudioServicesPlaySystemSound(1104) // Standard system keyboard click
            #endif
        }
    }
    
    // Convenience methods for each sound type
    func playTypewriterSound() {
        playSound(type: .keyPress)
    }
    
    func playSpaceBarSound() {
        playSound(type: .spaceBar)
    }
    
    func playBackspaceSound() {
        playSound(type: .backspace)
    }
    
    func playReturnSound() {
        playSound(type: .carriageReturn)
    }
    
    func toggleSound() {
        soundEnabled.toggle()
        print("Sound is now \(soundEnabled ? "enabled" : "disabled")")
    }
}