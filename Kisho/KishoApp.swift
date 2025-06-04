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
            KishoDocumentView()
                .environmentObject(file.document.model)
              

        }
        .commands {
            SectionEditCommands()
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
    
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            
            Button("Next") {
                documentModel?.selectNext()
            }
            .keyboardShortcut("]", modifiers: [.command])

            Button("Previous") {
                documentModel?.selectPrevious()
            }
            .keyboardShortcut("[", modifiers: [.command])
            // Add Sibling Section  ⌘.
            Button("Add Sibling Section") {
                documentModel?.addSiblingSection()
            }
            .keyboardShortcut("=", modifiers: [.command])
            .disabled(selectedSectionID == nil)
            
            // Add Child Section  ⇧⌘.
            Button("Add Child Section") {
                documentModel?.addChildSection()
            }
            .keyboardShortcut("+", modifiers: [.command, .shift])
            .disabled(selectedSectionID == nil)
            
            Divider()
            
            // Delete Section  ⌘⌫
            Button("Delete Section") {
                showDelete?.toggle()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedSectionID == nil)
        }
    }
}


struct CustomShortcutMenu: Commands {
    @EnvironmentObject private var document: KishoDocumentModel

    var body: some Commands {
        CommandGroup( after: .pasteboard){
            Button("Next") {
                //document.selectNext()
            }
            .keyboardShortcut("K", modifiers: [.command, .shift])

            Button("Previous") {
              //  document.selectPrevious()
            }
            .keyboardShortcut("L", modifiers: [.command, .option])
        }
    }
}
