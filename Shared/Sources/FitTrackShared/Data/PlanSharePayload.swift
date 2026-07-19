import Foundation

/// Kodiert/dekodiert einen `SharedPlanDTO` als `readylift://`-Link, der sich
/// sowohl als QR-Code (Scannen mit der System-Kamera erkennt den Link und
/// bietet an, ihn in der App zu öffnen - kein eigener Scanner in der App
/// nötig) als auch als normaler Link über die iOS-Teilen-Funktion (Nachrichten,
/// AirDrop, Mail, ...) verschicken lässt - beide Wege laufen über denselben
/// `onOpenURL`-Empfang, ohne dass ein eigenes Dateiformat/Dokumenttyp nötig wäre.
public enum PlanSharePayload {
    public static let urlScheme = "readylift"
    public static let host = "import-plan"
    private static let queryItemName = "plan"

    /// Ab dieser Zeichenlänge wird ein QR-Code zu dicht/unzuverlässig scannbar
    /// - jenseits davon sollte nur noch der Teilen-Link angeboten werden.
    public static let maxReliableQRLength = 900

    public static func url(for plan: SharedPlanDTO) -> URL? {
        guard let data = try? JSONEncoder().encode(plan) else { return nil }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = host
        components.queryItems = [URLQueryItem(name: queryItemName, value: encoded)]
        return components.url
    }

    public static func decode(from url: URL) -> SharedPlanDTO? {
        guard url.scheme == urlScheme, url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == queryItemName })?.value else { return nil }
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // URL-Encoding verliert oft das Padding ("="), ohne das Base64 nicht
        // dekodierbar ist - hier wieder auf ein Vielfaches von 4 auffüllen.
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(SharedPlanDTO.self, from: data)
    }
}
