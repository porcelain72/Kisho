//
//  KishoDocumentEditorView.swift
//  Kisho
//

import SwiftUI
import RichTextEditor

#if os(macOS)
import AppKit

/// Locates the composite editor's NSTextView within its window and scrolls a
/// section's heading to the top when requested.
final class EditorScrollProxy: ObservableObject {
    weak var anchorView: NSView?

    func currentAttributedString() -> NSAttributedString? {
        locateTextView()?.attributedString()
    }

    func focus(sectionID id: UUID, in composite: NSAttributedString) {
        guard let textView = locateTextView() else { return }

        // Place the caret at the end of the selected section's own content.
        if let caret = KishoSection.compositeCaretIndex(forSectionID: id, in: composite) {
            let clamped = min(max(0, caret), textView.string.utf16.count)
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }

        // Keep the section's heading in view (after the caret move so it wins).
        scroll(toSectionID: id, in: composite, textView: textView)
    }

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
        return Self.firstTextView(in: root)
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
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
                TagEditorView(
                    tags: Binding(
                        get: { selected.tags },
                        set: { selected.tags = $0 }
                    ),
                    allAvailableTags: document.allTags
                )
            }
        }
        .padding()
        .onAppear {
            editor.undoManager = undoManager
            document.beforeStructureEdit = { [weak editor, weak scrollProxy] in
                editor?.flushLiveEdits(from: scrollProxy?.currentAttributedString())
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isRichTextFocused = true
            }
        }
        .onChange(of: document.selectedSectionID) { newID in
            guard let newID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scrollProxy.focus(sectionID: newID, in: editor.compositeContent.attributedString)
            }
        }
    }
}
#endif
