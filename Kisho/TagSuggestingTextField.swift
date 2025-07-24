//
//  TagSuggestingTextField.swift
//  Kisho
//
//  Created by Peter Macdonald on 24/07/2025.
//

import SwiftUI
import AppKit
/*
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
*/
import SwiftUI

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

// MARK: - Demo View
struct TagSuggestionDemoView: View {
    @State private var tagInput: String = ""
    @State private var currentSuggestion: String? = nil
    let allTags = ["swift", "macos", "ios", "editor", "keyboard"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.headline)

            ZStack(alignment: .leading) {
                if let suggestion = currentSuggestion {
                    HStack {
                        Text(tagInput)
                        + Text(tagInput.ghostSuffix(with: suggestion))
                            .foregroundColor(.red)
                            //.opacity(0.5)
                        Spacer()
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)
                }

                TagSuggestingTextField(
                    text: $tagInput,
                    suggestion: $currentSuggestion,
                    onChange: { _ in updateSuggestion() },
                    acceptSuggestion: {
                        if let suggestion = currentSuggestion {
                            acceptSuggestion(suggestion)
                        }
                    }
                )
                .frame(height: 24)
            }

        }
        .padding()
        .frame(width: 400)
        .onAppear { updateSuggestion() }
    }

    func updateSuggestion() {
        let typed = tagInput.split(separator: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if typed.isEmpty {
            currentSuggestion = nil
        } else {
            currentSuggestion = allTags.first(where: { $0.lowercased().hasPrefix(typed.lowercased()) })
        }
        print("Ghost suggestion is: \(currentSuggestion ?? "nil")")

    }

    func acceptSuggestion(_ suggestion: String) {
        var parts = tagInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.isEmpty {
            parts = [suggestion]
        } else {
            parts[parts.count - 1] = suggestion
        }
        tagInput = parts.joined(separator: ", ") + ", "
        updateSuggestion()
    }
}

#Preview {
    TagSuggestionDemoView()
}

