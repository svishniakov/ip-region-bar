# Contributing

Thank you for contributing to IP Region Bar.

## Local Development

1. Fork and clone this repository.
2. Open `Package.swift` in Xcode (or build from CLI).
3. Build locally.

```bash
make build
```

## Code Style

- Swift 5.9+
- Run SwiftLint before opening a PR:

```bash
swiftlint lint --strict
```

## Issues

When opening an issue, include:

- macOS version
- app version
- reproduction steps
- expected and actual behavior

## Pull Requests

- Keep PRs focused and reviewable.
- Include tests or verification steps.
- Update docs/changelog when behavior changes.

## Proposing New IP Providers

To propose a new external-IP provider:

1. Open an issue with provider URL and SLA details.
2. Explain privacy implications and response format.
3. Provide rate-limit and reliability information.
