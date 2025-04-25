//
//  DeleteConfirmationView.swift
//  freewrite
//
//  Created by Bahrawy on 15/04/2025.
//
import SwiftUI

struct DeleteConfirmationView: View {
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack() {
            Text("Delete entry?")
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .tint(.red)
            Spacer()
            HStack(spacing: 24) {
                Button("Yes") {
                    onConfirm()
                }
                .buttonStyle(.borderless)
                .tint(.red)
                
                Button("No") {
                    onCancel()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(Color(red: 1.0, green: 0.3, blue: 0.3, opacity: 0.1))
    }
}
