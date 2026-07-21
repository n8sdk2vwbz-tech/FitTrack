import SwiftUI
import SwiftData
import UIKit

/// Erlaubt, einen Trainingsplan von Claude/ChatGPT generieren zu lassen: ein
/// vorgefertigter Prompt (mit dem erwarteten JSON-Format) wird in die
/// Zwischenablage kopiert, die KI-Antwort danach hier eingefügt und in einen
/// echten Plan umgewandelt. Bewusst ohne Server/Login (siehe Gespräch dazu) -
/// der Nutzer bleibt selbst die Brücke zwischen ReadyLift und der KI-App.
struct AIPlanImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var onCreated: (TrainingPlan) -> Void

    @State private var pastedText = ""
    @State private var errorMessage: String?
    @State private var didCopyPrompt = false

    private let promptTemplate = """
    Erstelle einen Trainingsplan für mich und gib ihn NUR als JSON in genau diesem Format aus, ohne weitere Erklärungen davor oder danach:

    {
      "name": "Plan-Name",
      "notes": "Kurze Beschreibung (optional)",
      "days": [
        {
          "name": "Tag 1",
          "items": [
            {
              "exerciseName": "Bankdrücken (Langhantel)",
              "targetSets": 4,
              "targetReps": 8,
              "targetRepsMax": 10,
              "warmupSetCount": 2,
              "notes": ""
            }
          ]
        }
      ]
    }

    Hinweise: "targetRepsMax" ist optional (nur bei einer Wdh.-Spanne wie 8-10 angeben, sonst weglassen). "warmupSetCount" ist optional (0, falls keine Aufwärmsätze gewünscht).

    Meine Wünsche: [hier ergänzen - Ziel, Trainingstage pro Woche, verfügbare Geräte, Erfahrungslevel, Verletzungen/Einschränkungen, etc.]
    """

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Kopiere den Prompt, ergänze am Ende deine Wünsche und schick ihn an Claude oder ChatGPT. Füge die Antwort danach unten ein.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        UIPasteboard.general.string = promptTemplate
                        didCopyPrompt = true
                    } label: {
                        Label(didCopyPrompt ? "Prompt kopiert" : "Prompt kopieren", systemImage: didCopyPrompt ? "checkmark" : "doc.on.doc")
                    }
                }

                Section("Antwort der KI einfügen") {
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 180)
                        .font(.caption.monospaced())
                        // Verhindert, dass iOS beim Einfügen gerade
                        // Anführungszeichen automatisch durch typografische
                        // ersetzt - würde sonst gültiges JSON kaputt machen
                        // (siehe Normalisierung in `AIPlanImporter.parse`,
                        // die das zusätzlich zur Sicherheit auch rückgängig macht).
                        .autocorrectionDisabled()
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Mit KI erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") { importPlan() }
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func importPlan() {
        do {
            let payload = try AIPlanImporter.parse(pastedText)
            let plan = AIPlanImporter.makeTrainingPlan(from: payload)
            modelContext.insert(plan)
            try modelContext.save()
            onCreated(plan)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Der eingefügte Text konnte nicht als Plan gelesen werden."
        }
    }
}
