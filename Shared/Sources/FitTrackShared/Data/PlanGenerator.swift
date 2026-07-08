import Foundation

/// Trainingsziel - bestimmt Wiederholungsbereich und Satzzahl.
public enum TrainingGoal: String, CaseIterable, Identifiable, Codable {
    case strength
    case hypertrophy
    case generalFitness
    case fatLoss

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strength: return "Kraftaufbau"
        case .hypertrophy: return "Muskelaufbau"
        case .generalFitness: return "Allgemeine Fitness"
        case .fatLoss: return "Fettabbau"
        }
    }
}

public enum ExperienceLevel: String, CaseIterable, Identifiable, Codable {
    case beginner
    case intermediate
    case advanced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .beginner: return "Anfänger"
        case .intermediate: return "Fortgeschritten"
        case .advanced: return "Erfahren"
        }
    }
}

public enum SessionDuration: String, CaseIterable, Identifiable, Codable {
    case short
    case medium
    case long

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .short: return "Kurz (ca. 30 Min.)"
        case .medium: return "Mittel (ca. 45-60 Min.)"
        case .long: return "Lang (ca. 75-90 Min.)"
        }
    }

    /// Ungefähre Anzahl Übungen pro Trainingstag.
    var exerciseCount: Int {
        switch self {
        case .short: return 4
        case .medium: return 6
        case .long: return 8
        }
    }
}

public enum SplitType: String, CaseIterable, Identifiable, Codable {
    case fullBody
    case upperLower
    case pushPullLegs
    case bodyPart

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fullBody: return "Ganzkörper"
        case .upperLower: return "Oberkörper / Unterkörper"
        case .pushPullLegs: return "Push / Pull / Legs"
        case .bodyPart: return "Muskelgruppen-Split (je Tag ein Fokus)"
        }
    }

    public var explanation: String {
        switch self {
        case .fullBody: return "Jede Einheit trainiert den ganzen Körper - gut bei 2-3 Trainingstagen/Woche."
        case .upperLower: return "Wechsel zwischen Ober- und Unterkörper - gut bei 4 Trainingstagen/Woche."
        case .pushPullLegs: return "Drück-, Zug- und Beinübungen getrennt - gut ab 3, ideal bei 6 Trainingstagen/Woche."
        case .bodyPart: return "Jeder Tag hat einen eigenen Muskelgruppen-Schwerpunkt - für mehr Trainingstage/Woche."
        }
    }

    /// Liste der Tages-Vorlagen (Name + Ziel-Muskelgruppen), die zyklisch auf
    /// die gewünschte Anzahl Trainingstage/Woche verteilt werden.
    func dayTemplates() -> [(name: String, muscles: [MuscleGroup])] {
        switch self {
        case .fullBody:
            return [("Ganzkörper", [.chest, .upperBack, .lats, .shoulders, .quads, .hamstrings, .glutes, .biceps, .triceps, .abs])]
        case .upperLower:
            return [
                ("Oberkörper", [.chest, .upperBack, .lats, .shoulders, .biceps, .triceps, .traps]),
                ("Unterkörper", [.quads, .hamstrings, .glutes, .calves, .abs])
            ]
        case .pushPullLegs:
            return [
                ("Push (Brust/Schultern/Trizeps)", [.chest, .shoulders, .triceps]),
                ("Pull (Rücken/Bizeps)", [.upperBack, .lats, .biceps, .traps]),
                ("Legs (Beine)", [.quads, .hamstrings, .glutes, .calves, .abs])
            ]
        case .bodyPart:
            return [
                ("Brust", [.chest, .triceps]),
                ("Rücken", [.upperBack, .lats, .biceps, .traps]),
                ("Schultern", [.shoulders, .traps]),
                ("Beine", [.quads, .hamstrings, .glutes, .calves]),
                ("Arme", [.biceps, .triceps, .forearms]),
                ("Bauch", [.abs, .obliques, .lowerBack])
            ]
        }
    }
}

public struct PlanGeneratorInput {
    public var splitType: SplitType
    public var daysPerWeek: Int
    public var experienceLevel: ExperienceLevel
    public var goal: TrainingGoal
    public var availableEquipment: Set<Equipment>
    public var sessionDuration: SessionDuration
    /// Muskelgruppen, die wegen Verletzungen/Einschränkungen möglichst
    /// gemieden werden sollen (weder primär noch sekundär belastet).
    public var excludedMuscles: Set<MuscleGroup>

    public init(splitType: SplitType, daysPerWeek: Int, experienceLevel: ExperienceLevel, goal: TrainingGoal, availableEquipment: Set<Equipment>, sessionDuration: SessionDuration, excludedMuscles: Set<MuscleGroup> = []) {
        self.splitType = splitType
        self.daysPerWeek = daysPerWeek
        self.experienceLevel = experienceLevel
        self.goal = goal
        self.availableEquipment = availableEquipment
        self.sessionDuration = sessionDuration
        self.excludedMuscles = excludedMuscles
    }
}

