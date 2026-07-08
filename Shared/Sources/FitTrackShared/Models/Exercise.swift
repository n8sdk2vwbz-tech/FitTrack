import Foundation

public enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case strength
    case cardio
    case mobility

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strength: return "Kraft"
        case .cardio: return "Ausdauer"
        case .mobility: return "Mobilität"
        }
    }
}

public enum Equipment: String, Codable, CaseIterable, Identifiable {
    case none
    case barbell
    case dumbbell
    case kettlebell
    case machine
    case cable
    case bodyweight
    case band
    case bike
    case treadmill

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "Kein Gerät"
        case .barbell: return "Langhantel"
        case .dumbbell: return "Kurzhantel"
        case .kettlebell: return "Kettlebell"
        case .machine: return "Maschine"
        case .cable: return "Kabelzug"
        case .bodyweight: return "Körpergewicht"
        case .band: return "Widerstandsband"
        case .bike: return "Fahrrad"
        case .treadmill: return "Laufband"
        }
    }
}

/// Statische Übungs-Definition aus der Bibliothek. Kein SwiftData-Modell,
/// da diese Daten fest mit der App ausgeliefert werden und auf iPhone
/// und Watch identisch verfügbar sein müssen, ohne Sync-Bedarf.
public struct Exercise: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let category: ExerciseCategory
    public let equipment: Equipment
    public let primaryMuscles: [MuscleGroup]
    public let secondaryMuscles: [MuscleGroup]
    public let instructions: String

    public init(id: String, name: String, category: ExerciseCategory, equipment: Equipment, primaryMuscles: [MuscleGroup], secondaryMuscles: [MuscleGroup], instructions: String) {
        self.id = id
        self.name = name
        self.category = category
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
    }

    public var allMuscles: [MuscleGroup] {
        primaryMuscles + secondaryMuscles
    }
}
