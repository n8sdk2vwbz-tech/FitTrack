import SwiftUI
import UIKit
import Combine

/// Beobachtet, ob gerade die Bildschirmtastatur eingeblendet ist. Wird genutzt,
/// um einen "Fertig"-Button in der normalen Navigationsleiste einzublenden -
/// `ToolbarItemGroup(placement: .keyboard)` (die eigentlich dafür vorgesehene
/// Tastatur-Zubehörleiste) hat sich in dieser App innerhalb von
/// `.fullScreenCover`/verschachtelten Listen als unzuverlässig erwiesen und
/// wurde teils gar nicht angezeigt - ein normaler Toolbar-Button rendert
/// dagegen immer zuverlässig.
@MainActor
private final class KeyboardVisibilityObserver: ObservableObject {
    @Published var isVisible = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.isVisible = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.isVisible = false }
            .store(in: &cancellables)
    }
}

private struct KeyboardDoneButtonModifier: ViewModifier {
    @StateObject private var keyboard = KeyboardVisibilityObserver()

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // Bewusst IMMER genau ein ToolbarItem deklariert (nur Sichtbarkeit
                // per Opacity/allowsHitTesting umgeschaltet) statt es bedingt
                // hinzuzufügen/zu entfernen - Letzteres hat in dieser App
                // innerhalb von .fullScreenCover/verschachtelten Listen dazu
                // geführt, dass während der Ein-/Ausblend-Animation kurzzeitig
                // ein zusätzliches, nicht mehr reagierendes Duplikat sichtbar war.
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                    .opacity(keyboard.isVisible ? 1 : 0)
                    .allowsHitTesting(keyboard.isVisible)
                }
            }
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
