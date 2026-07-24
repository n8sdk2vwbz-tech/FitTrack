import Foundation

public struct RecoveryInputs {
    public var sleepHours: Double?
    /// Anteil Schlafzeit an der Zeit im Bett (0-1).
    public var sleepEfficiency: Double?
    public var hrvMs: Double?
    /// Rollender Basiswert der letzten ~14 Nächte.
    public var hrvBaselineMs: Double?
    public var restingHeartRate: Double?
    public var restingHeartRateBaseline: Double?
    /// Gesamt-Trainingslast über alle Muskeln aus `MuscleLoadCalculator.overallLoad`.
    public var acuteLoad: Double
    public var chronicLoad: Double
    /// Anzahl bisher geloggter Trainingseinheiten mit tatsächlichem Volumen
    /// (nicht Kalendertage - mehrere Einheiten am selben Tag zählen einzeln).
    /// Ab `RecoveryEngine`s Schwelle (siehe dort) fließt zusätzlich die
    /// langfristige Belastung (ACWR) ein; davor zählt nur die aktuelle Einheit.
    public var sessionCount: Int
    /// Kombinierte Belastung (Volumen × wahrgenommene Anstrengung) ALLER
    /// Einheiten der letzten `RecoveryEngine.recentSessionLoadFadeDays` Tage,
    /// dabei ist jede einzelne Einheit bereits nach ihrem eigenen Alter
    /// abklingend gewichtet (siehe `DashboardViewModel`) - so behält z.B. ein
    /// hartes Bein-Training auch dann noch spürbaren Einfluss, wenn danach
    /// bereits eine neuere (z.B. Cardio-)Einheit protokolliert wurde, statt
    /// beim Erscheinen einer neueren Einheit abrupt komplett zu verschwinden.
    public var recentSessionLoad: Double
    /// Alter (in Tagen) der zuletzt protokollierten Einheit - bestimmt nur
    /// noch, wie stark der Trainingslast-Baustein gegenüber Schlaf/HRV/
    /// Ruhepuls zusätzlich gewichtet wird (`freshnessBoost`), NICHT mehr das
    /// Abklingen von `recentSessionLoad` selbst (das ist dort bereits
    /// eingerechnet).
    public var daysSinceRecentSession: Double?
    /// Persönlicher Median der Sitzungs-Last aus früheren Einheiten (ohne die
    /// aktuellste), sobald genug Historie existiert - macht `recentSessionLoad`
    /// relativ zum eigenen typischen Volumen statt gegen einen für alle
    /// gleichen absoluten Richtwert zu bewerten (siehe `RecoveryEngine`s
    /// Kommentar zu `typicalSessionLoad`). `nil`, solange zu wenig Historie
    /// existiert, um verlässlich zu sein.
    public var personalTypicalSessionLoad: Double?
    /// Gewichteter Schnitt der wahrgenommenen Anstrengung (RPE und/oder
    /// Trainings-Herzfrequenz) der letzten ca. 2 Tage, 1.0 = neutral (RPE 5).
    public var recentIntensity: Double?

    public init(sleepHours: Double?, sleepEfficiency: Double?, hrvMs: Double?, hrvBaselineMs: Double?, restingHeartRate: Double?, restingHeartRateBaseline: Double?, acuteLoad: Double, chronicLoad: Double, sessionCount: Int, recentSessionLoad: Double, daysSinceRecentSession: Double?, personalTypicalSessionLoad: Double? = nil, recentIntensity: Double?) {
        self.sleepHours = sleepHours
        self.sleepEfficiency = sleepEfficiency
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateBaseline = restingHeartRateBaseline
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.sessionCount = sessionCount
        self.recentSessionLoad = recentSessionLoad
        self.daysSinceRecentSession = daysSinceRecentSession
        self.personalTypicalSessionLoad = personalTypicalSessionLoad
        self.recentIntensity = recentIntensity
    }
}

public enum ReadinessCategory: String, Codable {
    case optimal
    case adequate
    case compromised
    case low

    public var displayName: String {
        switch self {
        case .optimal: return "Optimal erholt"
        case .adequate: return "Ausreichend erholt"
        case .compromised: return "Eingeschränkt erholt"
        case .low: return "Geringe Erholung"
        }
    }
}

public struct ReadinessResult {
    public let score: Int
    public let category: ReadinessCategory
    public let sleepScore: Int?
    public let hrvScore: Int?
    public let rhrScore: Int?
    public let trainingLoadScore: Int?
    /// Rohwerte hinter den Scores oben, rein zur Anzeige (z.B. "HRV 45 ms ·
    /// Ø 42 ms"), damit nachvollziehbar ist, warum ein Score bei 100 gedeckelt
    /// ist - die Scores selbst kappen bei Erreichen/Überschreiten des
    /// eigenen Basiswerts, zeigen also nicht, wie weit darüber man liegt.
    public let sleepHours: Double?
    public let hrvMs: Double?
    public let hrvBaselineMs: Double?
    public let restingHeartRate: Double?
    public let restingHeartRateBaseline: Double?

