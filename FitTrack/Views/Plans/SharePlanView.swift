import SwiftUI
import CoreImage.CIFilterBuiltins
import FitTrackShared

/// Zeigt einen Plan als QR-Code (falls kompakt genug, um zuverlässig scannbar
/// zu sein) und/oder als teilbarer `readylift://`-Link (Nachrichten, AirDrop,
/// Mail, ...) - beide Wege lösen beim Empfänger denselben `onOpenURL`-Import
/// aus. Bewusst ohne Gewichte, nur Übungen/Sätze-Wdh./Notizen werden übernommen.
struct SharePlanView: View {
    let plan: TrainingPlan
    @Environment(\.dismiss) private var dismiss

    private var shareURL: URL? {
        PlanSharePayload.url(for: plan.toSharedDTO())
    }

    private var isQRFeasible: Bool {
        guard let shareURL else { return false }
        return shareURL.absoluteString.count <= PlanSharePayload.maxReliableQRLength
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let shareURL {
                    Group {
                        if isQRFeasible, let qrImage = Self.qrCodeImage(from: shareURL.absoluteString) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260)
                            Text("Mit der Kamera-App scannen lassen - öffnet den Plan direkt zum Importieren.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            ContentUnavailableView(
                                "Plan zu groß für einen QR-Code",
                                systemImage: "qrcode",
                                description: Text("Zu viele Tage/Übungen für einen zuverlässig scannbaren Code - nutze stattdessen den Link unten.")
                            )
                        }
                    }

                    ShareLink(item: shareURL) {
                        Label("Link teilen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Nur Übungen, Sätze/Wiederholungen und Notizen werden übertragen - Gewichte startet jede Person selbst bei 0.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Plan konnte nicht kodiert werden.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 24)
            .padding(.horizontal)
            .navigationTitle("Plan teilen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private static func qrCodeImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
