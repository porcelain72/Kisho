//
//  KishoDocumentModel.swift
//  Kisho
//
//  Created by Peter Macdonald on 03/06/2025.
//

import SwiftUI

final class KishoDocumentModel: ObservableObject, Codable {
    @Published var sections: [KishoSection]
    @Published var selectedSectionID : UUID? = nil
    
    enum CodingKeys: String, CodingKey { case sections }
    
    var selectedSection : KishoSection? {
        get {
            guard let id = self.selectedSectionID else { return nil}
            return self.section(withID: id, inSections: self.sections)
        }
    }
    init(sections: [KishoSection] = [KishoSection(title: "Untitled Section")]) {
        self.sections = sections
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([KishoSection].self, forKey: .sections)
        self.sections = decoded
        // Fix parent pointers
        func fixParents(_ list: [KishoSection]) {
            for s in list {
                for child in s.children {
                    child.parent = s
                    fixParents([child])
                }
            }
        }
        fixParents(self.sections)
    }
    
    func select(section: KishoSection) {
        DispatchQueue.main.async{
            print("Selecting\(section.title)")
            self.selectedSectionID = section.id
        }
    }
    
    func selectNext(){
        DispatchQueue.main.async{
            self.self.selectedSectionID = self.nextSectionID()
        }
    }
    
    func selectPrevious(){
        DispatchQueue.main.async{
            self.self.selectedSectionID = self.previousSectionID()
        }
    }

    
    // MARK: –– Undo‐aware move (as sibling)
    func moveAsSibling(draggedID: UUID, destinationID: UUID, insertBefore: Bool, using undoManager: UndoManager? = nil) {
      // Locate the “dragged” section and remove it
      guard let dragged = removeSection(withID: draggedID),
            let destParent = parent(forSectionID: destinationID, inSections: sections)
      else {
        // Could be moving at top level
        // Similar logic would go here…
        return
      }
      // Compute “undo” by remembering old parent and index
      let originalParentID = parent(forSectionID: draggedID, inSections: sections)?.id
      let originalIndex: Int
      if let pID = originalParentID,
         let p = section(withID: pID, inSections: sections),
         let i = p.children.firstIndex(where: { $0.id == draggedID })
      {
        originalIndex = i
      } else if let i = sections.firstIndex(where: { $0.id == draggedID }) {
        originalIndex = i
      } else {
        originalIndex = 0
      }

      // Register undo: move back to original parent/index
      undoManager?.registerUndo(withTarget: self) { target in
        if let origParentID = originalParentID {
          if let origParent = target.section(withID: origParentID, inSections: target.sections) {
            origParent.children.insert(dragged, at: originalIndex)
            target.selectedSectionID = draggedID
          }
        } else {
          target.sections.insert(dragged, at: originalIndex)
          target.selectedSectionID = draggedID
        }
      }
      undoManager?.setActionName("Move Section")

      // Now insert under the new parent
      if destParent.id == dragged.id {
        // If dragging a parent onto itself, ignore
        return
      }
      if let idx = destParent.children.firstIndex(where: { $0.id == destinationID }) {
        destParent.children.insert(dragged, at: insertBefore ? idx : idx + 1)
        self.selectedSectionID = draggedID
      }
    }
    
    /*
    
    // Move as sibling (above/below)
     func moveAsSibling(draggedID: UUID, destinationID: UUID, insertBefore: Bool) {

         if let parent = self.parent(forSectionID: destinationID, inSections: self.sections)
         {
             guard  draggedID != parent.id else { return }

             if let draggingSection = self.removeSection(withID: draggedID),
                  let idx = parent.children.firstIndex(where: { $0.id == destinationID }) {
                     
                     parent.children.insert(draggingSection, at: insertBefore ? idx : idx + 1)
                 }
             
         } else {
             
             if let draggingSection = self.removeSection(withID: draggedID),
                let idx = self.sections.firstIndex(where: { $0.id == destinationID }) {
                
                 self.sections.insert(draggingSection, at: insertBefore ? idx : idx + 1)
             }
         }
         

        
    }
*/
    // Move as child (on)
     func moveAsChild(draggedID: UUID, destinationID: UUID) {
        
        if let dragged = removeSection(withID: draggedID),
           let parent = self.section(withID: destinationID, inSections: self.sections),
           dragged.id != parent.id
        {
            parent.children.append(dragged)
        }
    }
    
