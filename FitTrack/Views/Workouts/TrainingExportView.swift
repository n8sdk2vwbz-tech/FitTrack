import SwiftUI
import SwiftData
import UIKit

/// Fasst Trainings, gespeicherte Bereitschafts-Snapshots (siehe
/// `DailyReadinessSnapshot`) und Übungs-Fortschritt für einen wählbaren
/// Zeitraum als lesbaren Text zusammen, zum Einfügen in ein Claude-/
/// ChatGPT-Gespräch für eine Trainingsanalyse (z.B. "Brauche ich eine
/// Deload-Woche?").
struct TrainingExportView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var allSessions: [WorkoutSession]
    @Query(sort: \DailyReadinessSnapshot.day, order: .reverse) private var allSnapshots: [DailyReadinessSnapshot]
    @Environment(\.dismiss) private var dismiss

    @State private var rangeDays = 30
    @State private var didCopy = false

    private static let rangeOptions = [7, 14, 30, 90]

    private var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -rangeDays, to: .now) ?? .now
    }

    private var sessionsInRange: [WorkoutSession] {
        allSessions.filter { $0.date >= cutoffDate }.sorted { $0.date < $1.date }
    }

    private var snapshotsInRange: [DailyReadinessSnapshot] {
        allSnapshots.filter { $0.day >= cutoffDate }.sorted { $0.day < $1.day }
    }

    private var exportText: String {
        Self.buildExportText(sessions: sessionsInRange, snapshots: snapshotsInRange, rangeDays: rangeDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitraum") {
                    Picker("Zeitraum", selection: $rangeDays) {
                        ForEach(Self.rangeOptions, id: \.self) { days in
                            Text("\(days) Tage").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("\(sessionsInRange.count) Trainings, \(snapshotsInRange.count) Tage mit gespeicherten Erholungsdaten im gewählten Zeitraum.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        UIPasteboard.general.string = exportText
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Kopiert" : "Als Text kopieren", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                }

                Section("Vorschau") {
                    Text(exportText)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Für KI-Analyse exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onChange(of: rangeDays) { _, _ in didCopy = false }
        }
    }

    private static func buildExportText(sessions: [WorkoutSession], snapshots: [DailyReadinessSnapshot], rangeDays: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        var lines: [String] = []

        lines.append("Trainingsdaten der letzten \(rangeDays) Tage")
        lines.append("")

        lines.append("== Trainings ==")
        if sessions.isEmpty {
            lines.append("Keine Trainings in diesem Zeitraum.")
        }
        for session in sessions {
            var parts = ["\(dateFormatter.string(from: session.date)) - \(session.activityName)"]
            parts.append("Dauer \(Int(session.durationSeconds / 60)) min")
            if let kcal = session.totalEnergyBurnedKcal { parts.append("\(Int(kcal)) kcal") }
            if let hr = session.averageHeartRate { parts.append("Ø HF \(Int(hr)) bpm") }
            if let effort = session.perceivedExertion { parts.append("Anstrengung \(effort)/10") }
            lines.append(parts.joined(separator: ", "))
            for entry in session.entryList.sorted(by: { $0.order < $1.order }) {
                let workSets = entry.setList.filter { !$0.isWarmup }.sorted { $0.order < $1.order }
                guard !workSets.isEmpty else { continue }
                let setsText = workSets
                    .map { "\($0.reps)x\($0.weightKg.formatted(.number.precision(.fractionLength(0...1))))kg" }
                    .joined(separator: ", ")
                lines.append("  \(entry.exerciseName): \(setsText)")
            }
        }
        lines.append("")

        lines.append("== Erholung (täglicher Bereitschafts-Score) ==")
        if snapshots.isEmpty {
            lines.append("Noch keine gespeicherten Erholungsdaten - diese werden ab jetzt täglich erfasst, für vergangene Tage vor der Einführung gibt es keine Historie.")
        }
        for snapshot in snapshots {
            var parts = ["\(dateFormatter.string(from: snapshot.day)): \(snapshot.score)/100 (\(snapshot.category.displayName))"]
            if let sleep = snapshot.sleepHours { parts.append("Schlaf \(sleep.formatted(.number.precision(.fractionLength(0...1))))h") }
            if let hrv = snapshot.hrvMs { parts.append("HRV \(Int(hrv))ms") }
            if let rhr = snapshot.restingHeartRate { parts.append("Ruhepuls \(Int(rhr))") }
            lines.append(parts.joined(separator: ", "))
        }
        lines.append("")

        lines.append("== Fortschritt je Übung (Top-Satz-Gewicht im Zeitraum) ==")
        let exerciseEntries = sessions.flatMap(\.entryList)
        let exerciseIds = Array(Set(exerciseEntries.map(\.exerciseId))).sorted()
        if exerciseIds.isEmpty {
            lines.append("Keine Übungsdaten in diesem Zeitraum.")
        }
        for exerciseId in exerciseIds {
            let history = WorkoutSession.history(forExerciseId: exerciseId, in: sessions)
            guard let name = exerciseEntries.first(where: { $0.exerciseId == exerciseId })?.exerciseName, !history.isEmpty else { continue }
            let trend = history
                .map { "\(dateFormatter.string(from: $0.date)): \($0.topWeight.formatted(.number.precision(.fractionLength(0...1))))kg" }
                .joined(separator: " -> ")
            lines.append("\(name): \(trend)")
        }

        return lines.joined(separator: "\n")
    }
}
