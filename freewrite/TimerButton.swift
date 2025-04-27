//
//  TimerButton.swift
//  freewrite
//
//  Created by sa1l on 2025/4/26.
//

import SwiftUI

struct TimerButton: View {
    @Binding var timerButtonTitle: String
    var body: some View {
        Text(timerButtonTitle)
    }
}


