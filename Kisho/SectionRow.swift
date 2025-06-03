//
//  SectionRow.swift
//  Kisho
//
//  Created by Peter Macdonald on 02/06/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SectionRow: View {
    let section: KishoSection
    @Binding var selectedSectionID: UUID?
    @Binding var allSections: [KishoSection]
    var parentSections: Binding<[KishoSection]> // Parent array (for sibling drops)

    @State private var dropPosition: DropPosition?

    enum DropPosition { case above, on, below }

    var body: some View {
        VStack(spacing: 0) {
            // Drop above
            dropTargetView(position: .above)

            // The row content
            HStack {
                Text(section.title)
                    .padding(.leading, 4)
                    .background(selectedSectionID == section.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    .onTapGesture { selectedSectionID = section.id }
                Spacer()
            }
            .background(dropPosition == .on ? Color.accentColor.opacity(0.12) : Color.clear)
            .onDrag {
                NSItemProvider(object: section.id.uuidString as NSString)
            }
            .onDrop(of: [UTType.text], isTargeted: Binding(get: { dropPosition == .on }, set: { _ in }),
                    perform: { providers in handleDrop(providers: providers, position: .on) })

            // Drop below
            dropTargetView(position: .below)

            // Children, indented
            if !section.children.isEmpty {
                VStack(spacing: 0) {
                    ForEach(section.children) { child in
                        SectionRow(
                            section: child,
                            selectedSectionID: $selectedSectionID,
                            allSections: $allSections,      // <--- KEEP PASSING THE ROOT
                            parentSections: binding(for: section, in: $allSections)?.children ?? .constant([])
                        )
                        .padding(.leading, 20)
                    }


                }
            }
        }
        .background(dropPosition == .above || dropPosition == .below ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    // Drop target for above/below sibling insert
    @ViewBuilder
    private func dropTargetView(position: DropPosition) -> some View {
        Rectangle()
            .frame(height: 10)
            .foregroundColor(dropPosition == position ? Color.accentColor.opacity(0.22) : Color.clear)
            .onDrop(of: [UTType.text], isTargeted: Binding(
                get: { dropPosition == position }, set: { isOver in if !isOver { dropPosition = nil } }
            ), perform: { providers in handleDrop(providers: providers, position: position) })
    }

    // Drop handling for all three positions
    private func handleDrop(providers: [NSItemProvider], position: DropPosition) -> Bool {
        dropPosition = position // highlight
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            var idStr: String?
            if let data = item as? Data, let s = String(data: data, encoding: .utf8) { idStr = s }
            else if let s = item as? String { idStr = s }
            guard let idStr, let draggedID = UUID(uuidString: idStr), draggedID != section.id else { return }
            DispatchQueue.main.async {
                switch position {
                case .on:
                    moveAsChild(draggedID: draggedID)
                case .above:
                    moveAsSibling(draggedID: draggedID, insertBefore: true)
                case .below:
                    moveAsSibling(draggedID: draggedID, insertBefore: false)
                }
                dropPosition = nil
            }
        }
        return true
    }


    

    // Move as sibling (above/below)
    private func moveAsSibling(draggedID: UUID, insertBefore: Bool) {
        print("Sibling move with ID:\t\t\(draggedID.uuidString)")
        guard let parentArray = parentSections.wrappedValue as? [KishoSection] else { return }
        print("Removing from allSections:\n\t\(allSections.map{$0.id.uuidString})")
        if let dragged = removeSection(withID: draggedID, in: &allSections) {
            if let idx = parentSections.wrappedValue.firstIndex(where: { $0.id == section.id }) {
                parentSections.wrappedValue.insert(dragged, at: insertBefore ? idx : idx + 1)
            }
        }
    }

    // Move as child (on)
    private func moveAsChild(draggedID: UUID) {
        if let dragged = removeSection(withID: draggedID, in: &allSections) {
            if !section.children.contains(where: { $0.id == draggedID }) {
                if let selfBinding = binding(for: section, in: $allSections) {
                    selfBinding.children.wrappedValue.append(dragged)
                }
            }
        }
    }

    // Recursively get binding to target section or its children array
    private func binding(for target: KishoSection, in sections: Binding<[KishoSection]>) -> Binding<KishoSection>? {
        for idx in sections.wrappedValue.indices {
            if sections.wrappedValue[idx].id == target.id {
                return sections[idx]
            }
            if let child = binding(for: target, in: sections[idx].children) {
                return child
            }
        }
        return nil
    }
}




// Remove section and return it
private func removeSection(withID id: UUID, in sections: inout [KishoSection]) -> KishoSection? {
    if let idx = sections.firstIndex(where: { $0.id == id }) {
        return sections.remove(at: idx)
    }
    for idx in sections.indices {
        if let found = removeSection(withID: id, in: &sections[idx].children) {
            return found
        }
    }
    return nil
}
