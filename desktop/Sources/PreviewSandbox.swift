import SwiftUI

/// A screenshot-friendly stage for the same picker rendered by TokenPicker.
struct PreviewSandbox: View {
    @ObservedObject var model: AppModel
    @StateObject private var picker = PickerState()
    private let scale: CGFloat = 0.84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(red: 9 / 255, green: 9 / 255, blue: 11 / 255))
            PreviewDots().clipShape(RoundedRectangle(cornerRadius: 12))
            Text("token-reference-panel")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Protegia.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            PickerView(state: picker, allowsDragging: false, editableSearch: true)
                .clipShape(RoundedRectangle(cornerRadius: Protegia.panelRadius))
                .overlay(RoundedRectangle(cornerRadius: Protegia.panelRadius)
                    .stroke(Protegia.level2.opacity(0.65), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 7)
                .scaleEffect(scale)
                .frame(width: PickerLayout.width * scale, height: PickerLayout.height * scale)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            picker.tokens = model.tokens
            picker.choose = { [weak picker] token in
                guard let picker, let index = picker.matches.firstIndex(of: token) else { return }
                picker.selected = index
            }
        }
        .onReceive(model.$indices) { indices in
            picker.tokens = indices.first(where: { $0.repository.id == model.activeID })?.tokens ?? []
        }
        .onChange(of: model.activeID) { _, _ in picker.tokens = model.tokens }
    }
}

private struct PreviewDots: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: CGFloat(5), through: size.width, by: 5) {
                for y in stride(from: CGFloat(5), through: size.height, by: 5) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 0.8, height: 0.8))
                }
            }
            context.fill(dots, with: .color(.white.opacity(0.12)))
        }
        .accessibilityHidden(true)
    }
}
