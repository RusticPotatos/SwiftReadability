//
//  SwiftReadabilityTests.swift
//  SwiftReadabilityTests
//
//  Created by rustic on 1/11/26.
//

import XCTest
@testable import SwiftReadability

final class ReadabilityFixtureTests: XCTestCase {
    private struct FixtureExpectation {
        let name: String
        let titleMustContain: String
        let textMustContain: String?
        let minContentLength: Int
        let minPlainTextLength: Int
        let expectDescription: Bool
        let expectImage: Bool
        let expectedAuthor: String?
        let expectedDatePrefix: String?
        let expectedKeywords: [String]?
    }

    private let fixtures: [FixtureExpectation] = [
        .init(
            name: "article1",
            titleMustContain: "Trump's appointment of Greenland envoy",
            textMustContain: "Trump's appointment of Greenland envoy",
            minContentLength: 400,
            minPlainTextLength: 200,
            expectDescription: false,
            expectImage: true,
            expectedAuthor: nil,
            expectedDatePrefix: nil,
            expectedKeywords: nil
        ),
        .init(
            name: "article2",
            titleMustContain: "Where Does Joe Jonas Live?",
            textMustContain: "Where Does Joe Jonas Live?",
            minContentLength: 400,
            minPlainTextLength: 200,
            expectDescription: false,
            expectImage: true,
            expectedAuthor: nil,
            expectedDatePrefix: nil,
            expectedKeywords: nil
        ),
        .init(
            name: "article3",
            titleMustContain: "Politics Is Fandom; Fascism Is Fanfic",
            textMustContain: nil,
            minContentLength: 400,
            minPlainTextLength: 200,
            expectDescription: false,
            expectImage: true,
            expectedAuthor: nil,
            expectedDatePrefix: nil,
            expectedKeywords: nil
        ),
        .init(
            name: "article4",
            titleMustContain: "Newly released Epstein files spotlight Trump",
            textMustContain: nil,
            minContentLength: 400,
            minPlainTextLength: 200,
            expectDescription: false,
            expectImage: true,
            expectedAuthor: nil,
            expectedDatePrefix: nil,
            expectedKeywords: nil
        ),
        .init(
            name: "article5",
            titleMustContain: "Need a new colour ereader for the holiday season",
            textMustContain: "Kobo",
            minContentLength: 400,
            minPlainTextLength: 200,
            expectDescription: true,
            expectImage: true,
            expectedAuthor: nil,
            expectedDatePrefix: "2025-12-23",
            expectedKeywords: nil
        ),
        .init(
            name: "article_structured",
            titleMustContain: "Structured Headline",
            textMustContain: "JSON-LD is preferred when present",
            minContentLength: 200,
            minPlainTextLength: 150,
            expectDescription: true,
            expectImage: true,
            expectedAuthor: "Jane Doe",
            expectedDatePrefix: "2024-01-02",
            expectedKeywords: ["alpha", "beta", "gamma"]
        ),
        .init(
            name: "article_comments",
            titleMustContain: "Comments Fixture Title",
            textMustContain: "short article body",
            minContentLength: 150,
            minPlainTextLength: 100,
            expectDescription: true,
            expectImage: false,
            expectedAuthor: nil,
            expectedDatePrefix: nil,
            expectedKeywords: nil
        ),
        .init(
            name: "article_links",
            titleMustContain: "Main Story",
            textMustContain: "core article content",
            minContentLength: 150,
            minPlainTextLength: 100,
            expectDescription: false,
            expectImage: false,
            expectedAuthor: nil,
            expectedDatePrefix: nil,
            expectedKeywords: nil
        ),
        .init(
            name: "article_noise",
            titleMustContain: "Noise Fixture",
            textMustContain: nil,
            minContentLength: 100,
            minPlainTextLength: 80,
            expectDescription: false,
            expectImage: false,
            expectedAuthor: nil,
            expectedDatePrefix: nil,
            expectedKeywords: nil
        )
    ]

