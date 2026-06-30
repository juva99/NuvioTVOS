//
//  AuthConfig.swift
//  NuvioTV
//
//  Backend credentials for the Supabase-backed account system.
//

import Foundation

/// Supabase credentials for the account / TV-login system.
///
/// These mirror the Android app's `local.properties` values
/// (`SUPABASE_URL` / `SUPABASE_ANON_KEY`). They are intentionally left blank in
/// source control — fill them in before shipping, or inject them at build time.
///
/// When `supabaseURL` or `anonKey` is empty the login screen still renders but
/// shows a "not configured" notice instead of contacting the backend.
enum AuthConfig {
    /// e.g. "https://xxxxxxxx.supabase.co"
    static let supabaseURL = ""

    /// Supabase anon / public API key.
    static let anonKey = ""

    /// Base URL the phone opens to approve a TV login. Matches the Android
    /// `TV_LOGIN_WEB_BASE_URL` default; the backend ultimately returns the real
    /// `web_url` to encode in the QR code, so this is only a fallback hint.
    static let tvLoginWebBaseURL = "https://app.nuvio.tv/tv-login"

    static var isConfigured: Bool {
        !supabaseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !anonKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static var normalizedSupabaseURL: String {
        var url = supabaseURL.trimmingCharacters(in: .whitespaces)
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}
