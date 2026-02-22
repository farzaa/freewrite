//
//  VideoRecordingView.swift
//  freewrite
//
//  Created by Claude Code
//

import SwiftUI
import AVFoundation
import AppKit
import Speech

class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: Int = 0
    @Published var permissionGranted = false
    @Published var microphonePermissionGranted = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    private var liveCaptionText: String = ""
    private var committedCaptionText: String = ""
    @Published var speechPermissionGranted = false

    private let sessionQueue = DispatchQueue(label: "freewrite.camera.session")
    private let speechQueue = DispatchQueue(label: "freewrite.camera.speech")
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var recordingTimer: Timer?
    private var outputURL: URL?
    private var isSessionConfigured = false
    private var isSettingUpSession = false
    private var hasNotifiedReady = false
    private var hasNotifiedCannotRecord = false
    private var shouldRunLiveCaptions = false
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var speechRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognitionTask: SFSpeechRecognitionTask?
    private var captionPauseCommitWorkItem: DispatchWorkItem?
    private var latestRecognitionText: String = ""
    private var committedCharacterOffset: Int = 0
    private let captionPauseCommitDelaySeconds: Double = 1.2
    private var pendingTranscriptForCompletion: String = ""

    var onRecordingComplete: ((URL, String) -> Void)?
    var onReadyToRecord: (() -> Void)?
    var onCannotRecord: (() -> Void)?

    override init() {
        super.init()
    }

    private func permissionStatusText(_ mediaType: AVMediaType) -> String {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    private func logPermissionState(_ context: String) {
        print("[CameraManager] \(context) | camera=\(permissionStatusText(.video)) mic=\(permissionStatusText(.audio))")
    }

    func checkPermissions() {
        logPermissionState("checkPermissions() start")
        hasNotifiedReady = false
        hasNotifiedCannotRecord = false
        requestSpeechPermissionIfNeeded { [weak self] in
            self?.requestCameraPermissionIfNeeded {
                self?.requestMicrophonePermissionIfNeeded {
                    self?.evaluateCapturePermissionsAndSetup()
                }
            }
        }
    }

    private func requestSpeechPermissionIfNeeded(completion: @escaping () -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechPermissionGranted = true
            refreshLiveCaptionState()
            completion()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    self?.speechPermissionGranted = status == .authorized
                    self?.refreshLiveCaptionState()
                    completion()
                }
            }
        case .denied, .restricted:
            speechPermissionGranted = false
            refreshLiveCaptionState()
            completion()
        @unknown default:
            speechPermissionGranted = false
            refreshLiveCaptionState()
            completion()
        }
    }

    private func requestCameraPermissionIfNeeded(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            completion()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.logPermissionState("camera requestAccess callback granted=\(granted)")
                    self?.permissionGranted = granted
                    completion()
                }
            }
        default:
            permissionGranted = false
            completion()
        }
    }

    private func requestMicrophonePermissionIfNeeded(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermissionGranted = true
            completion()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.logPermissionState("microphone requestAccess callback granted=\(granted)")
                    self?.microphonePermissionGranted = granted
                    completion()
                }
            }
        default:
            microphonePermissionGranted = false
            completion()
        }
    }

    private func evaluateCapturePermissionsAndSetup() {
        if permissionGranted && microphonePermissionGranted && speechPermissionGranted {
            setupCamera()
            return
        }

        if !permissionGranted {
            print("[CameraManager] camera access unavailable; recording is blocked until enabled in System Settings.")
        }
        if !microphonePermissionGranted {
            print("[CameraManager] microphone access unavailable; recording is blocked until enabled in System Settings.")
        }
        if !speechPermissionGranted {
            print("[CameraManager] speech recognition access unavailable; recording is blocked until enabled in System Settings.")
        }

        notifyCannotRecordIfNeeded()
    }

    func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isSessionConfigured {
                self.ensureSessionRunningAndPreviewAttached()
                return
            }
            
            if self.isSettingUpSession {
                return
            }
            self.isSettingUpSession = true
            defer { self.isSettingUpSession = false }

            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let audioDevice = AVCaptureDevice.default(for: .audio) else {
                print("Failed to get camera/audio device")
                DispatchQueue.main.async {
                    self.notifyCannotRecordIfNeeded()
                }
                return
            }

            do {
                let session = AVCaptureSession()
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                let output = AVCaptureMovieFileOutput()
                let captionAudioOutput = AVCaptureAudioDataOutput()

                session.beginConfiguration()
                session.sessionPreset = .high

                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                }

                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }

                if session.canAddOutput(output) {
                    session.addOutput(output)
                }

                if session.canAddOutput(captionAudioOutput) {
                    captionAudioOutput.setSampleBufferDelegate(self, queue: self.speechQueue)
                    session.addOutput(captionAudioOutput)
                }

                session.commitConfiguration()

                self.captureSession = session
                self.videoOutput = output
                self.audioDataOutput = captionAudioOutput
                self.isSessionConfigured = true
                print("[CameraManager] capture session configured with audio + video")
                self.ensureSessionRunningAndPreviewAttached()
            } catch {
                print("Error setting up camera: \(error)")
                DispatchQueue.main.async {
                    self.notifyCannotRecordIfNeeded()
                }
            }
        }
    }

    private func ensureSessionRunningAndPreviewAttached() {
        guard let captureSession = captureSession else { return }
        
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
        attachPreviewLayerIfNeeded(session: captureSession)
    }

    private func attachPreviewLayerIfNeeded(session captureSession: AVCaptureSession) {
        DispatchQueue.main.async {
            if self.previewLayer?.session !== captureSession {
                let layer = AVCaptureVideoPreviewLayer(session: captureSession)
                layer.videoGravity = .resizeAspectFill
                self.previewLayer = layer
            }
            self.refreshLiveCaptionState()
            self.notifyReadyIfPossible()
        }
    }

    private func notifyReadyIfPossible() {
        guard permissionGranted, microphonePermissionGranted, speechPermissionGranted, previewLayer != nil else { return }
        notifyReadyIfNeeded()
    }

    private func notifyReadyIfNeeded() {
        guard !hasNotifiedReady else { return }
        hasNotifiedReady = true
        onReadyToRecord?()
    }

    private func notifyCannotRecordIfNeeded() {
        guard !hasNotifiedCannotRecord else { return }
        hasNotifiedCannotRecord = true
        onCannotRecord?()
    }

    func startRecording(to url: URL) {
        outputURL = url
        prepareTranscriptCaptureForRecording()

        sessionQueue.async { [weak self] in
            guard let self = self, let videoOutput = self.videoOutput else { return }
            guard !videoOutput.isRecording else { return }

            videoOutput.startRecording(to: url, recordingDelegate: self)

            DispatchQueue.main.async {
                self.isRecording = true
                self.recordingTime = 0
                self.recordingTimer?.invalidate()
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.recordingTime += 1
                }
            }
        }
    }

    func stopRecording() {
        executeOnMain {
            self.pendingTranscriptForCompletion = self.finalizedTranscriptText()
            self.setCaptionsEnabled(false)
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
        }

        sessionQueue.async { [weak self] in
            guard let self = self, let videoOutput = self.videoOutput, videoOutput.isRecording else { return }
            videoOutput.stopRecording()
        }
    }

    func cleanup() {
        setCaptionsEnabled(false)

        DispatchQueue.main.async {
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if let videoOutput = self.videoOutput, videoOutput.isRecording {
                videoOutput.stopRecording()
            }

            if let session = self.captureSession {
                if session.isRunning {
                    session.stopRunning()
                }
            }

            self.captureSession = nil
            self.videoOutput = nil
            self.audioDataOutput = nil
            self.isSessionConfigured = false
            self.isSettingUpSession = false
            self.hasNotifiedReady = false
            self.hasNotifiedCannotRecord = false

            DispatchQueue.main.async {
                self.previewLayer = nil
                self.stopLiveCaptionRecognition(clearText: true)
            }
        }
    }

    func setCaptionsEnabled(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.shouldRunLiveCaptions = enabled
            self.refreshLiveCaptionState()
        }
    }

    private func refreshLiveCaptionState() {
        let shouldStart = shouldRunLiveCaptions &&
            isSessionConfigured &&
            permissionGranted &&
            microphonePermissionGranted &&
            speechPermissionGranted

        if shouldStart {
            startLiveCaptionRecognitionIfNeeded()
        } else {
            stopLiveCaptionRecognition(clearText: !shouldRunLiveCaptions)
        }
    }

    private func startLiveCaptionRecognitionIfNeeded() {
        guard speechRecognitionTask == nil else { return }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        speechRecognitionRequest = request

        speechRecognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.processRecognitionResult(result)
                }

                if error != nil {
                    self.stopLiveCaptionRecognition(clearText: false)
                    self.scheduleLiveCaptionRestart()
                }
            }
        }
    }

    private func stopLiveCaptionRecognition(clearText: Bool) {
        captionPauseCommitWorkItem?.cancel()
        captionPauseCommitWorkItem = nil
        speechRecognitionRequest?.endAudio()
        speechRecognitionRequest = nil
        speechRecognitionTask?.cancel()
        speechRecognitionTask = nil
        latestRecognitionText = ""
        committedCharacterOffset = 0
        if clearText {
            liveCaptionText = ""
            committedCaptionText = ""
        }
    }

    private func scheduleLiveCaptionRestart() {
        guard shouldRunLiveCaptions else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.refreshLiveCaptionState()
        }
    }

    private func processRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let fullText = normalizeCaptionText(result.bestTranscription.formattedString)
        latestRecognitionText = fullText

        let fullNSString = fullText as NSString
        let fullLength = fullNSString.length
        committedCharacterOffset = min(committedCharacterOffset, fullLength)

        let liveChunk = fullLength > committedCharacterOffset ? fullNSString.substring(from: committedCharacterOffset) : ""
        liveCaptionText = normalizeCaptionText(liveChunk)

        if result.isFinal {
            commitPendingLiveTranscript(asParagraph: true)
            captionPauseCommitWorkItem?.cancel()
            captionPauseCommitWorkItem = nil
        } else {
            schedulePauseCommitIfNeeded()
        }
    }

    private func schedulePauseCommitIfNeeded() {
        captionPauseCommitWorkItem?.cancel()

        guard !normalizeCaptionText(liveCaptionText).isEmpty else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.commitPendingLiveTranscript(asParagraph: true)
        }

        captionPauseCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + captionPauseCommitDelaySeconds, execute: workItem)
    }

    private func prepareTranscriptCaptureForRecording() {
        executeOnMain {
            self.pendingTranscriptForCompletion = ""
            self.committedCharacterOffset = 0
            self.latestRecognitionText = ""
            self.captionPauseCommitWorkItem?.cancel()
            self.captionPauseCommitWorkItem = nil
            self.liveCaptionText = ""
            self.committedCaptionText = ""
            self.stopLiveCaptionRecognition(clearText: true)
            self.setCaptionsEnabled(true)
        }
    }

    private func executeOnMain(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private func commitPendingLiveTranscript(asParagraph: Bool) {
        let live = normalizeCaptionText(liveCaptionText)
        guard !live.isEmpty else { return }
        appendCommittedCaption(live, addSentenceTerminator: true, asParagraph: asParagraph)
        committedCharacterOffset = (latestRecognitionText as NSString).length
        liveCaptionText = ""
    }

    private func appendCommittedCaption(_ text: String, addSentenceTerminator: Bool, asParagraph: Bool) {
        var cleaned = normalizeCaptionText(text)
        guard !cleaned.isEmpty else { return }

        cleaned = capitalizeSentenceStart(cleaned)

        if addSentenceTerminator && !endsWithTerminalPunctuation(cleaned) {
            cleaned += "."
        }

        if committedCaptionText.isEmpty {
            committedCaptionText = cleaned
        } else if asParagraph {
            committedCaptionText += "\n\n" + cleaned
        } else {
            committedCaptionText += " " + cleaned
        }
    }

    private func normalizeCaptionText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func endsWithTerminalPunctuation(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return [".", "!", "?"].contains(last)
    }

    private func capitalizeSentenceStart(_ text: String) -> String {
        guard let firstLetterIndex = text.firstIndex(where: { $0.isLetter }) else {
            return text
        }

        var characters = Array(text)
        let arrayIndex = text.distance(from: text.startIndex, to: firstLetterIndex)
        characters[arrayIndex] = Character(String(characters[arrayIndex]).uppercased())
        return String(characters)
    }

    private func finalizedTranscriptText() -> String {
        captionPauseCommitWorkItem?.cancel()
        captionPauseCommitWorkItem = nil
        commitPendingLiveTranscript(asParagraph: true)

        let paragraphCandidates = committedCaptionText
            .components(separatedBy: "\n\n")
            .map { normalizeCaptionText($0) }
            .filter { !$0.isEmpty }

        let finalizedParagraphs = paragraphCandidates.map { paragraph -> String in
            var normalized = capitalizeSentenceStart(paragraph)
            if !endsWithTerminalPunctuation(normalized) {
                normalized += "."
            }
            return normalized
        }.filter { !$0.isEmpty }

        return finalizedParagraphs.joined(separator: "\n\n")
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false

            if let error = error {
                print("Recording error: \(error)")
                self?.pendingTranscriptForCompletion = ""
            } else {
                let finalizedTranscript = self?.pendingTranscriptForCompletion ?? ""
                self?.pendingTranscriptForCompletion = ""
                self?.onRecordingComplete?(outputFileURL, finalizedTranscript)
            }
        }
    }
}