/// Rein regelbasierter, lokaler Trainingsplan-Generator (keine externe KI,
/// keine Internetverbindung nötig): wählt anhand von Split, Zielen,
/// Erfahrung, verfügbarem Equipment und Einschränkungen passende Übungen aus
/// der bestehenden Bibliothek und legt sinnvolle Satz-/Wiederholungszahlen
/// sowie Aufwärmsätze fest.
public enum PlanGenerator {

    public struct GeneratedDay {
        public let name: String
        public let items: [GeneratedItem]
    }

    public struct GeneratedItem {
        public let exercise: Exercise
        public let targetSets: Int
        public let targetReps: Int
        public let warmupSetCount: Int
    }

    public static func generate(from input: PlanGeneratorInput) -> [GeneratedDay] {
        let templates = input.splitType.dayTemplates()
        var usedExerciseIds = Set<String>()
        var days: [GeneratedDay] = []

        for dayIndex in 0..<max(input.daysPerWeek, 1) {
            let template = templates[dayIndex % templates.count]
            // Bei mehr Trainingstagen als Vorlagen (z.B. 6x Ganzkörper) den
            // Tagesnamen durchnummerieren, damit Tage unterscheidbar bleiben.
            let cycle = dayIndex / templates.count
            let dayName = templates.count > 1 || cycle == 0 ? template.name : "\(template.name) \(cycle + 1)"

            let items = selectExercises(
                for: template.muscles,
                input: input,
                usedExerciseIds: &usedExerciseIds,
                exerciseCount: input.sessionDuration.exerciseCount
            )
            days.append(GeneratedDay(name: dayName, items: items))
        }
        return days
    }

    private static func selectExercises(
        for muscles: [MuscleGroup],
        input: PlanGeneratorInput,
        usedExerciseIds: inout Set<String>,
        exerciseCount: Int
    ) -> [GeneratedItem] {
        let eligible = ExerciseLibrary.all.filter { exercise in
            exercise.category == .strength
                && (exercise.equipment == .bodyweight || input.availableEquipment.contains(exercise.equipment))
                && exercise.allMuscles.allSatisfy { !input.excludedMuscles.contains($0) }
        }

        var selected: [Exercise] = []
        // Pro Ziel-Muskelgruppe mindestens eine Übung, solange noch Plätze frei sind.
        for muscle in muscles where selected.count < exerciseCount {
            let candidates = eligible
                .filter { $0.primaryMuscles.contains(muscle) && !usedExerciseIds.contains($0.id) && !selected.contains($0) }
                .sorted { $0.allMuscles.count > $1.allMuscles.count } // Verbundübungen zuerst
            guard let pick = candidates.first else { continue }
            selected.append(pick)
            usedExerciseIds.insert(pick.id)
        }

        // Verbleibende Plätze mit weiteren passenden Übungen aus denselben
        // Ziel-Muskelgruppen auffüllen (z.B. bei langer Trainingsdauer).
        var muscleIndex = 0
        while selected.count < exerciseCount, !muscles.isEmpty {
            let muscle = muscles[muscleIndex % muscles.count]
            muscleIndex += 1
            if muscleIndex > muscles.count * 4 { break } // Sicherheitsnetz gegen Endlosschleife bei zu wenig Übungen

            let candidates = eligible
                .filter { $0.primaryMuscles.contains(muscle) && !selected.contains($0) }
                .sorted { $0.allMuscles.count > $1.allMuscles.count }
            guard let pick = candidates.first(where: { !usedExerciseIds.contains($0.id) }) ?? candidates.first else { continue }
            selected.append(pick)
            usedExerciseIds.insert(pick.id)
        }

        // Verbundübungen (mehr beteiligte Muskeln) zuerst in der Einheit.
        selected.sort { $0.allMuscles.count > $1.allMuscles.count }

        return selected.map { exercise in
            let isCompound = exercise.allMuscles.count >= 2
            let (sets, reps) = setsAndReps(goal: input.goal, experience: input.experienceLevel, isCompound: isCompound)
            let warmupSetCount = isCompound && exercise.equipment != .bodyweight ? 2 : (isCompound ? 1 : 0)
            return GeneratedItem(exercise: exercise, targetSets: sets, targetReps: reps, warmupSetCount: warmupSetCount)
        }
    }

    private static func setsAndReps(goal: TrainingGoal, experience: ExperienceLevel, isCompound: Bool) -> (sets: Int, reps: Int) {
        var (sets, reps): (Int, Int) = {
            switch goal {
            case .strength: return isCompound ? (4, 5) : (3, 8)
            case .hypertrophy: return isCompound ? (4, 10) : (3, 12)
            case .generalFitness: return (3, 12)
            case .fatLoss: return (3, 15)
            }
        }()

        switch experience {
        case .beginner: sets = max(2, sets - 1)
        case .intermediate: break
        case .advanced: sets = min(5, sets + 1)
        }

        return (sets, reps)
    }
}
