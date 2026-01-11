//
//  SwiftReadability.swift
//  SwiftReadability
//
//  Created by rustic on 1/11/26.
//

import Foundation
import SwiftSoup

/// A structured result from Readability extraction.
///
/// This payload is designed to be rendered directly (HTML) or indexed (plain text).
public struct ReadabilityData: Sendable {
    /// Best-effort title for the document.
    public let title: String
    /// Metadata description or a fallback excerpt.
    public let description: String?
    /// Primary image URL, when available.
    public let topImage: String?
    /// Plain text content.
    public let text: String?
    /// Full HTML content with formatting preserved.
    public let content: String?
    /// Primary video URL, when available.
    public let topVideo: String?
    /// Keywords from metadata or structured data.
    public let keywords: [String]?
    /// Published date string as found in metadata or structured data.
    public let datePublished: String?
    /// Author name as found in metadata or structured data.
    public let author: String?
    /// Estimated reading time in minutes, based on plain text.
    public let estimatedReadingTime: Int?
    /// Extracted comment tuples, if comment extraction was requested.
    public let comments: [(author: String, date: String, content: String)]?
}

// MARK: - Data Structures

enum ReadabilityError: Error {
    case invalidURL, decodingFailed, parsingFailed, unknownError
}

// MARK: - Flag System

/// Flags to toggle different heuristics during extraction.
///
/// Use `.all` for the default behavior, or combine individual flags to
/// enable or disable specific heuristics during scoring and cleanup.
public struct ReadabilityFlags: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let stripUnlikelies    = ReadabilityFlags(rawValue: 1 << 0)
    public static let weightClasses      = ReadabilityFlags(rawValue: 1 << 1)
    public static let cleanConditionally = ReadabilityFlags(rawValue: 1 << 2)
    public static let all: ReadabilityFlags = [.stripUnlikelies, .weightClasses, .cleanConditionally]
}

private let shareClassRegex = try! NSRegularExpression(pattern: "(\\b|_)(share|sharedaddy|coral|comments-link)(\\b|_)", options: [.caseInsensitive])

private func estimatedReadingTime(for text: String) -> Int {
    let wordsPerMinute = 200 // Average reading speed
    let wordCount = text.split { !$0.isLetter }.count
    return max(1, wordCount / wordsPerMinute)
}

// MARK: - Readability Class

/// Extracts the primary article content and metadata from HTML.
///
/// Initialize with raw HTML, then call `extractReadabilityData()` to get a
/// structured payload. Use `Readability.parse(url:)` for a convenience async
/// flow that fetches and parses a URL in one step.
public class Readability {
    // TODO: Align heuristics and scoring with Firefox Readability (parsing phases, content scoring, and cleanup).
    // TODO: Define whether instances are single-use or make extraction non-mutating to allow repeat calls.
    // MARK: Internal Types
    private struct StructuredData {
        let title: String?
        let description: String?
        let author: String?
        let datePublished: String?
        let image: String?
        let keywords: [String]?
    }
    private let document: Document
    private let flags: ReadabilityFlags
    private let commentExtractor: ((Document) throws -> [(author: String, date: String, content: String)])?
    private let verboseLogging: Bool
    private let titleMetaSelectors = [
        "meta[property='og:title']",
        "meta[name='twitter:title']",
        "meta[name='title']"
    ]
    private let descriptionMetaSelectors = [
        "meta[name='description']",
        "meta[property='og:description']",
        "meta[name='twitter:description']"
    ]
    private let keywordsMetaSelectors = [
        "meta[name='keywords']",
        "meta[name='news_keywords']",
        "meta[name='parsely-tags']",
        "meta[name='article:tag']"
    ]
    private let authorMetaSelectors = [
        "meta[name='author']",
        "meta[property='article:author']",
        "meta[name='byl']",
        "meta[name='sailthru.author']",
        "meta[name='parsely-author']",
        "meta[property='og:article:author']"
    ]
    private let dateMetaSelectors = [
        "meta[property='article:published_time']",
        "meta[name='pubdate']",
        "meta[name='date']",
        "meta[name='parsely-pub-date']",
        "meta[name='DC.date']",
        "meta[itemprop='datePublished']"
    ]

