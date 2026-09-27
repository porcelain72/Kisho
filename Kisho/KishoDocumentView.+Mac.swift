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

    @State private var focusTitle: Bool = false
    // Track whether to show the export‐choice sheet:
    @State private var showingExportOptions = false
    
    @State private var fontFamilies: [String] = []
    @State private var selectedFontFamily: String = NSFont.systemFont(ofSize: 12).familyName ?? "System"
    @State private var fontSize: Double = 12
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false

    
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
                    //showingExportOptions = true
                    document.makeChildren(undoManager: undoManager)
                } label: {
                    Label("Split…", systemImage: "square.fill.text.grid.1x2")
                }
                .keyboardShortcut("p", modifiers: .command)

                .help("Create new subsections from paragraphs")
                
          
                Button {
                    //showingExportOptions = true
                    document.gather(undoManager: undoManager)
                } label: {
                    Label("Gather…", systemImage: "rectangle.compress.vertical")
                }
                .keyboardShortcut("o", modifiers: [.command])

                .help("Gather all child content into section")
                
  
                Button {
                    showingExportOptions = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .help("Export document as Plaintext or pdf")
         
              Button {
                undoManager?.undo()
              } label: {
                Label("Undo", systemImage: "arrow.uturn.left")
              }
              .keyboardShortcut("z", modifiers: .command)
              .disabled(!(undoManager?.canUndo ?? false))
         
                 
              Button {
                undoManager?.redo()
              } label: {
                Label("Redo", systemImage: "arrow.uturn.right")
              }
              .keyboardShortcut("z", modifiers: [.command, .shift])
              .disabled(!(undoManager?.canRedo ?? false))
           
                Button {
                    document.addSiblingSection(using: undoManager)
                    focusTitle = true

                } label: {
                
                    Label("Add Child", systemImage: "plus")
                }
                 .keyboardShortcut("=", modifiers: [.command])
                .help("Add section at same level as selected")

                Button {
                    document.addChildSection(using: undoManager)
                    focusTitle = true

                } label: {
                    Label("Add Sibling", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("+", modifiers: [.command, .shift])
                .disabled(document.selectedSection == nil)
                .help("Add child section")

         
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Section", systemImage: "trash")
                }
                .disabled(document.selectedSection == nil)
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
    
    // Anywhere in your code (e.g. in DocumentView.swift)

    /// Walks the entire hierarchy and returns the KishoSection whose `id` matches.
    func findSection(
        with targetID: UUID,
        in sections: [KishoSection]
    ) -> KishoSection? {
        for s in sections {
            if s.id == targetID { return s }
            if let childMatch = findSection(with: targetID, in: s.children) {
                return childMatch
            }
        }
        return nil
    }

}




// Helper for deep bindings
extension Array where Element: Identifiable {
    var binding: Binding<[Element]> {
        .constant(self)
    }
}

struct SectionEditor: View {
    @Binding var section: KishoSection

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Title", text: $section.title)
                .font(.title)
            // Add more section editing UI here
        }
        .padding()
    }
}


