import Foundation
import FitTrackShared

/// Bewusst getrenntes, für eine KI-Antwort lesbares JSON-Schema (volle
/// Feldnamen) statt des kompakten `SharedPlanItemDTO`-Formats fürs
/// QR-Teilen (einbuchstabige Keys) - eine KI müsste sonst exakt dieses
/// interne, abgekürzte Format treffen, was fehleranfälliger wäre als ein
/// selbsterklärendes Schema.
struct AIPlanPayload: Codable {
    var name: String
    var notes: String?
    var days: [AIPlanDay]
}

struct AIPlanDay: Codable {
    var name: String
    var items: [AIPlanItem]
}

struct AIPlanItem: Codable {
    var exerciseName: String
    var targetSets: Int
    var targetReps: Int
    var targetRepsMax: Int?
    var warmupSetCount: Int?
    var notes: String?
}

enum AIPlanImportError: LocalizedError {
    case noJSONFound
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .noJSONFound: return "Kein JSON im eingefügten Text gefunden."
        case .decodingFailed: return "Der Text entspricht nicht dem erwarteten Plan-Format."
        }
    }
}

enum AIPlanImporter {
    /// KI-Antworten enthalten das JSON oft in einem ```json ... ```-Codeblock
    /// oder mit erklärendem Text drumherum - hier wird nur der Teil zwischen
    /// der ersten `{` und der letzten `}` decodiert, statt beim kleinsten
    /// Rauschen komplett zu scheitern.
    static func parse(_ text: String) throws -> AIPlanPayload {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw AIPlanImportError.noJSONFound
        }
        // iOS' Texteingabefeld ersetzt beim Einfügen automatisch gerade durch
        // "intelligente" (typografische) Anführungszeichen ("..." -> „..."/
        // '...' -> '...') - gültiges JSON verlangt aber zwingend gerade
        // Zeichen, sonst scheitert das Decodieren trotz korrekt aussehendem
        // Text. Deshalb hier zurück auf gerade Anführungszeichen normalisieren.
        let normalized = String(text[start...end])
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
        guard let data = normalized.data(using: .utf8) else { throw AIPlanImportError.noJSONFound }
        do {
            return try JSONDecoder().decode(AIPlanPayload.self, from: data)
        } catch {
            throw AIPlanImportError.decodingFailed
        }
    }

    static func makeTrainingPlan(from payload: AIPlanPayload) -> TrainingPlan {
        let planDays: [PlanDay] = payload.days.enumerated().map { dayIndex, day in
            let items: [PlanItem] = day.items.enumerated().map { itemIndex, item in
                let exercise = matchExercise(named: item.exerciseName)
                return PlanItem(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    targetSets: max(1, item.targetSets),
                    targetReps: max(1, item.targetReps),
                    targetRepsMax: item.targetRepsMax,
                    warmupSetCount: max(0, item.warmupSetCount ?? 0),
                    order: itemIndex,
                    notes: item.notes ?? ""
                )
            }
            return PlanDay(name: day.name, order: dayIndex, items: items)
        }
        return TrainingPlan(name: payload.name, notes: payload.notes ?? "", days: planDays)
    }

    /// Ordnet den von der KI genannten Übungsnamen einer Übung aus der
    /// Bibliothek zu (case-insensitiv), damit Muskel-Zuordnung/Belastung
    /// funktionieren. Kein Treffer? Als eigenständige Übung ohne
    /// Muskelgruppen anlegen (wie bei importierten/geteilten Plänen mit
    /// unbekannter exerciseId) - der Import gelingt trotzdem, nur ohne
    /// Beitrag zur Muskelbelastungs-Ansicht.
    private static func matchExercise(named name: String) -> Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = ExerciseLibrary.all.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }
        let slug = trimmed
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "-")
        return Exercise(id: "custom-\(slug)", name: trimmed, category: .strength, equipment: .none, primaryMuscles: [], secondaryMuscles: [], instructions: "")
    }
}
