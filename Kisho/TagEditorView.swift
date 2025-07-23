//
//  TagEditorView.swift
//  Kisho
//
//  Created by Peter Macdonald on 24/07/2025.
//

import SwiftUI
import AppKit

struct TagEditorView: View {
    @Binding var tags: [String]
    var allAvailableTags: [String]

    @State private var tagInput: String = ""
    @State private var currentSuggestion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tags")
                .font(.headline)
            ZStack(alignment: .leading) {
                // Suggestion overlay
                if let suggestion = currentSuggestion {
                    HStack {
                        Text(tagInput) +
                        Text(tagInput.ghostSuffix(with: suggestion))
                            .foregroundColor(.gray.opacity(0.5))
                           
                        Spacer()
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)
                }

                // Actual input field
                TagSuggestingTextField(
                    text: $tagInput,
                    suggestion: currentSuggestion,
                    onChange: { _ in updateSuggestion() },
                    acceptSuggestion: {
                        if let suggestion = currentSuggestion {
                            acceptSuggestion(suggestion)
                        }
                    }
                )
                
                .frame(height: 24)
                .font(.system(size: 13, design: .monospaced))
            }

        }
        .onAppear {
            tagInput = tags.joined(separator: ", ")
            updateSuggestion()
        }
    }

    private func updateSuggestion() {
        print("Suggestion:", currentSuggestion ?? "nil")

        let typedParts = tagInput.split(separator: ",")
        guard let current = typedParts.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !current.isEmpty else {
            currentSuggestion = nil
            return
        }

        currentSuggestion = allAvailableTags
            .filter { $0.lowercased().hasPrefix(current.lowercased()) }
            .filter { !tags.contains($0) }
            .first
    }

    private func acceptSuggestion(_ suggestion: String) {
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
