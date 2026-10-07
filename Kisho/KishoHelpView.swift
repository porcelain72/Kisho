//
//  KishoHelpView.swift
//  Kisho
//
//  "How Kisho Works": the one page a new user needs. Shown once on first
//  launch and from Help ▸ How Kisho Works (⌘?).
//

import SwiftUI

#if os(macOS)

struct KishoHelpView: View {
    static let windowID = "kisho-help"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How Kisho Works")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Long-form writing as a stack of named blocks.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                topic("Blocks",
                      "A Kisho document is a tree of blocks. Each block has a title, a body and optional tags. The sidebar shows the tree; the editor shows every block as a card, in reading order, nested blocks indented under their parents. Click a card or a sidebar row to select a block.")

                topic("Adding and arranging",
                      "⌘= adds a block after the selected one; ⇧⌘= adds one inside it. Drag rows in the sidebar to move blocks — onto a row to nest, between rows to reorder. In a block's title, Tab nests it under the block above and ⇧Tab moves it out again (⌘] and ⌘[ do the same anywhere); ⌥⌘↑ and ⌥⌘↓ swap a block with the one above or below it. Everything is undoable with ⌘Z.")

                topic("Split and Gather",
                      "Split (⌥⌘P) turns each paragraph of the selected block into its own child block, titled from its first sentence. Gather (⌥⌘G) does the reverse: it pulls the text of all sub-blocks back into the parent, in order, and removes them. Use them to go from a rough draft to a structure and back.")

                topic("Writing",
                      "Type in any card; the body grows as you write. ⌘B, ⌘I and ⌘U apply bold, italic and underline to the selection. The document's font and size are set in the inspector's Document section (or Format ▸ Document Font) and keep your bold/italic/underline. ⌘↩ in a body adds a new block right after the current one.")

                topic("Tags and filtering",
                      "Add tags to the selected block in the bar below the editor. When any block has tags, a filter appears above the sidebar: pick a tag to see only the blocks carrying it (their parents stay visible, dimmed, for context).")

                topic("Planning with the inspector",
                      "View ▸ Show Inspector (⌥⌘I) opens a panel for the selected block: a status (Draft, Revised, Final, Done), one of eight colours, a synopsis and private notes. The sidebar shows the colour as a dot and the status as a small symbol, and View ▸ Show Synopses puts each synopsis under its title — so the sidebar doubles as an outline you can plan in. Notes are never exported.")

                topic("Focus Mode and typewriter scrolling",
                      "View ▸ Enter Focus Mode (⌥⌘F) hides the sidebar and inspector and empties the toolbar, narrows the cards to a reading width and dims every block but the one you're in. Typewriter Scrolling (⌥⌘T) keeps the line you're typing at the centre of the window. View ▸ Editor Theme sets the editor to light, dark or sepia independently of the system; the Format menu has Bold, Italic, Underline and Document Font presets.")

                topic("Find and replace",
                      "⌘F searches titles, bodies and tags. Return or ⌘G steps through matches, ⇧⌘G steps back, ⌘E uses the selected text as the search term. Replace changes the current match; All changes every match in one undoable step and keeps each word's capitalisation.")

                topic("Export and import",
                      "File ▸ Export As writes the whole document as Plain Text, Markdown, Word (.docx with real heading styles), PDF or HTML. File ▸ Import Markdown… builds a new document from a Markdown file, one block per heading.")

                shortcuts
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 500)
    }

    private func topic(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let shortcutRows: [(String, String)] = [
        ("Add block after", "⌘="),
        ("Add block inside", "⇧⌘="),
        ("Add block from body", "⌘↩"),
        ("Delete block", "⇧⌘⌫"),
        ("Indent / outdent block", "⌘] / ⌘[  (Tab / ⇧Tab in a title)"),
        ("Move block up / down", "⌥⌘↑ / ⌥⌘↓"),
        ("Split paragraphs into blocks", "⌥⌘P"),
        ("Gather sub-blocks", "⌥⌘G"),
        ("Next / previous block", "⌃⌘↓ / ⌃⌘↑"),
        ("Into first child / up to parent", "⌃⌘→ / ⌃⌘←"),
        ("Bold / italic / underline", "⌘B / ⌘I / ⌘U"),
        ("Find", "⌘F"),
        ("Find next / previous", "⌘G / ⇧⌘G"),
        ("Use selection for find", "⌘E"),
        ("Inspector", "⌥⌘I"),
        ("Focus Mode / Typewriter Scrolling", "⌥⌘F / ⌥⌘T"),
        ("This page", "⌘?"),
    ]

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard shortcuts").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                ForEach(Self.shortcutRows, id: \.0) { row in
                    GridRow {
                        Text(row.0)
                        Text(row.1).monospaced().foregroundStyle(.secondary)
                    }
                }
            }
        }
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
