# Contributing to Paperflip

Thank you for your interest in improving Paperflip. This project uses a maintainer-reviewed pull request workflow so the public package stays stable for Flutter developers.

## Project governance

- The default branch is `main`.
- Do not push directly to `main`. Submit changes through a pull request from a feature branch or fork.
- The repository owner and maintainers explicitly authorized by the owner are responsible for final review and merge decisions.
- A pull request is not approved for merge merely because it has been opened or has passing checks. A maintainer must review it.
- Maintainers may request changes, defer work, or close a pull request that is out of scope, unsafe, incomplete, or inconsistent with the project's direction.
- Being able to open a pull request does not grant write or merge access to the repository.

Repository settings must enforce these rules; see **GitHub settings to configure** below.

## Before opening an issue or pull request

For bugs, include a minimal reproduction when possible. For larger features or public API changes, open an issue first to discuss the design before spending substantial time implementing it. Small documentation fixes and narrowly scoped bug fixes can usually be submitted directly as pull requests.

Check existing issues and pull requests to avoid duplicating ongoing work.

## Development workflow

1. Fork the repository if you do not have write access.
2. Create a branch from the current `main` branch. Suggested prefixes are `fix/`, `feat/`, `docs/`, `test/`, and `refactor/`.
3. Make a focused change. Avoid unrelated formatting, generated output, secrets, and large fixtures unless they are needed and legally redistributable.
4. Add or update tests for bug fixes and behavior changes.
5. Update the README or other documentation when behavior, setup steps, or public APIs change.
6. Run formatting, analysis, and tests using the Flutter SDK pinned by the repository. If the project uses FVM, use `fvm flutter` consistently.
7. Push your branch to your fork and open a pull request against `main`.
8. Respond to review feedback and resolve conversations. Only an authorized maintainer merges the pull request.

## Checks to run

From the package root:

```bash
fvm flutter pub get
dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
```

If FVM is not used, run the equivalent `flutter` commands with the project's intended Flutter SDK. If a test requires an optional fixture that is absent, report it clearly; do not silently remove or weaken the test to obtain a green result. Include the output of any check that could not be completed.

For package release validation, maintainers should also run:

```bash
dart pub publish --dry-run
```

## Pull request requirements

A pull request should:

- Explain the problem and the proposed solution.
- Link the relevant issue, if one exists.
- Describe behavior changes and public API changes, if any.
- List the tests and checks performed, including anything that could not be run.
- Include screenshots or short recordings when a UI or page-curl rendering change is easier to review visually.
- Update tests and documentation where appropriate.
- Avoid unrelated changes and unnecessary dependency upgrades.
- Confirm that no credentials, private documents, copyrighted test books, or unrelated generated files are included.

### Rendering and engine changes

Changes to mesh geometry, camera projection, texture lifetime, page caching, gestures, or animation settling should include targeted regression tests where practical. Please explain any trade-offs that may affect rendering quality, performance, memory use, or cross-platform behavior.

### Public API and breaking changes

Paperflip is in its initial-release stage and its API may evolve before `1.0.0`. Even so, discuss public API changes in an issue or pull request description. Do not remove or rename an exported API without explaining the impact and updating documentation and tests.

## Coding conventions

- Follow idiomatic Dart and Flutter style.
- Keep changes small and readable.
- Prefer tests that verify observable behavior rather than private implementation details.
- Avoid adding dependencies when the existing Flutter SDK or package dependencies already provide the required functionality.
- Do not include generated files unless they are intentionally maintained in the repository.

## License

By submitting a contribution, you agree that it may be distributed under the license that applies to the Paperflip project. Check the repository's `LICENSE` file before contributing.

## GitHub settings to configure (maintainers)

This document states the policy but does not enforce repository permissions. In GitHub, configure a ruleset or branch protection rule targeting `main`:

1. Require a pull request before merging.
2. Require at least one approving review for contributions from other people.
3. Require review from code owners if you use `.github/CODEOWNERS`.
4. Require all review conversations to be resolved.
5. Block force pushes and branch deletion.
6. Add successful CI status checks as required checks only after the workflow is configured and consistently passing.
7. Restrict who can bypass the rules. Keep bypass rights limited to the repository owner and trusted maintainers.

If you want maintainers to merge only after another person's approval, make sure the settings also dismiss stale approvals after new commits and do not allow the PR author to satisfy the approval requirement themselves. Availability of particular controls depends on repository visibility, ownership, and GitHub plan.
