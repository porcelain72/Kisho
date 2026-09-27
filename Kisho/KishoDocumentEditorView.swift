//
//  KishoDocumentEditorView.swift
//  Kisho
//

import SwiftUI
import RichTextEditor

#if os(macOS)
import AppKit

/// Locates the composite editor's NSTextView within its window, scrolls a
/// section's heading into view when requested, and reports which section the
/// caret is in when the user moves it.
final class EditorScrollProxy: ObservableObject {
    weak var anchorView: NSView?

    /// Set just before the proxy changes the document selection because the
    /// caret moved, so the view's selection handler knows not to move the
    /// caret back.
    var isSyncingFromCaret = false

    /// Selection changes before this instant are treated as programmatic
    /// (the text view was just reset by a rebuild) and not synced.
    var suppressSyncUntil: Date = .distantPast

    /// Called on the main thread with the ID of the section the caret moved
    /// into (user-driven moves only).
    var onCaretSectionChange: ((UUID) -> Void)?

    private var selectionObserver: NSObjectProtocol?
    private var isRelocatingCaret = false

    init() {
        selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSelectionChange(notification)
        }
    }

    deinit {
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
        }
    }

    func currentAttributedString() -> NSAttributedString? {
        locateTextView()?.attributedString()
    }

    /// Places the caret at the end of the section's own content and keeps its
    /// heading in view.
    func focus(sectionID id: UUID, in composite: NSAttributedString) {
        guard let textView = locateTextView() else { return }

        if let caret = KishoSection.compositeCaretIndex(forSectionID: id, in: composite) {
            let length = textView.string.utf16.count
            // Never past the closing paragraph break.
            let limit = (textView.string as NSString).hasSuffix("\n") ? max(0, length - 1) : length
            let clamped = min(max(0, caret), limit)
            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                layoutManager.ensureLayout(for: container)
            }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }

        scroll(toSectionID: id, in: composite, textView: textView)
    }

    /// Selects the section's heading text so that typing renames it.
    func selectHeading(sectionID id: UUID, in composite: NSAttributedString) {
        guard let textView = locateTextView(),
              let range = KishoSection.compositeRange(forSectionID: id, in: composite) else {
            focus(sectionID: id, in: composite)
            return
        }
        // The heading run ends with its paragraph break; don't select that.
        var headingRange = range
        let ns = textView.string as NSString
        while headingRange.length > 0,
              NSMaxRange(headingRange) <= ns.length,
              ["\n", "\r"].contains(ns.substring(with: NSRange(location: NSMaxRange(headingRange) - 1, length: 1))) {
            headingRange.length -= 1
        }
        guard NSMaxRange(headingRange) <= ns.length else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(headingRange)
        scroll(toSectionID: id, in: composite, textView: textView)
    }

    // MARK: - Caret → section

    private func handleSelectionChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              !textView.isFieldEditor,
              let window = anchorView?.window,
              textView.window === window,
              let storage = textView.textStorage,
              storage.length > 0 else { return }

        // The document ends with a plain paragraph break outside any card. A
        // caret parked after it (where resets and clicks below the last card
        // put it) is moved to the end of the last block's body instead, so
        // typing always lands inside a block.
        let selection = textView.selectedRange()
        if !isRelocatingCaret, selection.length == 0, selection.location >= storage.length,
           (storage.string as NSString).hasSuffix("\n") {
            isRelocatingCaret = true
            textView.setSelectedRange(NSRange(location: storage.length - 1, length: 0))
            isRelocatingCaret = false
            return
        }

        guard Date() >= suppressSyncUntil,
              isUserDrivenSelectionChange(in: textView) else { return }

        let location = textView.selectedRange().location
        // Look at the character under the caret; at the end of a body (just
        // before an untagged section break) fall back to the one before it.
        let probe = min(max(0, location), storage.length - 1)
        var idString = storage.attribute(.kishoSectionID, at: probe, effectiveRange: nil) as? String
        if idString == nil, probe > 0 {
            idString = storage.attribute(.kishoSectionID, at: probe - 1, effectiveRange: nil) as? String
        }
        guard let idString, let id = UUID(uuidString: idString) else { return }
        onCaretSectionChange?(id)
    }

    /// Only mouse clicks/drags inside the text view and key presses while it
    /// is first responder count as the user moving the caret. Programmatic
    /// resets (rebuilds, focus) must not change the document selection.
    private func isUserDrivenSelectionChange(in textView: NSTextView) -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            guard event.window === textView.window else { return false }
            let point = textView.convert(event.locationInWindow, from: nil)
            return textView.bounds.contains(point)
        case .keyDown:
            return textView.window?.firstResponder === textView
        default:
            return false
        }
    }

    // MARK: - Scrolling

    private func scroll(toSectionID id: UUID, in composite: NSAttributedString, textView: NSTextView) {
        guard let range = KishoSection.compositeRange(forSectionID: id, in: composite) else { return }

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else {
            textView.scrollRangeToVisible(range)
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.y += textView.textContainerInset.height

        let visibleHeight = scrollView.contentView.bounds.height
        let maxY = max(0, textView.bounds.height - visibleHeight)
        let targetY = min(max(0, rect.minY), maxY)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func locateTextView() -> NSTextView? {
        guard let root = anchorView?.window?.contentView else { return nil }
        return Self.firstEditorTextView(in: root)
    }

    /// The editor's own text view — never a field editor, which is what an
    /// active NSTextField (e.g. the tag input) temporarily installs.
    private static func firstEditorTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, !textView.isFieldEditor { return textView }
        for subview in view.subviews {
            if let found = firstEditorTextView(in: subview) { return found }
        }
        return nil
    }
}

