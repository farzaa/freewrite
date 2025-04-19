//
//  GetLineHeight.swift
//  freewrite
//
//  Created by Gaspar Dolcemascolo on 18-04-25.
//

import Foundation
import AppKit

// Helper function to calculate line height
func getLineHeight(font: NSFont) -> CGFloat {
    return font.ascender - font.descender + font.leading
}
