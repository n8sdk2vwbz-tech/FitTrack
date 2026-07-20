import Foundation
import AuthenticationServices
import UIKit

enum StravaError: LocalizedError {
    case missingCode
    case notConnected
    case uploadFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingCode: return "Strava hat keinen Autorisierungs-Code zurückgegeben."
        case .notConnected: return "Nicht mit Strava verbunden."
        case .uploadFailed(let status): return "Strava-Upload fehlgeschlagen (Status \(status))."
        }
    }
}

private struct StravaTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

/// Kapselt die Strava-Anbindung: OAuth-Login per `ASWebAuthenticationSession`
/// (kein eigenes Web-View, Strava-Login läuft im sicheren System-Kontext),
/// Token-Verwaltung im Schlüsselbund und den Upload einzelner Trainings als
/// manuelle (GPS-lose) Aktivität. Bewusst die "private Nutzung"-Variante mit
/// eingebettetem Client Secret direkt in der App (siehe `StravaConfig`) -
/// für eine öffentliche Veröffentlichung müsste der Token-Austausch
/// stattdessen über einen eigenen Server laufen, der das Secret hält.
@MainActor
final class StravaManager: NSObject, ObservableObject {
    static let shared = StravaManager()

    @Published private(set) var isConnected: Bool
    /// Ob abgeschlossene, direkt in FitTrack geloggte Trainings automatisch
    /// hochgeladen werden (siehe `autoUploadIfNeeded`). Absichtlich nicht für
    /// aus Health importierte Einheiten (z.B. Läufe) - die kommen über Stravas
    /// eigenen Health-Sync oft schon selbst an, ein zusätzlicher Upload würde
    /// sie doppelt anlegen.
    @Published var autoUploadEnabled: Bool {
        didSet { UserDefaults.standard.set(autoUploadEnabled, forKey: Self.autoUploadDefaultsKey) }
    }

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private var authSession: ASWebAuthenticationSession?

    private enum Keys {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let expiresAt = "expiresAt"
    }
    private static let autoUploadDefaultsKey = "stravaAutoUploadEnabled"

    private override init() {
        let storedRefreshToken = KeychainHelper.get(Keys.refreshToken)
        accessToken = KeychainHelper.get(Keys.accessToken)
        refreshToken = storedRefreshToken
        if let expiresString = KeychainHelper.get(Keys.expiresAt), let interval = Double(expiresString) {
            tokenExpiresAt = Date(timeIntervalSince1970: interval)
        }
        isConnected = storedRefreshToken != nil
        autoUploadEnabled = (UserDefaults.standard.object(forKey: Self.autoUploadDefaultsKey) as? Bool) ?? true
        super.init()
    }

    func connect() async throws {
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: StravaConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: StravaConfig.redirectURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:write,read")
        ]

        guard let authURL = components.url, let callbackScheme = StravaConfig.redirectURL.scheme else {
            throw StravaError.missingCode
        }

        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = items.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: StravaError.missingCode)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            authSession = session
            session.start()
        }

        try await exchangeCodeForTokens(code: code)
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        KeychainHelper.remove(Keys.accessToken)
        KeychainHelper.remove(Keys.refreshToken)
        KeychainHelper.remove(Keys.expiresAt)
        isConnected = false
    }

    /// Lädt eine `WorkoutSession` hoch, sofern verbunden, automatischer
    /// Upload aktiviert ist und sie nicht aus Health importiert wurde (siehe
    /// `autoUploadEnabled`). Bewusst best-effort (Fehler werden verschluckt) -
    /// scheitert der Hintergrund-Upload, bleibt der manuelle Weg (Wischen im
    /// Verlauf) als Rückfalloption, ohne bei jedem Training eine Fehlermeldung
    /// zu zeigen.
    func autoUploadIfNeeded(session: WorkoutSession) async {
        guard isConnected, autoUploadEnabled, session.source != .health else { return }
        try? await uploadActivity(for: session)
    }

    /// Manueller Upload (z.B. per Wisch-Geste im Verlauf) - wirft im
    /// Fehlerfall, damit der Aufrufer eine Rückmeldung anzeigen kann.
    func uploadActivity(for session: WorkoutSession) async throws {
        let totalVolume = session.entries.reduce(0.0) { $0 + $1.totalVolume }
        var descriptionParts: [String] = []
        if totalVolume > 0 { descriptionParts.append("\(Int(totalVolume.rounded())) kg bewegt") }
        if let rpe = session.perceivedExertion { descriptionParts.append("Anstrengung \(rpe)/10") }
        let description = descriptionParts.isEmpty ? nil : descriptionParts.joined(separator: " · ")

        try await uploadActivity(
            name: session.activityName,
            startDate: session.date,
            durationSeconds: session.durationSeconds,
            description: description
        )
    }

    /// Lädt ein abgeschlossenes Training als manuelle (GPS-lose) Aktivität
    /// hoch - der dafür vorgesehene Strava-Endpunkt für Einheiten ohne
    /// eigenen Track (im Gegensatz zum Datei-Upload für Cardio mit GPS).
    func uploadActivity(name: String, startDate: Date, durationSeconds: Double, description: String?) async throws {
        try await refreshAccessTokenIfNeeded()
        guard let accessToken else { throw StravaError.notConnected }

        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/activities")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "name": name,
            "type": "WeightTraining",
            "sport_type": "WeightTraining",
            "start_date_local": ISO8601DateFormatter().string(from: startDate),
            "elapsed_time": max(1, Int(durationSeconds))
        ]
        if let description { body["description"] = description }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw StravaError.uploadFailed(status)
        }
    }

    private func exchangeCodeForTokens(code: String) async throws {
        let response = try await tokenRequest(bodyParams: [
            "client_id": StravaConfig.clientId,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ])
        store(response: response)
    }

    /// Erneuert das Zugriffs-Token, falls es abgelaufen (oder in Kürze
    /// abläuft) ist - Zugriffs-Tokens gelten bei Strava nur 6 Stunden.
    private func refreshAccessTokenIfNeeded() async throws {
        if let tokenExpiresAt, tokenExpiresAt > Date().addingTimeInterval(60), accessToken != nil {
            return
        }
        guard let refreshToken else { throw StravaError.notConnected }

        let response = try await tokenRequest(bodyParams: [
            "client_id": StravaConfig.clientId,
            "client_secret": StravaConfig.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
        store(response: response)
    }

    private func tokenRequest(bodyParams: [String: String]) async throws -> StravaTokenResponse {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(StravaTokenResponse.self, from: data)
    }

    private func store(response: StravaTokenResponse) {
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        tokenExpiresAt = Date(timeIntervalSince1970: TimeInterval(response.expiresAt))
        KeychainHelper.set(response.accessToken, forKey: Keys.accessToken)
        KeychainHelper.set(response.refreshToken, forKey: Keys.refreshToken)
        KeychainHelper.set(String(response.expiresAt), forKey: Keys.expiresAt)
        isConnected = true
    }
}

extension StravaManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
