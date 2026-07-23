import SwiftUI

public extension FatigueLevel {
    var color: Color {
        switch self {
        case .noData: return .gray
        case .fresh: return .blue
        case .optimal: return .green
        case .elevated: return .orange
        case .highStrain: return .red
        }
    }
}

public extension ShortTermReadiness {
    var color: Color {
        switch self {
        case .noData: return .gray
        case .recovering: return .orange
        case .ready: return .green
        }
    }

    var label: String {
        switch self {
        case .noData: return "Keine Daten"
        case .recovering(let hoursRemaining): return "Noch ~\(Int(hoursRemaining.rounded()))h"
        case .ready: return "Bereit"
        }
    }
}

public extension ReadinessCategory {
    var color: Color {
        switch self {
        case .optimal: return .green
        case .adequate: return .blue
        case .compromised: return .orange
        case .low: return .red
        }
    }
}
