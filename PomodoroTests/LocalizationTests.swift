import XCTest
@testable import Pomodoro

/// Guards the Russian and Uzbek string tables: same keys, no empty values, placeholders that match the key.
final class LocalizationTests: XCTestCase {
    private func table(_ language: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
            "\(language).lproj/Localizable.strings is missing from the app bundle"
        )
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    /// Placeholder types in order of argument position ("%2$@ … %1$lld" → ["lld", "@"]).
    private func placeholders(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(lld|ld|d|@)")
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var sequential = 0
        var byPosition: [Int: String] = [:]
        for match in matches {
            let type = String(text[Range(match.range(at: 2), in: text)!])
            if let range = Range(match.range(at: 1), in: text), let position = Int(text[range]) {
                byPosition[position] = type
            } else {
                sequential += 1
                byPosition[sequential] = type
            }
        }
        return byPosition.keys.sorted().map { byPosition[$0]! }
    }

    func testRussianAndUzbekCoverTheSameKeys() throws {
        let ru = try table("ru")
        let uz = try table("uz")
        XCTAssertGreaterThan(ru.count, 200)
        XCTAssertEqual(Set(ru.keys).subtracting(uz.keys), [], "Missing in Uzbek")
        XCTAssertEqual(Set(uz.keys).subtracting(ru.keys), [], "Missing in Russian")
    }

    func testTranslationsAreNonEmptyAndKeepPlaceholders() throws {
        for language in ["ru", "uz"] {
            for (key, value) in try table(language) where !key.isEmpty {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): empty value for \(key)")
                XCTAssertEqual(placeholders(in: value), placeholders(in: key), "\(language): placeholders differ for \(key)")
            }
        }
    }
}
