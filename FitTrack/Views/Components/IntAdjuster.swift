import SwiftUI

/// Kompakte Ganzzahl-Eingabe (z.B. Wiederholungen): +/- für Einzelschritte,
/// Antippen des Zahlenfelds erlaubt die manuelle Eingabe über die Zifferntastatur.
///
/// Nutzt bewusst KEIN `TextField(value:format:)` - siehe Kommentar in
/// `WeightAdjuster` für den Grund (doppelte Ziffern/Sprünge auf den
/// Maximalwert durch den Format-Style-Reparse-Zyklus bei jedem Tastendruck).
struct IntAdjuster: View {
    @Binding var value: Int
    var step: Int = 1
    var range: ClosedRange<Int> = 1...50

    @State private var text: String = ""
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                value = clamp(value - step)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            NoAccessoryTextField(text: $text, keyboardType: .numberPad) { editing in
                isEditing = editing
                if !editing { commit() }
            }
            .frame(width: 34, height: 28)
            .onAppear { text = String(value) }
            .onChange(of: value) { _, newValue in
                guard !isEditing else { return }
                text = String(newValue)
            }

            Button {
                value = clamp(value + step)
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func commit() {
        let parsed = Int(text) ?? value
        value = clamp(parsed)
        text = String(value)
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
