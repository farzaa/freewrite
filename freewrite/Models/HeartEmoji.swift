//
//  HeartEmoji.swift
//  freewrite
//
//  Created by Gaspar Dolcemascolo on 17-04-25.
//

import Foundation

struct HeartEmoji: Identifiable {
    let id = UUID()
    var position: CGPoint
    var offset: CGFloat = 0
}
