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

    @State private var treeShowing = true
    
    let fileURL : URL?
    
    /// A computed “title” that tracks the file’s name if available,
      /// otherwise falls back to your model’s internal title (or “Untitled”).
    private var documentTitle: String {
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return  "Untitled"
       
    }
    
    @ViewBuilder private func treeView() -> some View {
        
    }
    
   
    var body: some View {
        Group{
        if treeShowing == true {
            KishoSidebarOutlineView(showDeleteAlert: $showDeleteAlert)
                .transition(.move(edge: .leading))
                
                .environmentObject(self.document)
        } else {
            if let sectionID = document.selectedSectionID,
               let sectionObject = document.section(withID:sectionID, inSections: document.sections) {
                KishoSectionEditorView(section: sectionObject)
                    .transition(.move(edge: .trailing))

                    .environmentObject(self.document)
            } else {
                Text("No selection")
            }
        }
   

        }
        .animation(.easeInOut, value: treeShowing)
        .onChange(of: document.selectedSectionID, { oldValue, newValue in
            self.treeShowing = false
        })
        
        
       
        
      
        /*
        NavigationSplitView {
            
          
                
    
        } content: {
            if let sectionObject = document.selectedSection {
                KishoSectionEditorView(section: sectionObject, focusTitle: $focusTitle)
                    .environmentObject(self.document)
                   
            }else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
              
            }
            
        } detail: {
            
            if  let section = document.selectedSection {
                KishoInspectorView(section: section)
                               .environmentObject(self.document)
    } else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
              
            }
        }
         */
        .toolbar {
            ToolbarItem {
                Button {
                    //showingExportOptions = true
                    treeShowing.toggle()
                } label: {
                    Label("Show outline…", systemImage: "list.number")
                }

                .help("Create new subsections from paragraphs")
                
            }
            
            ToolbarItem {
                Button {
                    //showingExportOptions = true
                    document.makeChildren(undoManager: undoManager)
                } label: {
                    Label("Split…", systemImage: "square.fill.text.grid.1x2")
                }

                .help("Create new subsections from paragraphs")
                
            }
            ToolbarItem {
                Button {
                    showingExportOptions = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .help("Export document as Plaintext or pdf")
                
            }
            ToolbarItem {
              Button {
                undoManager?.undo()
              } label: {
                Label("Undo", systemImage: "arrow.uturn.left")
              }
              .disabled(!(undoManager?.canUndo ?? false))
            }

            ToolbarItem {
                 
              Button {
                undoManager?.redo()
              } label: {
                Label("Redo", systemImage: "arrow.uturn.right")
              }
              .disabled(!(undoManager?.canRedo ?? false))
            }
            
            ToolbarItem {
                Button {
                    document.addSiblingSection(using: undoManager)
                    focusTitle = true

                } label: {
                
                    Label("Add Child", systemImage: "plus")
                }
                .help("Add section at same level as selected")

            }
            ToolbarItem {
                Button {
                    document.addChildSection(using: undoManager)
                    focusTitle = true

                } label: {
                    Label("Add Sibling", systemImage: "plus.square.on.square")
                }
                .disabled(document.selectedSection == nil)
                .help("Add child section")

            }
            ToolbarItem {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Section", systemImage: "trash")
                }
                .disabled(document.selectedSection == nil)
            }
            ToolbarItem {
                Button {
                    //showingExportOptions = true
                    document.gather(undoManager: undoManager)
                } label: {
                    Label("Gather…", systemImage: "rectangle.compress.vertical")
                }

                .help("Gather all child content into section")
                
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


