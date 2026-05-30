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
        ),
        .init(
            name: "lazy_loaded_images_and_recirculation",
            titleMustContain: "Synthetic Watch Roundup",
            textMustContain: "synthetic article exists only to test readability extraction behavior",
            minContentLength: 1_500,
            minPlainTextLength: 700,
            expectDescription: true,
            expectImage: true,
            expectedAuthor: "Fixture Author",
            expectedDatePrefix: "2026-05-29",
            expectedKeywords: nil
        ),
        .init(
            name: "split_content_modules_and_gallery",
            titleMustContain: "Synthetic Split Module Article",
            textMustContain: "first split content module introduces the article",
            minContentLength: 1_500,
            minPlainTextLength: 700,
            expectDescription: true,
            expectImage: true,
            expectedAuthor: "Fixture Writer",
            expectedDatePrefix: "2026-05-29",
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

    // MARK: - Lazy Image Regression Tests

    private func extractLazyImageFixture() throws -> ReadabilityData {
        let html = try Self.loadFixture(named: "lazy_loaded_images_and_recirculation")
        let readability = try Readability(html: html)
        return try readability.extractReadabilityData(includeComments: false)
    }

    func testLazyImageFixtureExtractsExpectedMetadata() throws {
        let data = try extractLazyImageFixture()

        XCTAssertTrue(data.title.localizedCaseInsensitiveContains("Synthetic Watch Roundup"))
        XCTAssertEqual(data.author, "Fixture Author")
        XCTAssertTrue((data.datePublished ?? "").hasPrefix("2026-05-29"))
        XCTAssertTrue(data.description?.contains("Synthetic fixture") == true)
        XCTAssertTrue(data.topImage?.contains("synthetic-hero.jpg") == true)
    }
    

    func testLazyImagesBecomeRenderableImages() throws {
        let data = try extractLazyImageFixture()
        let content = data.content ?? ""

        XCTAssertTrue(content.contains("<img"), "Lazy image fixture should preserve inline article images")
        XCTAssertFalse(
            content.contains("data-src=\"https://example.com/images/synthetic-watch-01.jpg"),
            "Renderable output should not leave this lazy image only in data-src"
        )
        XCTAssertTrue(
            content.contains(#"src="https://example.com/images/synthetic-watch-01.jpg"#),
            "The first lazy inline article image should have a real src attribute directly on the img tag"
        )
    }

    func testLazySrcsetBecomesRenderableSrcset() throws {
        let data = try extractLazyImageFixture()
        let content = data.content ?? ""

        XCTAssertFalse(
            content.contains("data-srcset=\"https://example.com/images/synthetic-watch-01.jpg"),
            "Renderable output should not leave this lazy image srcset only in data-srcset"
        )
        XCTAssertTrue(
            content.contains(#"src="https://example.com/images/synthetic-watch-01.jpg"#) &&
            content.contains(#"srcset="https://example.com/images/synthetic-watch-01.jpg 1200w, https://example.com/images/synthetic-watch-01-small.jpg 600w"#),
            "The first lazy inline article image should have a real srcset attribute directly on the img tag"
        )
    }

    func testRenderableContentDoesNotDependOnLazyLoadingAttributes() throws {
        let data = try extractLazyImageFixture()
        let content = data.content ?? ""

        XCTAssertFalse(content.contains("data-src="), "Extracted reader HTML should not depend on JavaScript lazy-loading data-src attributes")
        XCTAssertFalse(content.contains("data-srcset="), "Extracted reader HTML should not depend on JavaScript lazy-loading data-srcset attributes")
        XCTAssertFalse(content.contains("lazyload"), "Extracted reader HTML should not depend on site lazy-loading CSS classes")
    }

    func testLazyImageNormalizationSupportsCommonFallbackAttributes() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Fallback Lazy Image Fixture</title>
            <meta name="description" content="Synthetic fixture for common lazy image fallback attributes.">
        </head>
        <body>
            <article>
                <h1>Fallback Lazy Image Fixture</h1>
                <p>This synthetic article verifies common lazy image fallback attributes used by multiple publishing platforms.</p>
                <p>The parser should convert fallback image attributes into renderable image attributes without relying on site JavaScript.</p>
                <p>Additional article body text keeps this fixture large enough for readability extraction.</p>
                <img alt="Fallback image" data-original="https://example.com/images/fallback-original.jpg">
                <img alt="Lazy srcset only image" data-lazy-srcset="https://example.com/images/fallback-srcset-large.jpg 1200w, https://example.com/images/fallback-srcset-small.jpg 600w">
            </article>
        </body>
        </html>
        """

        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)
        let content = data.content ?? ""

        XCTAssertTrue(content.contains(#"src="https://example.com/images/fallback-original.jpg"#))
        XCTAssertTrue(content.contains(#"src="https://example.com/images/fallback-srcset-large.jpg"#))
        XCTAssertTrue(content.contains(#"srcset="https://example.com/images/fallback-srcset-large.jpg 1200w, https://example.com/images/fallback-srcset-small.jpg 600w"#))
        XCTAssertFalse(content.contains("data-original="))
        XCTAssertFalse(content.contains("data-lazy-srcset="))
    }

    func testLazyImageNormalizationPreservesNonLazyClasses() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Lazy Class Cleanup Fixture</title>
        </head>
        <body>
            <article>
                <h1>Lazy Class Cleanup Fixture</h1>
                <p>This synthetic article verifies lazy image class cleanup without removing useful presentation classes.</p>
                <p>Only lazy-loading implementation classes should be removed from images after normalization.</p>
                <p>Article body text ensures the readability parser treats this node as the primary article.</p>
                <img class="lazy lazyload aligncenter article-image" alt="Class cleanup image" data-src="https://example.com/images/class-cleanup.jpg">
            </article>
        </body>
        </html>
        """

        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)
        let content = data.content ?? ""

        XCTAssertTrue(content.contains(#"src="https://example.com/images/class-cleanup.jpg"#))
        XCTAssertTrue(content.contains("aligncenter"))
        XCTAssertTrue(content.contains("article-image"))
        XCTAssertFalse(content.contains("lazyload"))
        XCTAssertFalse(content.contains(#"class="lazy"#))
    }

    func testArticleDoesNotStopAtRecirculationModule() throws {
        let data = try extractLazyImageFixture()
        let text = data.text ?? ""

        XCTAssertTrue(
            text.contains("currently observed cutoff location"),
            "Fixture should include the currently observed cutoff point so this test guards against false positives"
        )
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("Travel Clock Section"),
            "Article should continue after the recirculation module instead of stopping early"
        )
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("Calendar Watch Section"),
            "Article should preserve later sections after the first lazy image"
        )
    }

    func testArticleRemovesReadThisNextRecirculation() throws {
        let data = try extractLazyImageFixture()
        let text = data.text ?? ""
        let content = data.content ?? ""

        XCTAssertFalse(text.localizedCaseInsensitiveContains("Read this Next"), "Reader text should remove recirculation modules")
        XCTAssertFalse(content.localizedCaseInsensitiveContains("Read this Next"), "Reader HTML should remove recirculation modules")
    }

    // MARK: - Split Content Module Regression Tests

    private func extractSplitContentModuleFixture() throws -> ReadabilityData {
        let html = try Self.loadFixture(named: "split_content_modules_and_gallery")
        let readability = try Readability(html: html)
        return try readability.extractReadabilityData(includeComments: false)
    }

    func testSplitContentModuleFixtureExtractsExpectedMetadata() throws {
        let data = try extractSplitContentModuleFixture()

        XCTAssertTrue(data.title.localizedCaseInsensitiveContains("Synthetic Split Module Article"))
        XCTAssertEqual(data.author, "Fixture Writer")
        XCTAssertTrue((data.datePublished ?? "").hasPrefix("2026-05-29"))
        XCTAssertTrue(data.description?.contains("Synthetic fixture") == true)
        XCTAssertTrue(data.topImage?.contains("split-module-hero.jpg") == true)
    }

    func testArticleContinuesAcrossSplitContentModules() throws {
        let data = try extractSplitContentModuleFixture()
        let text = data.text ?? ""

        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("first split content module introduces the article"),
            "Reader text should include the first split content module"
        )
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("second split content module continues the article"),
            "Reader text should include the second split content module instead of stopping at the ad break"
        )
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("Final split content module closes the article"),
            "Reader text should include the final split content module"
        )
    }

    func testSplitContentModuleLazyImagesBecomeRenderableImages() throws {
        let data = try extractSplitContentModuleFixture()
        let content = data.content ?? ""

        XCTAssertTrue(content.contains("<img"), "Split module fixture should preserve inline article images")
        XCTAssertFalse(
            content.contains("data-src=\"https://example.com/images/split-module-watch-01.jpg"),
            "Renderable output should not leave the first split module image only in data-src"
        )
        XCTAssertTrue(
            content.contains(#"src="https://example.com/images/split-module-watch-01.jpg"#),
            "The first split module lazy image should have a real src attribute"
        )
    }

    func testPostArticleGalleryIsRemovedFromReaderOutput() throws {
        let data = try extractSplitContentModuleFixture()
        let text = data.text ?? ""
        let content = data.content ?? ""

        XCTAssertFalse(text.localizedCaseInsensitiveContains("Images from this post"), "Reader text should remove post-article gallery headings")
        XCTAssertFalse(content.localizedCaseInsensitiveContains("Images from this post"), "Reader HTML should remove post-article gallery headings")
        XCTAssertFalse(content.contains("data-bg="), "Reader HTML should not preserve post-gallery background image lazy-loading attributes")
        XCTAssertFalse(content.contains(#"class="post-gallery"#), "Reader HTML should not preserve standalone post-gallery modules")
        XCTAssertFalse(content.contains(" post-gallery "), "Reader HTML should not preserve post-gallery as a class token")
    }

    func testGalleryWordsInsideArticleArePreservedWhenNotPostGalleryModules() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Legitimate Gallery Article Fixture</title>
            <meta name="description" content="Synthetic fixture for preserving legitimate gallery article language.">
        </head>
        <body>
            <article>
                <h1>Legitimate Gallery Article Fixture</h1>
                <p>This synthetic article is about a museum gallery and should not be removed simply because the word gallery appears in article text.</p>
                <section class="gallery-analysis">
                    <h2>Gallery Analysis Section</h2>
                    <p>The gallery analysis section is real article content, not a post-article image collection or recirculation module.</p>
                    <p>Reader cleanup should preserve this section because it contains narrative article text instead of a post-gallery class or Images from this post marker.</p>
                </section>
                <p>The final paragraph confirms that legitimate article sections using the word gallery remain in reader output.</p>
            </article>
        </body>
        </html>
        """

        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)
        let text = data.text ?? ""

        XCTAssertTrue(text.localizedCaseInsensitiveContains("museum gallery"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Gallery Analysis Section"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("legitimate article sections using the word gallery"))
    }

    // MARK: - Generic Scoring Heuristic Regression Tests

    func testPositiveArticleClassContainerWinsOverLongNavigationNoise() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Positive Article Class Fixture</title>
            <meta name="description" content="Synthetic fixture for positive article class scoring.">
        </head>
        <body>
            <main>
                <section class="menu sidebar navigation-links">
                    <h2>Navigation Links</h2>
                    <p><a href="/one">Navigation item one</a> <a href="/two">Navigation item two</a> <a href="/three">Navigation item three</a></p>
                    <p><a href="/four">Navigation item four</a> <a href="/five">Navigation item five</a> <a href="/six">Navigation item six</a></p>
                    <p><a href="/seven">Navigation item seven</a> <a href="/eight">Navigation item eight</a> <a href="/nine">Navigation item nine</a></p>
                </section>
                <section class="article-content story-body">
                    <h1>Positive Article Class Fixture</h1>
                    <p>The positive article class container should be selected because it contains narrative article text.</p>
                    <p>This synthetic paragraph gives the article node enough readable language to compete against nearby navigation noise.</p>
                    <p>Additional body text confirms that positive article-like class names help scoring prefer the real story container.</p>
                    <p>The final article paragraph should remain in the reader output while unrelated navigation links are removed.</p>
                </section>
            </main>
        </body>
        </html>
        """

        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)
        let text = data.text ?? ""

        XCTAssertTrue(text.localizedCaseInsensitiveContains("positive article class container should be selected"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("final article paragraph should remain"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Navigation item nine"))
    }

    func testNegativeUtilityClassContainerIsRemovedWhileArticleBodyRemains() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Negative Utility Class Fixture</title>
            <meta name="description" content="Synthetic fixture for negative utility class cleanup.">
        </head>
        <body>
            <article class="post-content entry-content">
                <h1>Negative Utility Class Fixture</h1>
                <p>The main article body should remain visible after cleanup removes unrelated utility containers.</p>
                <p>This paragraph represents source-agnostic article content that should not depend on one publisher's markup.</p>
                <p>The final narrative paragraph confirms that the article survived after nearby negative class containers were removed.</p>
                <div class="widget sponsor supplemental-box">
                    <h2>Sponsored Widget</h2>
                    <p><a href="/deal-one">Sponsored deal one</a> <a href="/deal-two">Sponsored deal two</a> <a href="/deal-three">Sponsored deal three</a></p>
                </div>
            </article>
        </body>
        </html>
        """

        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)
        let text = data.text ?? ""

        XCTAssertTrue(text.localizedCaseInsensitiveContains("main article body should remain visible"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("final narrative paragraph confirms"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Sponsored Widget"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Sponsored deal one"))
    }

    func testNegativeWordsInsideNarrativeArticleArePreserved() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Negative Words Narrative Fixture</title>
            <meta name="description" content="Synthetic fixture for preserving narrative uses of cleanup terms.">
        </head>
        <body>
            <article class="article-body">
                <h1>Negative Words Narrative Fixture</h1>
                <p>This article discusses a community newsletter and a site menu as part of the narrative text.</p>
                <p>The words sponsor, footer, sidebar, and navigation can appear naturally in an article and should not cause paragraph removal.</p>
                <p>A robust readability parser should distinguish between class or id cleanup signals and ordinary prose.</p>
                <p>The final paragraph confirms that narrative uses of negative cleanup terms remain readable.</p>
            </article>
        </body>
        </html>
        """

        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)
        let text = data.text ?? ""

        XCTAssertTrue(text.localizedCaseInsensitiveContains("community newsletter"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("sponsor, footer, sidebar, and navigation"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("negative cleanup terms remain readable"))
    }

    func testPositiveContentClassBeatsLongerGenericSiblingWithoutArticleTag() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Positive Content Class Without Article Tag Fixture</title>
            <meta name="description" content="Synthetic fixture for positive class scoring without article tags.">
        </head>
        <body>
            <main>
                <div class="entry-content hentry story-text">
                    <h1>Positive Content Class Without Article Tag Fixture</h1>
                    <p>The real story lives inside a positive content class but does not use an article tag.</p>
                    <p>This paragraph should be selected because the class name indicates authored article content.</p>
                    <p>The final story paragraph confirms that positive class scoring can identify the correct container.</p>
                </div>
                <div class="discussion-area reader-responses">
                    <h2>Reader Responses</h2>
                    <p>This longer generic sibling is not the authored article even though it contains many words and sentences.</p>
                    <p>Comment-like discussion text can be long enough to compete with article text if class scoring is weak.</p>
                    <p>The parser should not select this response area simply because it has more paragraph text than the story.</p>
                    <p>Additional response copy makes this sibling longer while still remaining outside the intended article content.</p>
                    <p>More response copy creates a stronger false positive for parsers that only count text length and paragraph density.</p>
                </div>
            </main>
        </body>
        </html>
        """

        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)
        let text = data.text ?? ""

        XCTAssertTrue(text.localizedCaseInsensitiveContains("real story lives inside a positive content class"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("final story paragraph confirms"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Reader Responses"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("longer generic sibling is not the authored article"))
    }

    func testNegativeCommentLikeClassLosesEvenWithLongNarrativeText() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Negative Comment Class Fixture</title>
            <meta name="description" content="Synthetic fixture for negative comment-like class scoring.">
        </head>
        <body>
            <main>
                <div class="post-body article-text">
                    <h1>Negative Comment Class Fixture</h1>
                    <p>The article body is shorter than the comment-like section but should still be selected.</p>
                    <p>Positive article class names should help the extractor prefer authored content over response content.</p>
                    <p>The final article sentence should remain while the longer response area is excluded.</p>
                </div>
                <div class="comment-body user-comment discussion-content">
                    <h2>Top Comment</h2>
                    <p>This comment-like region contains narrative prose and no link-heavy pattern to make cleanup easy.</p>
                    <p>It is intentionally longer than the article so weak scoring may accidentally choose it as the main content.</p>
                    <p>The response text keeps adding words to resemble a dense article-like block despite being user feedback.</p>
                    <p>Another response paragraph makes the false candidate more competitive for text-density-only extraction.</p>
                    <p>The parser should use negative class signals to avoid treating this comment-like section as the article.</p>
                </div>
            </main>
        </body>
        </html>
        """

        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)
        let text = data.text ?? ""

        XCTAssertTrue(text.localizedCaseInsensitiveContains("article body is shorter than the comment-like section"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("final article sentence should remain"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Top Comment"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("false candidate more competitive"))
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

    func testPreservesConclusionWhileTrimmingTailReadMoreCluster() throws {
        let html = try Self.loadFixture(named: "article_tail_noise")
        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)

        let text = data.text ?? ""
        XCTAssertTrue(text.contains("Conclusion"))
        XCTAssertTrue(text.contains("Final takeaways should remain visible"))
        XCTAssertFalse(text.contains("Read More"))
        XCTAssertFalse(text.contains("Suggested Story 1"))
        XCTAssertFalse(text.contains("Suggested Story 4"))
    }

    func testRemovesMidArticleSponsorBlockButKeepsNarrativeAndImage() throws {
        let html = try Self.loadFixture(named: "article_mid_sponsor")
        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)

        let text = data.text ?? ""
        let content = data.content ?? ""
        XCTAssertTrue(text.contains("opening article paragraph"))
        XCTAssertTrue(text.contains("article then resumes with relevant analysis"))
        XCTAssertTrue(text.contains("closing paragraph"))
        XCTAssertFalse(text.contains("Limited offer one"))
        XCTAssertFalse(text.contains("Limited offer two"))
        XCTAssertFalse(text.contains("Sponsored"))
        XCTAssertTrue(content.contains("inline.jpg"))
    }

    func testRemovesLatestArticlesTailList() throws {
        let html = try Self.loadFixture(named: "article_latest_articles")
        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)

        let text = data.text ?? ""
        XCTAssertTrue(text.contains("Main body paragraph"))
        XCTAssertTrue(text.contains("Another article paragraph"))
        XCTAssertFalse(text.contains("LATEST ARTICLES"))
        XCTAssertFalse(text.contains("Latest Item 1"))
        XCTAssertFalse(text.contains("Latest Item 4"))
    }

    func testRemovesTechradarPopularBoxRecirculation() throws {
        let html = try Self.loadFixture(named: "article_techradar_popular_box")
        let readability = try Readability(html: html)
        let data = try readability.extractReadabilityData(includeComments: false)

        let text = data.text ?? ""
        XCTAssertTrue(text.contains("I drove the compact EV"))
        XCTAssertTrue(text.contains("charging curve and software experience"))
        XCTAssertFalse(text.contains("LATEST ARTICLES"))
        XCTAssertFalse(text.contains("Popular Item 1"))
        XCTAssertFalse(text.contains("Popular Item 3"))
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
