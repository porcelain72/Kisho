//
//  KishoCardListEditorView.swift
//  Kisho
//
//  The "stacked cards" editor: every block in the document is shown as its
//  own card — a title field plus a self-sizing text view bound directly to
//  that block's content — laid out top to bottom with nesting as indentation.
//  There is no combined text, no tagging and no parsing: the block is the
//  unit in the model, the sidebar and the editor alike.
//

import SwiftUI
import RichTextEditor

#if os(macOS)
import AppKit

// MARK: - Editor

struct KishoCardListEditorView: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(document.sections) { section in
                            SectionCardTree(section: section, depth: 0)
                        }
                        // Room to scroll the last card up into comfortable view.
                        Color.clear.frame(height: 160)
                    }
                    .padding(20)
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 25.0))
                .onChange(of: document.focusRequest) { request in
                    guard let request else { return }
                    // A block created by this same edit is not laid out yet;
                    // scroll once the card exists, and again once it has its
                    // measured height.
                    for delay in [0.05, 0.25] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            guard document.focusRequest == request else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(request.sectionID, anchor: .center)
                            }
                        }
                    }
                }
                .onAppear {
                    // Otherwise AppKit hands initial key focus to the first title field.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        document.requestFocus(document.selectedSectionID ?? document.sections.first?.id, .body)
                    }
                }
            }

            if let selected = document.selectedSection {
                SectionTagsBar(section: selected)
                    .id(selected.id)
            }
        }
        .padding()
    }
}

/// A block's card followed by its children, indented one step further.
private struct SectionCardTree: View {
    @ObservedObject var section: KishoSection
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCard(section: section, depth: depth)
                .id(section.id)
            ForEach(section.children) { child in
                SectionCardTree(section: child, depth: depth + 1)
            }
        }
    }
}

// MARK: - Card

private struct SectionCard: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager
    @ObservedObject var section: KishoSection
    let depth: Int

    @State private var draftTitle: String
    @FocusState private var isTitleFocused: Bool
    @StateObject private var bodyHandle = CardTextViewHandle()

    init(section: KishoSection, depth: Int) {
        self.section = section
        self.depth = depth
        // Seed from the model so the field never starts out empty (an empty
        // field that has keyboard focus at launch would write "" back).
        self._draftTitle = State(initialValue: section.title)
    }

    private var isSelected: Bool { document.selectedSectionID == section.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Heading
            HStack(spacing: 8) {
                TextField("Untitled", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: headingSize, weight: .bold))
                    .focused($isTitleFocused)
                    .onSubmit { commitTitle(); bodyHandle.focus(atEnd: true) }
                    .onExitCommand { draftTitle = section.title; isTitleFocused = false }
                Spacer(minLength: 0)
                if section.totalWordCount > 0 {
                    Text("\(section.totalWordCount)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(CardPalette.headingFill(depth: depth))

            // Body
            CardTextView(
                content: section.content,
                handle: bodyHandle,
                typography: document.typography,
                onBeginEditing: { selectFromEditor() },
                onChange: { old, new in
                    document.recordBodyEdit(for: section, from: old, to: new, using: undoManager)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: bodyHandle.height)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(CardPalette.bodyFill(depth: depth))
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(CardPalette.accent(depth: depth))
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? CardPalette.accent(depth: depth) : Color.clear, lineWidth: 1.5)
        )
        .frame(maxWidth: .infinity)
        .padding(.leading, CGFloat(min(depth, 6)) * 24)
        .onChange(of: section.title) { newValue in
            if !isTitleFocused { draftTitle = newValue }
        }
        .onChange(of: isTitleFocused) { focused in
            if focused { selectFromEditor() } else { commitTitle() }
        }
        .onReceive(document.$focusRequest) { request in
            guard let request, request.sectionID == section.id else { return }
            // Let the scroll/layout pass land first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                switch request.field {
                case .title:
                    isTitleFocused = true
                case .body:
                    bodyHandle.focus(atEnd: true)
                }
            }
        }
    }

    private var headingSize: CGFloat {
        switch depth {
        case 0: return 20
        case 1: return 18
        case 2: return 16
        default: return 14
        }
    }

    private func commitTitle() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            document.setTitle(trimmed, for: section, using: undoManager)
        }
        // A blank field keeps the existing title.
        draftTitle = section.title
    }

    /// The user clicked or tabbed into this card: make it the selected block
    /// without scrolling or moving their caret.
    private func selectFromEditor() {
        if document.selectedSectionID != section.id {
            document.selectedSectionID = section.id
        }
    }
}

// MARK: - Tags bar

private struct SectionTagsBar: View {
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

// MARK: - Palette

private enum CardPalette {
    private static func hue(_ depth: Int) -> Double {
        (0.55 + Double(depth) * 0.08).truncatingRemainder(dividingBy: 1.0)
    }

    static func accent(depth: Int) -> Color {
        Color(hue: hue(depth), saturation: 0.50, brightness: 0.62)
    }

