# SwiftReadability

A lightweight Swift implementation of Readability-style article extraction.

## Install (Swift Package Manager)

Add to `Package.swift`:

```swift
.package(url: "https://github.com/RusticPotatos/SwiftReadability", from: "0.1.0")
```

Then add the product to your target:

```swift
.product(name: "SwiftReadability", package: "SwiftReadability")
```

## Usage

```swift
import SwiftReadability

let readability = try Readability(html: html)
let data = try readability.extractReadabilityData()

print(data.title)
print(data.text ?? "")
```

Async URL convenience:

```swift
let data = try await Readability.parse(url: url)
```

## Tests

```sh
swift test
```

## Contributing

See `CONTRIBUTING.md`.
