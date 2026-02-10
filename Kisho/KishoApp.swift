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
        DocumentGroup(newDocument: KishoDocument()) { file in
            
              
#if os(macOS)
                
                KishoDocumentView(fileURL: file.fileURL)
                    .environmentObject(file.document.model)
                    .frame(minWidth: 1200, idealWidth: 1800, minHeight: 800, idealHeight: 1200)
                
#else
                KishoDocumentView(fileURL: file.fileURL)
                    .environmentObject(file.document.model)
            /*
            .onChange(of: file.document.model.selectedSectionID, { oldValue, newValue in
                if let sectionObjectID = newValue {
                    self.navigationPath.append(NavDestination.section(sectionObjectID))
                }
            })
             */
#endif
            
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
            .keyboardShortcut(.downArrow, modifiers: [.command])

            Button("Previous") {
                documentModel?.selectPrevious()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            
            Button("Level down") {
                documentModel?.selectDown()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            
            Button("Level up") {
                documentModel?.selectUp()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            
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

