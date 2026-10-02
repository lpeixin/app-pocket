//
//  Theme.swift
//  AppPocket
//
//  Shared visual language. Everything here follows the system appearance, so
//  the app inherits light/dark mode and the user's accent colour for free.
//

import SwiftUI

extension Color {
    /// Parses `#RRGGBB` (or `RRGGBB`). Falls back to the accent colour when the
    /// string is malformed, so a hand-edited document can never produce an
    /// invisible sidebar row.
    init(hex: String, fallback: Color = .accentColor) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self = fallback
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Metrics {
    static let tileSpacing: CGFloat = 6
    static let gridPadding: CGFloat = 20
    static let tileCornerRadius: CGFloat = 14
    static let iconCornerRadiusRatio: CGFloat = 0.2237 // macOS icon squircle
    static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (196, 224, 300)
    static let headerHeight: CGFloat = 64
}

extension View {
    /// The rounded plate behind a category's symbol in the sidebar.
    func categoryBadge(color: Color, size: CGFloat = 20, corner: CGFloat = 6) -> some View {
        self
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(color.gradient)
            )
    }

    /// A subtle card surface that reads correctly in both appearances.
    func panelBackground(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.background.secondary)
        )
    }
}

/// A tile's hover / selection treatment, animated consistently everywhere.
struct TileSurface: ViewModifier {
    let isSelected: Bool
    let isFocused: Bool
    let isHovering: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor : Color.primary.opacity(isSelected ? 0.18 : 0.08),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .animation(.easeOut(duration: 0.13), value: isHovering)
            .animation(.easeOut(duration: 0.13), value: isSelected)
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        if isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

extension View {
    func tileSurface(
        isSelected: Bool,
        isFocused: Bool,
        isHovering: Bool,
        cornerRadius: CGFloat = Metrics.tileCornerRadius
    ) -> some View {
        modifier(
            TileSurface(
                isSelected: isSelected,
                isFocused: isFocused,
                isHovering: isHovering,
                cornerRadius: cornerRadius
            )
        )
    }
}
