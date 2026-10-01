//
//  FlowLayout.swift
//  Kisho
//
//  Created by Peter Macdonald on 24/07/2025.
//

import SwiftUI

struct FlowLayout<Content: View>: View {
    let data: [String]
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (String) -> Content

    @State private var containerWidth: CGFloat = .zero
    @State private var sizes: [String: CGSize] = [:]

    init(data: [String],
         spacing: CGFloat = 8,
         alignment: HorizontalAlignment = .leading,
         @ViewBuilder content: @escaping (String) -> Content) {
        self.data = data
        self.spacing = spacing
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            let rows = computeRows(for: containerWidth)

            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                            .fixedSize()
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(
                                            key: TagSizePreferenceKey.self,
                                            value: [item: proxy.size]
                                        )
                                }
                            )
                    }
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ContainerWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(TagSizePreferenceKey.self) { sizes = $0 }
        .onPreferenceChange(ContainerWidthKey.self) { containerWidth = $0 }
    }

    private func computeRows(for totalWidth: CGFloat) -> [[String]] {
        guard totalWidth > 0 else { return [data] }

        var rows: [[String]] = [[]]
        var currentRowWidth: CGFloat = 0

        for item in data {
            let size = sizes[item, default: CGSize(width: 80, height: 28)]

            if currentRowWidth + size.width + spacing > totalWidth {
                rows.append([item])
                currentRowWidth = size.width + spacing
            } else {
                rows[rows.count - 1].append(item)
                currentRowWidth += size.width + spacing
            }
        }

        return rows
    }
}


private struct TagSizePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
