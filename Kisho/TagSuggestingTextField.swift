//
//  TagSuggestingTextField.swift
//  Kisho
//
//  Created by Peter Macdonald on 24/07/2025.
//

import SwiftUI
import AppKit

struct TagSuggestingTextField: NSViewRepresentable {
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TagSuggestingTextField

        init(_ parent: TagSuggestingTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onChange(field.stringValue)
        }

        @objc func handleKeyDown(_ event: NSEvent) {
            guard let suggestion = parent.suggestion, !suggestion.isEmpty else { return }

            switch event.keyCode {
            case 48, 124: // 48 = Tab, 124 = Right Arrow
                parent.acceptSuggestion()
            default:
                break
            }
        }
    }

    @Binding var text: String
    var suggestion: String?
    var onChange: (String) -> Void
    var acceptSuggestion: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = true
        field.isBezeled = true
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.target = context.coordinator
        field.action = #selector(Coordinator.controlTextDidChange(_:))
        field.stringValue = text
        field.drawsBackground = false

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            context.coordinator.handleKeyDown(event)
            return event
        }

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}