    public init(score: Int, category: ReadinessCategory, sleepScore: Int?, hrvScore: Int?, rhrScore: Int?, trainingLoadScore: Int?, sleepHours: Double? = nil, hrvMs: Double? = nil, hrvBaselineMs: Double? = nil, restingHeartRate: Double? = nil, restingHeartRateBaseline: Double? = nil) {
        self.score = score
        self.category = category
        self.sleepScore = sleepScore
        self.hrvScore = hrvScore
        self.rhrScore = rhrScore
        self.trainingLoadScore = trainingLoadScore
        self.sleepHours = sleepHours
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateBaseline = restingHeartRateBaseline
    }

    public var summary: String {
        switch category {
        case .optimal:
            return "Schlaf, HRV und Trainingslast sprechen für ein hohes Leistungsniveau. Ein intensives Training ist gut vertretbar."
        case .adequate:
            return "Die Erholung ist solide. Normales Training ist möglich, auf das eigene Gefühl achten."
        case .compromised:
            return "Erholungswerte sind unterdurchschnittlich. Lieber moderat trainieren oder Fokus auf weniger belastete Muskelgruppen legen."
        case .low:
            return "Schlaf, HRV oder Trainingslast deuten auf starke Ermüdung hin. Ein Ruhetag oder aktive Erholung wird empfohlen."
        }
    }
}

/// Kombiniert Schlaf-, HRV-, Ruhepuls- und Trainingslast-Daten aus HealthKit zu
/// einer täglichen Regenerations-/Bereitschaftseinschätzung (0-100), angelehnt an
/// gängige Readiness-Scores von Wearables (z.B. Verhältnis zur eigenen Baseline
/// statt absoluter Normwerte, da HRV und Ruhepuls stark individuell sind).
public enum RecoveryEngine {

    /// Ab dieser Anzahl geloggter Trainingseinheiten fließt zusätzlich die
    /// langfristige Belastung (ACWR, akut:chronisch) in den Trainingslast-
    /// Baustein ein. Davor gibt es schlicht noch keine verlässliche 28-Tage-
    /// Basis, gegen die man vergleichen könnte.
    private static let matureSessionThreshold = 10

    /// Heuristischer Referenzwert für eine "durchschnittliche" Trainingseinheit
    /// (Volumen = Gewicht × Wiederholungen, summiert über alle beteiligten
    /// Muskeln). Dient nur als genereller Vergleichsmaßstab, solange noch
    /// keine eigene Trainingshistorie existiert (`personalTypicalSessionLoad`
    /// ist dann `nil`) - grob kalibriert an 2-3 Übungen à 3 Sätzen mit
    /// moderatem Gewicht. Ein fester, für alle gleicher Wert würde sonst
    /// dauerhaft jeden, der mit geringerem absolutem Gewicht trainiert (z.B.
    /// kleiner/schwächer, oder bei Isolationsübungen), praktisch immer bei
    /// 100 belassen - unabhängig davon, wie hart sich die Einheit für diese
    /// Person tatsächlich anfühlte.
    private static let typicalSessionLoad = 1500.0

    /// Nach wie vielen Tagen die Wirkung einer protokollierten Einheit auf den
    /// Trainingslast-Baustein vollständig auf neutral (100) abgeklungen ist,
    /// statt unbegrenzt lange (auch nach z.B. einer Woche ohne neues Training)
    /// unverändert weiter voll auf den Score zu wirken. Angelehnt an
    /// `MuscleLoadCalculator`s akute (3-Tage-)Spanne plus etwas Puffer, da eine
    /// einzelne harte Einheit üblicherweise nach 3-4 Tagen spürbar abgeklungen
    /// ist (echter Muskelkater klingt oft nicht schneller ab). Öffentlich,
    /// damit `DashboardViewModel` beim Aufsummieren mehrerer letzter Einheiten
    /// dasselbe Zeitfenster verwendet statt eines eigenen, abweichenden Werts.
    public static let recentSessionLoadFadeDays = 4.0