extension CameraManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === audioDataOutput,
              let speechRecognitionRequest = speechRecognitionRequest else {
            return
        }
        speechRecognitionRequest.appendAudioSampleBuffer(sampleBuffer)
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    final class PreviewContainerView: NSView {
        private var activePreviewLayer: AVCaptureVideoPreviewLayer?
        
        private func updatePreviewLayerFrame() {
            activePreviewLayer?.frame = bounds
        }
        
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            layer?.masksToBounds = true
        }
        
        func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
            if activePreviewLayer === layer {
                layer.frame = bounds
                return
            }
            
            activePreviewLayer?.removeFromSuperlayer()
            activePreviewLayer = layer
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.needsDisplayOnBoundsChange = true
            self.layer?.addSublayer(layer)
        }
        
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            updatePreviewLayerFrame()
        }
        
        override func setBoundsSize(_ newSize: NSSize) {
            super.setBoundsSize(newSize)
            updatePreviewLayerFrame()
        }
        
        override func layout() {
            super.layout()
            updatePreviewLayerFrame()
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = PreviewContainerView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setPreviewLayer(previewLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let containerView = nsView as? PreviewContainerView {
            containerView.setPreviewLayer(previewLayer)
        } else {
            DispatchQueue.main.async {
                previewLayer.frame = nsView.bounds
            }
        }
    }
}