    func testReadabilityExtractsFixtureContent() async throws {
        try await withThrowingTaskGroup(of: (FixtureExpectation, ReadabilityData).self) { group in
            for fixture in fixtures {
                group.addTask { [fixture] in
                    let html = try Self.loadFixture(named: fixture.name)
                    let readability = try Readability(html: html)
                    let data = try readability.extractReadabilityData(includeComments: false)
                    return (fixture, data)
                }
            }

            for try await (fixture, data) in group {
                XCTAssertNotNil(data.content, "\(fixture.name) returned nil content")
                XCTAssertTrue((data.content?.count ?? 0) >= fixture.minContentLength, "\(fixture.name) content too short")
                XCTAssertTrue((data.text?.count ?? 0) >= fixture.minPlainTextLength, "\(fixture.name) plain text too short")
                XCTAssertTrue(data.title.localizedCaseInsensitiveContains(fixture.titleMustContain), "\(fixture.name) title mismatch")
                if let snippet = fixture.textMustContain {
                    XCTAssertTrue(data.text?.localizedCaseInsensitiveContains(snippet) == true, "\(fixture.name) missing expected text")
                }
                XCTAssertTrue(data.content?.contains("readability-content") == true, "\(fixture.name) missing readability container")
                XCTAssertNotNil(data.estimatedReadingTime, "\(fixture.name) missing estimated reading time")
                if fixture.expectDescription {
                    XCTAssertNotNil(data.description, "\(fixture.name) missing description")
                }
                if fixture.expectImage {
                    XCTAssertNotNil(data.topImage, "\(fixture.name) missing top image")
                }
                if let author = fixture.expectedAuthor {
                    XCTAssertEqual(data.author, author, "\(fixture.name) author mismatch")
                }
                if let datePrefix = fixture.expectedDatePrefix {
                    XCTAssertTrue((data.datePublished ?? "").hasPrefix(datePrefix), "\(fixture.name) date mismatch")
                }
                if let keywords = fixture.expectedKeywords {
                    let extracted = data.keywords ?? []
                    for kw in keywords {
                        XCTAssertTrue(extracted.contains(where: { $0.caseInsensitiveCompare(kw) == .orderedSame }), "\(fixture.name) missing keyword \(kw)")
                    }
                }
            }
        }
    }

    func testExtractsCommentsFromCommonPatterns() throws {
        let html = try Self.loadFixture(named: "article_comments")
        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData()

        XCTAssertEqual(data.comments?.count, 2)
        XCTAssertEqual(data.comments?.first?.author, "Alice")
        XCTAssertEqual(data.comments?.first?.date, "2024-02-03T10:00:00Z")
        XCTAssertTrue(data.comments?.first?.content.contains("Great article") == true)
    }

    func testRemovesLinkHeavyRelatedBlocks() throws {
        let html = try Self.loadFixture(named: "article_links")
        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)

        XCTAssertTrue(data.text?.contains("core article content") == true)
        XCTAssertFalse(data.text?.contains("Related link A") == true)
        XCTAssertFalse(data.text?.contains("Related link B") == true)
        XCTAssertFalse(data.text?.contains("Related link C") == true)
    }

    func testRemovesNoiseMarkers() throws {
        let html = try Self.loadFixture(named: "article_noise")
        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)

        let text = data.text ?? ""
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains("Recommended Stories"))
        XCTAssertFalse(text.contains("Story 1"))
        XCTAssertFalse(text.contains("Advertisement"))
    }

    func testReadabilityDataPublicInitializer() {
        let data = ReadabilityData(
            title: "Sample Title",
            description: "Sample description",
            topImage: "https://example.com/image.jpg",
            text: "Sample text",
            content: "<p>Sample text</p>",
            topVideo: nil,
            keywords: ["alpha", "beta"],
            datePublished: "2025-01-01",
            author: "Jane Doe",
            estimatedReadingTime: 1,
            comments: [
                (author: "Alice", date: "2025-01-01T00:00:00Z", content: "Nice article.")
            ]
        )

        XCTAssertEqual(data.title, "Sample Title")
        XCTAssertEqual(data.description, "Sample description")
        XCTAssertEqual(data.topImage, "https://example.com/image.jpg")
        XCTAssertEqual(data.text, "Sample text")
        XCTAssertEqual(data.content, "<p>Sample text</p>")
        XCTAssertNil(data.topVideo)
        XCTAssertEqual(data.keywords ?? [], ["alpha", "beta"])
        XCTAssertEqual(data.datePublished, "2025-01-01")
        XCTAssertEqual(data.author, "Jane Doe")
        XCTAssertEqual(data.estimatedReadingTime, 1)
        XCTAssertEqual(data.comments?.count, 1)
    }

    private static func loadFixture(named name: String) throws -> String {
        if let url = Bundle(for: Self.self).url(forResource: name, withExtension: "html", subdirectory: "html_examples") {
            return try String(contentsOf: url, encoding: .utf8)
        }

        let fileURL = URL(fileURLWithPath: #filePath)
        let fallback = fileURL
            .deletingLastPathComponent() // NewspaperTests
            .appendingPathComponent("html_examples")
            .appendingPathComponent("\(name).html")

        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw NSError(domain: "ReadabilityFixtureTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture \(name) not found"])
        }

        return try String(contentsOf: fallback, encoding: .utf8)
    }
}
