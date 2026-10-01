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
        // A field plus a native stepper: both are standard toolbar height, so
        // the text group lines up with the buttons either side of it.
        HStack(spacing: 4) {
            TextField("", value: $fontSize, formatter: NumberFormatter.integer, onCommit: {
                fontSize = clamped(fontSize)
                apply()
            })
            .frame(width: 40)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .help("Font Size (points)")

            Stepper("Font Size", value: Binding(
                get: { fontSize },
                set: { fontSize = clamped($0); apply() }
            ), in: minSize...maxSize, step: 1)
            .labelsHidden()
            .help("Font Size (points)")
        }
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
