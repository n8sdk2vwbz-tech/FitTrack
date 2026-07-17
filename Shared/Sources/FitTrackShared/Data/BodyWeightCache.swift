import Foundation

/// Bestmöglicher, synchron lesbarer Zwischenspeicher für das zuletzt aus
/// Health gelesene Körpergewicht. Wird für Übungen mit `ExerciseLoadType`
/// `.bodyweightPlus`/`.bodyweightMinus` gebraucht (z.B. Klimmzüge mit
/// Zusatzgewicht, unterstützende Klimmzugmaschine) - die eigentlichen
/// Volumen-Berechnungen (`SetEntry.volume`, `ExerciseEntry.totalVolume`)
/// laufen synchron in vielen SwiftUI-Views, HealthKit-Abfragen sind aber nur
/// async möglich. Wird daher periodisch im Hintergrund aktualisiert (siehe
/// `DashboardViewModel.refresh`), statt bei jeder Berechnung neu abgefragt
/// zu werden.
public final class BodyWeightCache {
    public static let shared = BodyWeightCache()

    public private(set) var currentKg: Double?

    private init() {}

    public func refresh() async {
        if let value = await HealthKitManager.shared.fetchLatestBodyWeight() {
            currentKg = value
        }
    }
}
