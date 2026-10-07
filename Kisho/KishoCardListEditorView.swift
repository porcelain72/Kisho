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
    @Environment(\.kishoFocusMode) private var focusMode
    @Environment(\.kishoEditorTheme) private var editorTheme
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if find.isVisible {
                FindBar(find: find)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if document.sections.isEmpty {
                        EmptyDocumentPrompt()
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(document.sections) { section in
                                SectionCardTree(section: section, depth: 0)
                            }
                            // Room to scroll the last card up into comfortable view —
                            // half a screen in focus mode so the typewriter line can
                            // stay centred to the end of the text.
                            Color.clear.frame(height: focusMode ? 420 : 160)
                        }
                        .padding(20)
                        // Focus mode: a reading measure, centred.
                        .frame(maxWidth: focusMode ? 760 : .infinity)
                        .frame(maxWidth: .infinity)
                    }
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
                .onChange(of: focusMode) { _ in
                    // The column width and sidebar change under the scroll view;
                    // bring the block being worked on back into the middle.
                    guard let id = document.selectedSectionID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .onAppear {
                    // Otherwise AppKit hands initial key focus to the first title field.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        document.requestFocus(document.selectedSectionID ?? document.sections.first?.id, .body)
                    }
                }
            }

        }
        // Also set here so the editor matches the theme even where the window-level appearance can't reach it.
        .environment(\.colorScheme, editorTheme.colorScheme ?? systemColorScheme)
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

// MARK: - Empty document

