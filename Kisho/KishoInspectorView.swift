

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif


#if os(macOS)

/// A classic‐style macOS Inspector for a KishoSection.
/// - Appears as a narrow, scrollable vertical panel.
/// - Uses GroupBoxes for “Typography” and “Tags” sections.
/// - Applies a subtle NSVisualEffectMaterial.sidebar background.
/// - Constrains itself to a fixed width and scrolls if necessary.
struct KishoInspectorView: View {
    @ObservedObject var section: KishoSection
    @EnvironmentObject var document : KishoDocumentModel

    // MARK: –– One‐time initialization flags
    @State private var didLoadDefaults = false

    // MARK: –– Typography state
    @State private var fontFamilies: [String] = []
    #if os(macOS)
    @State private var selectedFontFamily: String = NSFont.systemFont(ofSize: 12).familyName ?? "System"
    #else
    @State private var selectedFontFamily: String = UIFont.systemFont(ofSize: 12).familyName ?? "System"

    #endif
    @State private var fontSize: Double = 12
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false
    @State private var textColor: Color = .primary

    // MARK: –– Tags state
    @State private var tagString: String = ""

    var body: some View {
        // Use a VisualEffect background to mimic a sidebar inspector
        ScrollView {
            VStack(spacing: 16) {
                // ─── Typography GroupBox ───────────────────────────
                GroupBox(label: Text("Typography").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Font Family Picker
                        Picker("Font Family", selection: $selectedFontFamily) {
                            ForEach(fontFamilies, id: \.self) { fam in
                                Text(fam).font(.custom(fam, size: 13))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        // Font Size Stepper
                        HStack {
                            Text("Size")
                            Spacer()
                            Stepper(value: $fontSize, in: 8...72, step: 1) {
                                Text("\(Int(fontSize)) pt")
                                    .frame(width:  40.0, alignment: .trailing)
                            }
                        }

                        // Bold / Italic Toggles
                        Toggle("Bold", isOn: $isBold)
                        Toggle("Italic", isOn: $isItalic)

                        // Color Picker
                        ColorPicker("Color", selection: $textColor)
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal)

                // ─── Tags GroupBox ──────────────────────────────────
                GroupBox(label: Text("Tags").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("tag1, tag2, tag3", text: $tagString, onCommit: commitTags)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal)

                Spacer(minLength: 20)
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
        }
        .background(
            // Use the macOS “sidebar” material so it blends with the window
            VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                .ignoresSafeArea()
        
        )
   
        // Constrain inspector’s width so it never expands too far
        .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
        .onAppear {
            guard !didLoadDefaults else { return }
            didLoadDefaults = true
            // Populate font families once
            fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
         
            // Load initial typography from section.content
            loadCurrentValuesFromSection()

            // Load initial tags
            tagString = section.tags.joined(separator: ", ")
        }
        .onChange(of: selectedFontFamily) { _ in applyTypographyToDocument() }
        .onChange(of: fontSize) { _ in applyTypographyToDocument() }
        .onChange(of: isBold) { _ in applyTypographyToDocument() }
        .onChange(of: isItalic) { _ in applyTypographyToDocument() }
        .onChange(of: textColor) { _ in applyTypographyToDocument() }
        .onChange(of: tagString) { _ in commitTags() }
    }

    // MARK: –– Load the section’s existing font/color into state
    private func loadCurrentValuesFromSection() {
        let attributed = section.content.attributedString
        let fullLength = attributed.length
        guard fullLength > 0 else { return }

        if let firstFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            selectedFontFamily = firstFont.familyName ?? selectedFontFamily
            fontSize = Double(firstFont.pointSize)
            let traits = firstFont.fontDescriptor.symbolicTraits
            isBold = traits.contains(.bold)
            isItalic = traits.contains(.italic)
        }
        if let firstColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
            textColor = Color(firstColor)
        }
    }

    // MARK: –– Apply all typography state to the entire section string
    private func applyTypographyToDocument() {
        let fullText = section.content.attributedString.string
        let newAttributed = NSMutableAttributedString(string: fullText)
print(fontSize)
        // Build font descriptor
        var descriptor = NSFontDescriptor(fontAttributes: [.family: selectedFontFamily])
        var traits = NSFontDescriptor.SymbolicTraits()
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }
        descriptor = descriptor.withSymbolicTraits(traits) ?? descriptor

        // Create NSFont
        let nsFont = NSFont(descriptor: descriptor, size: CGFloat(fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(fontSize))

        // Build attribute dictionary
        let nsColor = NSColor(textColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: nsColor
        ]
        newAttributed.addAttributes(attrs, range: NSRange(location: 0, length: newAttributed.length))

        
        //document.applyTypographyToEntireDocument(font: nsFont, color: nsColor, undoManager: undoManager)
        // Assign back to the section (Published → autosave)
      //  section.content.attributes = attrs
      //  section.content.attributedString = newAttributed
     //   section.inspectorVersion = UUID()
    }

    // MARK: –– Parse tagString into section.tags
    private func commitTags() {
        let split = tagString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        section.tags = split
    }
}

/// A helper NSViewRepresentable that wraps NSVisualEffectView
/// so we can use macOS 11+ materials in SwiftUI.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// A small helper so you can call `NSColor(some Color)`
extension NSColor {
    convenience init(_ color: Color) {
        let scanner = Scanner(string: color.description.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hex: UInt64 = 0
        scanner.scanHexInt64(&hex)
        let r = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hex & 0x00FF00) >> 8)  / 255.0
        let b = CGFloat(hex & 0x0000FF)         / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}



#endif
