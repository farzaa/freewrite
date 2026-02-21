//
//  VideoRecordingView.swift
//  freewrite
//
//  Created by Claude Code
//

import SwiftUI
import AVFoundation
import AppKit

class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: Int = 0
    @Published var permissionGranted = false
    @Published var microphonePermissionGranted = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    private let sessionQueue = DispatchQueue(label: "freewrite.camera.session")
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var recordingTimer: Timer?
    private var outputURL: URL?
    private var isSessionConfigured = false
    private var isSettingUpSession = false
    private var hasNotifiedReady = false
    private var hasNotifiedCannotRecord = false

    var onRecordingComplete: ((URL) -> Void)?
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

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            requestMicrophonePermissionAndSetup()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.logPermissionState("camera requestAccess callback granted=\(granted)")
                    self?.permissionGranted = granted
                    if granted {
                        self?.requestMicrophonePermissionAndSetup()
                    }
                }
            }
        default:
            permissionGranted = false
            notifyCannotRecordIfNeeded()
        }
    }

    func requestMicrophonePermissionAndSetup() {
        logPermissionState("requestMicrophonePermissionAndSetup() start")
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermissionGranted = true
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.logPermissionState("microphone requestAccess callback granted=\(granted)")
                    self?.microphonePermissionGranted = granted
                    if granted {
                        self?.setupCamera()
                    }
                }
            }
        default:
            microphonePermissionGranted = false
            print("[CameraManager] microphone access unavailable; recording is blocked until enabled in System Settings.")
            notifyCannotRecordIfNeeded()
        }
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

                session.commitConfiguration()

                self.captureSession = session
                self.videoOutput = output
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
            self.notifyReadyIfPossible()
        }
    }

    private func notifyReadyIfPossible() {
        guard permissionGranted, microphonePermissionGranted, previewLayer != nil else { return }
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
        DispatchQueue.main.async {
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
        }

        sessionQueue.async { [weak self] in
            guard let self = self, let videoOutput = self.videoOutput, videoOutput.isRecording else { return }
            videoOutput.stopRecording()
        }
    }

    func cleanup() {
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
            self.isSessionConfigured = false
            self.isSettingUpSession = false
            self.hasNotifiedReady = false
            self.hasNotifiedCannotRecord = false

            DispatchQueue.main.async {
                self.previewLayer = nil
            }
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false

            if let error = error {
                print("Recording error: \(error)")
            } else {
                self?.onRecordingComplete?(outputFileURL)
            }
        }
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
    @State private var isHoveringSettings = false
    @State private var isHoveringRetry = false

    var onRecordingComplete: (URL) -> Void

    init(
        isPresented: Binding<Bool>,
        cameraManager: CameraManager? = nil,
        onRecordingComplete: @escaping (URL) -> Void
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
        cameraManager.permissionGranted && cameraManager.microphonePermissionGranted
    }

    var displayTimer: String {
        cameraManager.isRecording ? timeString : "0:00"
    }

    var body: some View {
        ZStack {
            cameraSurface
            permissionOverlay
            floatingBottomNav
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            if cameraManager.previewLayer == nil {
                cameraManager.checkPermissions()
            }
        }
        .onDisappear {
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
            Color.black
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var permissionOverlay: some View {
        if !canRecord {
            VStack(spacing: 10) {
                Text(cameraManager.permissionGranted ? "Microphone Access Needed" : "Camera Access Needed")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)

                Text(
                    cameraManager.permissionGranted
                    ? "Enable microphone access in System Settings to record with audio."
                    : "Enable camera access in System Settings to record video."
                )
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.5))
            )
        }
    }

    private var floatingBottomNav: some View {
        VStack {
            Spacer()

            ZStack(alignment: .bottom) {
                HStack(spacing: 8) {
                    Text(displayTimer)
                        .foregroundColor(.white.opacity(0.92))

                    Text("•")
                        .foregroundColor(.white.opacity(0.55))

                    Text(cameraManager.isRecording ? "Recording" : "Ready")
                        .foregroundColor(cameraManager.isRecording ? Color.red.opacity(0.92) : .white.opacity(0.92))

                    Spacer()

                    if !canRecord {
                        settingsButton

                        Text("•")
                            .foregroundColor(.white.opacity(0.55))

                        retryPermissionButton

                        Text("•")
                            .foregroundColor(.white.opacity(0.55))
                    }

                    closeButton
                }
                .font(.system(size: 13))
                .padding(.horizontal, 24)
                .padding(.bottom, 22)

                recordButton
                    .padding(.bottom, 16)
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

    private var settingsButton: some View {
        Button("System Settings") {
            openSystemSettings()
        }
        .buttonStyle(.plain)
        .foregroundColor(isHoveringSettings ? .white : .white.opacity(0.9))
        .onHover { hovering in
            isHoveringSettings = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var retryPermissionButton: some View {
        Button("Retry Permission") {
            cameraManager.checkPermissions()
        }
        .buttonStyle(.plain)
        .foregroundColor(isHoveringRetry ? .white : .white.opacity(0.9))
        .onHover { hovering in
            isHoveringRetry = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.42))

                Circle()
                    .stroke(Color.white.opacity(0.32), lineWidth: 1)

                if cameraManager.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.95))
                        .frame(width: 18, height: 18)
                } else {
                    Circle()
                        .fill(Color.red.opacity(0.95))
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 68, height: 68)
            .shadow(color: Color.black.opacity(0.45), radius: 10, y: 5)
            .scaleEffect(isHoveringRecord ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .help(cameraManager.isRecording ? "Stop Recording" : "Start Recording")
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

    private func toggleRecording() {
        if cameraManager.isRecording {
            cameraManager.stopRecording()
            return
        }

        cameraManager.onRecordingComplete = { url in
            onRecordingComplete(url)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        cameraManager.startRecording(to: tempURL)
    }

    private func closeRecorder() {
        if cameraManager.isRecording {
            cameraManager.onRecordingComplete = { url in
                try? FileManager.default.removeItem(at: url)
            }
            cameraManager.stopRecording()
        }

        isPresented = false
    }

    private func openSystemSettings() {
        let privacyPane = cameraManager.permissionGranted ? "Privacy_Microphone" : "Privacy_Camera"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyPane)") {
            NSWorkspace.shared.open(url)
        }
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
