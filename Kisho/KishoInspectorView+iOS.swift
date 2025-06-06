//
//  KishoInspectorView+iOS.swift
//  Kisho
//
//  Created by Peter Macdonald on 06/06/2025.
//

import SwiftUI
import UIKit

/// An iOS “Inspector” for a single KishoSection’s typography and tags.
/// - Shows a grouped list with controls for font family, size, bold, italic, color, and tags.
/// - On appearance, it loads the section’s current attributes into @State properties.
/// - On each change, it rebuilds an NSAttributedString for the entire section and assigns it back.
struct KishoInspectorView: View {
    @ObservedObject var section: KishoSection

    // MARK: –– One‐time loading flag
    @State private var didLoadDefaults = false

    // MARK: –– Typography state
    @State private var fontFamilies: [String] = []
    @State private var selectedFontFamily: String = UIFont.systemFont(ofSize: 14).familyName ?? ""
    @State private var fontSize: Double = 14
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false
    @State private var uiColor: UIColor = .label  // default text color

    // MARK: –– Tags state
    @State private var tagString: String = ""

    var body: some View {
        // Use a Form with grouped style to mimic iOS Settings/Inspector look
        Form {
            // ─── Typography Section ─────────────────────────
            Section(header: Text("Typography").font(.headline)) {
                // Font Family Picker
                Picker(selection: $selectedFontFamily, label: Text("Font")) {
                    ForEach(fontFamilies, id: \.self) { fam in
                        Text(fam).font(.custom(fam, size: 17))
                    }
                }
                .labelsHidden()

                // Font Size Stepper (with a Text label)
                HStack {
                    Text("Size")
                    Spacer()
                    Stepper(value: $fontSize, in: 8...72, step: 1) {
                        Text("\(Int(fontSize))")
                    }
                    .frame(width: 100)
                }

                // Bold / Italic Toggles
                Toggle("Bold", isOn: $isBold)
                Toggle("Italic", isOn: $isItalic)

                // Color Picker
                ColorPicker("Color", selection: Binding(
                    get: { Color(uiColor) },
                    set: { newColor in uiColor = UIColor(newColor) }
                ))
            }

            // ─── Tags Section ────────────────────────────────
            Section(header: Text("Tags").font(.headline)) {
                TextField("comma, separated, tags", text: $tagString)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .onAppear {
            guard !didLoadDefaults else { return }
            didLoadDefaults = true

            // 1) Populate font families once
            fontFamilies = UIFont.familyNames.sorted()

            // 2) Load existing typography from the section’s attributed string
            loadCurrentValuesFromSection()

            // 3) Load existing tags
            tagString = section.tags.joined(separator: ", ")
        }
        // Whenever any typography state changes, re‐apply to section.content
        .onChange(of: selectedFontFamily) { _ in applyTypography() }
        .onChange(of: fontSize)           { _ in applyTypography() }
        .onChange(of: isBold)             { _ in applyTypography() }
        .onChange(of: isItalic)           { _ in applyTypography() }
        .onChange(of: uiColor)            { _ in applyTypography() }
        // Whenever tags string changes, commit tags
        .onChange(of: tagString) { _ in commitTags() }
        // Use the grouped inset style to look like a native inspector
        .environment(\.defaultMinListRowHeight, 44)
    }

    // MARK: –– Load the current attributes from section.content.attributedString
    private func loadCurrentValuesFromSection() {
        let attributed = section.content.attributedString
        let fullLength = attributed.length
        guard fullLength > 0 else { return }

        // Sample at index 0 for font traits
        if let firstFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
            selectedFontFamily = firstFont.familyName ?? selectedFontFamily
            fontSize = Double(firstFont.pointSize)
            let traits = firstFont.fontDescriptor.symbolicTraits
            isBold = traits.contains(.traitBold)
            isItalic = traits.contains(.traitItalic)
        }

        // Sample at index 0 for color
        if let firstColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor {
            uiColor = firstColor
        }
    }

    // MARK: –– Apply current typography state to the entire section’s attributed string
    private func applyTypography() {
        // Build a base mutable attributed string from the plain text of the section
        let plain = section.content.attributedString.string
        let mutable = NSMutableAttributedString(string: plain)

        // Construct a UIFontDescriptor with family + traits
        var descriptor = UIFontDescriptor(fontAttributes: [.family: selectedFontFamily])
        var symbolicTraits = UIFontDescriptor.SymbolicTraits()
        if isBold   { symbolicTraits.insert(.traitBold) }
        if isItalic { symbolicTraits.insert(.traitItalic) }
        if let withTraits = descriptor.withSymbolicTraits(symbolicTraits) {
            descriptor = withTraits
        }

        // Create UIFont from descriptor + size
        let uiFont = UIFont(descriptor: descriptor, size: CGFloat(fontSize))

        // Build attributes dictionary
        let attrs: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .foregroundColor: uiColor
        ]

        // Apply to entire range
        mutable.addAttributes(attrs, range: NSRange(location: 0, length: mutable.length))

        // Write back to the section (this is a @Published property→auto‐refresh)
        section.content.attributedString = mutable
    }

    // MARK: –– Parse tagString into section.tags array
    private func commitTags() {
        let split = tagString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        section.tags = split
    }
}

// Extension to convert SwiftUI Color to UIKit UIColor
fileprivate extension UIColor {
    convenience init(_ color: Color) {
        // Extract RGBA components from Color’s description
        let uiColor = UIColor { trait in
            return UIColor.systemBackground
        }
        if let cg = color.cgColor {
            self.init(cgColor: cg)
        } else {
            self.init(cgColor: uiColor.cgColor)
        }
    }
}