    /*
    func deleteSection()  {
        guard let selected = self.self.selectedSectionID else { return }
        
        if var parent = self.parent(forSectionID: selected, inSections: self.sections),
        let sIndex = parent
            .children.firstIndex(where: {$0.id == selected}){
            
            DispatchQueue.main.async{
                parent.children.remove(at: sIndex)
             
            }
        } else {
            if let sIndex = self.sections.firstIndex(where: {$0.id == selected}){
                
                DispatchQueue.main.async{
                    self.sections.remove(at: sIndex)
                    
                }
                
            }
            self.selectedSectionID = nil
        }
      
        return
        }
*/
    // MARK: –– Undo‐aware deletion of the selected section
    func deleteSelectedSection(using undoManager: UndoManager? = nil) {
      guard let idToDelete = selectedSectionID else { return }
      // First, capture a deep copy of the section being deleted (so we can re‐insert it on undo)
      guard let toDelete = section(withID: idToDelete, inSections: sections) else {
        return
      }
      // Find its parent (if any) and index
      if let parent = parent(forSectionID: idToDelete, inSections: sections),
         let idx = parent.children.firstIndex(where: { $0.id == idToDelete })
      {
        // Register undo to re‐insert this child at the same index
        undoManager?.registerUndo(withTarget: self) { target in
          if let p = target.section(withID: parent.id, inSections: target.sections) {
            p.children.insert(toDelete, at: idx)
            target.selectedSectionID = toDelete.id
          }
        }
        undoManager?.setActionName("Delete Section")

        // Perform delete
        parent.children.remove(at: idx)
        self.selectedSectionID = parent.id
      } else if let idx = sections.firstIndex(where: { $0.id == idToDelete }) {
        // Top‐level section
        undoManager?.registerUndo(withTarget: self) { target in
          target.sections.insert(toDelete, at: idx)
          target.selectedSectionID = toDelete.id
        }
        undoManager?.setActionName("Delete Section")

        sections.remove(at: idx)
        self.selectedSectionID = nil
      }
    }
    
    public func depth(forSection: KishoSection) -> Int {
        var depth = 0
   
        var parent  = self.parent(forSectionID: forSection.id, inSections: self.sections)
        
        while let pa = parent{
            depth = depth + 1
            parent = self.parent(forSectionID: pa.id, inSections: self.sections)
        }
        
        return depth
    }
    
// Section insertion helpers as above...
    func addSiblingSection(using undoManager: UndoManager? = nil) {
        if let sect = self.selectedSectionID {
            
            if let parent = self.parent(forSectionID: sect, inSections: self.sections) {
                let title = String(parent.children.count+1)
                let new = KishoSection(title: title)
          
                // Register undo: re‐remove that child from parent
                undoManager?.registerUndo(withTarget: self) { target in
                  // On undo, remove the child from parent
                    if let p = target.section(withID: parent.id, inSections: target.sections),
                     let idx = p.children.firstIndex(where: { $0.id == new.id })
                  {
                    p.children.remove(at: idx)
                        target.selectedSectionID = parent.id
                  }
                }
                undoManager?.setActionName("Add Child Section")
                parent.children.append(new)
                self.self.selectedSectionID = new.id

            } else {
                let title = String(self.sections.count+1)
                let new = KishoSection(title: title)
                
                undoManager?.registerUndo(withTarget: self, handler: { target in
                    target.removeSection(withID: new.id, using: undoManager)

                })
                undoManager?.setActionName("Add Sibling")
                
                self.sections.append(new)
                self.selectedSectionID = new.id
            }
            
            
            return
        } else {
            let title = String(self.sections.count+1)
            let new = KishoSection(title: title)
            
            undoManager?.registerUndo(withTarget: self, handler: { target in
                target.removeSection(withID: new.id, using: undoManager)

            })
            undoManager?.setActionName("Add Sibling")
            
            self.sections.append(new)
            self.selectedSectionID = new.id
        }
    }
    
