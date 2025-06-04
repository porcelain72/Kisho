//
//  KishoDocumentView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//
import SwiftUI
import Combine


struct KishoDocumentView: View {
  //  @Binding var document: KishoDocumentModel
   
    @State private var showDeleteAlert = false

    @EnvironmentObject var document : KishoDocumentModel

    @State private var focusTitle: Bool = false
    
    var body: some View {
        NavigationSplitView {
            
            KishoSidebarOutlineView()
                .environmentObject(self.document)
                .focusedValue(\.kishoDocumentModel, document)
                .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                .focusedValue(\.showDeleteAlert , $showDeleteAlert)

            .frame(minWidth: 220)
    
        } content: {
            if let sectionObject = document.selectedSection {
                KishoSectionEditorView(section: sectionObject, focusTitle: $focusTitle)
                    .frame(minWidth: 600)
                    .environmentObject(self.document)
                    .focusedValue(\.kishoDocumentModel, document)
                    .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                    .focusedValue(\.showDeleteAlert , $showDeleteAlert)

            }else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
                    .focusedValue(\.kishoDocumentModel, document)
                    .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                    .focusedValue(\.showDeleteAlert , $showDeleteAlert)

            }
            
        } detail: {
            if  let section = document.selectedSection {
                Text("Inspector view")
                    .focusedValue(\.kishoDocumentModel, document)
                    .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                    .focusedValue(\.showDeleteAlert , $showDeleteAlert)


            } else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
                    .focusedValue(\.kishoDocumentModel, document)
                    .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                    .focusedValue(\.showDeleteAlert , $showDeleteAlert)

            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    self.document.addSiblingSection()
                    focusTitle = true

                } label: {
                
                    Label("Add Child", systemImage: "plus")
                }
                .help("Add section at same level as selected")

            }
            ToolbarItem {
                Button {
                    self.document.addChildSection()
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
            
            
        }
        .alert("Delete Section?",
               isPresented: $showDeleteAlert,
               actions: {
            Button("Delete") {
             
                    document.deleteSection()
                }
            .keyboardShortcut(.defaultAction)
            
            
            Button("Cancel", role: .cancel) { }
        },
               message: {
            Text("Are you sure you want to delete the selected section? All child sections will be deleted.")
        }
        )
        
    }

    

    
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


