import Foundation
import Supabase

enum Config {
    static let supabaseURL = URL(string: "https://ezhncubadxbyjaiuzima.supabase.co")!
    /// Publishable key: safe to ship in the app. Row-level security decides what each signed-in user can see.
    static let supabaseKey = "sb_publishable_fHi05k7K6I6atHwOcjFMrQ_wBW3vlQj"
    static let urlScheme = "tandem"
    static let bucket = "pet-files"

    static func inviteURL(code: String) -> URL {
        URL(string: "\(urlScheme)://join?code=\(code)")!
    }
}

enum Backend {
    static let client: SupabaseClient = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = PostgrestClient.Configuration.jsonEncoder.dateEncodingStrategy

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = PostgrestClient.Configuration.jsonDecoder.dateDecodingStrategy

        return SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabaseKey,
            options: SupabaseClientOptions(
                db: .init(encoder: encoder, decoder: decoder),
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }()
}

/// Turns backend errors into something a person can act on.
func friendlyMessage(for error: Error) -> String {
    if let e = error as? PostgrestError {
        if e.code == "42501" { return "You don't have access to do that." }
        return e.message
    }
    if let e = error as? AuthError {
        let text = e.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login") { return "That email and password don't match." }
        if text.localizedCaseInsensitiveContains("already registered") { return "There's already an account with that email. Try signing in." }
        if text.localizedCaseInsensitiveContains("not confirmed") { return "Check your email to confirm your account, then sign in." }
        return text
    }
    if (error as? URLError) != nil { return "Can't reach the server. Check your connection and try again." }
    return error.localizedDescription
}
