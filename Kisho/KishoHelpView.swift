//
//  KishoHelpView.swift
//  Kisho
//
//  "How Kisho Works": the one page a new user needs. Shown once on first
//  launch and from Help ▸ How Kisho Works (⌘?).
//
//  Branded to match the app icon: a graphite header carrying the icon, warm
//  paper-toned cards, charcoal badges. Follows the system appearance.
//

import SwiftUI

#if os(macOS)
import AppKit

/// The icon's palette (graphite squircle, paper disc, charcoal tree) as
/// light/dark-adaptive colours for the help page.
private enum HelpPalette {
    static let graphiteTop = Color(red: 0.290, green: 0.302, blue: 0.322)     // #4A4D52
    static let graphiteBottom = Color(red: 0.165, green: 0.173, blue: 0.188)  // #2A2C30
    static let paper = Color(red: 0.965, green: 0.945, blue: 0.902)           // #F6F1E6

    /// Page behind the cards.
    static let page = adaptive(light: NSColor(red: 0.957, green: 0.941, blue: 0.906, alpha: 1),
                               dark: NSColor(red: 0.118, green: 0.122, blue: 0.133, alpha: 1))
    /// Card face.
    static let card = adaptive(light: NSColor(red: 0.992, green: 0.984, blue: 0.965, alpha: 1),
                               dark: NSColor(red: 0.165, green: 0.173, blue: 0.188, alpha: 1))
    /// Card and keycap outline.
    static let border = adaptive(light: NSColor(red: 0.231, green: 0.243, blue: 0.263, alpha: 0.14),
                                 dark: NSColor(white: 1, alpha: 0.10))
    /// Keycap fill.
    static let keyFill = adaptive(light: NSColor(red: 0.945, green: 0.925, blue: 0.880, alpha: 1),
                                  dark: NSColor(white: 1, alpha: 0.07))

    static var badge: LinearGradient {
        LinearGradient(colors: [graphiteTop, graphiteBottom], startPoint: .top, endPoint: .bottom)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }
}

struct KishoHelpView: View {
    static let windowID = "kisho-help"

    private struct Topic: Identifiable {
        let symbol: String
        let title: LocalizedStringResource
        let text: LocalizedStringResource
        var id: String { title.key }
    }

    private static let topics: [Topic] = [
        Topic(symbol: "list.bullet.indent", title: "Blocks",
              text: "A Kisho document is a tree of blocks. Each block has a title, a body and optional tags. The sidebar shows the tree; the editor shows every block as a card, in reading order, nested blocks indented under their parents. Click a card or a sidebar row to select a block."),
        Topic(symbol: "plus.square.on.square", title: "Adding and arranging",
              text: "⌘= adds a block after the selected one; ⇧⌘= adds one inside it. Drag rows in the sidebar to move blocks — onto a row to nest, between rows to reorder. In a block's title, Tab nests it under the block above and ⇧Tab moves it out again (⌘] and ⌘[ do the same anywhere). Everything is undoable with ⌘Z."),
        Topic(symbol: "arrow.triangle.branch", title: "Split and Gather",
              text: "Split (⌥⌘P) turns each paragraph of the selected block into its own child block, titled from its first sentence. Gather (⌥⌘G) does the reverse: it pulls the text of all sub-blocks back into the parent, in order, and removes them. Use them to go from a rough draft to a structure and back."),
        Topic(symbol: "pencil.line", title: "Writing",
              text: "Type in any card; the body grows as you write. ⌘B, ⌘I and ⌘U apply bold, italic and underline to the selection. The document's font and size are set in the inspector's Document section (or Format ▸ Document Font) and keep your bold/italic/underline. ⌘↩ in a body adds a new block right after the current one."),
        Topic(symbol: "tag", title: "Tags and filtering",
              text: "Add tags to the selected block in the bar below the editor. When any block has tags, a filter appears above the sidebar: pick a tag to see only the blocks carrying it (their parents stay visible, dimmed, for context)."),
        Topic(symbol: "slider.horizontal.3", title: "Planning with the inspector",
              text: "View ▸ Show Inspector (⌥⌘I) opens a panel for the selected block: a status (Draft, Revised, Final, Done), one of eight colours, a synopsis and private notes. The sidebar shows the colour as a dot and the status as a small symbol, and View ▸ Show Synopses puts each synopsis under its title — so the sidebar doubles as an outline you can plan in. Notes are never exported."),
        Topic(symbol: "scope", title: "Focus Mode and typewriter scrolling",
              text: "View ▸ Enter Focus Mode (⌥⌘F) hides the sidebar and inspector and empties the toolbar, narrows the cards to a reading width and dims every block but the one you're in. Typewriter Scrolling (⌥⌘T) keeps the line you're typing at the centre of the window. View ▸ Editor Theme sets all of Kisho — editor, sidebar and inspector — to light, dark or sepia independently of the system; the Format menu has Bold, Italic, Underline and Document Font presets."),
        Topic(symbol: "magnifyingglass", title: "Find and replace",
              text: "⌘F searches titles, bodies and tags. Return or ⌘G steps through matches, ⇧⌘G steps back, ⌘E uses the selected text as the search term. Replace changes the current match; All changes every match in one undoable step and keeps each word's capitalisation."),
        Topic(symbol: "square.and.arrow.up", title: "Export and import",
              text: "File ▸ Export As writes the whole document as Plain Text, Markdown, Word (.docx with real heading styles), PDF or HTML. File ▸ Import Markdown… builds a new document from a Markdown file, one block per heading."),
    ]