/// What a document with no blocks shows instead of a blank canvas.
private struct EmptyDocumentPrompt: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("No blocks yet")
                .font(.title2.weight(.semibold))
            Text("A Kisho document is a stack of named blocks. Add one and start writing; split it into more as the shape emerges.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Button {
                document.addSiblingSection(using: undoManager)
            } label: {
                Label("Add a Block", systemImage: "plus")
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            Text("⌘=  ·  Help ▸ How Kisho Works")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(60)
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

// MARK: - Card

private struct SectionCard: View {
    @EnvironmentObject var document: KishoDocumentModel
    @EnvironmentObject var find: FindState
    @Environment(\.undoManager) private var undoManager
    @Environment(\.kishoFocusMode) private var focusMode
    @Environment(\.kishoEditorTheme) private var editorTheme
    @ThemeAccent private var accent
    @ObservedObject var section: KishoSection
    let depth: Int

    @State private var draftTitle: String
    /// Mirrors the AppKit title field's first-responder state.
    @State private var isTitleFocused = false
    @StateObject private var titleHandle = TitleFieldHandle()
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
            attributes: [.font: PlatformFont.kishoHeading(family: document.typography.fontFamily, size: headingSize),
                         .foregroundColor: NSColor.clear])
        let length = ns.length
        // Translucent even for the current match: an opaque wash under the
        // heading's semibold text makes it hard to read.
        for range in hits.all where NSMaxRange(range) <= length {
            let color = NSColor.findHighlightColor.withAlphaComponent(range == hits.current ? 0.55 : 0.25)
            ns.addAttribute(.backgroundColor, value: color, range: range)
        }
        return AttributedString(ns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Heading
            HStack(spacing: 8) {
                TitleField(
                    text: $draftTitle,
                    placeholder: "Untitled",
                    fontFamily: document.typography.fontFamily,
                    fontSize: headingSize,
                    handle: titleHandle,
                    onFocusChange: { isTitleFocused = $0 },
                    onSubmit: { commitTitle(); bodyHandle.focus(atEnd: true) },
                    onEscape: { draftTitle = section.title; bodyHandle.focus(atEnd: false) },
                    // Outliner habit: Tab nests the block under the one above, ⇧Tab moves it out.
                    onTab: { commitTitle(); document.indentSection(withID: section.id, focusing: .title, using: undoManager) },
                    onBacktab: { commitTitle(); document.outdentSection(withID: section.id, focusing: .title, using: undoManager) },
                    onCommandReturn: { commitTitle(); document.addSiblingSection(using: undoManager) }
                )
                .background(alignment: .leading) { titleHighlightBackdrop }
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
                theme: editorTheme,
                highlight: bodyHighlight,
                onBeginEditing: { selectFromEditor() },
                onChange: { old, new, location in
                    document.recordBodyEdit(for: section, from: old, to: new, editLocation: location, using: undoManager)
                },
                onCommandReturn: { document.addSiblingSection(using: undoManager) }
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
                .strokeBorder(isSelected ? accent : Theme.hairline,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .frame(maxWidth: .infinity)
        .padding(.leading, CGFloat(min(depth, 6)) * 24)
        // Focus mode: everything but the block you're in recedes.
        .opacity(focusMode && !isSelected ? 0.32 : 1)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
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
                    titleHandle.focus()
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

// MARK: - Title field

/// Lets the card focus its title field from a focus request.
final class TitleFieldHandle: ObservableObject {
    weak var field: NSTextField?
    func focus() {
        guard let field, let window = field.window else { return }
        window.makeFirstResponder(field)
    }
}

/// The block title. An AppKit field rather than SwiftUI's `TextField` so Tab
/// and ⇧Tab can indent/outdent the block instead of moving focus, Escape can
/// revert, and ⌘↩ can add a block — the deployment target predates
/// `onKeyPress`.
private struct TitleField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontFamily: String
    let fontSize: CGFloat
    let handle: TitleFieldHandle
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    let onCommandReturn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TitleNSTextField {
        let field = TitleNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isBezeled = false
        field.textColor = .labelColor
        field.font = PlatformFont.kishoHeading(family: fontFamily, size: fontSize)
        context.coordinator.appliedFamily = fontFamily
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.stringValue = text
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.onBecomeFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onFocusChange(true)
        }
        field.onCommandReturn = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCommandReturn()
        }
        handle.field = field
        return field
    }

    func updateNSView(_ field: TitleNSTextField, context: Context) {
        context.coordinator.parent = self
        handle.field = field
        if field.stringValue != text { field.stringValue = text }
        if field.font?.pointSize != fontSize || context.coordinator.appliedFamily != fontFamily {
            field.font = PlatformFont.kishoHeading(family: fontFamily, size: fontSize)
            context.coordinator.appliedFamily = fontFamily
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TitleField
        var appliedFamily: String?
        init(_ parent: TitleField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):   parent.onSubmit();   return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onEscape();   return true
            case #selector(NSResponder.insertTab(_:)):       parent.onTab();      return true
            case #selector(NSResponder.insertBacktab(_:)):   parent.onBacktab();  return true
            default: return false
            }
        }
    }
}