/// Invisible helper that captures the hosting NSView so the proxy can reach the window.
private struct WindowAnchor: NSViewRepresentable {
    let proxy: EditorScrollProxy

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { proxy.anchorView = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { proxy.anchorView = nsView }
    }
}

/// Tag editor for one section. Observes the section itself so removals and
/// undo/redo of tag edits refresh the pills.
private struct SectionTagsEditor: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager
    @ObservedObject var section: KishoSection

    var body: some View {
        TagEditorView(
            tags: Binding(
                get: { section.tags },
                set: { document.setTags($0, for: section, using: undoManager) }
            ),
            allAvailableTags: document.allTags
        )
    }
}

/// Shows the entire document — every top-level section and its descendants —
/// as one editable rich-text composite with section titles as inline headings.
struct KishoDocumentEditorView: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager

    @StateObject private var editor: DocumentCompositeEditorModel
    @StateObject private var scrollProxy = EditorScrollProxy()

    @FocusState private var isRichTextFocused: Bool

    init(document: KishoDocumentModel) {
        self._editor = StateObject(wrappedValue: DocumentCompositeEditorModel(document: document))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Color(NSColor.textBackgroundColor)

                VStack {
                    RichTextEditor(
                        content: editor.compositeContent,
                        inspector: .constant(UUID()),
                        undoManager: undoManager
                    )
                    .focused($isRichTextFocused)

                    Rectangle()
                        .foregroundStyle(Color(NSColor.textBackgroundColor))
                        .frame(height: 100)
                }
                .padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 25.0))
            .background(WindowAnchor(proxy: scrollProxy))

            if let selected = document.selectedSection {
                SectionTagsEditor(section: selected)
                    .id(selected.id)
            }
        }
        .padding()
        .onAppear {
            editor.undoManager = undoManager
            document.beforeStructureEdit = { [weak editor, weak scrollProxy] in
                editor?.flushLiveEdits(from: scrollProxy?.currentAttributedString())
            }
            editor.onRebuild = { [weak scrollProxy] in
                scrollProxy?.suppressSyncUntil = Date().addingTimeInterval(0.4)
            }
            scrollProxy.onCaretSectionChange = { [weak document, weak scrollProxy] id in
                guard let document, document.selectedSectionID != id,
                      document.section(withID: id) != nil else { return }
                scrollProxy?.isSyncingFromCaret = true
                document.selectedSectionID = id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isRichTextFocused = true
            }
            // Place the caret in the selected block on first appearance too;
            // otherwise it sits at the very end of the document, below the cards.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if let id = document.selectedSectionID {
                    scrollProxy.focus(sectionID: id, in: editor.compositeContent.attributedString)
                }
            }
        }
        .onChange(of: undoManager) { newValue in
            editor.undoManager = newValue
        }
        .onChange(of: document.selectedSectionID) { newID in
            guard let newID else { return }
            // The caret is already there; don't move it back.
            if scrollProxy.isSyncingFromCaret {
                scrollProxy.isSyncingFromCaret = false
                return
            }
            let wantsTitleEdit = document.pendingTitleEditID == newID
            document.pendingTitleEditID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let composite = editor.compositeContent.attributedString
                if wantsTitleEdit {
                    scrollProxy.selectHeading(sectionID: newID, in: composite)
                } else {
                    scrollProxy.focus(sectionID: newID, in: composite)
                }
            }
        }
    }
}
#endif