    private struct QuickStart: Identifiable {
        let symbol: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
        let keys: String?
        var id: String { title.key }
    }

    private static let quickStart: [QuickStart] = [
        QuickStart(symbol: "plus.square.on.square", title: "Add a block",
                   detail: "After the selected one", keys: "⌘="),
        QuickStart(symbol: "arrow.up.and.down.and.arrow.left.and.right", title: "Arrange",
                   detail: "Drag rows in the sidebar", keys: nil),
        QuickStart(symbol: "arrow.triangle.branch", title: "Split a draft",
                   detail: "One block per paragraph", keys: "⌥⌘P"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 28) {
                    quickStartRow

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.topics) { topicCard($0) }
                    }

                    shortcuts

                    footer
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HelpPalette.page)
        .frame(minWidth: 540, minHeight: 520)
    }

    // MARK: Header

    private var hero: some View {
        HStack(spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("WELCOME TO KISHO")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(HelpPalette.paper.opacity(0.62))
                Text("How Kisho Works")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(HelpPalette.paper)
                    .accessibilityAddTraits(.isHeader)
                Text("Long-form writing as a stack of named blocks.")
                    .font(.title3)
                    .foregroundColor(HelpPalette.paper.opacity(0.80))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [HelpPalette.graphiteTop, HelpPalette.graphiteBottom],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: Quick start

    private var quickStartRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start here")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Self.quickStart) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        badge(item.symbol, size: 30)
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        Text(item.detail)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let keys = item.keys {
                            KeyCap(text: keys)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(CardStyle())
                }
            }
        }
    }

    // MARK: Topics

    private func topicCard(_ topic: Topic) -> some View {
        HStack(alignment: .top, spacing: 14) {
            badge(topic.symbol, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(topic.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardStyle())
    }

    /// Charcoal circle with a paper-coloured symbol, echoing the icon.
    private func badge(_ symbol: String, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(HelpPalette.badge)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundColor(HelpPalette.paper)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Shortcuts

    private struct ShortcutRow: Identifiable {
        let label: LocalizedStringResource
        let keys: [String]
        var note: LocalizedStringResource? = nil
        var id: String { label.key }
    }

    private static let shortcutRows: [ShortcutRow] = [
        ShortcutRow(label: "Add block after", keys: ["⌘="]),
        ShortcutRow(label: "Add block inside", keys: ["⇧⌘="]),
        ShortcutRow(label: "Add block from body", keys: ["⌘↩"]),
        ShortcutRow(label: "Delete block", keys: ["⇧⌘⌫"]),
        ShortcutRow(label: "Indent / outdent block", keys: ["⌘]", "⌘["], note: "Tab / ⇧Tab in a title"),
        ShortcutRow(label: "Split paragraphs into blocks", keys: ["⌥⌘P"]),
        ShortcutRow(label: "Gather sub-blocks", keys: ["⌥⌘G"]),
        ShortcutRow(label: "Next / previous block", keys: ["⌃⌘↓", "⌃⌘↑"]),
        ShortcutRow(label: "Into first child / up to parent", keys: ["⌃⌘→", "⌃⌘←"]),
        ShortcutRow(label: "Bold / italic / underline", keys: ["⌘B", "⌘I", "⌘U"]),
        ShortcutRow(label: "Find", keys: ["⌘F"]),
        ShortcutRow(label: "Find next / previous", keys: ["⌘G", "⇧⌘G"]),
        ShortcutRow(label: "Use selection for find", keys: ["⌘E"]),
        ShortcutRow(label: "Inspector", keys: ["⌥⌘I"]),
        ShortcutRow(label: "Focus Mode / Typewriter Scrolling", keys: ["⌥⌘F", "⌥⌘T"]),
        ShortcutRow(label: "This page", keys: ["⌘?"]),
    ]

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard shortcuts")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(Self.shortcutRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(HelpPalette.border).frame(height: 1)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label)
                            if let note = row.note {
                                Text(note).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer(minLength: 12)
                        HStack(spacing: 6) {
                            ForEach(Array(row.keys.enumerated()), id: \.offset) { i, key in
                                if i > 0 { Text("/").foregroundColor(.secondary) }
                                KeyCap(text: key)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .modifier(CardStyle())
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Text("Press ⌘? at any time to open this page again.")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

/// Paper-toned rounded card with a hairline outline.
private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HelpPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HelpPalette.border, lineWidth: 1)
            )
    }
}

/// A small keyboard-key capsule.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(HelpPalette.keyFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(HelpPalette.border, lineWidth: 1)
            )
    }
}

/// Help ▸ How Kisho Works (replaces the default, empty "Kisho Help").
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("How Kisho Works") {
                openWindow(id: KishoHelpView.windowID)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

#endif
