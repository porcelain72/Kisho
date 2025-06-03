//
//  KishoDocumentView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//
import SwiftUI

struct KishoDocumentView: View {
    @Binding var document: KishoDocumentModel
    @State private var selectedID: UUID?
    @State private var showDeleteAlert = false


    var body: some View {
        NavigationSplitView {
            
            KishoSidebarOutlineView(sections: $document.sections, selectedSectionID: $selectedID)
            .frame(minWidth: 220)
    
        } content: {
            if let selectedID,
               let sectionObject = findSection(with: selectedID, in: document.sections) {
                KishoSectionEditorView(section: sectionObject)
                    .frame(minWidth: 600)
            }
            
        } detail: {
            if let selectedID, let section = $document.sections.binding(for: selectedID) {
                // KishoInspectorView(section: section.wrappedValue)
                Text("Inspector view")
                
            } else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    addSiblingSection()
                } label: {
                    Label("Add Sibling", systemImage: "plus.square.on.square")
                }
                .help("Add section at same level as selected")
            }
            ToolbarItem {
                Button {
                    addChildSection()
                } label: {
                    Label("Add Child", systemImage: "plus")
                }
                .help("Add child section")
            }
            ToolbarItem {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Section", systemImage: "trash")
                }
                .disabled(selectedID == nil)
            }
            
            
        }
        .alert("Delete Section?",
               isPresented: $showDeleteAlert,
               actions: {
            Button("Delete", role: .destructive) { deleteSection() }
            Button("Cancel", role: .cancel) { }
        },
               message: {
            Text("Are you sure you want to delete the selected section? All child sections will be deleted.")
        }
        )
    }

        func deleteSection() {
              guard let selectedID else { return }
              if let idx = document.sections.firstIndex(where: { $0.id == selectedID }) {
                  document.sections.remove(at: idx)
                  self.selectedID = nil
                  return
              }
              deleteSectionRecursively(selectedID: selectedID, sections: $document.sections)
              self.selectedID = nil
          }

          private func deleteSectionRecursively(selectedID: UUID, sections: Binding<[KishoSection]>) {
              for idx in sections.wrappedValue.indices {
                  if let childIdx = sections.wrappedValue[idx].children.firstIndex(where: { $0.id == selectedID }) {
                      sections.wrappedValue[idx].children.remove(at: childIdx)
                      return
                  }
                  deleteSectionRecursively(selectedID: selectedID, sections: sections[idx].children)
              }
          }
        // Section insertion helpers as above...
    func addSiblingSection() {
        guard let selectedID else {
            document.sections.append(KishoSection(title: "New Section"))
            return
        }
        addSiblingSectionRecursively(selectedID: selectedID, sections: $document.sections)
    }

    private func addSiblingSectionRecursively(selectedID: UUID, sections: Binding<[KishoSection]>) {
        for idx in sections.wrappedValue.indices {
            if sections.wrappedValue[idx].id == selectedID {
                let newSection = KishoSection(title: "New Sibling Section")
                sections.wrappedValue.insert(newSection, at: idx + 1)
                return
            }
            addSiblingSectionRecursively(selectedID: selectedID, sections: sections[idx].children)
        }
    }

    func addChildSection() {
        guard let selectedID, let section = $document.sections.binding(for: selectedID) else {
            return
        }
        section.children.wrappedValue.append(KishoSection(title: "New Child Section"))
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


