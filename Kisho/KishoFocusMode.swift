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

/// Appearance of the editor area only — the sidebar and chrome follow the
/// system. Sepia is a light scheme with paper-toned surfaces.
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
    #endif

    static var current: EditorTheme {
        EditorTheme(rawValue: UserDefaults.standard.string(forKey: KishoPreferences.Key.editorTheme) ?? "") ?? .system
    }
}

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

#if os(macOS)

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

/// Format menu: selection formatting and the document font presets.
struct FormatCommands: Commands {
    @FocusedValue(\.kishoDocumentModel) private var documentModel

    private var activeUndoManager: UndoManager? { NSApp.keyWindow?.undoManager }

    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { SelectionFormatting.toggle(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { SelectionFormatting.toggle(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Underline") { SelectionFormatting.toggle(.underline) }
                .keyboardShortcut("u", modifiers: .command)

            Divider()

            Menu("Document Font") {
                ForEach(TypographyPreset.allCases) { preset in
                    Button {
                        documentModel?.setTypography(preset.settings, undoManager: activeUndoManager)
                    } label: {
                        let current = documentModel.map { TypographyPreset.matching($0.typography) == preset } ?? false
                        Text((current ? "✓ " : "") + "\(preset.title) — \(TypographySettings.displayName(forFamily: preset.settings.fontFamily)) \(Int(preset.settings.fontSize))")
                    }
                }
                Divider()
                Text("Any family and size can be chosen in the toolbar.")
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
