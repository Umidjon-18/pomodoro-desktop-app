import Foundation

/// Pure helpers for the Pomodoro block in /etc/hosts. Mirrors the validation and
/// output format of the root helper script `pomodoro-hosts`.
enum HostsBlock {
    static let beginMarker = "# >>> pomodoro >>>"
    static let endMarker = "# <<< pomodoro <<<"

    /// Turns user input such as "https://www.YouTube.com/watch?v=1" into "youtube.com".
    /// Returns nil when the result is not a blockable hostname.
    static func normalize(_ raw: String) -> String? {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return nil }

        if let scheme = host.range(of: "://") {
            host = String(host[scheme.upperBound...])
        }
        if let end = host.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            host = String(host[..<end])
        }
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        if host.hasPrefix("*.") {
            host.removeFirst(2)
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        // Drop a leading "www." unless that would leave a single label ("www.com").
        if host.hasPrefix("www."), host.dropFirst(4).contains(".") {
            host.removeFirst(4)
        }
        return isValid(host) ? host : nil
    }

    /// Strict hostname check: lowercase ASCII letters, digits and '-', at least two
    /// dot-separated labels of 1–63 characters that neither start nor end with '-',
    /// at most 253 characters, and a non-numeric last label (IPv4 literals are rejected).
    static func isValid(_ domain: String) -> Bool {
        guard (1...253).contains(domain.utf8.count) else { return false }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.utf8.count),
                  label.first != "-", label.last != "-",
                  label.unicodeScalars.allSatisfy(isHostCharacter)
            else { return false }
        }
        if let tld = labels.last, tld.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) {
            return false
        }
        return true
    }

    /// Hosts lines for the given domains (invalid ones are skipped), plus a "www."
    /// variant for domains that do not already start with "www.".
    static func entries(for domains: [String]) -> [String] {
        domains.filter(isValid).flatMap { domain -> [String] in
            var lines = ["0.0.0.0 \(domain)", "::1 \(domain)"]
            if !domain.hasPrefix("www.") {
                lines += ["0.0.0.0 www.\(domain)", "::1 www.\(domain)"]
            }
            return lines
        }
    }

    /// The blocked domain a page URL belongs to, matching the domain itself and every subdomain
    /// ("m.youtube.com" matches "youtube.com"; "notyoutube.com" does not). Nil for non-web URLs.
    static func blockedDomain(forURL url: String, in domains: [String]) -> String? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return domains.first { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func isHostCharacter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
    }
}
