//
//  KishoApp.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

import SwiftUI


enum NavDestination : Hashable {
    case section(UUID)
}


@main
struct KishoApp: App {
    @State  var navigationPath : NavigationPath = NavigationPath()

    init() {
        #if os(macOS)
        // Configure spell checker to use the language from the user's
        // system preferences / locale rather than defaulting to en-US.
        if let preferredLanguage = Locale.preferredLanguages.first {
            NSSpellChecker.shared.setLanguage(preferredLanguage)
        }
        #endif
    }

    var body: some Scene {
        DocumentGroup(newDocument: { KishoDocument() }) { file in
#if os(macOS)
            KishoDocumentView(fileURL: file.fileURL)
                .environmentObject(file.document.model)
                .frame(minWidth: 1200, idealWidth: 1800, minHeight: 800, idealHeight: 1200)
#else
            KishoDocumentView(fileURL: file.fileURL)
                .environmentObject(file.document.model)
#endif
        }
        #if os(macOS)
        .commands {
            SectionEditCommands()
            ExportCommands()
            FindCommands()
            HelpCommands()
            PrintCommands()
            InspectorCommands()
            ViewModeCommands()
            FormatCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            KishoSettingsView()
        }

        Window("How Kisho Works", id: KishoHelpView.windowID) {
            KishoHelpView()
        }
        .defaultSize(width: 620, height: 720)
        #endif
    }
}

#if os(macOS)
/// File ▸ Import Markdown… / Import OPML… and Export As … items.
struct ExportCommands: Commands {
    @FocusedValue(\.kishoDocumentModel) private var documentModel

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import Markdown…") { Markdown.importIntoNewDocument() }
            Button("Import OPML…") { OPML.importIntoNewDocument() }
            Menu("Export As") {
                ForEach(Exporter.Format.allCases) { format in
                    Button("\(format.title)…") {
                        guard let documentModel else { return }
                        Exporter.export(documentModel, as: format, title: Exporter.keyWindowDocumentTitle)
                    }
                }
            }
            .disabled(documentModel == nil)
        }
    }
}

/// A `Commands` block that injects into the Edit menu right after Paste/Cut/Copy.
struct SectionEditCommands: Commands {
    // 1) Grab the document model from FocusedValues:
    @FocusedValue(\.kishoDocumentModel) private var documentModel
    // 2) Grab the selected section ID binding (in order to enable/disable):
    @FocusedBinding(\.selectedSectionID) private var selectedSectionID

    @FocusedBinding(\.showDeleteAlert) private var showDelete

    /// The undo manager of the document window the user is working in, looked
    /// up when a command runs (never cached: a cached one would belong to
    /// whichever window happened to be key first, or be nil at launch).
    private var activeUndoManager: UndoManager? {
        NSApp.keyWindow?.undoManager
    }

    /// The focused binding is doubly optional (no focused window / nothing selected).
    private var currentSectionID: UUID? { selectedSectionID ?? nil }

    var body: some Commands {
        CommandGroup(after: .pasteboard) {

            Button("Next Block") {
                documentModel?.selectNext()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .control])
            .disabled(documentModel == nil)

            Button("Previous Block") {
                documentModel?.selectPrevious()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .control])
            .disabled(documentModel == nil)

            Button("Level Down") {
                documentModel?.selectDown()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
            .disabled(documentModel == nil)

            Button("Level Up") {
                documentModel?.selectUp()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
            .disabled(documentModel == nil)

            Divider()

            // Toolbar buttons carry the ⌘= / ⇧⌘= shortcuts.
            Button("Add Sibling Block") {
                documentModel?.addSiblingSection(using: activeUndoManager)
            }
            .disabled(documentModel == nil)

            Button("Add Child Block") {
                documentModel?.addChildSection(using: activeUndoManager)
            }
            .disabled(selectedSectionID == nil)

            Button("Split Paragraphs into Blocks") {
                documentModel?.makeChildren(undoManager: activeUndoManager)
            }
            .disabled(selectedSectionID == nil)

            Button("Gather Sub-blocks") {
                documentModel?.gather(undoManager: activeUndoManager)
            }
            .disabled(selectedSectionID == nil)

            Divider()

            // Outliner moves. Tab / ⇧Tab in a block title do the same.
            Button("Indent Block") {
                documentModel?.indentSelectedSection(using: activeUndoManager)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(currentSectionID.flatMap { documentModel?.canIndent(sectionID: $0) } != true)

            Button("Outdent Block") {
                documentModel?.outdentSelectedSection(using: activeUndoManager)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(currentSectionID.flatMap { documentModel?.canOutdent(sectionID: $0) } != true)

            Divider()

            // ⇧⌘⌫ — plain ⌘⌫ is "delete to beginning of line" in the text editor.
            Button("Delete Block…") {
                showDelete = true
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(selectedSectionID == nil)
        }
    }
}
#endif