    // Updated unwantedSelectors to include many of Firefox’s unlikely candidates plus common overlays.
    private let unwantedSelectors = """
    header, nav, footer, aside, .advertisement, .sponsored, .subscribe, .related, .breadcrumbs, .combx, .community, .cover-wrap, .disqus, .extra, .gdpr, .legends, .menu, .remark, .replies, .rss, .shoutbox, .sidebar, .skyscraper, .social, .sponsor, .supplemental, .ad-break, .agegate, .pagination, .pager, .popup, .yom-remote, .newsletter, .cookie, .cookie-banner, .modal, .overlay, .promo, .trending, .signup, .cta, .outbrain, .taboola, [data-component='header'], [data-component='footer']
    """
    
    // MARK: - Initialization
    /// Creates a Readability extractor from raw HTML.
    /// - Parameters:
    ///   - html: The document HTML to parse.
    ///   - flags: Heuristics to enable during extraction.
    ///   - verboseLogging: When true, emits verbose logs via `logger`.
    ///   - commentExtractor: Optional override for custom comment parsing.
    /// - Throws: `ReadabilityError` when HTML parsing fails.
    public init(
        html: String,
        flags: ReadabilityFlags = .all,
        verboseLogging: Bool = false,
        commentExtractor: ((Document) throws -> [(author: String, date: String, content: String)])? = nil
    ) throws {
        self.document = try SwiftSoup.parse(html)
        self.flags = flags
        self.commentExtractor = commentExtractor
        self.verboseLogging = verboseLogging

        // Initial cleanup passes to simplify later heuristics.
        try self.document.select(unwantedSelectors).remove()
        // TODO: Gate cleanup steps with flags (stripUnlikelies, cleanConditionally) to honor public API.
        try removeElementsWithRoles()
        try removeInvisibleElements()
        try removeShortLinks()
    }
    
