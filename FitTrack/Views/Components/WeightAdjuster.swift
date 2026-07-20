import SwiftUI

/// Schließt die Tastatur beim Wegwischen zuverlässig. Ein eigener,
/// tastaturabhängig ein-/ausgeblendeter "Fertig"-Button wurde zweimal
/// versucht (Navigationsleiste, Tastatur-Zubehörleiste) und zeigte beide Male
/// dasselbe Symptom: während der Ein-/Ausblend-Animation blieb innerhalb von
/// `.fullScreenCover`/verschachtelten Listen gelegentlich ein zusätzliches,
/// nicht mehr reagierendes Duplikat sichtbar. Bewusst ohne bedingte
/// Toolbar-Elemente, um diese Fehlerklasse komplett zu vermeiden.
private struct KeyboardDoneButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButtonModifier())
    }
}

/// Kompakte Gewichtseingabe: +/- für 0,5 kg-Schritte, Antippen des Zahlenfelds
/// erlaubt die manuelle Eingabe eines exakten Werts über die Zifferntastatur.
///
/// Nutzt bewusst KEIN `TextField(value:format:)`: dessen Format-Style parst
/// nach jedem Tastendruck den bisherigen Text neu und schreibt ihn neu
/// formatiert zurück, was während des Tippens (v.a. nach einem Komma) zu
/// doppelt eingefügten Ziffern, Sprüngen auf den Maximalwert und scheinbar
/// von selbst erscheinenden Zahlen führen kann. Stattdessen wird in einen
/// lokalen Text-Puffer getippt, der erst beim Verlassen des Felds geparst
/// und auf den Bereich begrenzt wird.
struct WeightAdjuster: View {
    @Binding var weightKg: Double
    var step: Double = 0.5
    var range: ClosedRange<Double> = 0...300

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button {
                weightKg = clamp(weightKg - step)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            TextField("kg", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 58)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { text = formatted(weightKg) }
                .onChange(of: weightKg) { _, newValue in
                    // Externe Änderung (+/- Button, Plan-Vorbefüllung) -
                    // während der Nutzer selbst tippt nicht überschreiben.
                    guard !isFocused else { return }
                    text = formatted(newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    guard !focused else { return }
                    commit()
                }

            Text("kg")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()

            Button {
                weightKg = clamp(weightKg + step)
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func commit() {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let parsed = Double(normalized) ?? weightKg
        weightKg = clamp(parsed)
        text = formatted(weightKg)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
