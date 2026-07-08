import SwiftUI

/// Zehn ansteigende Balken zur Auswahl der gefühlten Anstrengung (RPE 1-10),
/// angelehnt an Apples "Anstrengung bewerten"-Bildschirm nach einem Training.
struct EffortRatingBars: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(1...10, id: \.self) { level in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color(for: level))
                    .frame(height: 16 + CGFloat(level) * 7)
                    .onTapGesture { rating = level }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: rating)
    }

    private func color(for level: Int) -> Color {
        guard let rating else { return Color.secondary.opacity(0.25) }
        return level <= rating ? Color.orange : Color.secondary.opacity(0.2)
    }
}

func effortLabel(_ value: Int) -> String {
    switch value {
    case 1...2: return "Sehr leicht"
    case 3...4: return "Leicht"
    case 5...6: return "Moderat"
    case 7...8: return "Anstrengend"
    default: return "Maximal"
    }
}

/// Vollflächiger Bildschirm nach Trainingsende zur Anstrengungsbewertung,
/// analog zu Apples Workout-Effort-Screen. Optional - kann übersprungen werden.
struct RateEffortView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Button {
                    finish()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                }
                Spacer()
                Button {
                    finish()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.title3)
                }
                .disabled(session.perceivedExertion == nil)
            }
            .padding(.top)

            Spacer()

            Text("Anstrengung bewerten")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            EffortRatingBars(rating: $session.perceivedExertion)
                .frame(height: 100)
                .padding(.horizontal, 24)

            if let rating = session.perceivedExertion {
                Text("\(rating)/10 · \(effortLabel(rating))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Wie anstrengend war das Training für dich?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Fließt zusammen mit deiner Trainings-Herzfrequenz in die Belastungsberechnung und deinen Bereitschafts-Score ein.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func finish() {
        try? modelContext.save()
        dismiss()
    }
}
