//
//  KishoFindReplace.swift
//  Kisho
//
//  Find & replace across block titles, bodies and tags, plus the find bar
//  shown above the card editor. Matching and replacing live on the model
//  (testable, undoable); the bar and highlighting live in the view layer.
//

import SwiftUI
import Combine
import RichTextEditor

// MARK: - Model: matching and replacing

struct SearchMatch: Equatable {
    enum Field: Equatable {
        case title
        case body
        /// Index of the tag within the block's `tags`.
        case tag(Int)
    }
    let sectionID: UUID
    let field: Field
    /// Range within the title string, body string or tag string.
    let range: NSRange
}

extension KishoDocumentModel {
    private static func compareOptions(matchCase: Bool) -> NSString.CompareOptions {
        matchCase ? [] : [.caseInsensitive, .diacriticInsensitive]
    }

    /// All occurrences of `query` in reading order: within each block, the
    /// title first, then the body, then tags.
    func findMatches(_ query: String, matchCase: Bool = false) -> [SearchMatch] {
        guard !query.isEmpty else { return [] }
        let options = Self.compareOptions(matchCase: matchCase)
        var results: [SearchMatch] = []

        func ranges(in string: String) -> [NSRange] {
            let ns = string as NSString
            var found: [NSRange] = []
            var searchRange = NSRange(location: 0, length: ns.length)
            while searchRange.length > 0 {
                let r = ns.range(of: query, options: options, range: searchRange)
                guard r.location != NSNotFound, r.length > 0 else { break }
                found.append(r)
                let next = r.location + r.length
                searchRange = NSRange(location: next, length: ns.length - next)
            }
            return found
        }

        for section in orderedSections {
            for r in ranges(in: section.title) {
                results.append(SearchMatch(sectionID: section.id, field: .title, range: r))
            }
            for r in ranges(in: section.content.attributedString.string) {
                results.append(SearchMatch(sectionID: section.id, field: .body, range: r))
            }
            for (i, tag) in section.tags.enumerated() {
                for r in ranges(in: tag) {
                    results.append(SearchMatch(sectionID: section.id, field: .tag(i), range: r))
                }
            }
        }
        return results
    }

    /// The replacement text adapted to the capitalisation of the text it
    /// replaces, for case-insensitive searches: "River" → "Stream",
    /// "RIVER" → "STREAM", "river" → the replacement as typed.
    static func replacement(_ replacement: String, matchingCaseOf matched: String) -> String {
        let letters = matched.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard let first = letters.first, !replacement.isEmpty else { return replacement }
        let firstIsUpper = CharacterSet.uppercaseLetters.contains(first)
        guard firstIsUpper else { return replacement }
        let restAllUpper = letters.dropFirst().allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
        if letters.count > 1 && restAllUpper {
            return replacement.uppercased()
        }
        // Capitalised: upper-case the first letter, keep the rest as typed.
        return replacement.prefix(1).uppercased() + replacement.dropFirst()
    }

    /// Replaces one match. Returns false if the match no longer applies
    /// (text changed underneath it). Undoable through the usual title/body/tag
    /// paths. With `matchCase` off the replacement takes the capitalisation of
    /// the text it replaces.
    @discardableResult
    func replace(_ match: SearchMatch, with replacement: String, matchCase: Bool = false,
                 using undoManager: UndoManager? = nil) -> Bool {
        guard let section = section(withID: match.sectionID) else { return false }

        func adapted(for matched: String) -> String {
            matchCase ? replacement : Self.replacement(replacement, matchingCaseOf: matched)
        }

        switch match.field {
        case .title:
            let ns = section.title as NSString
            guard NSMaxRange(match.range) <= ns.length else { return false }
            let text = adapted(for: ns.substring(with: match.range))
            setTitle(ns.replacingCharacters(in: match.range, with: text), for: section, using: undoManager)
            return true

        case .body:
            let old = section.content.attributedString
            guard NSMaxRange(match.range) <= old.length else { return false }
            let text = adapted(for: (old.string as NSString).substring(with: match.range))
            let mutable = NSMutableAttributedString(attributedString: old)
            mutable.replaceCharacters(in: match.range, with: text)
            let new = NSAttributedString(attributedString: mutable)
            section.content.attributedString = new
            recordBodyEdit(for: section, from: old, to: new, editLocation: match.range.location, using: undoManager)
            return true

        case .tag(let index):
            guard section.tags.indices.contains(index) else { return false }
            let ns = section.tags[index] as NSString
            guard NSMaxRange(match.range) <= ns.length else { return false }
            let text = adapted(for: ns.substring(with: match.range))
            var tags = section.tags
            tags[index] = ns.replacingCharacters(in: match.range, with: text)
            setTags(tags, for: section, using: undoManager)
            return true
        }
    }

