import XCTest
@testable import Pomodoro

final class HostsBlockTests: XCTestCase {

    // MARK: normalize

    func testNormalizeStripsURLParts() {
        XCTAssertEqual(HostsBlock.normalize("https://www.YouTube.com/watch?v=1"), "youtube.com")
        XCTAssertEqual(HostsBlock.normalize("http://example.com"), "example.com")
        XCTAssertEqual(HostsBlock.normalize("example.com/path/to/page"), "example.com")
        XCTAssertEqual(HostsBlock.normalize("example.com?q=1"), "example.com")
        XCTAssertEqual(HostsBlock.normalize("example.com#section"), "example.com")
        XCTAssertEqual(HostsBlock.normalize("https://example.com:8443/x"), "example.com")
        XCTAssertEqual(HostsBlock.normalize("ftp://user:secret@files.example.com/"), "files.example.com")
    }

    func testNormalizeCaseWhitespaceAndDots() {
        XCTAssertEqual(HostsBlock.normalize("  Reddit.COM \n"), "reddit.com")
        XCTAssertEqual(HostsBlock.normalize("x.com."), "x.com")
        XCTAssertEqual(HostsBlock.normalize("*.example.org"), "example.org")
    }

    func testNormalizeWWWPrefix() {
        XCTAssertEqual(HostsBlock.normalize("www.facebook.com"), "facebook.com")
        XCTAssertEqual(HostsBlock.normalize("WWW.news.example.co.uk"), "news.example.co.uk")
        // Stripping would leave a single label, so it is kept.
        XCTAssertEqual(HostsBlock.normalize("www.com"), "www.com")
        // Only a leading "www." is removed.
        XCTAssertEqual(HostsBlock.normalize("mail.www.example.com"), "mail.www.example.com")
    }

    func testNormalizeKeepsSubdomains() {
        XCTAssertEqual(HostsBlock.normalize("news.ycombinator.com"), "news.ycombinator.com")
        XCTAssertEqual(HostsBlock.normalize("m.youtube.com"), "m.youtube.com")
    }

    func testNormalizeRejectsInvalidInput() {
        let invalid = [
            "", "   ", "localhost", "com", "http://localhost:3000",
            "1.2.3.4", "http://192.168.0.1/admin", "http://[::1]/",
            "you tube.com", "under_score.com", "ютуб.рф", "café.com",
            "a..com", "-bad.com", "bad-.com", "https://", "evil.com\n1.2.3.4 bank.com",
            "a.com;rm", "$(id).com",
            String(repeating: "a", count: 64) + ".com",
        ]
        for input in invalid {
            XCTAssertNil(HostsBlock.normalize(input), "expected nil for \(input.debugDescription)")
        }
    }

    // MARK: isValid

    func testIsValidAcceptsHostnames() {
        for domain in ["x.com", "youtube.com", "a-b.example.co.uk", "123.example.com", "xn--80ak6aa92e.com", "www.com"] {
            XCTAssertTrue(HostsBlock.isValid(domain), domain)
        }
        XCTAssertTrue(HostsBlock.isValid(String(repeating: "a", count: 63) + ".com"))
    }

    func testIsValidRejectsMalformedHostnames() {
        let invalid = [
            "", "com", "localhost", ".com", "a.com.", "a..com", "-a.com", "a-.com", "a.-b.com",
            "A.com", "a_b.com", "a b.com", "a.com ", "é.com", "1.2.3.4", "example.123",
            "../etc", "-rf", "a.com/x", "a.com:80", "a.com\n",
            String(repeating: "a", count: 64) + ".com",
        ]
        for domain in invalid {
            XCTAssertFalse(HostsBlock.isValid(domain), "expected invalid: \(domain.debugDescription)")
        }
    }

    func testIsValidTotalLengthLimit() {
        let label = String(repeating: "a", count: 63)
        let exactly253 = [label, label, label, String(repeating: "b", count: 61)].joined(separator: ".")
        XCTAssertEqual(exactly253.count, 253)
        XCTAssertTrue(HostsBlock.isValid(exactly253))
        XCTAssertFalse(HostsBlock.isValid(exactly253 + "c"))
    }

    // MARK: entries

    func testEntriesFormat() {
        XCTAssertEqual(HostsBlock.entries(for: ["x.com"]), [
            "0.0.0.0 x.com", "::1 x.com",
            "0.0.0.0 www.x.com", "::1 www.x.com",
        ])
    }

    func testEntriesSkipWWWVariantWhenAlreadyPrefixed() {
        XCTAssertEqual(HostsBlock.entries(for: ["www.example.com"]), [
            "0.0.0.0 www.example.com", "::1 www.example.com",
        ])
    }

    func testEntriesPreserveOrderAndSkipInvalid() {
        let lines = HostsBlock.entries(for: ["a.com", "not valid", "b.org"])
        XCTAssertEqual(lines.count, 8)
        XCTAssertEqual(lines.first, "0.0.0.0 a.com")
        XCTAssertEqual(lines[4], "0.0.0.0 b.org")
        XCTAssertTrue(HostsBlock.entries(for: []).isEmpty)
    }

    func testMarkersMatchHelperScript() {
        XCTAssertEqual(HostsBlock.beginMarker, "# >>> pomodoro >>>")
        XCTAssertEqual(HostsBlock.endMarker, "# <<< pomodoro <<<")
    }

    func testBlockedDomainMatchesDomainAndSubdomains() {
        let domains = ["youtube.com", "x.com"]
        XCTAssertEqual(HostsBlock.blockedDomain(forURL: "https://www.youtube.com/watch?v=1", in: domains), "youtube.com")
        XCTAssertEqual(HostsBlock.blockedDomain(forURL: "https://youtube.com", in: domains), "youtube.com")
        XCTAssertEqual(HostsBlock.blockedDomain(forURL: "http://m.YouTube.com./feed", in: domains), "youtube.com")
        XCTAssertEqual(HostsBlock.blockedDomain(forURL: "https://x.com/home", in: domains), "x.com")
        XCTAssertEqual(HostsBlock.blockedDomain(forURL: "https://user:pw@www.youtube.com:443/", in: domains), "youtube.com")
    }

    func testBlockedDomainIgnoresLookalikesAndNonWebURLs() {
        let domains = ["youtube.com", "x.com"]
        XCTAssertNil(HostsBlock.blockedDomain(forURL: "https://notyoutube.com/", in: domains))
        XCTAssertNil(HostsBlock.blockedDomain(forURL: "https://youtube.com.evil.org/", in: domains))
        XCTAssertNil(HostsBlock.blockedDomain(forURL: "https://box.com/", in: domains))
        XCTAssertNil(HostsBlock.blockedDomain(forURL: "chrome://newtab/", in: domains))
        XCTAssertNil(HostsBlock.blockedDomain(forURL: "file:///Users/me/youtube.com", in: domains))
        XCTAssertNil(HostsBlock.blockedDomain(forURL: "missing value", in: domains))
        XCTAssertNil(HostsBlock.blockedDomain(forURL: "https://youtube.com/", in: []))
    }
}
