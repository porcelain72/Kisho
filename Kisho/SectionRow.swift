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
    @Environment(\.undoManager) private var undoManager

    @ObservedObject var section: KishoSection

    @State private var dropPosition: DropPosition?

    let depth : Int
    @State private var showsSubSections = true

    enum DropPosition { case above, on, below }

    var body: some View {
        VStack(spacing: 0) {
            // Drop above
            dropTargetView(position: .above)

            // The row content
            HStack {
                Text(section.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                wordCountLabel()
                if !section.children.isEmpty {
                    showButton()
                }
            }
            .modifier(CellModifier(depth: depth, selected: self.section.id == document.selectedSectionID))
            .contentShape(Rectangle())
            .onTapGesture { self.document.select(section: section) }
            .overlay(
                Capsule()
                    .stroke(Color.accentColor, lineWidth: dropPosition == .on ? 2 : 0)
                    .padding(.horizontal, 6.0)
            )
            .onDrag {
                NSItemProvider(object: section.id.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.text],
                isTargeted: Binding(
                    get: { dropPosition == .on },
                    set: { isOver in dropPosition = isOver ? .on : (dropPosition == .on ? nil : dropPosition) }
                ),
                perform: { providers in handleDrop(providers: providers, position: .on) }
            )

            // Drop below
            dropTargetView(position: .below)

            // Children, indented
            if !section.children.isEmpty, showsSubSections {
                VStack(spacing: 0) {
                    ForEach(section.children) { child in
                        SectionRow(section: child, depth: self.depth + 1)
                            .padding(.leading, (depth < 4 ? 20 : 0))
                    }
                }
            }
        }
        .id(section.id)
    }

    @ViewBuilder private func wordCountLabel() -> some View {
        let count = section.totalWordCount
        if count > 0 {
            Text("\(count)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(0.6)
                .padding(.trailing, 2)
        }
    }

    @ViewBuilder private func showButton() -> some View {
        Button {
            showsSubSections.toggle()
        } label: {
            Image(systemName: showsSubSections ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
        }
        .buttonStyle(.plain)
        .opacity(0.4)
        .frame(width: 24.0, height: 24.0)
        .help(showsSubSections ? "Hide sub-sections" : "Show sub-sections")
    }

    // Drop target for above/below sibling insert
    @ViewBuilder
    private func dropTargetView(position: DropPosition) -> some View {
        Rectangle()
            .frame(height: 10)
            .foregroundColor(dropPosition == position ? Color.accentColor.opacity(0.5) : Color.clear)
            .onDrop(of: [UTType.text], isTargeted: Binding(
                get: { dropPosition == position },
                set: { isOver in
                    if isOver {
                        dropPosition = position
                    } else if dropPosition == position {
                        dropPosition = nil
                    }
                }
            ), perform: { providers in handleDrop(providers: providers, position: position) })
    }

    // Drop handling for all three positions
    private func handleDrop(providers: [NSItemProvider], position: DropPosition) -> Bool {
        guard let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) else {
            dropPosition = nil
            return false
        }
        let destinationID = section.id
        let undoManager = self.undoManager
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            var idStr: String?
            if let data = item as? Data, let s = String(data: data, encoding: .utf8) { idStr = s }
            else if let s = item as? String { idStr = s }
            else if let s = item as? NSString { idStr = s as String }

            DispatchQueue.main.async {
                defer { dropPosition = nil }
                guard let idStr = idStr?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let draggedID = UUID(uuidString: idStr) else { return }
                let destination: KishoDocumentModel.MoveDestination
                switch position {
                case .on:    destination = .into(destinationID)
                case .above: destination = .before(destinationID)
                case .below: destination = .after(destinationID)
                }
                guard document.canMove(sectionID: draggedID, to: destination) else { return }
                withAnimation {
                    document.move(sectionID: draggedID, to: destination, using: undoManager)
                }
            }
        }
        return true
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

extension Color {
    func shiftedHue(by amount: CGFloat) -> Color {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return self
        }

        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)

        let newHue = fmod(hue + amount, 1.0)
        let shifted = NSColor(hue: newHue, saturation: sat, brightness: bri, alpha: alpha)
        return Color(shifted)
    }
}
