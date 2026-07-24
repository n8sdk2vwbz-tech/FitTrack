import SwiftUI
import FitTrackShared

/// Ob die Muskel-Kacheln/Cardio-Karte den kurzfristigen ("heute trainierbar?")
/// oder langfristigen (ACWR-Trainingskonsistenz) Status prominent zeigen -
/// beide Werte bleiben in beiden Modi sichtbar, nur welcher davon die
/// Kachel-Farbe/erste Zeile bestimmt wechselt. Getrennt umschaltbar, weil
/// beide Fragen unterschiedlich sind ("kann ich heute trainieren" vs. "ist
/// mein Training über die Wochen ausgewogen") und ein einzelnes Feld für
/// beides leicht missverständlich ist (siehe `ShortTermReadiness`-Kommentar).
enum MuscleDisplayMode: String, CaseIterable, Identifiable {
    case shortTerm = "Kurzfristig"
    case longTerm = "Langfristig"
    var id: String { rawValue }
}

struct MuscleHeatmapView: View {
    let statuses: [MuscleGroup: MuscleLoadStatus]
    let readiness: ReadinessResult?
    @Binding var displayMode: MuscleDisplayMode

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    private var trainableMuscles: [MuscleGroup] {
        MuscleGroup.allCases.filter { $0 != .cardio }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Muskelbelastung")
                    .font(.headline)
                Text(displayMode == .shortTerm
                     ? "Zeigt, welche einzelne Muskelgruppe HEUTE für Krafttraining bereit ist - z.B. ob Beine trotz Cardio-Einheit schon wieder frisch genug für einen Bein-Tag sind."
                     : "Zeigt, ob dein Training pro Muskelgruppe über die letzten Wochen ausgewogen ist - weder Über- noch Unterbelastung im Vergleich zu deinem eigenen Muster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            MuscleLegendView(displayMode: displayMode)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(trainableMuscles) { muscle in
                    if let status = statuses[muscle] {
                        NavigationLink {
                            MuscleDetailView(status: status, readiness: readiness)
                        } label: {
                            MuscleCell(status: status, displayMode: displayMode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Kompakte Farb-Legende passend zum gewählten `MuscleDisplayMode` - die
/// kurzfristige und die langfristige Ansicht haben unterschiedlich viele
/// Stufen (3 bzw. 5), das war ohne Erklärung direkt in der App leicht
/// missverständlich (z.B. Blau kommt nur langfristig vor, siehe
/// `ShortTermReadiness`-Kommentar).
private struct MuscleLegendView: View {
    let displayMode: MuscleDisplayMode
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            if displayMode == .shortTerm {
                LegendChip(color: .green, label: "Bereit")
                LegendChip(color: .orange, label: "Erholt sich")
                LegendChip(color: .gray, label: "Keine Daten")
            } else {
                LegendChip(color: .blue, label: "Frisch")
                LegendChip(color: .green, label: "Optimal")
                LegendChip(color: .orange, label: "Erhöht")
                LegendChip(color: .red, label: "Hoch")
                LegendChip(color: .gray, label: "Keine Daten")
            }
        }
    }
}

private struct LegendChip: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Eigene, prominente Bereitschafts-Anzeige für die Herz-Kreislauf-Belastung
/// (Cardio), getrennt von der Muskel-Heatmap unten: Cardio-Belastung läuft
/// unabhängig von einzelnen Kraft-Muskelgruppen, daher eine eigene
/// "bin ich bereit für eine Cardio-Einheit"-Aussage statt sie in der langen
/// Muskel-Grid untergehen zu lassen.
struct CardioReadinessCard: View {
    let status: MuscleLoadStatus?
    let readiness: ReadinessResult?
    let displayMode: MuscleDisplayMode

    var body: some View {
        if let status {
            let shortTerm = status.shortTermReadiness()
            let primaryColor = displayMode == .shortTerm ? shortTerm.color : status.fatigueLevel.color
            let primaryLabel = displayMode == .shortTerm ? shortTerm.label : status.fatigueLevel.displayName
            let secondaryLabel = displayMode == .shortTerm
                ? "Trainingskonsistenz: \(status.fatigueLevel.displayName)"
                : "Kurzfristig: \(shortTerm.label)"
            NavigationLink {
                MuscleDetailView(status: status, readiness: self.readiness)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.title2)
                        .foregroundStyle(primaryColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cardio-Bereitschaft")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(primaryLabel)
                            .font(.caption)
                            .foregroundStyle(primaryColor)
                        Text(secondaryLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(primaryColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(primaryColor, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct MuscleCell: View {
    let status: MuscleLoadStatus
    let displayMode: MuscleDisplayMode

    private var shortTerm: ShortTermReadiness { status.shortTermReadiness() }
    private var primaryColor: Color { displayMode == .shortTerm ? shortTerm.color : status.fatigueLevel.color }
    private var primaryLabel: String { displayMode == .shortTerm ? shortTerm.label : status.fatigueLevel.displayName }
    private var secondaryLabel: String { displayMode == .shortTerm ? status.fatigueLevel.displayName : shortTerm.label }

    var body: some View {
        VStack(spacing: 4) {
            Text(status.muscle.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(primaryLabel)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(primaryColor)
            Text(secondaryLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(8)
        .background(primaryColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(primaryColor, lineWidth: 1.5))
    }
}

struct MuscleDetailView: View {
    let status: MuscleLoadStatus
    let readiness: ReadinessResult?

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: status.shortTermReadiness().label)
                    .foregroundStyle(status.shortTermReadiness().color)
                if let hoursSince = status.hoursSinceLastTrained() {
                    LabeledContent("Letzte Einheit", value: "vor \(Int(hoursSince)) Std.")
                }
            } header: {
                Text("Kurzfristig: heute trainierbar?")
            } footer: {
                Text("Grober Richtwert (\(Int(status.muscle.typicalRecoveryHours))h für \(status.muscle.displayName)) ohne Berücksichtigung der tatsächlichen Intensität der letzten Einheit.")
            }

            Section {
                LabeledContent("Status", value: status.fatigueLevel.displayName)
                LabeledContent("ACWR", value: String(format: "%.2f", status.acwr))
                if let days = status.daysSinceLastTrained {
                    LabeledContent("Zuletzt trainiert", value: "vor \(days) Tag(en)")
                } else {
                    LabeledContent("Zuletzt trainiert", value: "keine Daten")
                }
                if status.isRampingUp {
                    Label("Wiedereinstieg nach ruhigerer Zeit", systemImage: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Langfristig: Trainingskonsistenz")
            } footer: {
                Text(status.isRampingUp
                     ? "Deine Belastung ist im Vergleich zu einer ruhigeren Phase gerade spürbar gestiegen - beim Wiedereinstieg normal, baue aber lieber schrittweise statt sprunghaft weiter auf. Sagt nichts über die akute Erholung von der letzten Einheit aus, siehe oben."
                     : "Bewertet nur, ob die Trainingsfrequenz der letzten Wochen zu deinem eigenen Muster passt (weder Über- noch Unterbelastung) - sagt nichts über die akute Erholung von der letzten Einheit aus, siehe oben.")
            }

            if let readiness {
                Section("Empfehlung") {
                    Text(RecoveryEngine.recommendation(for: status, readiness: readiness))
                }
            }

            Section("Übungen für \(status.muscle.displayName)") {
                ForEach(ExerciseLibrary.exercises(for: status.muscle)) { exercise in
                    NavigationLink(exercise.name) {
                        ExerciseDetailView(exercise: exercise)
                    }
                }
            }
        }
        .navigationTitle(status.muscle.displayName)
    }
}