    /*
    func addChildSection() {
        if let selectedID = selectedSectionID,
           let selected = self.section(withID: selectedID, inSections: self.sections){
            let title = String(selected.children.count+1)
            let new = KishoSection(title: title)

            selected.children.append(new)
            self.selectedSectionID = new.id
        } else {
            let title = String(self.sections.count+1)
            let new = KishoSection(title: title)

            self.sections.append(new)
            self.selectedSectionID = new.id

            
        }
        
        
    }
    */
    // MARK: –– Undo‐aware insertion of a child
    func addChildSection(using undoManager: UndoManager? = nil) {
      guard let parentID = selectedSectionID,
            let parent = section(withID: parentID, inSections: sections)
      else {
        // No selection—just append a top‐level section
        let newTitle = String(self.sections.count + 1)
        let newSection = KishoSection(title: newTitle)

        // Register undo to remove the last element
        undoManager?.registerUndo(withTarget: self) { target in
          // Undoing: remove that last element
          target.removeSection(withID: newSection.id, using: undoManager)
        }
        undoManager?.setActionName("Add Section")

        // Perform the actual insertion
        self.sections.append(newSection)
        self.selectedSectionID = newSection.id
        return
      }

      // If a parent is selected, insert child into `parent.children`
      let newTitle = String(parent.children.count + 1)
      let newSection = KishoSection(title: newTitle)

      // Register undo: re‐remove that child from parent
      undoManager?.registerUndo(withTarget: self) { target in
        // On undo, remove the child from parent
        if let p = target.section(withID: parentID, inSections: target.sections),
           let idx = p.children.firstIndex(where: { $0.id == newSection.id })
        {
          p.children.remove(at: idx)
          target.selectedSectionID = parentID
        }
      }
      undoManager?.setActionName("Add Child Section")

      // Perform the insertion
      parent.children.append(newSection)
      self.selectedSectionID = newSection.id
    }


    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sections, forKey: .sections)
    }
    

}

private extension KishoDocumentModel {
    

    func nextSectionID() -> UUID? {
        var nextSection = self.sections.first
        
        if let selectedID = selectedSectionID,
           let siblings = siblings(forID: selectedID, inSections: self.sections),
           let index = siblings.firstIndex(where: {$0.id == selectedID}){
            if index<(siblings.count-1) {
                nextSection = siblings[index+1]
            } else {
                // Next next candidate
            }
        }
        
        return nextSection?.id
    }
    
    func previousSectionID() -> UUID? {
        var nextSection = self.sections.first
        
        if let selected = selectedSectionID,
           let siblings = siblings(forID: selected, inSections: self.sections),
           let index = siblings.firstIndex(where: {$0.id == selected}),
           index>0 {
            nextSection = siblings[index-1]
        }
        
        return nextSection?.id
    }
    // Remove section and return it
    func removeSection(withID id: UUID, using undoManager: UndoManager? = nil) -> KishoSection? {
        
        if let parent = self.parent(forSectionID: id, inSections: self.sections) ,
           let idx = parent.children.firstIndex(where: {$0.id == id}){
            
            undoManager?.registerUndo(withTarget: self, handler: { target in
               // target.removeSection(withID: new.id, using: undoManager)
                if let p = target.section(withID: parent.id, inSections: target.sections),
                   let idx = p.children.firstIndex(where: { $0.id == newSection.id })
                {
                  p.children.remove(at: idx)
                  target.selectedSectionID = parentID
                }
            })
            undoManager?.setActionName("Add Sibling")
            
           return parent.children.remove(at: idx)
        } else {
            if let idx = self.sections.firstIndex(where: {$0.id == id}){
                return self.sections.remove(at: idx)
            }
        }
        
      
        return nil
    }
    
