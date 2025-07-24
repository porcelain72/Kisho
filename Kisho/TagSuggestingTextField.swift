//
//  TagSuggestingTextField.swift
//  Kisho
//
//  Created by Peter Macdonald on 24/07/2025.
//

import SwiftUI
import AppKit


// MARK: - TagSuggestingTextField (Reused in SwiftUI)
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
            case 36: // Return key
                parent.acceptSuggestion()
            default:
                break
            }

        }
    }

    @Binding var text: String
    @Binding var suggestion: String?
    @Binding var isFocused: Bool

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
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.target = context.coordinator
        field.action = #selector(Coordinator.controlTextDidChange(_:))
        field.stringValue = text

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            context.coordinator.handleKeyDown(event)
            return event
        }
        NotificationCenter.default.addObserver(forName: NSControl.textDidBeginEditingNotification, object: field, queue: .main) { _ in
            self.isFocused = true
        }
        NotificationCenter.default.addObserver(forName: NSControl.textDidEndEditingNotification, object: field, queue: .main) { _ in
            self.isFocused = false
        }

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}

// MARK: - Ghost Suggestion Helper
extension String {
    func ghostSuffix(with suggestion: String) -> String {
        guard let last = self.split(separator: ",").last else { return "" }
        let current = last.trimmingCharacters(in: .whitespaces)
        if suggestion.lowercased().hasPrefix(current.lowercased()) {
            return String(suggestion.dropFirst(current.count))
        }
        return ""
    }
}

