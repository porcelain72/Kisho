//
//  KishoCardListEditorView+iOS.swift
//  Kisho
//
//  The stacked-cards editor on iOS: every block is a card — a title field
//  and a self-sizing UITextView bound to the block's content — laid out top
//  to bottom with nesting as indentation. The model is the same as on the
//  Mac and owns undo; the text views push each edit into it and report
//  where it happened. Structure commands (add, indent, outdent, bold…)
//  come from the keyboard accessory bar and hardware key commands.
//

#if os(iOS)
import SwiftUI
import UIKit
import RichTextEditor

// MARK: - Editor

struct KishoCardListEditorView: View {
    @EnvironmentObject var document: KishoDocumentModel
    @EnvironmentObject var find: FindState
    @Environment(\.undoManager) private var undoManager
    @Environment(\.kishoFocusMode) private var focusMode
    @Environment(\.kishoEditorTheme) private var editorTheme
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(KishoPreferences.Key.typewriterScrolling) private var typewriter = false

    var body: some View {
        VStack(spacing: 0) {
            if find.isVisible {
                FindBar(find: find)
                Divider()
            }
            cards
        }
        // Also set here so the editor matches the theme even where the window-level appearance can't reach it.
        .environment(\.colorScheme, editorTheme.colorScheme ?? systemColorScheme)
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if document.sections.isEmpty {
                    EmptyDocumentPrompt()
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(document.sections) { section in
                            SectionCardTree(section: section, depth: 0)
                        }
                        // Room to scroll the last card up above the keyboard —
                        // half a screen more in focus mode so the typewriter
                        // line can stay centred to the end of the text.
                        Color.clear.frame(height: focusMode || typewriter ? 480 : 240)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .onChange(of: document.focusRequest) { request in
                guard let request else { return }
                // A block created by this same edit is not laid out yet; scroll
                // once the card exists, and again once it has its height.
                for delay in [0.05, 0.3] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard document.focusRequest == request else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(request.sectionID, anchor: .center)
                        }
                    }
                }
            }
            .onAppear {
                // Show the selected block without raising the keyboard.
                if let id = document.selectedSectionID {
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
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
    @State private var isTitleFocused = false
    @StateObject private var titleHandle = TitleFieldHandle()
    @StateObject private var bodyHandle = CardTextViewHandle()

    init(section: KishoSection, depth: Int) {
        self.section = section
        self.depth = depth
        self._draftTitle = State(initialValue: section.title)
    }

    private var isSelected: Bool { document.selectedSectionID == section.id }

    private var bodyHighlight: BodyHighlight {
        let hits = find.bodyHighlights(for: section.id)
        return BodyHighlight(ranges: hits.all, current: hits.current)
    }

    /// Everything the accessory bar and key commands can do to this block.
    private var actions: CardActions {
        // Add acts on the selected block, so make sure that is this card
        // (it normally is, since the keyboard is here, but the bar belongs
        // to this card and must never add next to some other block).
        CardActions(
            addSibling: { commitTitle(); document.selectedSectionID = section.id; document.addSiblingSection(using: undoManager) },
            addChild: { commitTitle(); document.selectedSectionID = section.id; document.addChildSection(using: undoManager) },
            indent: { commitTitle(); document.indentSection(withID: section.id, focusing: .body, using: undoManager) },
            outdent: { commitTitle(); document.outdentSection(withID: section.id, focusing: .body, using: undoManager) },
            moveUp: { commitTitle(); document.moveSectionUp(withID: section.id, focusing: .body, using: undoManager) },
            moveDown: { commitTitle(); document.moveSectionDown(withID: section.id, focusing: .body, using: undoManager) },
            canIndent: { document.canIndent(sectionID: section.id) },
            canOutdent: { document.canOutdent(sectionID: section.id) },
            canMoveUp: { document.canMoveUp(sectionID: section.id) },
            canMoveDown: { document.canMoveDown(sectionID: section.id) },
            find: { commitTitle(); find.show() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TitleField(
                    text: $draftTitle,
                    placeholder: "Untitled",
                    fontFamily: document.typography.fontFamily,
                    fontSize: headingSize,
                    handle: titleHandle,
                    actions: actions,
                    onFocusChange: { isTitleFocused = $0 },
                    onSubmit: { commitTitle(); bodyHandle.focus(atEnd: true) },
                    onEscape: { draftTitle = section.title; bodyHandle.focus(atEnd: false) },
                    onTab: { commitTitle(); document.indentSection(withID: section.id, focusing: .title, using: undoManager) },
                    onBacktab: { commitTitle(); document.outdentSection(withID: section.id, focusing: .title, using: undoManager) },
                    onMoveUp: { commitTitle(); document.moveSectionUp(withID: section.id, focusing: .title, using: undoManager) },
                    onMoveDown: { commitTitle(); document.moveSectionDown(withID: section.id, focusing: .title, using: undoManager) }
                )
                Spacer(minLength: 0)
                if section.totalWordCount > 0 {
                    Text("\(section.totalWordCount)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 12)

            CardTextView(
                content: section.content,
                handle: bodyHandle,
                typography: document.typography,
                theme: editorTheme,
                highlight: bodyHighlight,
                actions: actions,
                undoManager: undoManager,
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
                .strokeBorder(isSelected ? accent : Theme.hairline,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .frame(maxWidth: .infinity)
        .padding(.leading, CGFloat(min(depth, 6)) * 16)
        // Focus mode: everything but the block you're in recedes.
        .opacity(focusMode && !isSelected ? 0.32 : 1)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping the card chrome (not a field) selects the block.
            if document.selectedSectionID != section.id { document.selectedSectionID = section.id }
        }
        .onChange(of: section.title) { newValue in
            draftTitle = newValue
        }
        .onChange(of: isTitleFocused) { focused in
            if focused { selectFromEditor() } else { commitTitle() }
        }
        .onReceive(document.$focusRequest) { request in
            guard let request, request.sectionID == section.id else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // A structural edit can publish two requests back to back
                // (the model's own, then the outline's keyboard-down one);
                // only the latest counts, or the first would raise the keyboard.
                guard document.focusRequest == request else { return }
                guard request.takesFocus else {
                    // Find bar stepping: show the place, keep focus in the bar.
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
        default: return 15
        }
    }

    private func commitTitle() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            document.setTitle(trimmed, for: section, using: undoManager)
        }
        draftTitle = section.title
    }

    /// The user put the caret in this card: make it the selected block
    /// without scrolling. (On iOS first responder only ever changes by a tap
    /// or one of our own focus requests, so no event check is needed.)
    private func selectFromEditor() {
        if document.selectedSectionID != section.id {
            document.selectedSectionID = section.id
        }
    }
}

// MARK: - Block actions for the keyboard

/// Closures a card hands to its fields, so the accessory bar and hardware
/// key commands act on the right block.
struct CardActions {
    var addSibling: () -> Void
    var addChild: () -> Void
    var indent: () -> Void
    var outdent: () -> Void
    var moveUp: () -> Void
    var moveDown: () -> Void
    var canIndent: () -> Bool
    var canOutdent: () -> Bool
    var canMoveUp: () -> Bool
    var canMoveDown: () -> Bool
    /// ⌘F from a hardware keyboard while editing.
    var find: () -> Void
}

/// The bar above the software keyboard: formatting on the left, structure
/// on the right, and a way to put the keyboard away. One per text view;
/// `formatting` is nil for the title field, which has no rich text.
final class KeyboardAccessoryBar: UIToolbar {
    /// One bar of each kind for the whole app, claimed by whichever field
    /// begins editing. Bars used to be owned per card and freed with it;
    /// iOS 26's keyboard controller keeps tracking the last responder's
    /// input views after the keyboard goes down, so a bar freed with a
    /// deleted card was still in that set, and the next keyboard placement
    /// (triggered when a context menu closed) messaged the dead object:
    /// "unrecognized selector … initializeTranslateGestureRecognizerIfNecessary".
    /// A bar that lives for the app's lifetime can never be dead.
    static let titleBar = KeyboardAccessoryBar(showsFormatting: false)
    static let bodyBar = KeyboardAccessoryBar(showsFormatting: true)

    var actions: CardActions?
    /// Toggle a trait in the text this bar belongs to.
    var formatting: ((SelectionFormatting.Trait) -> Void)?
    weak var owner: UIResponder?

    private var indentItem: UIBarButtonItem!
    private var outdentItem: UIBarButtonItem!
    /// iPad only: the iPhone bar has no room for them (Move Up/Down live in
    /// the Block menu and the outline's context menu there).
    private var moveUpItem: UIBarButtonItem?
    private var moveDownItem: UIBarButtonItem?

    init(showsFormatting: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        autoresizingMask = .flexibleWidth

        func button(_ symbol: String, _ label: String, _ action: Selector) -> UIBarButtonItem {
            let item = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
            item.accessibilityLabel = label
            return item
        }
        func gap(_ width: CGFloat) -> UIBarButtonItem {
            let item = UIBarButtonItem(systemItem: .fixedSpace)
            item.width = width
            return item
        }

        // iPad shows its own B/I/U in the shortcuts bar above the keyboard and
        // has a dismiss key on the keyboard; iPhone has neither.
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        var items: [UIBarButtonItem] = []
        if showsFormatting && isPhone {
            items += [
                button("bold", "Bold", #selector(bold)),
                button("italic", "Italic", #selector(italic)),
                button("underline", "Underline", #selector(underline)),
                gap(16),
            ]
        }
        outdentItem = button("decrease.indent", "Outdent Block", #selector(outdent))
        indentItem = button("increase.indent", "Indent Block", #selector(indent))
        items += [outdentItem, indentItem]
        if !isPhone {
            let up = button("arrow.up", "Move Block Up", #selector(moveUp))
            let down = button("arrow.down", "Move Block Down", #selector(moveDown))
            moveUpItem = up
            moveDownItem = down
            items += [gap(16), up, down]
        }
        items += [
            UIBarButtonItem(systemItem: .flexibleSpace),
            button("plus", "Add Block After", #selector(addSibling)),
            button("plus.square.on.square", "Add Sub-block", #selector(addChild)),
        ]
        if isPhone {
            items += [gap(16), button("keyboard.chevron.compact.down", "Hide Keyboard", #selector(dismiss))]
        }
        setItems(items, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A field that has (or is taking) the keyboard makes the bar act on
    /// its block. Called on begin-editing and on every update while focused,
    /// so the closures always see the current card.
    func claim(owner: UIResponder, actions: CardActions,
               formatting: ((SelectionFormatting.Trait) -> Void)? = nil) {
        self.owner = owner
        self.actions = actions
        self.formatting = formatting
        refresh()
    }

    /// Enable/disable the structure buttons for the block's current place.
    func refresh() {
        indentItem.isEnabled = actions?.canIndent() ?? false
        outdentItem.isEnabled = actions?.canOutdent() ?? false
        moveUpItem?.isEnabled = actions?.canMoveUp() ?? false
        moveDownItem?.isEnabled = actions?.canMoveDown() ?? false
    }

    @objc private func bold() { formatting?(.bold) }
    @objc private func italic() { formatting?(.italic) }
    @objc private func underline() { formatting?(.underline) }
    @objc private func indent() { actions?.indent() }
    @objc private func outdent() { actions?.outdent() }
    @objc private func moveUp() { actions?.moveUp() }
    @objc private func moveDown() { actions?.moveDown() }
    @objc private func addSibling() { actions?.addSibling() }
    @objc private func addChild() { actions?.addChild() }
    @objc private func dismiss() { owner?.resignFirstResponder() }
}

// MARK: - Title field

/// Lets the card focus its title field from a focus request.
final class TitleFieldHandle: ObservableObject {
    weak var field: UITextField?
    func focus() {
        field?.becomeFirstResponder()
    }
}

/// The block title. A UIKit field so Return can move to the body, and a
/// hardware keyboard's Tab/⇧Tab can indent/outdent, Escape revert and ⌘↩
/// add a block, as on the Mac.
private struct TitleField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontFamily: String
    let fontSize: CGFloat
    let handle: TitleFieldHandle
    let actions: CardActions
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    /// ⌃⌘↑ / ⌃⌘↓ from a hardware keyboard: move the block, focus stays in the title.
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TitleUITextField {
        let field = TitleUITextField()
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.textColor = .label
        field.font = PlatformFont.kishoHeading(family: fontFamily, size: fontSize)
        context.coordinator.appliedFamily = fontFamily
        field.placeholder = placeholder
        field.returnKeyType = .next
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.autocapitalizationType = .sentences
        field.clearButtonMode = .whileEditing
        field.text = text
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.commands = context.coordinator
        let bar = KeyboardAccessoryBar.titleBar
        field.inputAccessoryView = bar
        field.accessoryBar = bar
        handle.field = field
        return field
    }

    /// Fill the width the card offers; a text field's own ideal width is the
    /// width of its text, which would stretch the card off the screen.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: TitleUITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width,
               height: field.intrinsicContentSize.height)
    }

    /// The card is going away. UIKit's keyboard controller keeps tracking
    /// the last responder's input views even with the keyboard down; if the
    /// field and its accessory bar are freed while still tracked, the next
    /// keyboard placement (e.g. after a context menu closes) messages a
    /// dead object. Let go of them here, while the field is still alive.
    static func dismantleUIView(_ field: TitleUITextField, coordinator: Coordinator) {
        KishoKeyboard.release(field)
        field.commands = nil
        field.delegate = nil
    }

    func updateUIView(_ field: TitleUITextField, context: Context) {
        context.coordinator.parent = self
        handle.field = field
        if field.text != text { field.text = text }
        if field.font?.pointSize != fontSize || context.coordinator.appliedFamily != fontFamily {
            field.font = PlatformFont.kishoHeading(family: fontFamily, size: fontSize)
            context.coordinator.appliedFamily = fontFamily
        }
        if field.isFirstResponder {
            field.accessoryBar?.claim(owner: field, actions: actions)
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate, TitleFieldCommands {
        var parent: TitleField
        var appliedFamily: String?
        init(_ parent: TitleField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            KishoKeyboard.tookKeyboard(textField)
            (textField as? TitleUITextField)?.accessoryBar?.claim(owner: textField, actions: parent.actions)
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChange(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func tab() { parent.onTab() }
        func backtab() { parent.onBacktab() }
        func escape() { parent.onEscape() }
        func commandReturn() { parent.actions.addSibling() }
        func find() { parent.actions.find() }
        func moveUp() { parent.onMoveUp() }
        func moveDown() { parent.onMoveDown() }
    }
}

protocol TitleFieldCommands: AnyObject {
    func tab()
    func backtab()
    func escape()
    func commandReturn()
    func find()
    func moveUp()
    func moveDown()
}

final class TitleUITextField: UITextField {
    weak var commands: TitleFieldCommands?
    var accessoryBar: KeyboardAccessoryBar?

    override var keyCommands: [UIKeyCommand]? {
        let list = [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(handleBacktab)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape)),
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(handleCommandReturn)),
            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(handleFind)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [.command, .control], action: #selector(handleMoveUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [.command, .control], action: #selector(handleMoveDown)),
        ]
        // Our Tab beats the system's focus movement.
        list.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return list
    }

    @objc private func handleTab() { commands?.tab() }
    @objc private func handleBacktab() { commands?.backtab() }
    @objc private func handleEscape() { commands?.escape() }
    @objc private func handleCommandReturn() { commands?.commandReturn() }
    @objc private func handleFind() { commands?.find() }
    @objc private func handleMoveUp() { commands?.moveUp() }
    @objc private func handleMoveDown() { commands?.moveDown() }
}

// MARK: - Keyboard

enum KishoKeyboard {
    /// Puts the keyboard away wherever it is. Call before a structural edit
    /// that may destroy the card holding the first responder (deleting the
    /// selected block, above all): tearing a focused text view down with
    /// its card crashes in UIKit/SwiftUI gesture teardown.
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// The field that most recently took the keyboard, kept alive until
    /// another one does. iOS 26's keyboard controller keeps the last
    /// responder's input views in its tracking set *unretained* after the
    /// keyboard goes down, and only replaces the set when a new responder
    /// begins editing. Deleting the block that held the keyboard freed that
    /// field, and the next keyboard placement (triggered when a context
    /// menu closed) messaged the dead object:
    /// -[UITrackingElementWindowController changeToInputViewSet:] →
    /// EXC_BAD_ACCESS / unrecognized selector. Holding the field here costs
    /// one text view and guarantees the set never points at freed memory.
    static var lastResponder: UIView?

    static func tookKeyboard(_ view: UIView) {
        lastResponder = view
    }

    /// A text field/view is about to be destroyed: give up the keyboard if
    /// it holds it. (Its accessory bar is app-wide and outlives it, and if
    /// it was the last responder, `lastResponder` keeps it alive.)
    static func release(_ view: UIView) {
        if view.isFirstResponder { view.resignFirstResponder() }
    }
}

// MARK: - Keyboard frame

/// Where the keyboard (with its accessory bar) is on screen, from the
/// system notifications; nil when it is hidden.
final class KeyboardFrame {
    static let shared = KeyboardFrame()
    private(set) var endFrame: CGRect?

    private init() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(changed(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(hidden(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func changed(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        // A keyboard pushed off the bottom of the screen counts as hidden.
        let screen = UIScreen.main.bounds
        endFrame = frame.minY >= screen.maxY ? nil : frame
    }

    @objc private func hidden(_ note: Notification) { endFrame = nil }
}

/// Which ranges of a block's body to mark as search hits.
struct BodyHighlight: Equatable {
    var ranges: [NSRange]
    var current: NSRange?
}

// MARK: - Self-sizing text view

/// Lets the card reach its UITextView (to focus it) without the view layer
/// holding UIKit objects directly.
final class CardTextViewHandle: ObservableObject {
    weak var textView: UITextView?
    /// Height the body needs for its text, measured by the text view itself.
    @Published var height: CGFloat = 28

    func report(height newHeight: CGFloat) {
        let rounded = ceil(newHeight)
        guard abs(rounded - height) > 0.5 else { return }
        // Published from within UIKit layout; defer so SwiftUI isn't mutated mid-update.
        DispatchQueue.main.async { [weak self] in
            guard let self, abs(rounded - self.height) > 0.5 else { return }
            self.height = rounded
        }
    }

    func focus(atEnd: Bool) {
        guard let textView else { return }
        textView.becomeFirstResponder()
        if atEnd {
            textView.selectedRange = NSRange(location: textView.attributedText.length, length: 0)
        }
        (textView as? CardUITextView)?.scrollCaretIntoView()
    }

    func focus(at caret: Int) {
        guard let textView else { return }
        textView.becomeFirstResponder()
        let length = textView.attributedText.length
        textView.selectedRange = NSRange(location: max(0, min(caret, length)), length: 0)
        (textView as? CardUITextView)?.scrollCaretIntoView()
    }

    func focus(selecting range: NSRange) {
        guard let textView else { return }
        textView.becomeFirstResponder()
        textView.selectedRange = Self.clamp(range, in: textView)
        (textView as? CardUITextView)?.scrollCaretIntoView()
    }

    /// Bring a range into view without taking keyboard focus or changing the
    /// selection (the find highlight marks it).
    func show(_ range: NSRange) {
        guard let textView = textView as? CardUITextView else { return }
        textView.scrollRange(Self.clamp(range, in: textView))
    }

    private static func clamp(_ range: NSRange, in textView: UITextView) -> NSRange {
        let length = textView.attributedText.length
        let location = max(0, min(range.location, length))
        return NSRange(location: location, length: max(0, min(range.length, length - location)))
    }
}

/// One block's body. Sizes itself to its text (no internal scrolling), writes
/// every change straight into the block's `RichTextModel`, and reports when
/// it becomes first responder so the selection can follow the caret.
private struct CardTextView: UIViewRepresentable {
    @ObservedObject var content: RichTextModel
    let handle: CardTextViewHandle
    let typography: TypographySettings
    let theme: EditorTheme
    let highlight: BodyHighlight
    let actions: CardActions
    let undoManager: UndoManager?
    let onBeginEditing: () -> Void
    /// Called with the text before and after a user edit, and the character
    /// index where the edit happened.
    let onChange: (NSAttributedString, NSAttributedString, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CardUITextView {
        _ = KeyboardFrame.shared   // start listening before the first keyboard appears
        // TextKit 1, as the Mac editor uses: the same layout engine for the
        // same document, and clear of a TextKit 2 crash when a text view is
        // torn down during a context-menu dismissal.
        let textView = CardUITextView(usingTextLayoutManager: false)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.textContainer.lineFragmentPadding = 4
        // Rich text in, rich text out; the edit menu's B/I/U route through
        // our own toggles (see CardUITextView).
        textView.allowsEditingTextAttributes = true
        // The iPad shortcuts bar's own undo/redo would act on the text view's
        // undo manager, which is off (the document's is the one that counts,
        // and it is on the navigation bar).
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.delegate = context.coordinator
        textView.attributedText = content.attributedString
        applyDisplayColour(textView)
        textView.typingAttributes = typingAttributes()
        textView.onHeightChange = { [weak handle] height in handle?.report(height: height) }
        textView.onCommandReturn = { [weak coordinator = context.coordinator] in coordinator?.parent.actions.addSibling() }
        textView.onFormat = { [weak coordinator = context.coordinator] trait in coordinator?.toggle(trait) }
        textView.onFind = { [weak coordinator = context.coordinator] in coordinator?.parent.actions.find() }
        textView.onMoveUp = { [weak coordinator = context.coordinator] in coordinator?.parent.actions.moveUp() }
        textView.onMoveDown = { [weak coordinator = context.coordinator] in coordinator?.parent.actions.moveDown() }
        let bar = KeyboardAccessoryBar.bodyBar
        textView.inputAccessoryView = bar
        textView.accessoryBar = bar
        context.coordinator.textView = textView
        handle.textView = textView
        return textView
    }

    /// SwiftUI owns the frame: width from the card, height from our own
    /// measurement. Never the text view's intrinsic size, which for an
    /// unscrollable text view is the width of its longest line.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: CardUITextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? textView.bounds.width, height: handle.height)
    }

    /// See TitleField.dismantleUIView.
    static func dismantleUIView(_ textView: CardUITextView, coordinator: Coordinator) {
        KishoKeyboard.release(textView)
        textView.delegate = nil
        coordinator.textView = nil
    }

    func updateUIView(_ textView: CardUITextView, context: Context) {
        context.coordinator.parent = self
        handle.textView = textView
        textView.documentUndoManager = undoManager
        if textView.isFirstResponder {
            textView.accessoryBar?.claim(owner: textView, actions: actions,
                                         formatting: { [weak coordinator = context.coordinator] trait in coordinator?.toggle(trait) })
        }
        let stored = content.attributedString
        if !context.coordinator.isPushingToModel,
           !stored.isEqual(to: Self.withoutHighlight(textView.attributedText)) {
            let selection = textView.selectedRange
            context.coordinator.isApplyingModel = true
            textView.attributedText = stored
            applyDisplayColour(textView)
            context.coordinator.isApplyingModel = false
            context.coordinator.appliedHighlight = nil   // storage reset drops the marks
            let length = textView.attributedText.length
            textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        }
        if context.coordinator.appliedTheme != theme {
            context.coordinator.appliedTheme = theme
            textView.overrideUserInterfaceStyle = theme.colorScheme == .dark ? .dark : (theme.colorScheme == .light ? .light : .unspecified)
        }
        if textView.attributedText.length == 0 || context.coordinator.appliedTypography != typography {
            var attrs = typingAttributes()
            if let current = textView.typingAttributes[.font] as? UIFont,
               let base = attrs[.font] as? UIFont {
                attrs[.font] = SelectionFormatting.font(base, matchingTraitsOf: current)
            }
            textView.typingAttributes = attrs
            context.coordinator.appliedTypography = typography
        }
        textView.measure()
        applyHighlight(textView, context: context)
    }

    /// Search hits as a background colour in the storage — UIKit has no
    /// temporary attributes — stripped again before anything reaches the model.
    private func applyHighlight(_ textView: UITextView, context: Context) {
        guard context.coordinator.appliedHighlight != highlight else { return }
        context.coordinator.appliedHighlight = highlight
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage.length)
        context.coordinator.isApplyingModel = true
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: full)
        for range in highlight.ranges where NSMaxRange(range) <= storage.length {
            let colour = UIColor.systemYellow.withAlphaComponent(range == highlight.current ? 0.6 : 0.3)
            storage.addAttribute(.backgroundColor, value: colour, range: range)
        }
        storage.endEditing()
        context.coordinator.isApplyingModel = false
    }

    /// `text` without the find marks.
    static func withoutHighlight(_ text: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        copy.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: copy.length))
        return copy
    }

    /// Stored text may carry a baked-in colour from RTF; show it in the
    /// appearance-adaptive label colour.
    private func applyDisplayColour(_ textView: UITextView) {
        guard textView.attributedText.length > 0 else { return }
        textView.textStorage.addAttribute(.foregroundColor, value: UIColor.label,
                                          range: NSRange(location: 0, length: textView.textStorage.length))
    }

    private func typingAttributes() -> [NSAttributedString.Key: Any] {
        [.font: typography.baseFont, .foregroundColor: UIColor.label]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CardTextView
        weak var textView: CardUITextView?
        var isApplyingModel = false
        var isPushingToModel = false
        var appliedTypography: TypographySettings?
        var appliedHighlight: BodyHighlight?
        var appliedTheme: EditorTheme?

        init(_ parent: CardTextView) { self.parent = parent }

        /// Start of the range about to change: the edit site for undo caret placement.
        private var pendingEditLocation = 0

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            pendingEditLocation = range.location
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            KishoKeyboard.tookKeyboard(textView)
            (textView as? CardUITextView)?.accessoryBar?.claim(owner: textView, actions: parent.actions,
                                                                 formatting: { [weak self] trait in self?.toggle(trait) })
            parent.onBeginEditing()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingModel, textView.isFirstResponder else { return }
            (textView as? CardUITextView)?.scrollCaretIntoView()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingModel, let textView = self.textView else { return }
            pushToModel(textView)
            textView.measure()
            // Once now, and again after the card's new height has reached the
            // scroll view (a new line at the bottom of a card grows it first).
            DispatchQueue.main.async { textView.scrollCaretIntoView() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { textView.scrollCaretIntoView() }
        }

        /// Copies the live storage into the model and records the edit.
        func pushToModel(_ textView: UITextView) {
            let before = parent.content.attributedString
            // A snapshot, not the live storage: the model must own immutable
            // text or undo captures edits one keystroke late. Find marks stay
            // in the view.
            let after = CardTextView.withoutHighlight(textView.attributedText)
            isPushingToModel = true
            parent.content.attributedString = after
            isPushingToModel = false
            parent.onChange(before, after, pendingEditLocation)
        }

        /// Bold/italic/underline for the selection, or for the caret's typing
        /// attributes when nothing is selected.
        func toggle(_ trait: SelectionFormatting.Trait) {
            guard let textView else { return }
            let range = textView.selectedRange
            if range.length == 0 {
                let attrs = textView.typingAttributes
                textView.typingAttributes = SelectionFormatting.attributes(attrs, setting: trait,
                                                                           to: !SelectionFormatting.attributes(attrs, have: trait))
                return
            }
            pendingEditLocation = range.location
            SelectionFormatting.toggle(trait, in: textView.textStorage, range: range)
            textView.selectedRange = range
            // Same path as typing: push to the model, record undo, re-measure.
            pushToModel(textView)
            textView.measure()
        }
    }
}

/// UITextView that reports focus and the height its text needs, keeps its
/// caret visible above the keyboard, and routes the system's bold/italic/
/// underline (edit menu, ⌘B/⌘I/⌘U) through the card's own formatting.
final class CardUITextView: UITextView {
    var onHeightChange: ((CGFloat) -> Void)?
    var onCommandReturn: (() -> Void)?
    var onFormat: ((SelectionFormatting.Trait) -> Void)?
    var onFind: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var accessoryBar: KeyboardAccessoryBar?
    /// The document's undo manager, which owns every edit (the text view's
    /// own range-based undo would fall out of step whenever the model
    /// replaces the text, so it is switched off).
    weak var documentUndoManager: UndoManager?

    override var undoManager: UndoManager? { nil }

    private static let minimumTextHeight: CGFloat = 22
    private var lastMeasuredWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastMeasuredWidth) > 0.5 { measure() }
    }

    // SwiftUI sizes us; never report an intrinsic size that could fight it.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    /// Lays out at the current width and reports the height the text needs.
    func measure() {
        guard bounds.width > 0 else { return }
        lastMeasuredWidth = bounds.width
        let fitted = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let height = max(fitted.height, Self.minimumTextHeight + textContainerInset.top + textContainerInset.bottom)
        onHeightChange?(height)
    }

    /// The SwiftUI scroll view this card sits in.
    private var enclosingScrollView: UIScrollView? {
        var view = superview
        while let v = view {
            if let scroll = v as? UIScrollView, scroll !== self { return scroll }
            view = v.superview
        }
        return nil
    }

    /// The card body does not scroll itself, so bring the caret into the
    /// enclosing scroll view's visible area (above the keyboard) when it
    /// would otherwise be hidden.
    func scrollCaretIntoView() {
        guard isFirstResponder, let scrollView = enclosingScrollView, let range = selectedTextRange else { return }
        var rect = caretRect(for: range.end)
        guard rect.height.isFinite, rect.height > 0 else { return }
        rect = convert(rect, to: scrollView).insetBy(dx: 0, dy: -32)

        // The part of the scroll view not under the keyboard and its accessory
        // bar. SwiftUI's own keyboard avoidance is not reliable about the bar
        // (iPhone landscape), so take the keyboard's frame directly.
        var visible = scrollView.bounds.inset(by: scrollView.adjustedContentInset)
        if let keyboard = KeyboardFrame.shared.endFrame, keyboard.height > 0 {
            let inScroll = scrollView.convert(keyboard, from: nil)
            if inScroll.minY < visible.maxY {
                visible.size.height = max(0, inScroll.minY - visible.minY)
            }
        }
        var offset = scrollView.contentOffset
        if UserDefaults.standard.bool(forKey: KishoPreferences.Key.typewriterScrolling) {
            // Typewriter scrolling: the caret line sits at the middle of the
            // area above the keyboard.
            offset.y += rect.midY - visible.midY
        } else {
            guard !visible.contains(rect) else { return }
            if rect.maxY > visible.maxY { offset.y += rect.maxY - visible.maxY }
            if rect.minY < visible.minY { offset.y -= visible.minY - rect.minY }
        }
        let maxOffset = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        offset.y = max(-scrollView.adjustedContentInset.top, min(offset.y, max(-scrollView.adjustedContentInset.top, maxOffset)))
        scrollView.setContentOffset(offset, animated: true)
    }

    /// Scroll so `range` is in the visible area (for find stepping).
    func scrollRange(_ range: NSRange) {
        guard let scrollView = enclosingScrollView,
              let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return }
        var rect = firstRect(for: textRange)
        guard rect.height.isFinite, rect.height > 0 else { return }
        rect = convert(rect, to: scrollView).insetBy(dx: 0, dy: -60)
        var visible = scrollView.bounds.inset(by: scrollView.adjustedContentInset)
        if let keyboard = KeyboardFrame.shared.endFrame, keyboard.height > 0 {
            let inScroll = scrollView.convert(keyboard, from: nil)
            if inScroll.minY < visible.maxY { visible.size.height = max(0, inScroll.minY - visible.minY) }
        }
        guard !visible.contains(rect) else { return }
        var offset = scrollView.contentOffset
        offset.y += rect.midY - visible.midY
        let maxOffset = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        offset.y = max(-scrollView.adjustedContentInset.top, min(offset.y, max(-scrollView.adjustedContentInset.top, maxOffset)))
        scrollView.setContentOffset(offset, animated: true)
    }

    // The system's formatting commands (edit menu, hardware ⌘B/⌘I/⌘U) would
    // change the storage behind the model's back; route them through ours.
    override func toggleBoldface(_ sender: Any?) { onFormat?(.bold) }
    override func toggleItalics(_ sender: Any?) { onFormat?(.italic) }
    override func toggleUnderline(_ sender: Any?) { onFormat?(.underline) }

    override var keyCommands: [UIKeyCommand]? {
        let list = [
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(handleCommandReturn)),
            UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(handleUndo)),
            UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(handleRedo)),
            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(handleFind)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [.command, .control], action: #selector(handleMoveUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [.command, .control], action: #selector(handleMoveDown)),
        ]
        list.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return (super.keyCommands ?? []) + list
    }

    @objc private func handleCommandReturn() { onCommandReturn?() }
    @objc private func handleUndo() { documentUndoManager?.undo() }
    @objc private func handleRedo() { documentUndoManager?.redo() }
    @objc private func handleFind() { onFind?() }
    @objc private func handleMoveUp() { onMoveUp?() }
    @objc private func handleMoveDown() { onMoveDown?() }
}
#endif
