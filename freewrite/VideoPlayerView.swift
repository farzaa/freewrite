//
//  VideoPlayerView.swift
//  freewrite
//
//  Created by Claude Code
//

import SwiftUI
import AVKit
import AVFoundation
import AppKit

private struct FillVideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    
    final class PlayerContainerView: NSView {
        private let playerView = AVPlayerView()

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            wantsLayer = true
            layer?.masksToBounds = true

            playerView.translatesAutoresizingMaskIntoConstraints = false
            playerView.controlsStyle = .floating
            playerView.videoGravity = .resizeAspectFill
            playerView.showsFrameSteppingButtons = false

            addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                playerView.topAnchor.constraint(equalTo: topAnchor),
                playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        func setPlayer(_ player: AVPlayer) {
            if playerView.player !== player {
                playerView.player = player
            }
        }
    }

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.setPlayer(player)
        return view
    }
    
    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.setPlayer(player)
    }
}

struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
    @State private var playbackEndObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            if let player = player {
                FillVideoPlayerSurface(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .onAppear {
                        player.seek(to: .zero)
                        player.play()
                    }
            } else {
                Color.black
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    )
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onChange(of: videoURL) { _ in
            setupPlayer()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func setupPlayer() {
        tearDownPlayer()
        
        let item = AVPlayerItem(url: videoURL)
        let nextPlayer = AVPlayer(playerItem: item)
        nextPlayer.isMuted = false
        nextPlayer.actionAtItemEnd = .none
        
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak nextPlayer] _ in
            nextPlayer?.seek(to: .zero)
            nextPlayer?.play()
        }
        
        player = nextPlayer
        nextPlayer.play()
    }
    
    private func tearDownPlayer() {
        if let observer = playbackEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackEndObserver = nil
        }
        player?.pause()
        player = nil
    }
}
