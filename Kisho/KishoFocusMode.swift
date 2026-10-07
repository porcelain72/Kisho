//
//  KishoFocusMode.swift
//  Kisho
//
//  Writing-environment features: Focus Mode (just the cards, the current
//  one bright, the rest dimmed), Typewriter Scrolling (caret line kept at
//  the vertical centre), an editor theme independent of the system
//  appearance, and typography presets. Plus the Format menu they live in.
//

import SwiftUI

// MARK: - Editor theme

/// The app's appearance: editor, sidebar, inspector, toolbar and the other
/// windows all follow it. Sepia is a light scheme with paper-toned surfaces.
enum EditorTheme: String, CaseIterable, Identifiable {
    case system, light, dark, sepia
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .sepia: return "Sepia"
        }
    }

    /// The colour scheme to impose on the editor, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .sepia: return .light
        case .dark: return .dark
        }
    }

    #if os(macOS)
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light, .sepia: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies the theme's light/dark appearance to the whole app: every
    /// window, menu and panel, not just the editor. nil follows the system.
    func applyToApp() {
        NSApplication.shared.appearance = appearance
    }
    #endif

    static var current: EditorTheme {
        EditorTheme(rawValue: UserDefaults.standard.string(forKey: KishoPreferences.Key.editorTheme) ?? "") ?? .system
    }
}

/// The stored Editor Theme choice as a view property. Reads the preference
/// directly rather than the environment, so views in the sidebar, the
/// inspector and sheets — hosted separately from the editor — still redraw
/// the moment the theme changes.
@propertyWrapper
struct ThemeSetting: DynamicProperty {
    @AppStorage(KishoPreferences.Key.editorTheme) private var raw = EditorTheme.system.rawValue
    var wrappedValue: EditorTheme { EditorTheme(rawValue: raw) ?? .system }
}

#if os(macOS)
/// Gives the window itself the theme's surface. In Sepia the title bar goes
/// transparent over a paper-toned window background, so the toolbar and the
/// margins round the editor are paper too instead of the system's near-white.
/// Other themes put back whatever the window had.
///
/// A window restored straight into full screen builds its full-screen title bar
/// from the window's settings at that moment, so the styling is applied the
/// instant the view reaches the window, and once the window is in full screen
/// the title bar's transparency is flipped off and on to make AppKit rebuild
/// it. `onRefresh` also asks the owner to nudge its toolbar colour.
struct WindowThemeApplier: NSViewRepresentable {
    let theme: EditorTheme
    var onRefresh: () -> Void = {}

    final class Coordinator {
        var theme: EditorTheme = .system
        var onRefresh: () -> Void = {}
        var original: (transparent: Bool, background: NSColor)?
        weak var window: NSWindow?
        var observers: [NSObjectProtocol] = []

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

        func apply(to window: NSWindow) {
            if original == nil {
                original = (window.titlebarAppearsTransparent, window.backgroundColor)
            }
            if theme == .sepia {
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(Theme.canvas(.sepia))
            } else if let original {
                window.titlebarAppearsTransparent = original.transparent
                window.backgroundColor = original.background
            }
        }

        /// In full screen, off then on again so AppKit rebuilds the title bar.
        func rebuildFullScreenTitlebar() {
            guard theme == .sepia, let window, window.styleMask.contains(.fullScreen) else { return }
            window.titlebarAppearsTransparent = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.theme == .sepia, let window = self.window else { return }
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(Theme.canvas(.sepia))
            }
        }

        func refresh() {
            guard let window else { return }
            apply(to: window)
            rebuildFullScreenTitlebar()
            onRefresh()
        }

        func attach(to window: NSWindow) {
            apply(to: window)
            guard self.window !== window else { return }
            self.window = window
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            let names: [Notification.Name] = [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didChangeScreenNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    for delay in [0.0, 0.3, 0.8] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
                    }
                }
            }
            // Restoring into full screen finishes a moment after the window appears.
            for delay in [0.5, 1.5, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
            }
        }
    }

    /// Reports the window as soon as the view joins it, before the first layout
    /// pass, rather than a run-loop turn later.
    final class HostView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HostView {
        let coordinator = context.coordinator
        coordinator.theme = theme
        coordinator.onRefresh = onRefresh
        let view = HostView()
        view.onWindow = { [weak coordinator] window in coordinator?.attach(to: window) }
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        let coordinator = context.coordinator
        coordinator.theme = theme
        coordinator.onRefresh = onRefresh
        if let window = view.window { coordinator.apply(to: window) }
    }
}
#endif

// MARK: - Typography presets

/// Named font/size pairs, applied through the ordinary (undoable) document
/// typography change. The families are ones every Mac has.
enum TypographyPreset: String, CaseIterable, Identifiable {
    case manuscript, classic, modern, typewriter, largePrint
    var id: String { rawValue }

    var title: String {
        switch self {
        case .manuscript: return "Manuscript"
        case .classic: return "Classic"
        case .modern: return "Modern"
        case .typewriter: return "Typewriter"
        case .largePrint: return "Large Print"
        }
    }

    var settings: TypographySettings {
        switch self {
        case .manuscript: return TypographySettings(fontFamily: "Georgia", fontSize: 14)
        case .classic: return TypographySettings(fontFamily: "Palatino", fontSize: 15)
        case .modern: return TypographySettings(fontFamily: "Helvetica Neue", fontSize: 14)
        case .typewriter: return TypographySettings(fontFamily: "Menlo", fontSize: 13)
        case .largePrint: return TypographySettings(fontFamily: "Georgia", fontSize: 18)
        }
    }

