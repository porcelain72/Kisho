//
//  KishoDocumentView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct KishoDocumentView: View {
  //  @Binding var document: KishoDocumentModel
   
    @State private var showDeleteAlert = false
    @StateObject private var find = FindState()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @AppStorage(KishoPreferences.Key.hasShownWelcome) private var hasShownWelcome = false

    @EnvironmentObject var document : KishoDocumentModel

    // Track whether to show the export‐choice sheet:
    @State private var showingExportOptions = false
    

    
    let fileURL : URL?
    
    /// A computed “title” that tracks the file’s name if available,
      /// otherwise falls back to your model’s internal title (or “Untitled”).
    private var documentTitle: String {
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return  "Untitled"
       
    }
    
    var body: some View {
        NavigationSplitView {
            
            KishoSidebarOutlineView(showDeleteAlert: $showDeleteAlert)
                .environmentObject(self.document)
                .environmentObject(find)
                .focusedValue(\.kishoFindState, find)
                .focusedValue(\.kishoDocumentModel, document)
                .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                .focusedValue(\.showDeleteAlert , $showDeleteAlert)
                .frame(minWidth: 220)
    
        } detail: {
            KishoCardListEditorView()
                .environmentObject(self.document)
                .environmentObject(find)
                .focusedValue(\.kishoFindState, find)
                .focusedValue(\.kishoDocumentModel, document)
                .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                .focusedValue(\.showDeleteAlert , $showDeleteAlert)
        }
        .toolbar {
            ToolbarItemGroup {
                ToolbarTypographyControlsView()
          
                Button {
                    document.makeChildren(undoManager: undoManager)
                } label: {
                    Label("Split", systemImage: "square.fill.text.grid.1x2")
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(document.selectedSection == nil)
                .help("Split the selected section's paragraphs into sub-sections (⌥⌘P)")
                
                Button {
                    document.gather(undoManager: undoManager)
                } label: {
                    Label("Gather", systemImage: "rectangle.compress.vertical")
                }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(document.selectedSection?.children.isEmpty ?? true)
                .help("Gather all sub-section text back into the selected section (⌥⌘G)")
                
                Button {
                    find.show()
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .help("Find and replace across all blocks (⌘F)")

                Button {
                    showingExportOptions = true
                } label: {
                    Label("Export…", systemImage: "arrow.up.doc")
                }
                .help("Export document as plain text, Markdown, Word, PDF or HTML (also in the File menu)")
         
                Button {
                    undoManager?.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.left")
                }
                .disabled(!(undoManager?.canUndo ?? false))
                .help("Undo")
                 
                Button {
                    undoManager?.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.right")
                }
                .disabled(!(undoManager?.canRedo ?? false))
                .help("Redo")
           
                Button {
                    document.addSiblingSection(using: undoManager)
                } label: {
                    Label("Add Sibling", systemImage: "plus")
                }
                .keyboardShortcut("=", modifiers: [.command])
                .help("Add a section after the selected one, at the same level (⌘=)")

                Button {
                    document.addChildSection(using: undoManager)
                } label: {
                    Label("Add Child", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])
                .disabled(document.selectedSection == nil)
                .help("Add a sub-section inside the selected section (⇧⌘=)")

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Section", systemImage: "trash")
                }
                .disabled(document.selectedSection == nil)
                .help("Delete the selected section and its sub-sections (⇧⌘⌫)")
            }
        }
        .confirmationDialog(
            "Choose Export Format",
            isPresented: $showingExportOptions,
            titleVisibility: .visible
        ) {
            ForEach(Exporter.Format.allCases) { format in
                Button(format.title) {
                    Exporter.export(document, as: format, title: documentTitle)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear {
            // First launch: open the one-page guide beside the document.
            guard !hasShownWelcome else { return }
            hasShownWelcome = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                openWindow(id: KishoHelpView.windowID)
            }
        }
        .alert("Delete Section?",
               isPresented: $showDeleteAlert,
               actions: {
            Button("Delete") {
             
                document.deleteSelectedSection(using: undoManager)
                }
            .keyboardShortcut(.defaultAction)
            
            
            Button("Cancel", role: .cancel) { }
        },
               message: {
            Text("Are you sure you want to delete the selected section? All child sections will be deleted.")
        }
        )
        
    }

 

}
