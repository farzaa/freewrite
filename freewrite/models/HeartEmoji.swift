//
//  HeartEmoji.swift
//  freewrite
//
//  Created by JTV on 4/13/25.
//
//  Lightweight model used for animated emoji effects.
//

import SwiftUI

struct HeartEmoji: Identifiable {
    let id = UUID()
    var position: CGPoint
    var offset: CGFloat = 0
}
