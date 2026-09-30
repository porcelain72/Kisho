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
    @EnvironmentObject var find: FindState
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if find.isVisible {
                FindBar(find: find)
            }
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
                .background(Theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline, lineWidth: 1))
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
    @EnvironmentObject var find: FindState
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

    private var bodyHighlight: BodyHighlight {
        let hits = find.bodyHighlights(for: section.id)
        return BodyHighlight(ranges: hits.all, current: hits.current)
    }

    private var titleFont: Font { .system(size: headingSize, weight: .semibold) }

    /// Search hits in the title, drawn as a wash behind the field's text.
    /// Only while the field shows the model's title (not a draft being typed).
    @ViewBuilder private var titleHighlightBackdrop: some View {
        if let highlighted = highlightedTitle {
            Text(highlighted)
                .lineLimit(1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The title with search hits as background runs and clear glyphs, or nil
    /// when there is nothing to draw.
    private var highlightedTitle: AttributedString? {
        let hits = find.titleHighlights(for: section.id)
        guard !hits.all.isEmpty, !isTitleFocused, draftTitle == section.title else { return nil }
        let ns = NSMutableAttributedString(
            string: section.title,
            attributes: [.font: NSFont.systemFont(ofSize: headingSize, weight: .semibold),
                         .foregroundColor: NSColor.clear])
        let length = ns.length
        for range in hits.all where NSMaxRange(range) <= length {
            let color = range == hits.current
                ? NSColor.findHighlightColor
                : NSColor.findHighlightColor.withAlphaComponent(0.35)
            ns.addAttribute(.backgroundColor, value: color, range: range)
        }
        return AttributedString(ns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Heading
            HStack(spacing: 8) {
                TextField("Untitled", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .background(alignment: .leading) { titleHighlightBackdrop }
                    .focused($isTitleFocused)
                    .onSubmit { commitTitle(); bodyHandle.focus(atEnd: true) }
                    .onExitCommand { draftTitle = section.title; isTitleFocused = false }
                Spacer(minLength: 0)
                if section.totalWordCount > 0 {
                    Text("\(section.totalWordCount)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Hairline between heading and body
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 12)

            // Body
            CardTextView(
                content: section.content,
                handle: bodyHandle,
                typography: document.typography,
                highlight: bodyHighlight,
                onBeginEditing: { selectFromEditor() },
                onChange: { old, new, location in
                    document.recordBodyEdit(for: section, from: old, to: new, editLocation: location, using: undoManager)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: bodyHandle.height)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(isSelected ? Color.accentColor : Theme.hairline,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .frame(maxWidth: .infinity)
        .padding(.leading, CGFloat(min(depth, 6)) * 24)
        .onChange(of: section.title) { newValue in
            // Undo/redo may change the title while the field has focus; the
            // field must follow the model, not keep a stale draft.
            draftTitle = newValue
        }
        .onChange(of: isTitleFocused) { focused in
            if focused { selectFromEditor() } else { commitTitle() }
        }
        .onReceive(document.$focusRequest) { request in
            guard let request, request.sectionID == section.id else { return }
            // Let the scroll/layout pass land first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard request.takesFocus else {
                    // Find bar stepping: mark the place, keep focus in the bar.
                    if request.field == .body, let selection = request.selection {
                        bodyHandle.show(selection)
                    }
                    return
                }
                switch request.field {
                case .title:
                    isTitleFocused = true
                case .body:
                    if let selection = request.selection {
                        bodyHandle.focus(selecting: selection)
                    } else if let caret = request.caret {
                        bodyHandle.focus(at: caret)
                    } else {
                        bodyHandle.focus(atEnd: true)
                    }
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
        // Only a click or key press counts: AppKit also hands out first-responder
        // status on its own (e.g. to the first field at launch), and that must
        // not override the selection restored from the file.
        guard let event = NSApp.currentEvent,
              [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown].contains(event.type) else { return }
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

// MARK: - Theme

/// Outline-based look built on system semantic colours, so light and dark
/// mode need no special handling. Nesting is shown by indentation and
/// heading size alone.
enum Theme {
    static let cornerRadius: CGFloat = 8

    /// Hairline for outlines and dividers.
    static var hairline: Color { Color(nsColor: .separatorColor) }

    /// Card face: the text background, so cards sit flush with the editor.
    static var cardBackground: Color { Color(nsColor: .textBackgroundColor) }

    /// Editor canvas behind the cards: a step away from the card face so the
    /// outlines have something to sit against in both appearances.
    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
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

    func focus(at caret: Int) {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: max(0, min(caret, length)), length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func focus(selecting range: NSRange) {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
        let clamped = Self.clamp(range, in: textView)
        textView.setSelectedRange(clamped)
        textView.scrollRangeToVisible(clamped)
    }

    /// Bring a range into view without taking keyboard focus or changing the
    /// selection (the find highlight marks it; an inactive selection drawn on
    /// top would only muddy that).
    func show(_ range: NSRange) {
        guard let textView else { return }
        textView.scrollRangeToVisible(Self.clamp(range, in: textView))
    }

    private static func clamp(_ range: NSRange, in textView: NSTextView) -> NSRange {
        let length = (textView.string as NSString).length
        let location = max(0, min(range.location, length))
        return NSRange(location: location, length: max(0, min(range.length, length - location)))
    }
}

/// Which ranges of a block's body to mark as search hits.
struct BodyHighlight: Equatable {
    var ranges: [NSRange]
    var current: NSRange?
    static let none = BodyHighlight(ranges: [], current: nil)
}

/// One block's body. Sizes itself to its text (no internal scrolling), writes
/// every change straight into the block's `RichTextModel`, and reports when
/// it becomes first responder so the sidebar selection can follow the caret.
private struct CardTextView: NSViewRepresentable {
    @ObservedObject var content: RichTextModel
    let handle: CardTextViewHandle
    let typography: TypographySettings
    let highlight: BodyHighlight
    let onBeginEditing: () -> Void
    /// Called with the text before and after a user edit, and the character
    /// index where the edit happened.
    let onChange: (NSAttributedString, NSAttributedString, Int) -> Void

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
        // Underline misspellings, but no autocorrect/inline suggestion bubbles.
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.delegate = context.coordinator
        textView.contentModel = content
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
            context.coordinator.appliedHighlight = nil   // storage reset drops temporary attributes
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        if textView.string.isEmpty || context.coordinator.appliedTypography != typography {
            // Keep bold/italic the user has toggled for the caret, but adopt the
            // new family/size.
            var attrs = typingAttributes()
            if let current = textView.typingAttributes[.font] as? NSFont,
               let base = attrs[.font] as? NSFont {
                attrs[.font] = SelectionFormatting.font(base, matchingTraitsOf: current)
            }
            textView.typingAttributes = attrs
            context.coordinator.appliedTypography = typography
        }
        textView.measure()
        applyHighlight(textView, context: context)
    }

    /// Search hits as temporary layout attributes: visible, but never part of
    /// the document text.
    private func applyHighlight(_ textView: NSTextView, context: Context) {
        guard context.coordinator.appliedHighlight != highlight,
              let layoutManager = textView.layoutManager else { return }
        context.coordinator.appliedHighlight = highlight
        let length = (textView.string as NSString).length
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        for range in highlight.ranges where NSMaxRange(range) <= length {
            let isCurrent = range == highlight.current
            let color = isCurrent
                ? NSColor.findHighlightColor
                : NSColor.findHighlightColor.withAlphaComponent(0.35)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
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
        [.font: typography.baseFont, .foregroundColor: NSColor.labelColor]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CardTextView
        weak var textView: NSTextView?
        var isApplyingModel = false
        var isPushingToModel = false
        var appliedTypography: TypographySettings?
        var appliedHighlight: BodyHighlight?

        init(_ parent: CardTextView) { self.parent = parent }

        /// Start of the range about to change; NSTextView reports it before
        /// the edit, so it is the edit site for undo caret placement.
        private var pendingEditLocation = 0

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            pendingEditLocation = affectedCharRange.location
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingModel, let textView else { return }
            let before = parent.content.attributedString
            // attributedString() is the live NSTextStorage, not a copy. The model
            // must own an immutable snapshot, otherwise "before" and "after" are
            // the same mutating object: undo snapshots capture text one keystroke
            // late, the paragraph-break check never fires, and the identity-keyed
            // word-count cache never invalidates.
            let after = NSAttributedString(attributedString: textView.attributedString())
            isPushingToModel = true
            parent.content.attributedString = after
            isPushingToModel = false
            parent.onChange(before, after, pendingEditLocation)
        }
    }
}

/// NSTextView that reports when it becomes first responder and how tall its
/// text is (after every edit and every width change).
final class CardNSTextView: NSTextView {
    var onBecomeFirstResponder: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    /// The block body this view edits, so find actions can be routed to the
    /// right document when several windows are open.
    weak var contentModel: RichTextModel?

    private static let minimumTextHeight: CGFloat = 18

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onBecomeFirstResponder?() }
        return ok
    }

    /// The standard Edit ▸ Find items (⌘F, ⌘G, ⇧⌘G, ⌘E) send this to the first
    /// responder. Route them to Kisho's document-wide find bar instead of
    /// NSTextView's per-view find panel.
    /// NSTextView disables the Find items unless it uses its own find bar;
    /// Kisho handles them itself, so keep them enabled.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performFindPanelAction(_:)) { return true }
        return super.validateUserInterfaceItem(item)
    }

    override func performFindPanelAction(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag ?? 1
        var info: [String: Any] = ["tag": tag]
        if let contentModel { info["content"] = contentModel }
        if tag == Int(NSFindPanelAction.setFindString.rawValue) {
            let range = selectedRange()
            if range.length > 0 { info["string"] = (string as NSString).substring(with: range) }
        }
        NotificationCenter.default.post(name: .kishoFindPanelAction, object: self, userInfo: info)
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

// MARK: - Selection formatting

/// Bold/italic applied to the selected text of whichever block body has the
/// keyboard focus (or to the typing attributes when nothing is selected).
enum SelectionFormatting {
    enum Trait { case bold, italic

        var mask: NSFontTraitMask { self == .bold ? .boldFontMask : .italicFontMask }
    }

    /// The card body that currently has keyboard focus, if any.
    static var focusedTextView: CardNSTextView? {
        NSApp.keyWindow?.firstResponder as? CardNSTextView
    }

    static func toggle(_ trait: Trait) {
        guard let textView = focusedTextView, textView.isEditable else { return }
        let fm = NSFontManager.shared
        let range = textView.selectedRange()

        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            attrs[.font] = fm.traits(of: font).contains(trait.mask)
                ? fm.convert(font, toNotHaveTrait: trait.mask)
                : fm.convert(font, toHaveTrait: trait.mask)
            textView.typingAttributes = attrs
            return
        }

        guard let storage = textView.textStorage,
              textView.shouldChangeText(in: range, replacementString: nil) else { return }

        // If every run already has the trait, remove it; otherwise add it.
        var allHave = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            if !fm.traits(of: font).contains(trait.mask) { allHave = false }
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, runRange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let newFont = allHave
                ? fm.convert(font, toNotHaveTrait: trait.mask)
                : fm.convert(font, toHaveTrait: trait.mask)
            storage.addAttribute(.font, value: newFont, range: runRange)
        }
        storage.endEditing()
        // Runs the same path as typing: measures, pushes to the model, records undo.
        textView.didChangeText()
        textView.setSelectedRange(range)
    }

    /// Whether the selection (or caret) currently carries the trait — for the
    /// toolbar highlight.
    static func selectionHas(_ trait: Trait) -> Bool {
        guard let textView = focusedTextView else { return false }
        let fm = NSFontManager.shared
        let range = textView.selectedRange()
        let font: NSFont?
        if range.length == 0 || textView.textStorage == nil {
            font = textView.typingAttributes[.font] as? NSFont
        } else {
            font = textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        }
        guard let font else { return false }
        return fm.traits(of: font).contains(trait.mask)
    }

    /// `base` (family/size) carrying the bold/italic traits of `other`.
    static func font(_ base: NSFont, matchingTraitsOf other: NSFont) -> NSFont {
        let fm = NSFontManager.shared
        var font = base
        let traits = fm.traits(of: other)
        if traits.contains(.boldFontMask) { font = fm.convert(font, toHaveTrait: .boldFontMask) }
        if traits.contains(.italicFontMask) { font = fm.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }
}
#endif

extension Notification.Name {
    /// Posted by card text views when a standard Find menu item reaches them.
    /// userInfo: "tag" (NSFindPanelAction raw value), optional "string".
    static let kishoFindPanelAction = Notification.Name("KishoFindPanelAction")
}