final class TitleNSTextField: NSTextField {
    var onBecomeFirstResponder: (() -> Void)?
    var onCommandReturn: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onBecomeFirstResponder?() }
        return ok
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isCommandReturn, let onCommandReturn, currentEditor() != nil {
            onCommandReturn()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension NSEvent {
    /// Return (or keypad Enter) with only the Command key held.
    var isCommandReturn: Bool {
        guard type == .keyDown, keyCode == 36 || keyCode == 76 else { return false }
        return modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
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
        guard let textView else { return }
        takeFocus(textView)
        if atEnd {
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func focus(at caret: Int) {
        guard let textView else { return }
        takeFocus(textView)
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: max(0, min(caret, length)), length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func focus(selecting range: NSRange) {
        guard let textView else { return }
        takeFocus(textView)
        let clamped = Self.clamp(range, in: textView)
        textView.setSelectedRange(clamped)
        textView.scrollRangeToVisible(clamped)
    }

    /// Make the text view first responder, and make sure it stays so: a
    /// SwiftUI field being torn down in the same moment (the find bar
    /// closing) can resign focus for the window just after we took it.
    private func takeFocus(_ textView: NSTextView) {
        guard let window = textView.window else { return }
        window.makeFirstResponder(textView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak textView] in
            guard let textView, let window = textView.window,
                  window.firstResponder !== textView else { return }
            window.makeFirstResponder(textView)
        }
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
    let theme: EditorTheme
    let highlight: BodyHighlight
    let onBeginEditing: () -> Void
    /// Called with the text before and after a user edit, and the character
    /// index where the edit happened.
    let onChange: (NSAttributedString, NSAttributedString, Int) -> Void
    /// ⌘↩ in the body: add a block after this one.
    let onCommandReturn: () -> Void

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
        textView.onCommandReturn = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCommandReturn()
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
        if context.coordinator.appliedTheme != theme {
            context.coordinator.appliedTheme = theme
            textView.appearance = theme.appearance
            textView.backgroundColor = Theme.cardBackgroundPlatformColor
            applyDisplayColour(textView)
        }
    }

    /// Search hits as temporary layout attributes: visible, but never part of
    /// the document text.
    private func applyHighlight(_ textView: NSTextView, context: Context) {
        guard context.coordinator.appliedHighlight != highlight,
              let layoutManager = textView.layoutManager else { return }
        context.coordinator.appliedHighlight = highlight
        let length = (textView.string as NSString).length
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        // Translucent so the text stays legible in both appearances.
        for range in highlight.ranges where NSMaxRange(range) <= length {
            let color = NSColor.findHighlightColor.withAlphaComponent(range == highlight.current ? 0.55 : 0.25)
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
        var appliedTheme: EditorTheme?

        init(_ parent: CardTextView) { self.parent = parent }

        /// Start of the range about to change; NSTextView reports it before
        /// the edit, so it is the edit site for undo caret placement.
        private var pendingEditLocation = 0

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            pendingEditLocation = affectedCharRange.location
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingModel, let textView else { return }
            TypewriterScrolling.recentre(textView)
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
    var onCommandReturn: (() -> Void)?

    /// ⌘↩ adds a block; nothing else about the event is ours. The window
    /// offers key equivalents to every view, so only the focused body acts.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isCommandReturn, let onCommandReturn, window?.firstResponder === self {
            onCommandReturn()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
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

// MARK: - Selection formatting (AppKit side)

/// The focused card body and the toggles that act on it; the attribute
/// logic itself is in KishoSelectionFormatting.swift.
extension SelectionFormatting {
    /// The card body that currently has keyboard focus, if any.
    static var focusedTextView: CardNSTextView? {
        NSApp.keyWindow?.firstResponder as? CardNSTextView
    }

    static func toggle(_ trait: Trait) {
        guard let textView = focusedTextView, textView.isEditable else { return }
        let range = textView.selectedRange()

        if range.length == 0 {
            let attrs = textView.typingAttributes
            textView.typingAttributes = attributes(attrs, setting: trait, to: !attributes(attrs, have: trait))
            return
        }

        guard let storage = textView.textStorage,
              textView.shouldChangeText(in: range, replacementString: nil) else { return }
        toggle(trait, in: storage, range: range)
        // Runs the same path as typing: measures, pushes to the model, records undo.
        textView.didChangeText()
        textView.setSelectedRange(range)
    }

    /// Whether the selection (or caret) currently carries the trait — for the
    /// toolbar highlight.
    static func selectionHas(_ trait: Trait) -> Bool {
        guard let textView = focusedTextView else { return false }
        let range = textView.selectedRange()
        if range.length == 0 || textView.textStorage == nil {
            return attributes(textView.typingAttributes, have: trait)
        }
        let attrs = textView.textStorage?.attributes(at: range.location, effectiveRange: nil) ?? [:]
        return attributes(attrs, have: trait)
    }
}
#endif

extension Notification.Name {
    /// Posted by card text views when a standard Find menu item reaches them.
    /// userInfo: "tag" (NSFindPanelAction raw value), optional "string".
    static let kishoFindPanelAction = Notification.Name("KishoFindPanelAction")
}
