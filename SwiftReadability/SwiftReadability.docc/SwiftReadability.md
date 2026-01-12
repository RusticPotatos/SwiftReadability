# ``SwiftReadability``

A lightweight Swift implementation of Readability-style article extraction.

## Overview

SwiftReadability extracts the primary article content and metadata from raw HTML. It is designed to work on static documents without a browser engine, using SwiftSoup plus a set of heuristics that score and merge candidate elements.

The library returns a single `ReadabilityData` payload that includes both plain text and HTML so you can render or index the result.

> Note: The HTML output is wrapped in a `div` with `id="readability-content"` to make styling and inspection easier.

## Getting Started

Extract from raw HTML:

```swift
import SwiftReadability

let readability = try Readability(html: html)
let data = try readability.extractReadabilityData()
print(data.title)
```

Fetch and extract from a URL:

```swift
let data = try await Readability.parse(url: url)
```

## Core Concepts

### ReadabilityData

`ReadabilityData` is the single output type. It includes:
- `content`: HTML with structure preserved.
- `text`: plain text for indexing or summaries.
- `title`, `description`, `author`, `datePublished`: best-effort metadata.
- `topImage` and `topVideo`: primary media URLs if detected.
- `keywords`: tags parsed from metadata or JSON-LD.
- `estimatedReadingTime`: a simple words-per-minute estimate.
- `comments`: optional comment tuples when extraction is enabled.

### ReadabilityFlags

Use flags to tune heuristics:
- `stripUnlikelies`: remove elements that look like non-content.
- `weightClasses`: boost or penalize candidates based on class names.
- `cleanConditionally`: remove noisy blocks based on link density and text size.

`ReadabilityFlags.all` is the default.

## Extraction Pipeline (Maintainers)

High-level flow in `Readability.extractReadabilityData()`:
1. Parse HTML with SwiftSoup.
2. Initial cleanup: remove common non-content selectors, roles, invisible nodes, and short links.
3. Score candidates (`article`, `div`, `section`, `p`) with a weighted heuristic.
4. Pick the top candidate and merge sibling nodes with similar signal.
5. Strip share widgets, high link-density blocks, and noise markers.
6. Render HTML + plain text and compute reading time.
7. Optionally extract comments.

Key helpers:
- Scoring: `computeContentScore(for:)`
- Sibling merge: `mergeSiblings(with:)`
- Noise removal: `stripShareAndNoise(from:)`, `removeHighLinkDensityUtilityBlocks(in:)`, `removeNoiseMarkers(in:)`
- Metadata: `extractStructuredData()`, plus meta tag fallbacks

## Logging

Verbose logging is gated by the `verboseLogging` parameter passed to `Readability`. The underlying logger is an internal implementation detail (not a public API) and may change without notice.

## Tests and Fixtures

Tests live in `SwiftReadabilityTests/SwiftReadabilityTests.swift` and load HTML fixtures from `SwiftReadabilityTests/html_examples`.

Run tests with:

```sh
swift test
```

When adding new fixtures:
- Add a new HTML file in `SwiftReadabilityTests/html_examples`.
- Extend the expectations in `ReadabilityFixtureTests`.
- Prefer assertions on title, minimum content length, and key text snippets.

## Repository Layout

- `SwiftReadability/SwiftReadability.swift`: core extraction logic and public API.
- `SwiftReadability/Core/Logging.swift`: logging utilities used by `verboseLogging`.
- `SwiftReadability/SwiftReadability.docc`: public documentation.
- `SwiftReadabilityTests/`: test suite and HTML fixtures.

## Extending the Extractor

Common extension points:
- Pass a custom `commentExtractor` to `Readability` if your sources use custom comment markup.
- Add or remove selectors in `unwantedSelectors` to trim site-specific noise.
- Extend metadata selectors if you need additional fields.

## Known Limitations

- JavaScript-rendered content is not executed.
- Aggressive paywalls or obfuscated markup may reduce accuracy.
- Inline-heavy navigation lists can still leak into content if they resemble prose.

## Topics

### Essentials

- ``Readability``
- ``ReadabilityData``
- ``ReadabilityFlags``
