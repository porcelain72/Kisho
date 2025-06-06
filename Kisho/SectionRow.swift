//
//  SectionRow.swift
//  Kisho
//
//  Created by Peter Macdonald on 02/06/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SectionRow: View {
    @EnvironmentObject var document : KishoDocumentModel

    @ObservedObject var section: KishoSection
   
    @State private var dropPosition: DropPosition?

  //  @Binding var showDeleteAlert : Bool
    let depth : Int
    
    enum DropPosition { case above, on, below }

    var body: some View {
        VStack(spacing: 0) {
            // Drop above
            dropTargetView(position: .above)

            // The row content
            HStack {
                Text(section.title)
                   
                                      
                Spacer()
            }
            .modifier(CellModifier(depth: depth, selected: self.section.id == document.selectedSectionID))
           
.onTapGesture {self.document.select(section: section)}
            
            //.background(dropPosition == .on ? Color.accentColor.opacity(0.12) : Color.clear)
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
                        SectionRow(section: child, depth: self.depth + 1)
                            .padding(.leading, (depth<4 ? 20 : 0))
                    }
                }
            }
        }
      

        .background(dropPosition == .above || dropPosition == .below ? Color.accentColor.opacity(0.08) : Color.clear)
    }
  
    
    // ─── Computed capsule background, tinted by depth ─────────
    private var labelBackground: some View {
        let base = Color.blue    // pick any base color you like
        // reduce lightness (or increase opacity) per depth
        let fraction = min(0.6 + Double(self.depth) * 0.08, 0.95)
        return base
            .opacity(0.15)         // overall translucence
            .blendMode(.plusLighter)
            .background(
                Capsule()
                    .fill(base.opacity(fraction * 0.8))
                    .blur(radius: 0) // subtle “frosted” feel
            )
    }
    /*
    private var labelBackground: some View {
        let hue = Double(section.depth) * 0.08 // deeper = more offset in hue
        let color = Color(hue: hue.truncatingRemainder(dividingBy: 1.0), saturation: 0.4, brightness: 0.9)
        return Capsule()
            .fill(color.opacity(0.15))
            .background(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }

    let palette: [Color] = [.blue, .teal, .green, .yellow, .orange]
    let idx = section.depth % palette.count
    return Capsule()
        .fill(palette[idx].opacity(0.12))
        .overlay(
            Capsule()
                .stroke(palette[idx].opacity(0.3), lineWidth: 1)
        )

    */
    
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
                    self.document.moveAsChild(draggedID: draggedID, destinationID: self.section.id)
                case .above:
                    self.document.moveAsSibling(draggedID: draggedID, destinationID: self.section.id, insertBefore: true)
                case .below:
                    self.document.moveAsSibling(draggedID: draggedID, destinationID: self.section.id,  insertBefore: false)
                }
                dropPosition = nil
            }
        }
        return true
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



struct CellModifier : ViewModifier {
    
    let depth : Int
    
    let selected : Bool
    func body(content: Content) -> some View {
        content
            .font(.headline) // headline font
                               .padding(.horizontal, 12)
                               .padding(.vertical, 8)
            .background(
             Capsule()
                .fill(capsuleColor.opacity(selected == true ?  0.6 : 0.2))
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal,6.0)
    }
    
    /// Compute a base color that darkens slightly as depth increases
      private var capsuleColor: Color {
          // Example: shift hue or adjust brightness by depth
          let baseHue: Double = 0.55 // roughly teal/blue
          let depthFactor = Double(self.depth) * 0.08
          let hue = (baseHue + depthFactor).truncatingRemainder(dividingBy: 1.0)
          return Color(hue: hue, saturation: 0.4, brightness: 0.9)
      }
}
