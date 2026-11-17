import Foundation

/// Which host the SDK WebView loads from.
///
/// `standard` is the Verisoul host for the environment. `custom` is a customer hostname passed
/// to `configure`, used for every load attempt with no fallback to the Verisoul host. `invalid`
/// means a hostname was passed but is unusable: the WebView then fails with SESSION_UNAVAILABLE
/// so a broken integration is visible, and the Verisoul host is never loaded in its place.
enum WebViewHostConfig: Equatable {
    case standard
    case custom(String)
    case invalid(reason: String)
}

enum CustomHostname {

    static let invalidMessage = "Invalid custom hostname"

    private static let maxHostnameLength = 253
    private static let maxLabelLength = 63
    private static let labelCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
    private static let ipv4Characters = CharacterSet(charactersIn: "0123456789.")

    /// Normalizes the hostname passed to `configure`.
    ///
    /// Accepts a bare DNS hostname such as "js.example.com". Surrounding whitespace, upper case and
    /// one trailing dot are normalized. A scheme, port, path, query, userinfo, IP literal or inner
    /// whitespace makes the value invalid.
    static func resolve(_ raw: String?) -> WebViewHostConfig {
        guard let raw else { return .standard }

        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasSuffix(".") { host.removeLast() }

        if host.isEmpty { return .invalid(reason: "empty") }
        if host.count > maxHostnameLength { return .invalid(reason: "too_long") }
        if host.contains("://") { return .invalid(reason: "has_scheme") }
        if host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return .invalid(reason: "has_whitespace")
        }
        if host.contains("@") { return .invalid(reason: "has_userinfo") }
        if host.contains("/") || host.contains("?") || host.contains("#") {
            return .invalid(reason: "has_path")
        }
        if host.contains(":") || host.contains("[") || host.contains("]") {
            return .invalid(reason: "has_port_or_ip_literal")
        }
        if host.unicodeScalars.allSatisfy({ ipv4Characters.contains($0) }) {
            return .invalid(reason: "ip_literal")
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count < 2 { return .invalid(reason: "no_dot") }
        for label in labels {
            let valid = !label.isEmpty
                && label.count <= maxLabelLength
                && label.unicodeScalars.allSatisfy { labelCharacters.contains($0) }
                && !label.hasPrefix("-")
                && !label.hasSuffix("-")
            if !valid { return .invalid(reason: "bad_label") }
        }
        return .custom(host)
    }
}