    /// Bildet ein Belastungsverhältnis (z.B. ACWR, oder heutiges Volumen
    /// gegen einen Referenzwert) auf einen Score ab. Bewusst eine sanfte,
    /// stückweise Kurve statt einer harten linearen Funktion: eine
    /// 1:1-Skalierung (`100 - (ratio-1)*100`) sättigt bereits bei einem
    /// Verhältnis von ca. 2.0 vollständig bei 0 - dadurch hätten ein moderat
    /// hartes und ein extrem hartes Training denselben (maximalen) Effekt auf
    /// den Score, obwohl sie klar unterschiedlich belastend waren.
    ///
    /// Unterhalb von 1.3 (weniger/angemessene Belastung relativ zum
    /// Vergleichswert, inkl. vollständig ausgeruht bei Ratio 0) gibt es
    /// bewusst keinen Abzug: Für die *heutige* Bereitschaft ist Erholung
    /// immer gut, nie schlecht - anders als z.B. bei `FatigueLevel`, wo
    /// niedrige ACWR-Werte ebenfalls positiv als `.fresh` gerahmt sind. Die
    /// gegenteilige langfristige Sorge (zu wenig Trainingsreiz über Wochen,
    /// "Detraining") ist eine Trainingsplanungs-, keine Tagesbereitschafts-Frage
    /// und würde sonst z.B. einen nach einer harten Einheit voll erholten
    /// Nutzer fälschlich mit einem gesenkten Score "bestrafen".
    private static func loadRatioScore(_ ratio: Double) -> Double {
        switch ratio {
        case ..<1.3:
            return 100
        default:
            let overshoot = ratio - 1.3
            return clamp(100 - overshoot * 40, 0, 100)
        }
    }

    public static func evaluate(inputs: RecoveryInputs) -> ReadinessResult {
        var components: [(score: Double, weight: Double)] = []

        var sleepScore: Int?
        if let hours = inputs.sleepHours {
            let base = clamp(hours / 8.0 * 100, 0, 115)
            let efficiencyFactor = inputs.sleepEfficiency.map { clamp($0, 0.5, 1.0) } ?? 1.0
            let score = clamp(base * efficiencyFactor, 0, 100)
            sleepScore = Int(score.rounded())
            components.append((score, 0.30))
        }

        var hrvScore: Int?
        if let hrv = inputs.hrvMs, let baseline = inputs.hrvBaselineMs, baseline > 0 {
            let score = clamp(100 * (hrv / baseline), 0, 100)
            hrvScore = Int(score.rounded())
            components.append((score, 0.25))
        }

        var rhrScore: Int?
        if let rhr = inputs.restingHeartRate, let baseline = inputs.restingHeartRateBaseline, rhr > 0 {
            let score = clamp(100 * (baseline / rhr), 0, 100)
            rhrScore = Int(score.rounded())
            components.append((score, 0.15))
        }

        var loadScore: Int?
        var loadScoreParts: [Double] = []

        // (1) Immer verfügbar, ab der allerersten Einheit: die (bereits nach
        // Alter abklingend gewichtete, siehe `recentSessionLoad`-Dokumentation)
        // kombinierte Belastung der letzten Tage gegen den eigenen typischen
        // Wert (`personalTypicalSessionLoad`), sobald genug Historie existiert
        // - sonst gegen den generischen `typicalSessionLoad`-Richtwert, da vor
        // der ersten Einheit noch keine eigene Historie existiert. Relativ
        // zum eigenen Durchschnitt statt zu einem für alle gleichen absoluten
        // Wert zu vergleichen ist wichtig, damit z.B. jemand, der grundsätzlich
        // mit geringerem Gewicht trainiert, bei einer für diese Person
        // tatsächlich harten Einheit auch einen entsprechend reduzierten Score
        // sieht - nicht dauerhaft 100, nur weil die absoluten kg-Zahlen klein sind.
        if inputs.recentSessionLoad > 0.01 {
            let reference = inputs.personalTypicalSessionLoad ?? typicalSessionLoad
            let ratio = inputs.recentSessionLoad / reference
            loadScoreParts.append(loadRatioScore(ratio))
        }

        // (2) Immer verfügbar, sofern bewertet: wie anstrengend fühlte sich
        // das letzte Training an (RPE/Herzfrequenz)? Auch das braucht keine
        // Historie - ein einzelnes, sehr hartes erstes Training senkt den
        // Score direkt, ein leichtes senkt ihn kaum.
        if let intensity = inputs.recentIntensity {
            let score = clamp(100 - (intensity - 1.0) * 60, 0, 100)
            loadScoreParts.append(score)
        }

        // (3) Erst ab `matureSessionThreshold` Einheiten zusätzlich: die
        // langfristige Belastung (ACWR, akut:chronisch), sobald die 28-Tage-
        // Basis genug Historie hatte, um verlässlich zu sein.
        if inputs.sessionCount >= matureSessionThreshold, inputs.chronicLoad > 0.01 {
            let acwr = inputs.acuteLoad / inputs.chronicLoad
            loadScoreParts.append(loadRatioScore(acwr))
        }

        if !loadScoreParts.isEmpty {
            let combined = loadScoreParts.reduce(0, +) / Double(loadScoreParts.count)
            loadScore = Int(combined.rounded())
            // Je frischer die zuletzt protokollierte Einheit, desto mehr
            // zusätzliches Gewicht bekommt die Trainingslast gegenüber
            // Schlaf/HRV/Ruhepuls: Die drei beschreiben nur den Zustand VOR
            // dieser Einheit (Schlaf letzte Nacht, HRV/Ruhepuls als
            // Tageswerte) und können ein gerade erst absolviertes, hartes
            // Training grundsätzlich noch nicht "sehen" - ohne diesen
            // Ausgleich würde ein guter Morgen-Score direkt danach
            // fälschlich weiter volle Bereitschaft suggerieren. Klingt über
            // denselben Zeitraum wie `recentSessionLoadFadeDays` aus, bis nur
            // noch die Basisgewichtung greift.
            let freshnessBoost = clamp(1 - (inputs.daysSinceRecentSession ?? recentSessionLoadFadeDays), 0, 1) * 0.25
            components.append((combined, 0.30 + freshnessBoost))
        }

        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let finalScore: Int
        if totalWeight > 0 {
            let weighted = components.reduce(0) { $0 + $1.score * $1.weight } / totalWeight
            finalScore = Int(weighted.rounded())
        } else {
            finalScore = 70 // neutraler Default ohne jegliche Gesundheitsdaten
        }

        let category: ReadinessCategory
        switch finalScore {
        case 80...: category = .optimal
        case 60..<80: category = .adequate
        case 40..<60: category = .compromised
        default: category = .low
        }

        return ReadinessResult(
            score: finalScore,
            category: category,
            sleepScore: sleepScore,
            hrvScore: hrvScore,
            rhrScore: rhrScore,
            trainingLoadScore: loadScore,
            sleepHours: inputs.sleepHours,
            hrvMs: inputs.hrvMs,
            hrvBaselineMs: inputs.hrvBaselineMs,
            restingHeartRate: inputs.restingHeartRate,
            restingHeartRateBaseline: inputs.restingHeartRateBaseline
        )
    }