    func section(withID id: UUID, inSections: [KishoSection]) -> KishoSection? {
      for s in inSections {
        if s.id == id { return s }
        if let found = section(withID: id, inSections: s.children) {
          return found
        }
      }
      return nil
    }
    
    
    func parent(forSectionID id: UUID, inSections: [KishoSection]) -> KishoSection? {
      for s in inSections {
        if s.children.contains(where: { $0.id == id }) {
          return s
        }
        if let sub = parent(forSectionID: id, inSections: s.children) {
          return sub
        }
      }
      return nil
    }
    
    
    func siblings(forID: UUID, inSections: [KishoSection]) -> [KishoSection]? {
        
        for idx in inSections.indices {
             let sect = inSections[idx]
              if sect.id == forID {
                return inSections
            }
        }
        
        for idx in inSections.indices {
            if let returnSections = self.siblings(forID: forID, inSections: inSections[idx].children) {
                return returnSections
            }
        }
        
        return nil
    
    }
    
    
}

// RTF helpers
extension NSAttributedString {
    func rtfData() -> Data {
        (try? self.data(from: NSRange(location: 0, length: length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    static func fromRTF(data: Data) -> NSAttributedString? {
        try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    }
}

extension FocusedValues {
    // 1) A key for passing the document model down the responder chain
    private struct DocumentModelKey: FocusedValueKey {
        typealias Value = KishoDocumentModel
    }
    var kishoDocumentModel: KishoDocumentModel? {
        get { self[DocumentModelKey.self] }
        set { self[DocumentModelKey.self] = newValue }
    }

    // 2) A key for passing the selected‐section ID (a Binding<UUID?>)
    private struct SelectedSectionIDKey: FocusedValueKey {
        typealias Value = Binding<UUID?>
    }
    var selectedSectionID: Binding<UUID?>? {
        get { self[SelectedSectionIDKey.self] }
        set { self[SelectedSectionIDKey.self] = newValue }
    }
    
    // 2) A key for passing the selected‐section ID (a Binding<UUID?>)
    private struct ShowDeleteAlertKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }
    var showDeleteAlert: Binding<Bool>? {
        get { self[ShowDeleteAlertKey.self] }
        set { self[ShowDeleteAlertKey.self] = newValue }
    }
}


final class KishoDocumentModrl: ObservableObject, Codable {
  @Published var sections: [KishoSection]
  @Published var selectedSectionID: UUID? = nil

  var selectedSection: KishoSection? {
    guard let id = selectedSectionID else { return nil }
    return section(withID: id, inSections: sections)
  }

  init(sections: [KishoSection] = [KishoSection(title: "Untitled Section")]) {
    self.sections = sections
  }

  // … Codable conformance …

  // MARK: –– Undo‐aware insertion of a child
  func addChildSection(using undoManager: UndoManager? = nil) {
    guard let parentID = selectedSectionID,
          let parent = section(withID: parentID, inSections: sections)
    else {
      // No selection—just append a top‐level section
      let newTitle = String(self.sections.count + 1)
      let newSection = KishoSection(title: newTitle)

      // Register undo to remove the last element
      undoManager?.registerUndo(withTarget: self) { target in
        // Undoing: remove that last element
        target.removeSection(withID: newSection.id, using: undoManager)
      }
      undoManager?.setActionName("Add Section")

      // Perform the actual insertion
      self.sections.append(newSection)
      self.selectedSectionID = newSection.id
      return
    }

    // If a parent is selected, insert child into `parent.children`
    let newTitle = String(parent.children.count + 1)
    let newSection = KishoSection(title: newTitle)

    // Register undo: re‐remove that child from parent
    undoManager?.registerUndo(withTarget: self) { target in
      // On undo, remove the child from parent
      if let p = target.section(withID: parentID, inSections: target.sections),
         let idx = p.children.firstIndex(where: { $0.id == newSection.id })
      {
        p.children.remove(at: idx)
        target.selectedSectionID = parentID
      }
    }
    undoManager?.setActionName("Add Child Section")

    // Perform the insertion
    parent.children.append(newSection)
    self.selectedSectionID = newSection.id
  }

  // MARK: –– Undo‐aware deletion of the selected section
  func deleteSelectedSection(using undoManager: UndoManager? = nil) {
    guard let idToDelete = selectedSectionID else { return }
    // First, capture a deep copy of the section being deleted (so we can re‐insert it on undo)
    guard let toDelete = section(withID: idToDelete, inSections: sections) else {
      return
    }
    // Find its parent (if any) and index
    if let parent = parent(forSectionID: idToDelete, inSections: sections),
       let idx = parent.children.firstIndex(where: { $0.id == idToDelete })
    {
      // Register undo to re‐insert this child at the same index
      undoManager?.registerUndo(withTarget: self) { target in
        if let p = target.section(withID: parent.id, inSections: target.sections) {
          p.children.insert(toDelete, at: idx)
          target.selectedSectionID = toDelete.id
        }
      }
      undoManager?.setActionName("Delete Section")

      // Perform delete
      parent.children.remove(at: idx)
      self.selectedSectionID = parent.id
    } else if let idx = sections.firstIndex(where: { $0.id == idToDelete }) {
      // Top‐level section
      undoManager?.registerUndo(withTarget: self) { target in
        target.sections.insert(toDelete, at: idx)
        target.selectedSectionID = toDelete.id
      }
      undoManager?.setActionName("Delete Section")

      sections.remove(at: idx)
      self.selectedSectionID = nil
    }
  }

  // MARK: –– Undo‐aware move (as sibling)
  func moveAsSibling(draggedID: UUID, destinationID: UUID, insertBefore: Bool, using undoManager: UndoManager? = nil) {
    // Locate the “dragged” section and remove it
    guard let dragged = removeSection(withID: draggedID),
          let destParent = parent(forSectionID: destinationID, inSections: sections)
    else {
      // Could be moving at top level
      // Similar logic would go here…
      return
    }
    // Compute “undo” by remembering old parent and index
    let originalParentID = parent(forSectionID: draggedID, inSections: sections)?.id
    let originalIndex: Int
    if let pID = originalParentID,
       let p = section(withID: pID, inSections: sections),
       let i = p.children.firstIndex(where: { $0.id == draggedID })
    {
      originalIndex = i
    } else if let i = sections.firstIndex(where: { $0.id == draggedID }) {
      originalIndex = i
    } else {
      originalIndex = 0
    }

    // Register undo: move back to original parent/index
    undoManager?.registerUndo(withTarget: self) { target in
      if let origParentID = originalParentID {
        if let origParent = target.section(withID: origParentID, inSections: target.sections) {
          origParent.children.insert(dragged, at: originalIndex)
          target.selectedSectionID = draggedID
        }
      } else {
        target.sections.insert(dragged, at: originalIndex)
        target.selectedSectionID = draggedID
      }
    }
    undoManager?.setActionName("Move Section")

    // Now insert under the new parent
    if destParent.id == dragged.id {
      // If dragging a parent onto itself, ignore
      return
    }
    if let idx = destParent.children.firstIndex(where: { $0.id == destinationID }) {
      destParent.children.insert(dragged, at: insertBefore ? idx : idx + 1)
      self.selectedSectionID = draggedID
    }
  }

  // … similarly update moveAsChild(draggedID:destinationID:using:) to register undo …

  // MARK: –– Helpers for finding/removing
  func removeSection(withID id: UUID) -> KishoSection? {
    if let parent = parent(forSectionID: id, inSections: sections),
       let idx = parent.children.firstIndex(where: { $0.id == id })
    {
      return parent.children.remove(at: idx)
    } else if let idx = sections.firstIndex(where: { $0.id == id }) {
      return sections.remove(at: idx)
    }
    return nil
  }

  func section(withID id: UUID, inSections: [KishoSection]) -> KishoSection? {
    for s in inSections {
      if s.id == id { return s }
      if let found = section(withID: id, inSections: s.children) {
        return found
      }
    }
    return nil
  }

  func parent(forSectionID id: UUID, inSections: [KishoSection]) -> KishoSection? {
    for s in inSections {
      if s.children.contains(where: { $0.id == id }) {
        return s
      }
      if let sub = parent(forSectionID: id, inSections: s.children) {
        return sub
      }
    }
    return nil
  }

  // … and any other helpers (depth, siblings, etc.) unchanged …
}
