//
//  FontSizePicker.swift
//  Kisho
//
//  Created by Peter Macdonald on 23/07/2025.
//

import SwiftUI

struct FontSizePicker: View {
    @Binding var fontSize: Double
    var apply: () -> Void

    private let minSize: Double = 8
    private let maxSize: Double = 72

    var body: some View {
        HStack(spacing: 4) {
            // Text Field
            TextField("", value: $fontSize, formatter: NumberFormatter.integer, onCommit: {
                fontSize = clamped(fontSize)
                apply()
            })
            .frame(width: 40)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .help("Font Size (points)")

            // Up/Down Chevron Buttons
            VStack(spacing: 2) {
                Button(action: {
                    fontSize = clamped(fontSize + 1)
                    apply()
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 12)
                }
                .buttonStyle(BorderlessButtonStyle())

                Button(action: {
                    fontSize = clamped(fontSize - 1)
                    apply()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 12)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .frame(height: 28)
            .padding(.trailing, 4)
        }
        .frame(width: 80, alignment: .leading)
    }

    private func clamped(_ value: Double) -> Double {
        return min(max(value, minSize), maxSize)
    }
}

extension NumberFormatter {
    static var integer: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 8
        formatter.maximum = 72
        return formatter
    }
}