    // MARK: - Public API
    /// Fetches a URL, parses HTML, and extracts `ReadabilityData`.
    /// - Parameters:
    ///   - url: The URL to fetch.
    ///   - flags: Heuristics to enable during extraction.
    ///   - verboseLogging: When true, emits verbose logs via `logger`.
    ///   - commentExtractor: Optional override for custom comment parsing.
    /// - Returns: Extracted `ReadabilityData` for the URL content.
    public class func parse(
        url: URL,
        flags: ReadabilityFlags = .all,
        verboseLogging: Bool = false,
        commentExtractor: ((Document) throws -> [(String, String, String)])? = nil
    ) async throws -> ReadabilityData {
        // TODO: Normalize commentExtractor tuple labels across public APIs.
        if verboseLogging {
            logger("Readability: fetching HTML for \(url.absoluteString)")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        if verboseLogging {
            logger("Readability: fetched \(data.count) bytes for \(url.absoluteString)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            logger("Failed to decode HTML from data")
            throw ReadabilityError.decodingFailed
        }
        if verboseLogging {
            let snippet = html.prefix(2000)
            logger("Readability raw HTML for \(url.absoluteString) (\(html.count) chars) [first 2000 chars]\n\(snippet)")
        }
        let readability = try Readability(html: html, flags: flags, verboseLogging: verboseLogging, commentExtractor: commentExtractor)
        return try readability.extractReadabilityData()
    }
    
    /// Extracts the main article payload into `ReadabilityData`.
    /// Computes a content score for a given element.
    /// Here we use a base score based on tag type, boost for punctuation (commas),
    /// and penalize for high link density.
    private func computeContentScore(for element: Element) throws -> Double {
        var score = 0.0
        let tagName = element.tagName().lowercased()
        // Base scores for common tags.
        switch tagName {
        case "article":
            score += 15.0
        case "main":
            score += 12.0
        case "p":
            score += 5.0
        case "div":
            score += 3.0
        case "section":
            score += 4.0
        case "ul", "ol":
            score -= 3.0
        case "nav":
            score -= 6.0
        case "h1", "h2", "h3", "h4", "h5", "h6":
            score -= 1.0
        default:
            break
        }
        
        // (Optional) If flag is set, adjust score based on class names.
        if flags.contains(.weightClasses) {
            let className = try element.className()
            if className.lowercased().contains("article") {
                score += 10
            }
            if className.lowercased().contains("comment") {
                score -= 10
            }
        }
        
        let text = try element.text()
        // Boost score for commas (as a proxy for sentence complexity).
        score += Double(text.split(separator: ",").count)
        // Add up to 3 extra points for every 100 characters.
        score += Double(min(text.count / 100, 3))
        
        // Subtract score based on link density.
        let linkDensity = try computeLinkDensity(for: element)
        score *= (1.0 - linkDensity)
        
        return score
    }
    
    /// Computes the link density (ratio of text in links vs. total text) of an element.
    private func computeLinkDensity(for element: Element) throws -> Double {
        let text = try element.text()
        let textLength = text.count
        guard textLength > 0 else { return 0.0 }
        let links = try element.select("a")
        var linkTextLength = 0
        for link in links.array() {
            linkTextLength += try link.text().count
        }
        return Double(linkTextLength) / Double(textLength)
    }
    
    /// Finds and returns the element with the highest content score.
    private func extractTopCandidate() throws -> Element? {
        let candidates = try document.select("article, div, section, p")
        var topCandidate: Element?
        var topScore = 0.0
        
        for candidate in candidates.array() {
            if try candidate.text().count < 25 { continue }
            let score = try computeContentScore(for: candidate)
            if score > topScore {
                topScore = score
                topCandidate = candidate
            }
        }
        return topCandidate
    }
    
    /// Returns true if an element contains inline media (img/picture).
    private func elementContainsInlineMedia(_ element: Element) -> Bool {
        (try? element.select("img, picture img").isEmpty == false) ?? false
    }
    
    /// Merges the top candidate with sibling nodes that also appear to belong to the article.
    private func mergeSiblings(with topCandidate: Element) throws -> Element {
        let containerHTML = "<div id='readability-content'></div>"
        let containerDoc = try SwiftSoup.parseBodyFragment(containerHTML)
        guard let container = containerDoc.body()?.child(0) else { return topCandidate }
        try container.appendChild(topCandidate)
        
        guard let parent = topCandidate.parent() else { return topCandidate }
        let siblings = parent.children()
        for sibling in siblings.array() {
            if sibling == topCandidate { continue }
            let siblingText = try sibling.text()
            // Keep media siblings even if they have little/no text (hero images).
            if siblingText.count < 25 && !elementContainsInlineMedia(sibling) { continue }
            let siblingLinkDensity = try computeLinkDensity(for: sibling)
            if siblingLinkDensity < 0.2 || elementContainsInlineMedia(sibling) {
                try container.appendChild(sibling)
            }
        }
        return container
    }
    /// Extracts the main article payload into `ReadabilityData`.
    /// - Parameter includeComments: Whether to attempt comment extraction.
    public func extractReadabilityData(includeComments: Bool = true) throws -> ReadabilityData {
        // 1) Metadata (title/desc/author/date/keywords/images).
        let structured = try extractStructuredData()
        let title = try structured?.title ?? extractTitle()
        let description = try structured?.description ?? extractDescription()
        let metaImage = try document.select("meta[property='og:image'], meta[name='twitter:image'], meta[property='og:image:url']").first()?.attr("content")
        let topImage = structured?.image ?? metaImage ?? extractFallbackImage(in: document.body())
        let topVideo = try document.select("meta[property='og:video:url']").first()?.attr("content")
        let author = try extractAuthor(structured: structured)
        let datePublished = try extractDate(structured: structured)
        let keywords = structured?.keywords ?? extractKeywords()
        
        // 2) Main content.
        guard let topCandidate = try extractTopCandidate() else {
            throw ReadabilityError.parsingFailed
        }
        let mergedContent = try mergeSiblings(with: topCandidate)
        try stripShareAndNoise(from: mergedContent)
        
        // 3) Render payload.
        let contentHTML = try mergedContent.outerHtml()
        let plainText = try mergedContent.text()
        let readingTime = plainText.isEmpty ? nil : estimatedReadingTime(for: plainText)
        let comments = includeComments ? try extractComments() : nil
        
        if verboseLogging {
            let snippet = contentHTML.prefix(2000)
            logger("Readability extracted article HTML (\(contentHTML.count) chars) for \"\(title)\" [first 2000 chars]\n\(snippet)")
        }
        
        return ReadabilityData(
            title: title,
            description: description,
            topImage: topImage,
            text: plainText,
            content: contentHTML,
            topVideo: topVideo,
            keywords: keywords,
            datePublished: datePublished,
            author: author,
            estimatedReadingTime: readingTime,
            comments: comments
        )
    }
    
    // MARK: - Visibility & Pruning
    /// Remove elements whose role attribute indicates non-content (navigation, dialog, etc).
    private func removeElementsWithRoles() throws {
        let rolesToRemove = ["navigation", "menubar", "complementary", "dialog", "alertdialog"]
        let elementsWithRole = try document.select("[role]")
        for element in elementsWithRole.array() {
            let role = try element.attr("role").lowercased()
            if rolesToRemove.contains(role) {
                try element.remove()
            }
        }
    }
    
    /// Remove <a> elements whose text (trimmed) is shorter than 20 characters.
    private func removeShortLinks() throws {
        let links = try document.select("a")
        for link in links.array() {
            let text = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            // If the text is too short and does not seem to be a meaningful sentence, remove the link.
            if text.count > 0 && text.count < 20 {
                // TODO: Consider unwrapping links instead of removing to preserve inline text.
                try link.remove()
            }
        }
    }
    
    /// Mimics Firefox's _isProbablyVisible() by checking inline styles and attributes.
    private func isProbablyVisible(element: Element) throws -> Bool {
        if element.hasAttr("hidden") {
            return false
        }
        if let style = try? element.attr("style").lowercased() {
            if style.contains("display:none") || style.contains("display: none") {
                return false
            }
            if style.contains("visibility:hidden") || style.contains("visibility: hidden") {
                return false
            }
        }
        if element.hasAttr("aria-hidden") {
            let ariaHidden = try element.attr("aria-hidden").lowercased()
            if ariaHidden == "true" {
                return false
            }
        }
        if let role = try? element.attr("role").lowercased(), ["navigation", "menu", "complementary"].contains(role) {
            return false
        }
        return true
    }
    
    /// Removes elements that are likely not visible (using inline style attributes).
    private func removeInvisibleElements() throws {
        let allElements = try document.select("*")
        for element in allElements.array() {
            if !(try isProbablyVisible(element: element)) {
                try element.remove()
            }
        }
    }
    
    /// Checks whether an element is a share or comment element based on its class, id, or aria-label.
    private func isShareOrCommentElement(_ element: Element) throws -> Bool {
        let className = try element.className()
        let idName = element.id()
        
        // Check if the class or id matches the share/comment regex.
        let classRange = NSRange(location: 0, length: className.utf16.count)
        if shareClassRegex.firstMatch(in: className, options: [], range: classRange) != nil {
            return true
        }
        let idRange = NSRange(location: 0, length: idName.utf16.count)
        if shareClassRegex.firstMatch(in: idName, options: [], range: idRange) != nil {
            return true
        }
        
        // Check the aria-label attribute if it exists.
        if let ariaLabel = try? element.attr("aria-label"), ariaLabel.lowercased().contains("share") {
            return true
        }
        
        return false
    }
    
    /// Remove obvious share/utility noise from the merged article content.
    private func stripShareAndNoise(from root: Element) throws {
        let allElements = try root.select("*")
        for el in allElements.array().reversed() {
            if try isShareOrCommentElement(el) {
                try el.remove()
            }
        }
        let shareButtons = try root.select("[aria-label*='share'], [aria-label*='Share']")
        try shareButtons.remove()
        try removeHighLinkDensityUtilityBlocks(in: root)
        try removeNoiseMarkers(in: root)
    }

    /// Removes blocks that are likely nav/related lists based on high link density and low text content.
    private func removeHighLinkDensityUtilityBlocks(in root: Element) throws {
        let candidates = try root.select("ul, ol, nav, section, div")
        for el in candidates.array().reversed() {
            let text = try el.text()
            let textLength = text.count
            if textLength < 20 { continue }
            let density = try computeLinkDensity(for: el)
            let linkCount = try el.select("a").size()
            let lower = text.lowercased()
            // Remove obvious ads/noise labels.
            if textLength < 80 && ["advertisement", "sponsored", "sponsored content", "ad"].contains(lower.trimmingCharacters(in: .whitespacesAndNewlines)) {
                try el.remove()
                continue
            }
            // Remove if mostly links and relatively short text, to trim "related" and category lists.
            if density > 0.6 && (textLength < 500 || linkCount >= 5) {
                try el.remove()
                continue
            }
            // Remove blocks labelled as recommendations/related if moderately link-heavy.
            let hasNoiseKeyword = lower.contains("recommended") || lower.contains("related") || lower.contains("more stories") || lower.contains("read more") || lower.contains("you may also like")
            if hasNoiseKeyword && density > 0.3 && textLength < 800 {
                try el.remove()
            }
        }
    }

    /// Removes headings or small paragraphs that are obvious noise markers.
    private func removeNoiseMarkers(in root: Element) throws {
        let selectors = "h1, h2, h3, h4, h5, h6, p, div"
        let noiseTerms = ["advertisement", "recommended", "recommended stories", "related stories", "more stories", "sponsored"]
        let elements = try root.select(selectors).array()
        for el in elements.reversed() {
            let text = try el.text().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if text.isEmpty { continue }
            if noiseTerms.contains(text) || noiseTerms.contains(where: { text.hasPrefix($0) }) {
                // Remove the marker itself.
                try el.remove()
                // Also remove an immediate following list/section that is mostly links (common for "recommended" blocks).
                if let next = try el.nextElementSibling() {
                    let tag = next.tagName().lowercased()
                    if tag == "ul" || tag == "ol" || tag == "section" || tag == "div" {
                        let density = (try? computeLinkDensity(for: next)) ?? 0.0
                        let textLength = (try? next.text().count) ?? 0
                        if density > 0.4 && textLength < 800 {
                            try next.remove()
                        }
                    }
                }
            }
        }
    }
    
    private func extractComments() throws -> [(author: String, date: String, content: String)] {
        if let extractor = commentExtractor {
            return try extractor(document)
        }

        let primarySelectors = [
            ".comment-list .comment",
            ".comments .comment",
            ".comment",
            "li.comment",
            "[itemprop='comment']"
        ]
        let secondarySelectors = [
            "[class*=comment]",
            "[id*=comment]",
            "[class*=reply]",
            "[id*=reply]",
            "[class*=discussion]",
            "[id*=discussion]",
            ".comment-list",
            ".comment-body",
            ".comment-content",
            "#disqus_thread",
            ".fb-comments"
        ]

        var elements = try document.select(primarySelectors.joined(separator: ", ")).array()
        if elements.isEmpty {
            elements = try document.select(secondarySelectors.joined(separator: ", ")).array()
        }
        var comments: [(String, String, String)] = []
        var seen: Set<String> = []

        for el in elements {
            let content = try el.select("div.post-body, p, .comment-content, .comment-body, .content").text()
            if content.count < 20 { continue }

            let author = try? el.select(".author, .user, .username, span.post-author, .comment-author, [itemprop='author'], .fn").first()?.text() ?? "Anonymous"
            let date = try? el.select("time[datetime], time, [data-datetime], .comment-date, .date, [itemprop='datePublished']").first()?.attr("datetime") ?? ""

            let key = "\(author ?? "Anonymous")|\(date ?? "")|\(content)"
            if seen.contains(key) { continue }
            seen.insert(key)
            comments.append((author ?? "Anonymous", date ?? "", content))
            if comments.count >= 50 { break }
        }
        if comments.isEmpty {
            // Fallback: treat each <div class="comment"> as a comment block even if the parent was selected.
            let fallback = try document.select("div.comment, li.comment")
            for el in fallback.array() {
                let content = try el.select("div.post-body, p, .comment-content, .comment-body, .content").text()
                if content.count < 20 { continue }
                let author = try? el.select(".author, .user, .username, span.post-author, .comment-author, [itemprop='author'], .fn").first()?.text() ?? "Anonymous"
                let date = try? el.select("time[datetime], time, [data-datetime], .comment-date, .date, [itemprop='datePublished']").first()?.attr("datetime") ?? ""
                let key = "\(author ?? "Anonymous")|\(date ?? "")|\(content)"
                if seen.contains(key) { continue }
                seen.insert(key)
                comments.append((author ?? "Anonymous", date ?? "", content))
                if comments.count >= 50 { break }
            }
        }
        return comments
    }
    
    // MARK: - Metadata Extraction
    private func extractTitle() throws -> String {
        for selector in titleMetaSelectors {
            if let value = try document.select(selector).first()?.attr("content"), value.isEmpty == false {
                return value
            }
        }
        let docTitle = try document.title()
        let genericTitles = ["home", "menu", "index", "untitled", "page not found"]
        if genericTitles.contains(docTitle.lowercased()) {
            if let h1 = try document.select("h1").first()?.text(), h1.isEmpty == false {
                return h1
            }
        }
        return docTitle
    }

    private func extractDescription() throws -> String? {
        for selector in descriptionMetaSelectors {
            if let value = try document.select(selector).first()?.attr("content"), value.isEmpty == false {
                return value
            }
        }
        // Fallback: use the first paragraph text if no meta description is available.
        if let p = try document.select("p").first()?.text(), p.count > 40 {
            return p
        }
        return nil
    }

    private func extractAuthor(structured: StructuredData?) throws -> String? {
        if let author = structured?.author, author.isEmpty == false { return author }
        for selector in authorMetaSelectors {
            if let value = try document.select(selector).first()?.attr("content"), value.isEmpty == false {
                return value
            }
        }
        // Look for bylines in the DOM.
        if let value = try document.select(".byline, .by-author, .author, [rel='author'], .posted-by, .article-author, [itemprop='author']").first()?.text(), value.isEmpty == false {
            return value
        }
        return nil
    }

    private func extractDate(structured: StructuredData?) throws -> String? {
        if let date = structured?.datePublished, date.isEmpty == false { return date }
        for selector in dateMetaSelectors {
            if let value = try document.select(selector).first()?.attr("content"), value.isEmpty == false {
                return value
            }
        }
        if let time = try document.select("time[datetime]").first()?.attr("datetime"), time.isEmpty == false {
            return time
        }
        if let timeText = try document.select("time").first()?.text(), timeText.isEmpty == false {
            return timeText
        }
        return nil
    }

    private func extractKeywords() -> [String]? {
        for selector in keywordsMetaSelectors {
            if let content = try? document.select(selector).first()?.attr("content"), content.isEmpty == false {
                return content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
        }
        return nil
    }

    private func extractStructuredData() throws -> StructuredData? {
        let scripts = try document.select("script[type='application/ld+json']").array()
        for script in scripts {
            let raw = script.data()
            guard let data = raw.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let article = extractArticleNode(from: json) {
                return StructuredData(
                    title: extractTitle(from: article),
                    description: article["description"] as? String,
                    author: extractAuthor(from: article["author"]),
                    datePublished: article["datePublished"] as? String ?? article["dateCreated"] as? String,
                    image: extractImage(from: article["image"]),
                    keywords: extractKeywords(from: article["keywords"])
                )
            }
        }
        return nil
    }

    private func extractArticleNode(from json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if isArticleType(dict["@type"]) { return dict }
            if let graph = dict["@graph"] as? [Any] {
                for node in graph {
                    if let found = extractArticleNode(from: node) { return found }
                }
            }
        }
        if let array = json as? [Any] {
            for item in array {
                if let found = extractArticleNode(from: item) { return found }
            }
        }
        return nil
    }

    private func isArticleType(_ type: Any?) -> Bool {
        if let s = type as? String {
            return s.lowercased().contains("article") || s.lowercased().contains("blogposting")
        }
        if let arr = type as? [Any] {
            return arr.contains { element in
                if let s = element as? String {
                    return s.lowercased().contains("article") || s.lowercased().contains("blogposting")
                }
                return false
            }
        }
        return false
    }

    private func extractTitle(from dict: [String: Any]) -> String? {
        if let headline = dict["headline"] as? String, !headline.isEmpty { return headline }
        if let name = dict["name"] as? String, !name.isEmpty { return name }
        return nil
    }

    private func extractAuthor(from authorField: Any?) -> String? {
        if let s = authorField as? String { return s }
        if let dict = authorField as? [String: Any] {
            if let name = dict["name"] as? String, !name.isEmpty { return name }
        }
        if let arr = authorField as? [Any] {
            for item in arr {
                if let name = extractAuthor(from: item), !name.isEmpty { return name }
            }
        }
        return nil
    }

    private func extractImage(from imageField: Any?) -> String? {
        if let s = imageField as? String { return s }
        if let dict = imageField as? [String: Any] {
            if let url = dict["url"] as? String, !url.isEmpty { return url }
        }
        if let arr = imageField as? [Any] {
            for item in arr {
                if let url = extractImage(from: item), !url.isEmpty { return url }
            }
        }
        return nil
    }

    private func extractKeywords(from keywordsField: Any?) -> [String]? {
        if let arr = keywordsField as? [String] {
            let cleaned = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }
        if let s = keywordsField as? String {
            let cleaned = s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    private func extractFallbackImage(in element: Element?) -> String? {
        guard let element else { return nil }
        let imgSelectors = [
            "img[src]",
            "img[data-src]",
            "img[data-original]",
            "img[data-lazy-src]",
            "img[data-srcset]"
        ]
        if let img = try? element.select(imgSelectors.joined(separator: ", ")).first() {
            if let src = try? img.attr("src"), !src.isEmpty { return src }
            if let src = try? img.attr("data-src"), !src.isEmpty { return src }
            if let src = try? img.attr("data-original"), !src.isEmpty { return src }
            if let src = try? img.attr("data-lazy-src"), !src.isEmpty { return src }
            if let srcset = try? img.attr("data-srcset"), !srcset.isEmpty {
                return srcset.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? "" }.first { !$0.isEmpty }
            }
        }
        return nil
    }
}