    /// The preset matching `settings`, if any (for the menu's check mark).
    static func matching(_ settings: TypographySettings) -> TypographyPreset? {
        allCases.first { $0.settings.fontFamily == settings.fontFamily && $0.settings.fontSize == settings.fontSize }
    }
}

// MARK: - Focus mode state

private struct FocusModeEnvironmentKey: EnvironmentKey { static let defaultValue = false }
private struct EditorThemeEnvironmentKey: EnvironmentKey { static let defaultValue = EditorTheme.system }

extension EnvironmentValues {
    /// True inside a document window that is in Focus Mode.
    var kishoFocusMode: Bool {
        get { self[FocusModeEnvironmentKey.self] }
        set { self[FocusModeEnvironmentKey.self] = newValue }
    }
    /// The editor theme in force, so cards re-render when it changes.
    var kishoEditorTheme: EditorTheme {
        get { self[EditorThemeEnvironmentKey.self] }
        set { self[EditorThemeEnvironmentKey.self] = newValue }
    }
}

extension FocusedValues {
    private struct FocusModeKey: FocusedValueKey { typealias Value = Binding<Bool> }
    /// Whether the focused document window is in Focus Mode.
    var kishoFocusMode: Binding<Bool>? {
        get { self[FocusModeKey.self] }
        set { self[FocusModeKey.self] = newValue }
    }
}

// MARK: - Commands

#if os(macOS)

/// View ▸ Focus Mode, Typewriter Scrolling, Editor Theme.
struct ViewModeCommands: Commands {
    @FocusedBinding(\.kishoFocusMode) private var focusMode
    @AppStorage(KishoPreferences.Key.typewriterScrolling) private var typewriter = false
    @AppStorage(KishoPreferences.Key.editorTheme) private var editorTheme = EditorTheme.system.rawValue

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button((focusMode ?? false) ? "Exit Focus Mode" : "Enter Focus Mode") {
                focusMode?.toggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(focusMode == nil)

            Toggle("Typewriter Scrolling", isOn: $typewriter)
                .keyboardShortcut("t", modifiers: [.command, .option])

            Picker("Editor Theme", selection: $editorTheme) {
                ForEach(EditorTheme.allCases) { theme in
                    Text(theme.title).tag(theme.rawValue)
                }
            }
            Divider()
        }
    }
}

/// Format menu: selection formatting and the document font presets. The
/// document is a focused *object* here, so the tick follows the font as it
/// changes (a focused value would only refresh when focus moves).
struct FormatCommands: Commands {
    @FocusedObject private var documentModel: KishoDocumentModel?

    private var activeUndoManager: UndoManager? { NSApp.keyWindow?.undoManager }

    private var presetSelection: Binding<TypographyPreset?> {
        Binding(
            get: { documentModel.flatMap { TypographyPreset.matching($0.typography) } },
            set: { preset in
                guard let preset, let documentModel else { return }
                documentModel.setTypography(preset.settings, undoManager: activeUndoManager)
            }
        )
    }

    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { SelectionFormatting.toggle(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { SelectionFormatting.toggle(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Underline") { SelectionFormatting.toggle(.underline) }
                .keyboardShortcut("u", modifiers: .command)

            Divider()

            Picker("Document Font", selection: presetSelection) {
                ForEach(TypographyPreset.allCases) { preset in
                    Text("\(preset.title) — \(TypographySettings.displayName(forFamily: preset.settings.fontFamily)) \(Int(preset.settings.fontSize))")
                        .tag(TypographyPreset?.some(preset))
                }
                Divider()
                // Ticked when the inspector's family/size match no preset.
                Text("Custom (from the inspector)").tag(TypographyPreset?.none)
            }
            .disabled(documentModel == nil)
        }
    }
}

// MARK: - Typewriter scrolling

enum TypewriterScrolling {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: KishoPreferences.Key.typewriterScrolling) }

    /// Scroll the enclosing scroll view so the caret line sits at the vertical
    /// centre. Only while the text view has focus (not on programmatic
    /// selection changes while the user is elsewhere).
    static func recentre(_ textView: NSTextView, animated: Bool = true) {
        guard isEnabled,
              textView.window?.firstResponder === textView,
              let scrollView = textView.enclosingScrollView,
              let documentView = scrollView.documentView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let selection = textView.selectedRange()
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(selection.location, max(0, (textView.string as NSString).length)))
        var lineRect: NSRect
        if layoutManager.numberOfGlyphs == 0 {
            lineRect = NSRect(x: 0, y: 0, width: 1, height: textView.font?.pointSize ?? 14)
        } else {
            let safeIndex = min(glyphIndex, max(0, layoutManager.numberOfGlyphs - 1))
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: safeIndex, effectiveRange: nil)
            // Caret after the final newline sits below the last fragment.
            if glyphIndex >= layoutManager.numberOfGlyphs, textView.string.hasSuffix("\n") {
                lineRect.origin.y += lineRect.height
            }
        }
        lineRect.origin.x += textView.textContainerInset.width
        lineRect.origin.y += textView.textContainerInset.height

        let inDocument = textView.convert(lineRect, to: documentView)
        let visible = scrollView.contentView.bounds
        let maxY = max(0, documentView.bounds.height - visible.height)
        let targetY = min(max(0, inDocument.midY - visible.height / 2), maxY)
        guard abs(targetY - visible.origin.y) > 1 else { return }

        let target = NSPoint(x: visible.origin.x, y: targetY)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.allowsImplicitAnimation = true
                scrollView.contentView.animator().setBoundsOrigin(target)
            }
        } else {
            scrollView.contentView.setBoundsOrigin(target)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
#endif