    static func headingFill(depth: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedHue: hue(depth), saturation: 0.28, brightness: dark ? 0.34 : 0.86, alpha: 0.88)
        })
    }

    static func bodyFill(depth: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedHue: hue(depth), saturation: 0.10, brightness: dark ? 0.22 : 0.96, alpha: 0.62)
        })
    }
}

// MARK: - Self-sizing text view

/// Lets the card reach its NSTextView (to focus it) without the view layer
/// holding AppKit objects directly.
final class CardTextViewHandle: ObservableObject {
    weak var textView: NSTextView?
    /// Height the body needs for its text, measured by the text view itself.
    @Published var height: CGFloat = 24

    func report(height newHeight: CGFloat) {
        let rounded = ceil(newHeight)
        guard abs(rounded - height) > 0.5 else { return }
        // Published from within AppKit layout; defer so SwiftUI isn't mutated mid-update.
        DispatchQueue.main.async { [weak self] in
            guard let self, abs(rounded - self.height) > 0.5 else { return }
            self.height = rounded
        }
    }

    func focus(atEnd: Bool) {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
        if atEnd {
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}

/// One block's body. Sizes itself to its text (no internal scrolling), writes
/// every change straight into the block's `RichTextModel`, and reports when
/// it becomes first responder so the sidebar selection can follow the caret.
private struct CardTextView: NSViewRepresentable {
    @ObservedObject var content: RichTextModel
    let handle: CardTextViewHandle
    let typography: TypographySettings
    let onBeginEditing: () -> Void
    /// Called with the text before and after a user edit.
    let onChange: (NSAttributedString, NSAttributedString) -> Void

    private static let insets = NSSize(width: 4, height: 4)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CardNSTextView {
        let textView = CardNSTextView()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        // Undo is model-level (see Coordinator); NSTextView's own range-based
        // undo would fall out of step whenever the model replaces the text.
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textContainerInset = Self.insets
        // SwiftUI owns the frame: width from the card, height from our own
        // measurement (see CardNSTextView.measure). The container wraps at the
        // frame width and is unbounded vertically.
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 4
        textView.onHeightChange = { [weak handle] height in
            handle?.report(height: height)
        }
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.delegate = context.coordinator
        textView.onBecomeFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onBeginEditing()
        }
        textView.textStorage?.setAttributedString(content.attributedString)
        applyDisplayColour(textView)
        textView.typingAttributes = typingAttributes()
        context.coordinator.textView = textView
        handle.textView = textView
        textView.measure()
        return textView
    }

    func updateNSView(_ textView: CardNSTextView, context: Context) {
        context.coordinator.parent = self
        handle.textView = textView
        let stored = content.attributedString
        if !context.coordinator.isPushingToModel, !stored.isEqual(to: textView.attributedString()) {
            let selection = textView.selectedRange()
            context.coordinator.isApplyingModel = true
            textView.textStorage?.setAttributedString(stored)
            applyDisplayColour(textView)
            context.coordinator.isApplyingModel = false
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        if textView.string.isEmpty {
            textView.typingAttributes = typingAttributes()
        }
        textView.measure()
    }

    /// Stored text may carry a baked-in colour from RTF; show it in the
    /// appearance-adaptive label colour.
    private func applyDisplayColour(_ textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    private func typingAttributes() -> [NSAttributedString.Key: Any] {
        var descriptor = NSFontDescriptor(fontAttributes: [.family: typography.fontFamily])
        var traits = NSFontDescriptor.SymbolicTraits()
        if typography.isBold { traits.insert(.bold) }
        if typography.isItalic { traits.insert(.italic) }
        descriptor = descriptor.withSymbolicTraits(traits)
        let font = NSFont(descriptor: descriptor, size: CGFloat(typography.fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(typography.fontSize))
        return [.font: font, .foregroundColor: NSColor.labelColor]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CardTextView
        weak var textView: NSTextView?
        var isApplyingModel = false
        var isPushingToModel = false

        init(_ parent: CardTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingModel, let textView else { return }
            let before = parent.content.attributedString
            let after = textView.attributedString()
            isPushingToModel = true
            parent.content.attributedString = after
            isPushingToModel = false
            parent.onChange(before, after)
        }
    }
}

/// NSTextView that reports when it becomes first responder and how tall its
/// text is (after every edit and every width change).
final class CardNSTextView: NSTextView {
    var onBecomeFirstResponder: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    private static let minimumTextHeight: CGFloat = 18

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onBecomeFirstResponder?() }
        return ok
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { measure() }
    }

    override func didChangeText() {
        super.didChangeText()
        measure()
    }

    /// Lays out at the current width and reports the height the text needs.
    func measure() {
        guard let layoutManager, let textContainer, bounds.width > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let height = max(used.height, Self.minimumTextHeight) + textContainerInset.height * 2
        onHeightChange?(height)
    }

    // SwiftUI sizes us; never report an intrinsic size that could fight it.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
#endif