    /// Replaces every occurrence as one undo step. Returns the number replaced.
    func replaceAll(_ query: String, with replacement: String, matchCase: Bool = false,
                    using undoManager: UndoManager? = nil) -> Int {
        let matches = findMatches(query, matchCase: matchCase)
        guard !matches.isEmpty else { return 0 }

        undoManager?.beginUndoGrouping()
        defer {
            undoManager?.setActionName("Replace All")
            undoManager?.endUndoGrouping()
        }

        // Replace from the end of each string backwards so earlier ranges stay valid.
        var count = 0
        for match in matches.reversed()
        where replace(match, with: replacement, matchCase: matchCase, using: undoManager) {
            count += 1
        }
        return count
    }

    // MARK: Tag filter helpers

    /// Whether the block or any descendant carries the tag.
    func subtreeHasTag(_ tag: String, in section: KishoSection) -> Bool {
        section.subtree.contains { $0.tags.contains(tag) }
    }
}

#if os(macOS)

// MARK: - Find state (view layer)

/// State of the find bar. One per document window; cards read it to
/// highlight matches, the bar drives navigation and replacement.
final class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published var replacement = ""
    @Published var matchCase = false
    @Published private(set) var matches: [SearchMatch] = []
    @Published private(set) var currentIndex: Int?

    /// Bumped when the bar should take keyboard focus (⌘F).
    @Published var focusToken = UUID()
    /// Set by `show()` for a bar that is not on screen yet: it focuses its
    /// field when it appears. Not set by ⌘E, which leaves focus in the text.
    var pendingFocus = false

    private weak var document: KishoDocumentModel?
    private var cancellables = Set<AnyCancellable>()

    func attach(to document: KishoDocumentModel) {
        guard self.document !== document else { return }
        self.document = document
        cancellables.removeAll()
        // Re-run the search when the text or structure changes.
        document.stats.$version
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(keepingCurrent: true) }
            .store(in: &cancellables)
        document.$sections
            .dropFirst()
            .sink { [weak self] _ in self?.refresh(keepingCurrent: true) }
            .store(in: &cancellables)
        // Standard Find menu items arriving at a card text view in our window.
        NotificationCenter.default.publisher(for: .kishoFindPanelAction)
            .sink { [weak self] note in
                guard let self, let document = self.document,
                      let content = note.userInfo?["content"] as? RichTextModel,
                      document.orderedSections.contains(where: { $0.content === content }) else { return }
                let tag = note.userInfo?["tag"] as? Int ?? 1
                switch NSFindPanelAction(rawValue: UInt(max(0, tag))) {
                case .next: self.step(forward: true)
                case .previous: self.step(forward: false)
                case .setFindString:
                    // ⌘E: adopt the selection without moving focus to the bar.
                    if let s = note.userInfo?["string"] as? String { self.query = s }
                    self.refresh()
                    self.isVisible = true
                default: self.show()
                }
            }
            .store(in: &cancellables)
    }


    var current: SearchMatch? {
        guard let i = currentIndex, matches.indices.contains(i) else { return nil }
        return matches[i]
    }

    var summary: String {
        if query.isEmpty { return "" }
        if matches.isEmpty { return "No matches" }
        if let i = currentIndex { return "\(i + 1) of \(matches.count)" }
        return "\(matches.count) match\(matches.count == 1 ? "" : "es")"
    }

    /// Show the bar and focus its field.
    func show() {
        pendingFocus = !isVisible
        isVisible = true
        focusToken = UUID()
    }

    /// Close the bar. If the user had stepped to a match, leave the caret
    /// there (selected), otherwise focus stays where AppKit puts it.
    func hide() {
        guard let landing = current else {
            isVisible = false
            return
        }
        // Hand focus to the card first and remove the bar afterwards: taking
        // the bar's focused field out of the hierarchy while it is still first
        // responder resigns focus for the whole window, which would undo the
        // hand-over and leave only the selection behind.
        reveal(landing, takingFocus: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.isVisible = false
            self.currentIndex = nil
        }
    }

    /// "Use Selection for Find" (⌘E): take the selected text of whichever
    /// text field or text view has keyboard focus as the search term.
    func useSelection() {
        guard let responder = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let range = responder.selectedRange()
        guard range.length > 0 else { return }
        let selected = (responder.string as NSString).substring(with: range)
        // A multi-paragraph selection isn't a useful search term.
        query = selected.components(separatedBy: .newlines).first ?? selected
        refresh()
        if !isVisible { isVisible = true }
    }

    func refresh(keepingCurrent: Bool = false) {
        guard let document else { return }
        let previous = current
        matches = document.findMatches(query, matchCase: matchCase)
        if keepingCurrent, let previous, let i = matches.firstIndex(of: previous) {
            currentIndex = i
        } else if matches.isEmpty {
            currentIndex = nil
        } else if let i = currentIndex, matches.indices.contains(i) {
            // keep
        } else {
            currentIndex = nil
        }
    }

    /// Advance to the next/previous match and ask the editor to show it.
    func step(forward: Bool) {
        refresh(keepingCurrent: true)
        guard !matches.isEmpty else { return }
        if let i = currentIndex {
            currentIndex = (i + (forward ? 1 : matches.count - 1)) % matches.count
        } else {
            currentIndex = forward ? 0 : matches.count - 1
        }
        reveal(current, takingFocus: false)
    }

    func replaceCurrent(using undoManager: UndoManager?) {
        guard let document else { return }
        if current == nil { step(forward: true) }
        guard let match = current else { return }
        let index = currentIndex ?? 0
        document.replace(match, with: replacement, matchCase: matchCase, using: undoManager)
        refresh()
        guard !matches.isEmpty else { currentIndex = nil; return }
        // The match at `index` was consumed; the next one now sits at the same index.
        currentIndex = min(index, matches.count - 1)
        reveal(current, takingFocus: false)
    }

    func replaceAll(using undoManager: UndoManager?) {
        guard let document else { return }
        _ = document.replaceAll(query, with: replacement, matchCase: matchCase, using: undoManager)
        refresh()
    }

    /// Select the block and scroll its card into view, marking the matched
    /// text. While the bar is in use (`takingFocus` false) keyboard focus stays
    /// in the bar so Return keeps stepping instead of typing into the card.
    private func reveal(_ match: SearchMatch?, takingFocus: Bool) {
        guard let document, let match else { return }
        document.selectedSectionID = match.sectionID
        switch match.field {
        case .body:
            document.requestFocus(match.sectionID, .body, selection: match.range, takesFocus: takingFocus)
        case .title, .tag:
            document.requestFocus(match.sectionID, .title, takesFocus: takingFocus)
        }
    }

    /// Ranges to highlight in one block's body, and which of them is current.
    func bodyHighlights(for sectionID: UUID) -> (all: [NSRange], current: NSRange?) {
        highlights(for: sectionID, field: .body)
    }

    /// Ranges to highlight in one block's title, and which of them is current.
    func titleHighlights(for sectionID: UUID) -> (all: [NSRange], current: NSRange?) {
        highlights(for: sectionID, field: .title)
    }

    private func highlights(for sectionID: UUID, field: SearchMatch.Field) -> (all: [NSRange], current: NSRange?) {
        guard isVisible, !query.isEmpty else { return ([], nil) }
        let all = matches.filter { $0.sectionID == sectionID && $0.field == field }.map { $0.range }
        let cur: NSRange? = (current?.sectionID == sectionID && current?.field == field) ? current?.range : nil
        return (all, cur)
    }
}

