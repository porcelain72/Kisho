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
    @Environment(\.undoManager) private var undoManager

    @EnvironmentObject var document : KishoDocumentModel

    // Track whether to show the export‐choice sheet:
    @State private var showingExportOptions = false
    /// Bumped on every undo-manager checkpoint so the Undo/Redo toolbar
    /// buttons re-evaluate `canUndo`/`canRedo`.
    @State private var undoCheckpoint = 0
    

    
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
                .focusedValue(\.kishoDocumentModel, document)
                .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                .focusedValue(\.showDeleteAlert , $showDeleteAlert)
                .frame(minWidth: 220)
    
        } detail: {
            KishoDocumentEditorView(document: document)
                .environmentObject(self.document)
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
                    showingExportOptions = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .help("Export document as plain text, PDF or HTML")
         
                Button {
                    undoManager?.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.left")
                }
                .disabled(!(undoManager?.canUndo ?? false) || undoCheckpoint < 0)
                .help("Undo")
                 
                Button {
                    undoManager?.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.right")
                }
                .disabled(!(undoManager?.canRedo ?? false) || undoCheckpoint < 0)
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
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerCheckpoint)) { note in
            if let manager = undoManager, (note.object as AnyObject?) === manager {
                undoCheckpoint &+= 1
            }
        }
        .confirmationDialog(
            "Choose Export Format",
            isPresented: $showingExportOptions,
            titleVisibility: .visible
        ) {
            Button("Plain Text") {
                exportAsPlainText()
            }
            Button("PDF") {
                exportAsPDF()
            }
            Button("HTML") {
                let html = Exporter.htmlString(from: document.sections)
                let data = Data(html.utf8)
                let filename = "\(documentTitle).html"
                #if os(macOS)
                showSavePanel(for: data, defaultFileName: filename, allowedTypes: ["html", "htm"])
                #else
                #endif
            }
            Button("Cancel", role: .cancel) { }
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

 

    // MARK: –– Export Actions

    private func exportAsPlainText() {
        let fullText = Exporter.plainText(from: document.sections)
        let data = Data(fullText.utf8)
        let filename = "\(documentTitle).txt"
        #if os(macOS)
        showSavePanel(for: data, defaultFileName: filename, allowedTypes: ["txt"])
        #else
        #endif
    }

    private func exportAsPDF() {
        let fullAttr = Exporter.attributedText(from: document.sections)
        guard let pdfData = Exporter.pdfData(from: fullAttr) else {
            // Handle PDF generation failure if needed
            return
        }
        let filename = "\(documentTitle).pdf"
        #if os(macOS)
        showSavePanel(for: pdfData, defaultFileName: filename, allowedTypes: ["pdf"])
        #else
        
        #endif
    }


    #if os(macOS)
    /// Presents the standard NSSavePanel and writes the given data to the chosen file URL.
    private func showSavePanel(
        for data: Data,
        defaultFileName: String,
        allowedTypes: [String]
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    // Present an alert if write fails
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }
    #endif
    
}
