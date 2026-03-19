// Swift 5.0
//
//  AmbientSoundManager.swift
//  freewrite
//
//  Procedurally generated ambient sounds for focus sessions.
//  Uses AVAudioEngine with AVAudioSourceNode to synthesize
//  noise patterns — no bundled audio files required.
//

import AVFoundation

enum AmbientSound: String, CaseIterable, Identifiable {
    case whiteNoise = "White Noise"
    case rain = "Rain"
    case ocean = "Ocean"
    case fireplace = "Fireplace"
    case wind = "Wind"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .whiteNoise: return "waveform"
        case .rain: return "cloud.rain"
        case .ocean: return "water.waves"
        case .fireplace: return "flame"
        case .wind: return "wind"
        }
    }
}

class AmbientSoundManager: ObservableObject {
    @Published var currentSound: AmbientSound?
    @Published var isPlaying = false

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?

    // State for noise generation
    private var brownNoiseState: Float = 0
    private var rainDropTimer: Float = 0
    private var crackleTimer: Float = 0
    private var gustPhase: Float = 0

    func play(_ sound: AmbientSound) {
        stop()
        currentSound = sound
        isPlaying = true

        // Reset generator state
        brownNoiseState = 0
        rainDropTimer = 0
        crackleTimer = 0
        gustPhase = 0

        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        let generator = createGenerator(for: sound)
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffer = UnsafeMutableBufferPointer<Float>(
                start: bufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self),
                count: Int(frameCount)
            )
            for i in 0..<Int(frameCount) {
                buffer[i] = generator(i)
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.3

        do {
            try engine.start()
            audioEngine = engine
            sourceNode = source
        } catch {
            print("Error starting ambient sound: \(error)")
            isPlaying = false
            currentSound = nil
        }
    }

    func stop() {
        audioEngine?.stop()
        if let source = sourceNode {
            audioEngine?.detach(source)
        }
        audioEngine = nil
        sourceNode = nil
        isPlaying = false
        currentSound = nil
    }

    func toggle(_ sound: AmbientSound) {
        if currentSound == sound && isPlaying {
            stop()
        } else {
            play(sound)
        }
    }

    // MARK: - Noise Generators

    private func createGenerator(for sound: AmbientSound) -> (Int) -> Float {
        switch sound {
        case .whiteNoise:
            return whiteNoiseGenerator()
        case .rain:
            return rainGenerator()
        case .ocean:
            return oceanGenerator()
        case .fireplace:
            return fireplaceGenerator()
        case .wind:
            return windGenerator()
        }
    }

    /// Pure white noise — equal energy across all frequencies.
    private func whiteNoiseGenerator() -> (Int) -> Float {
        return { _ in
            Float.random(in: -0.4...0.4)
        }
    }

    /// Rain — layered filtered noise with random drop accents.
    private func rainGenerator() -> (Int) -> Float {
        var lowPassState: Float = 0
        var dropAccent: Float = 0

        return { _ in
            // Base: low-passed white noise for steady rain
            let white = Float.random(in: -1...1)
            let alpha: Float = 0.15
            lowPassState = alpha * white + (1 - alpha) * lowPassState
            let base = lowPassState * 0.6

            // Random drop accents
            dropAccent *= 0.9992
            if Float.random(in: 0...1) < 0.0003 {
                dropAccent = Float.random(in: 0.3...0.7)
            }
            let drop = Float.random(in: -1...1) * dropAccent * 0.4

            return base + drop
        }
    }

    /// Ocean waves — slow amplitude modulation on brown noise.
    private func oceanGenerator() -> (Int) -> Float {
        var brownState: Float = 0
        var phase: Float = 0
        let sampleRate: Float = 44100

        return { _ in
            // Brown noise base
            brownState += Float.random(in: -0.02...0.02)
            brownState = max(-1, min(1, brownState)) * 0.98

            // Slow wave envelope (~8 second cycle)
            phase += 1.0 / sampleRate
            let wave = (sin(phase * 2 * .pi / 8.0) + 1) / 2
            let envelope = 0.2 + wave * 0.5

            return brownState * envelope
        }
    }

    /// Fireplace — crackle bursts layered on warm low rumble.
    private func fireplaceGenerator() -> (Int) -> Float {
        var lowState: Float = 0
        var crackle: Float = 0

        return { _ in
            // Warm low rumble
            let white = Float.random(in: -1...1)
            let alpha: Float = 0.05
            lowState = alpha * white + (1 - alpha) * lowState
            let rumble = lowState * 0.5

            // Random crackle pops
            crackle *= 0.996
            if Float.random(in: 0...1) < 0.0002 {
                crackle = Float.random(in: 0.4...0.9)
            }
            let pop = Float.random(in: -1...1) * crackle * 0.5

            return rumble + pop
        }
    }

    /// Wind — modulated filtered noise with slow gusts.
    private func windGenerator() -> (Int) -> Float {
        var filterState: Float = 0
        var phase: Float = 0
        let sampleRate: Float = 44100

        return { _ in
            let white = Float.random(in: -1...1)

            // Varying filter cutoff for gusts (~12 second cycle)
            phase += 1.0 / sampleRate
            let gust = (sin(phase * 2 * .pi / 12.0) + 1) / 2
            let alpha = 0.05 + gust * 0.2

            filterState = alpha * white + (1 - alpha) * filterState
            let envelope = 0.3 + gust * 0.4

            return filterState * envelope
        }
    }
}