    /// Empfehlung pro Muskelgruppe: kombiniert die globale Bereitschaft mit dem
    /// spezifischen Ermüdungszustand dieses Muskels.
    public static func recommendation(for status: MuscleLoadStatus, readiness: ReadinessResult) -> String {
        // Kurzfristige Erholung von der LETZTEN Einheit hat Vorrang vor der
        // langfristigen ACWR-Einordnung unten - sonst könnte z.B. "optimal
        // belastet" (ACWR) fälschlich "bereit fürs nächste Training" ausgeben,
        // obwohl der Muskel erst vor Stunden trainiert wurde und laut
        // `shortTermReadiness` noch mitten in der Erholung steckt.
        if case .recovering(let hoursRemaining) = status.shortTermReadiness() {
            return "Vor Kurzem trainiert – voraussichtlich noch ca. \(Int(hoursRemaining.rounded())) Std. bis zur Erholung."
        }
        // Ein hohes ACWR-Verhältnis nach ruhigerer Vorzeit (Wiedereinstieg)
        // ist kein Anzeichen bestehender Überlastung, sondern eher ein
        // Hinweis, die Steigerung nicht zu abrupt zu forcieren - andere
        // Formulierung als bei tatsächlich schon hoher Basis (siehe
        // `MuscleLoadStatus.isRampingUp`).
        if status.isRampingUp, status.fatigueLevel == .elevated || status.fatigueLevel == .highStrain {
            return "Belastung steigt nach ruhigerer Zeit spürbar an – normal beim Wiedereinstieg, aber lieber schrittweise statt sprunghaft steigern."
        }
        switch (status.fatigueLevel, readiness.category) {
        case (.noData, _):
            return "Noch keine Trainingsdaten für diese Muskelgruppe."
        case (.highStrain, _):
            return "Stark beansprucht – Regeneration empfohlen."
        case (.elevated, .low), (.elevated, .compromised):
            return "Erhöhte Belastung und niedrige Erholung – heute eher schonen."
        case (.elevated, _):
            return "Erhöhte Belastung, aber Erholung ok – moderates Training möglich."
        case (.optimal, .low):
            return "Muskel bereit, aber Gesamterholung niedrig – auf den Körper hören."
        case (.optimal, _):
            return "Gut belastet und erholt – bereit für das nächste Training."
        case (.fresh, _):
            return "Lange nicht trainiert – bereit für einen neuen Trainingsreiz."
        }
    }

    private static func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}
