import SwiftUI

/// A multi-line field that grows with its content: Return inserts a newline, ⌘Return submits.
struct GrowingTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var font: Font = .system(size: 13)
    var maxHeight: CGFloat = 140
    var onCommit: () -> Void
    @FocusState.Binding var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A hidden copy of the text sets the height so the editor grows with its content.
            Text(text.isEmpty ? " " : text + (text.hasSuffix("\n") ? " " : ""))
                .font(font)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(Style.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(font)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .padding(.horizontal, 0)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        onCommit()
                        return .handled
                    }
                    return .ignored
                }
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}
