//
//  TagEditorView.swift
//  Kisho
//
//  Created by Peter Macdonald on 24/07/2025.
//
import SwiftUI


struct TagEditorView: View {
    @Binding var tags: [String]
    var allAvailableTags: [String]

    @State private var tagInput: String = ""
    @State private var currentSuggestion: String?

    var body: some View {
        // The host (the inspector's Tags section) supplies the heading.
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(data: tags + ["__add__"], spacing: 6) { tag in
                if tag == "__add__" {
                    TagInputPill(
                        text: $tagInput,
                        suggestion: $currentSuggestion,
                        onCommit: { accepted in
                            acceptSuggestion(accepted)
                        }
                    )
                }
                else {
                    TagPill(label: tag) {
                        removeTag(tag)
                    }
                }
            }
         
        }
        .onAppear {
            updateSuggestion()
        }
        .onChange(of: tagInput) { _ in
            updateSuggestion()
        }
        .onChange(of: tags) { _ in
            updateSuggestion()
        }
    }

    // MARK: - Logic

    private func updateTagsFromInput() {
        let split = tagInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        tags = Array(Set(split))
    }

    private func updateSuggestion() {
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
        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }

        tags.append(trimmed)
        tagInput = ""
        currentSuggestion = nil
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}



struct TagPill: View {
    let label: String
    var icon: String? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .foregroundColor(.primary)
    }
}




struct TagInputPill: View {
    @Binding var text: String
    @Binding var suggestion: String?
    var onCommit: (String) -> Void

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            if isEditing {
                ZStack(alignment: .leading) {
                    if let suggestion = suggestion, !text.isEmpty {
                        HStack {
                            Text(text) +
                            Text(text.ghostSuffix(with: suggestion))
                                .foregroundColor(.gray.opacity(0.5))
                            Spacer()
                        }
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .allowsHitTesting(false)
                    }

                    TextField("", text: $text)
                        .focused($isFocused)
                        .font(.system(size: 13, design: .monospaced))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            let accepted = suggestion ?? text
                            commitAndReset(with: accepted)
                        }
                        .frame(minWidth: 80)
                        .padding(.horizontal, 10)
                        .onAppear { isFocused = true }
                }
            } else {
                Button(action: {
                    withAnimation {
                        isEditing = true
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 28) // Ensures consistent height in FlowLayout
        .overlay(Capsule().strokeBorder(isEditing ? Color.accentColor : Theme.hairline, lineWidth: 1))
        .foregroundColor(isEditing ? .primary : .secondary)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }

    private func commitAndReset(with value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancel()
            return
        }

        onCommit(trimmed)
        text = ""
        suggestion = nil
        isEditing = false
    }

    private func cancel() {
        text = ""
        suggestion = nil
        isEditing = false
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
