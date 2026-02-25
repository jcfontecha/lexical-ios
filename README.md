# Lexical iOS

An extensible text editor/renderer written in Swift, built on top of TextKit, and sharing a philosophy and API with [Lexical JavaScript](https://lexical.dev).

## Status

Lexical iOS is used in multiple apps at Meta, including rendering feed posts that contain inline images in Workplace iOS.

Lexical iOS is in pre-release with no guarantee of support.

For changes between versions, see the [Lexical iOS Changelog](https://github.com/facebook/lexical-ios/blob/main/Lexical/Documentation.docc/Changelog.md).

## Fork Divergence (Public)

This repository tracks `facebook/lexical-ios` and is intentionally diverged for list rendering and cursor/placeholder behavior.

As of 2026-02-25:

- `upstream/main` is included via the `upstream` remote.
- This branch is `7` commits ahead of `upstream/main` and `0` commits behind.
- Upstream hotfixes from `main` are included (including event switch hardening, nil-coalescing cleanup, and iOS 17 deprecation annotations).

Current fork-only changes are in:

- `LIST_STYLING_CUSTOMIZATION.md`
- `Lexical/Core/Events.swift`
- `Lexical/Core/TextUtils.swift`
- `Lexical/Helper/AttributesUtils.swift`
- `Lexical/Helper/NSAttributedStringKey+Extensions.swift`
- `Lexical/Helper/Theme.swift`
- `Lexical/LexicalView/LexicalView.swift`
- `Lexical/TextView/TextView.swift`
- `Plugins/LexicalListPlugin/LexicalListPlugin/ListItemNode.swift`
- `Plugins/LexicalListPlugin/LexicalListPlugin/ListPlugin.swift`
- `Plugins/LexicalListPlugin/LexicalListPlugin/ListStyleEvents.swift`

### Why these diffs exist

1. Better list UX and appearance control (`Theme.swift`, `ListItemNode.swift`, `ListPlugin.swift`, `ListStyleEvents.swift`).
2. Placeholder behavior that updates after insert and supports empty single-heading documents (`TextUtils.swift`, `Events.swift`).
3. Cursor rendering options (`TextView.swift`, `LexicalView.swift`, `Theme.swift`).

### Minor shortcuts kept (and what they enable)

- Zero-width-space insertion for empty list items.
  - Enables reliable bullet rendering in custom-drawing paths for otherwise-empty list nodes.
  - Tradeoff: synthetic empty-text content is introduced and must be kept in sync with list lifecycle transitions.

- Hardcoded cursor-adjustment parameters inside `caretRect(for:)`.
  - Enables quick per-block visual tuning to avoid excessive visual height from spacing.
  - Tradeoff: behavior is not yet configurable through public `Theme` values.

- Theme-driven list spacing extension points were added for pragmatic styling control.
  - Enables quick UX iteration for list margins/indenting without changing core layout algorithms.

## Playground

We have a sample playground app demonstrating some of Lexical's features:

![Screenshot of playground app](docs/resources/playground.png)

The playground app contains the code for a rich text toolbar. While this is not specifically a reusable toolbar that you can drop straight into your projects, its code should provide a good starting point for you to customise.

This playground app is very new, and many more features will come in time!

## Requirements
Lexical iOS is written in Swift, and targets iOS 13 and above. (Note that the Playground app requires at least iOS 14, due to use of UIKit features such as UIMenu.)

## Building Lexical
We provide a Swift package file that is sufficient to build Lexical core. Add this as a dependency of your app to use Lexical.

Some plugins included in this repository do not yet have package files. (This is because we use a different build system internally at Meta. Adding these would be an easy PR if you want to start contributing to Lexical!)

## Using Lexical in your app
For editable text with Lexical, instantiate a `LexicalView`. To configure it with plugins and a theme, you can create an `EditorConfig` to pass in to the `LexicalView`'s initialiser.

To programatically work with the data within your `LexicalView`, you need access to the `Editor`. You can then call `editor.update {}`, and inside that closure you can use the Lexical API.

For more information, see the documentation.

## Full documentation
Read [the Lexical iOS documentation](https://facebook.github.io/lexical-ios/documentation/lexical/). 

## Join the Lexical community
Join us at [our Discord server](https://discord.gg/KmG4wQnnD9), where you can talk with the Lexical team and other users.

See the [CONTRIBUTING](CONTRIBUTING.md) file for how to help out.

## Tests
Lexical has a suite of unit tests, in XCTest format, which can be run from within Xcode. We do not currently have any end-to-end tests.

## License
Lexical is [MIT licensed](https://github.com/facebook/lexical/blob/main/LICENSE).