struct VideoRecordingView: View {
    @Binding var isPresented: Bool
    @StateObject private var cameraManager: CameraManager
    @State private var isHoveringClose = false
    @State private var isHoveringRecord = false
    @State private var viewOpacity: Double = 0

    var onRecordingComplete: (URL, String) -> Void

    init(
        isPresented: Binding<Bool>,
        cameraManager: CameraManager? = nil,
        onRecordingComplete: @escaping (URL, String) -> Void
    ) {
        self._isPresented = isPresented
        _cameraManager = StateObject(wrappedValue: cameraManager ?? CameraManager())
        self.onRecordingComplete = onRecordingComplete
    }

    var timeString: String {
        let minutes = cameraManager.recordingTime / 60
        let seconds = cameraManager.recordingTime % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var canRecord: Bool {
        cameraManager.permissionGranted &&
        cameraManager.microphonePermissionGranted &&
        cameraManager.speechPermissionGranted
    }

    var displayTimer: String {
        cameraManager.isRecording ? timeString : "0:00"
    }

    var body: some View {
        ZStack {
            cameraSurface
            floatingBottomNav
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .opacity(viewOpacity)
        .onAppear {
            viewOpacity = 0
            withAnimation(.easeOut(duration: 1.0)) {
                viewOpacity = 1
            }
            cameraManager.setCaptionsEnabled(false)
            if cameraManager.previewLayer == nil {
                cameraManager.checkPermissions()
            }
        }
        .onDisappear {
            viewOpacity = 0
            cameraManager.setCaptionsEnabled(false)
            cameraManager.cleanup()
        }
    }

    @ViewBuilder
    private var cameraSurface: some View {
        if let previewLayer = cameraManager.previewLayer {
            CameraPreviewView(previewLayer: previewLayer)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .clipped()
                .ignoresSafeArea()
        } else {
            Color.white
                .overlay {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.gray.opacity(0.9))
                }
                .ignoresSafeArea()
        }
    }

    private var floatingBottomNav: some View {
        VStack {
            Spacer()

            ZStack(alignment: .bottom) {
                HStack(spacing: 8) {
                    if cameraManager.isRecording {
                        Text("Recording")
                            .foregroundColor(.red.opacity(0.92))

                        Text("•")
                            .foregroundColor(.white.opacity(0.55))

                        recordingControlButton

                        Text("•")
                            .foregroundColor(.white.opacity(0.55))

                        Text(displayTimer)
                            .foregroundColor(.white.opacity(0.92))
                    } else {
                        recordingControlButton

                        Text("•")
                            .foregroundColor(.white.opacity(0.55))

                        Text(displayTimer)
                            .foregroundColor(.white.opacity(0.92))
                    }

                    Spacer()
                    closeButton
                }
                .font(.system(size: 13))
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.62), Color.black.opacity(0.24), Color.clear]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 160)
                .allowsHitTesting(false),
                alignment: .bottom
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var recordingControlButton: some View {
        Button {
            toggleRecording()
        } label: {
            Text(cameraManager.isRecording ? "Stop Recording" : "Start Recording")
        }
        .buttonStyle(.plain)
        .foregroundColor(recordingControlColor)
        .onHover { hovering in
            isHoveringRecord = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .disabled(!canRecord)
        .opacity(canRecord ? 1.0 : 0.55)
    }

    private var recordingControlColor: Color {
        if cameraManager.isRecording {
            return isHoveringRecord ? .white : .white.opacity(0.92)
        }
        return isHoveringRecord ? .white : .white.opacity(0.92)
    }

    private var closeButton: some View {
        Button("Close") {
            closeRecorder()
        }
        .buttonStyle(.plain)
        .foregroundColor(isHoveringClose ? .white : .white.opacity(0.9))
        .onHover { hovering in
            isHoveringClose = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func toggleRecording() {
        if cameraManager.isRecording {
            cameraManager.stopRecording()
            return
        }

        cameraManager.onRecordingComplete = { url, transcript in
            onRecordingComplete(url, transcript)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        cameraManager.startRecording(to: tempURL)
    }

    private func closeRecorder() {
        if cameraManager.isRecording {
            cameraManager.onRecordingComplete = { url, _ in
                try? FileManager.default.removeItem(at: url)
            }
            cameraManager.stopRecording()
        }

        isPresented = false
    }

}

// Helper function to generate a thumbnail from a video
func generateVideoThumbnail(from url: URL, at time: CMTime = CMTime(seconds: 0, preferredTimescale: 1)) -> NSImage? {
    let asset = AVAsset(url: url)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true

    do {
        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    } catch {
        print("Error generating thumbnail: \(error)")
        return nil
    }
}
