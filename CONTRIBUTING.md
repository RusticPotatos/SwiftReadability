# Contributing

Thanks for helping improve SwiftReadability.

## Quick start

```sh
swift test
```

## Guidelines

- Keep public APIs stable; discuss changes before expanding the surface area.
- Prefer small, focused changes with tests.
- Add new HTML fixtures under `SwiftReadabilityTests/html_examples`.
- Update `SwiftReadabilityTests/SwiftReadabilityTests.swift` with expectations.
- Keep documentation in `SwiftReadability/SwiftReadability.docc` up to date.

## Branching and releases

We use a Gitflow-style model:
- `develop` is the default branch and the target for all pull requests.
- `release/*` branches are used to prepare a versioned release.
- `main` receives fast-forward or merge commits from `release/*` for published releases.

Release flow:
1) Branch `release/<version>` from `develop`.
2) Finalize docs/tests and tag the release on `main`.
3) Merge `main` back into `develop` after release.

## Docs

Generate DocC output:

```sh
make docs
```
