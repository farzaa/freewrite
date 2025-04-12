import AVFoundation

struct KeySound {
    let startTime: Double
    let duration: Double
}

class AudioManager {
    static let shared = AudioManager()
    private var soundData: Data?
    private var keySoundMap: [String: KeySound] = [:]
    private(set) var isEnabled: Bool = false
    
    private init() {
        setupKeyboardSound()
        loadKeyDefinitions()
    }
    
    private func setupKeyboardSound() {
        if let soundURL = Bundle.main.url(forResource: "cherry_black", withExtension: "mp3") {
            loadSound(from: soundURL)
        }
    }
    
    private func loadSound(from url: URL) -> Bool {
        do {
            soundData = try Data(contentsOf: url)
            return true
        } catch {
            return false
        }
    }
    
    private func loadKeyDefinitions() {
        if let configURL = Bundle.main.url(forResource: "cherry_black_config", withExtension: "json") {
            loadConfig(from: configURL)
        }
    }
    
    private func loadConfig(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let defines = json?["defines"] as? [String: [Double]] {
                for (key, value) in defines {
                    if value.count == 2 {
                        let startTime = value[0] / 1000.0
                        let duration = value[1] / 1000.0
                        keySoundMap[key] = KeySound(startTime: startTime, duration: duration)
                    }
                }
            }
        } catch {
            // Silently fail
        }
    }
    
    func toggleSound() {
        isEnabled.toggle()
    }
    
    func playKeyboardSound(forKey key: String = "1") {
        guard isEnabled,
              let soundData = soundData,
              let player = try? AVAudioPlayer(data: soundData) else {
            return
        }
        
        let keySound = keySoundMap[key] ?? keySoundMap["1"]
        if let soundInfo = keySound {
            player.enableRate = true
            player.volume = 0.5
            player.currentTime = soundInfo.startTime
            player.play()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + soundInfo.duration) {
                player.stop()
            }
        }
    }
} 