// MARK: - Find bar

struct FindBar: View {
    @EnvironmentObject var document: KishoDocumentModel
    @ObservedObject var find: FindState
    @Environment(\.undoManager) private var undoManager
    @FocusState private var queryFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: $find.query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 260)
                .focused($queryFocused)
                .onSubmit { find.step(forward: true) }
                .onExitCommand { find.hide() }

            TextField("Replace", text: $find.replacement)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, maxWidth: 240)
                .onSubmit { find.replaceCurrent(using: undoManager) }

            Toggle("Match case", isOn: $find.matchCase)
                .toggleStyle(.checkbox)
                .font(.caption)

            Text(find.summary)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                Button { find.step(forward: false) } label: { Image(systemName: "chevron.up") }
                    .help("Previous match (⇧⌘G)")
                Button { find.step(forward: true) } label: { Image(systemName: "chevron.down") }
                    .help("Next match (⌘G)")
            }
            .disabled(find.matches.isEmpty)

            Button("Replace") { find.replaceCurrent(using: undoManager) }
                .disabled(find.matches.isEmpty)
            Button("All") { find.replaceAll(using: undoManager) }
                .disabled(find.matches.isEmpty)
                .help("Replace all matches (one undo step)")

            Button { find.hide() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.canvas)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.hairline, lineWidth: 1))
        .onAppear {
            find.attach(to: document)
            find.refresh()
            if find.pendingFocus {
                find.pendingFocus = false
                queryFocused = true
            }
        }
        .onChange(of: find.focusToken) { _ in queryFocused = true }
        .onChange(of: find.query) { _ in find.refresh() }
        .onChange(of: find.matchCase) { _ in find.refresh() }
    }
}

extension FocusedValues {
    private struct FindStateKey: FocusedValueKey {
        typealias Value = FindState
    }
    var kishoFindState: FindState? {
        get { self[FindStateKey.self] }
        set { self[FindStateKey.self] = newValue }
    }
}

/// Edit ▸ Find items.
struct FindCommands: Commands {
    @FocusedValue(\.kishoFindState) private var find

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find…") { find?.show() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(find == nil)
            Button("Find Next") { find?.step(forward: true) }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(find == nil)
            Button("Find Previous") { find?.step(forward: false) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(find == nil)
            Button("Use Selection for Find") { find?.useSelection() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(find == nil)
        }
    }
}
#endif
