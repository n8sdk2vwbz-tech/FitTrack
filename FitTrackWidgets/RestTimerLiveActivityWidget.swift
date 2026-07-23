import ActivityKit
import WidgetKit
import SwiftUI
import FitTrackShared

/// Live Activity fürs aktive Training - siehe `RestTimerActivityAttributes`
/// (Datenmodell, in `FitTrackShared` geteilt mit der App) und
/// `LiveActivityManager` (App-Target, startet/aktualisiert/beendet sie).
/// Zeigt Puls, Pausen-Zeit und den nächsten Satz auf Sperrbildschirm/Dynamic
/// Island, inkl. interaktivem Abhaken/Wdh.-Anpassen ohne die App zu öffnen.
struct RestTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerActivityAttributes.self) { context in
            LockScreenRestTimerView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(context.state.heartRate))")
                            .font(.title2.bold())
                            .foregroundStyle(.red)
                        Text("bpm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isResting {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(context.state.restElapsedSeconds)s")
                                .font(.title2.bold())
                                .foregroundStyle(.orange)
                            if let target = context.state.restTargetHeartRate {
                                Text("Ziel \(target) bpm")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("fixe Wartezeit")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Bereit")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.nextExerciseName)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.hasNextSet {
                        RestTimerControls(state: context.state)
                    }
                }
            } compactLeading: {
                Text("\(Int(context.state.heartRate))")
                    .foregroundStyle(.red)
            } compactTrailing: {
                if context.state.isResting {
                    Text("\(context.state.restElapsedSeconds)s")
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            } minimal: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct LockScreenRestTimerView: View {
    let state: RestTimerActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(state.heartRate)) bpm")
                        .font(.headline)
                        .foregroundStyle(.red)
                    if state.isResting {
                        Text("Pause: \(state.restElapsedSeconds)s")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        if let target = state.restTargetHeartRate {
                            Text("Ziel: \(target) bpm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Ziel: fixe Wartezeit")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Bereit für den nächsten Satz")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                if state.hasNextSet {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(state.nextExerciseName)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text(setLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if state.hasNextSet {
                RestTimerControls(state: state)
            }
        }
        .padding()
    }

    private var setLabel: String {
        var text = "\(state.nextSetReps) Wdh."
        if let weight = state.nextSetWeightKg {
            text += " · \(String(format: "%.1f", weight)) kg"
        }
        if state.nextSetIsWarmup {
            text += " (Aufwärmen)"
        }
        return text
    }
}

/// Interaktive Buttons - nur ab iOS 17 möglich (`Button(intent:)` in Live
/// Activities), das Projekt-Deployment-Target liegt bereits bei 17.0.
private struct RestTimerControls: View {
    let state: RestTimerActivityAttributes.ContentState

    var body: some View {
        HStack {
            Button(intent: AdjustNextSetRepsIntent(delta: -1)) {
                Image(systemName: "minus.circle")
            }
            Text("\(state.nextSetReps)")
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 24)
            Button(intent: AdjustNextSetRepsIntent(delta: 1)) {
                Image(systemName: "plus.circle")
            }
            Spacer()
            Button(intent: CompleteSetLiveActivityIntent()) {
                Label("Satz erledigt", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
        .buttonStyle(.plain)
        .font(.title3)
    }
}
