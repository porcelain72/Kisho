//
//  KishoApp.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

import SwiftUI

@main
struct KishoApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: KishoDocument()) { file in
            KishoDocumentView(fileURL: file.fileURL)
                .environmentObject(file.document.model)
                .frame(minWidth: 1200, idealWidth: 1800, minHeight: 800, idealHeight: 1200)

        }
        #if os(macOS)
        .commands {
            SectionEditCommands()
        }
        #endif
    }
}

#if os(macOS)
let undoManager = NSApp.keyWindow?.undoManager

/// A `Commands` block that injects into the Edit menu right after Paste/Cut/Copy.
struct SectionEditCommands: Commands {
    // 1) Grab the document model from FocusedValues:
    @FocusedValue(\.kishoDocumentModel) private var documentModel
    // 2) Grab the selected section ID binding (in order to enable/disable):
    @FocusedBinding(\.selectedSectionID) private var selectedSectionID
    
    @FocusedBinding(\.showDeleteAlert) private var showDelete
    
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            
            Button("Next") {
                documentModel?.selectNext()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            Button("Previous") {
                documentModel?.selectPrevious()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            
            Button("Level down") {
                documentModel?.selectDown()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            
            Button("Level up") {
                documentModel?.selectUp()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            
            // Add Sibling Section  ⌘.
            Button("Add Sibling Section") {
                guard let man = undoManager else { fatalError()}
                documentModel?.addSiblingSection(using: undoManager)
            }
           // .keyboardShortcut("=", modifiers: [.command])
           // .disabled(selectedSectionID == nil)
            
            // Add Child Section  ⇧⌘.
            Button("Add Child Section") {
                guard let man = undoManager else { fatalError()}

                documentModel?.addChildSection(using: undoManager)
            }
           // .keyboardShortcut("+", modifiers: [.command, .shift])
           // .disabled(selectedSectionID == nil)
            
            Divider()
            
            // Delete Section  ⌘⌫
            Button("Delete Section") {
                showDelete?.toggle()
            }
            .keyboardShortcut(.delete, modifiers: .command)
          //  .disabled(selectedSectionID == nil)
        }
    }
}
#endif

