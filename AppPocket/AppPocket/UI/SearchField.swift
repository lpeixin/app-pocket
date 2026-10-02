//
//  SearchField.swift
//  AppPocket
//

import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey = "search.placeholder"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isFocused ? Color.accentColor : Color.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { isFocused = false }

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("search.clear")
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 216)
        .background(Capsule().fill(.background.secondary))
        .overlay {
            Capsule().strokeBorder(
                isFocused ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.09),
                lineWidth: 1
            )
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
        .background {
            // Keeps ⌘F working without taking up layout space.
            Button("") { isFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}
