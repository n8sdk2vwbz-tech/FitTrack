import SwiftUI
import FitTrackShared

/// Nachbildung von Stravas offiziellem "Connect with Strava"-Button (Farbe
/// #FC4C02) - falls das originale Bild-Asset aus Stravas Brand-Guidelines
/// gewünscht ist, kann es hier eingesetzt werden.
struct ConnectWithStravaButton: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
            Text("Connect with Strava")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(red: 0.988, green: 0.298, blue: 0.008))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StravaSettingsView: View {
    @ObservedObject private var strava = StravaManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isConnecting = false
    @State private var errorMessage: String?
    /// Auf welches Raster Aufwärmgewichte gerundet werden (siehe
    /// `ActiveWorkoutView.roundToRealisticWeight`) - nicht jedes Fitnessstudio
    /// hat Hantelscheiben in 2,5-kg-Schritten, manche nur in 5-kg-Schritten.
    @AppStorage("warmupWeightIncrementKg") private var warmupWeightIncrementKg: Double = 2.5
    /// Ob die Watch nach jedem abgehakten Satz per HF-basierter Satzpause
    /// vibrieren soll, sobald der Körper erholt genug für den nächsten Satz
    /// ist (siehe `WorkoutManager.startRestMonitoringIfNeeded`). Lebt hier
    /// (statt auf der Watch selbst, die keine Settings-UI hat) und wird per
    /// `WatchConnectivityManager` synchronisiert.
    @AppStorage("restTimerEnabled") private var restTimerEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Gewichts-Schritte", selection: $warmupWeightIncrementKg) {
                        Text("2,5 kg").tag(2.5)
                        Text("5 kg").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                    Toggle("HF-basierter Satzpausen-Timer", isOn: $restTimerEnabled)
                        .onChange(of: restTimerEnabled) { _, newValue in
                            WatchConnectivityManager.shared.sendRestTimerPreference(newValue)
                        }
                } header: {
                    Text("Training")
                } footer: {
                    Text("Auf dieses Raster werden vorgeschlagene Aufwärmgewichte gerundet - praktisch, falls dein Studio keine 2,5-kg-Hantelscheiben hat.\n\nDer Satzpausen-Timer lässt die Watch vibrieren, sobald deine Herzfrequenz nach einem Satz auf einen Erholungs-Richtwert gefallen ist (oder spätestens nach 4 Minuten).")
                }

                Section {
                    if strava.isConnected {
                        Label("Verbunden mit Strava", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button(role: .destructive) {
                            strava.disconnect()
                        } label: {
                            Text("Verbindung trennen")
                        }
                    } else {
                        Button {
                            connect()
                        } label: {
                            ConnectWithStravaButton()
                        }
                        .buttonStyle(.plain)
                        .disabled(isConnecting)

                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Nach der Verbindung kannst du abgeschlossene Trainings im Verlauf einzeln manuell auf Strava hochladen.")
                }

                if strava.isConnected {
                    Section {
                        Toggle("Automatisch hochladen", isOn: $strava.autoUploadEnabled)
                    } footer: {
                        Text("Jedes in FitTrack abgeschlossene Training (live oder nachgetragen) wird direkt automatisch auf Strava hochgeladen. Aus Apple Health importierte Einheiten (z.B. Läufe) sind davon ausgenommen, da Strava diese oft schon über den eigenen Health-Sync selbst findet. Zum manuellen Nachholen (z.B. bei ausgeschalteter Automatik oder älteren Trainings) im Verlauf nach rechts wischen.")
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await strava.connect()
            } catch {
                errorMessage = "Verbindung fehlgeschlagen: \(error.localizedDescription)"
            }
            isConnecting = false
        }
    }
}
