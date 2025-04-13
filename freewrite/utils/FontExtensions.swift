//
//  FontExtensions.swift
//  freewrite
//
//  Created by JTV on 4/13/25.
//
//  Extensions for working with NSFont, like calculating line height.
//

import SwiftUI

// Helper extension to get default line height
extension NSFont {
    func defaultLineHeight() -> CGFloat {
        return self.ascender - self.descender + self.leading
    }
}
