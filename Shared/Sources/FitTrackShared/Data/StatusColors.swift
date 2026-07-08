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
