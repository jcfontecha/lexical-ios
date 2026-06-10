/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

internal func isRootTextContentEmpty(isEditorComposing: Bool, trim: Bool = true) -> Bool {
  if isEditorComposing {
    return false
  }

  var text = rootTextContentRemovingEmptyInvisibles()
  if trim {
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  return text.isEmpty
}

private func rootTextContentRemovingEmptyInvisibles() -> String {
  textContentRemovingEmptyInvisibles(rootTextContent())
}

/// Removes every scalar in `emptyTextInvisibleScalarValues` from the text.
public func textContentRemovingEmptyInvisibles(_ textContent: String) -> String {
  var text = String.UnicodeScalarView()
  for scalar in textContent.unicodeScalars where !emptyTextInvisibleScalarValues.contains(scalar.value) {
    text.append(scalar)
  }
  return String(text)
}

/// Whether the text is empty once caret-anchor invisibles (and, with `trim`, whitespace) are ignored.
public func isTextContentEmptyIgnoringEmptyInvisibles(_ textContent: String, trim: Bool = true) -> Bool {
  var text = textContentRemovingEmptyInvisibles(textContent)
  if trim {
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return text.isEmpty
}

/// Number of scalars in the text that belong to `emptyTextInvisibleScalarValues`.
public func emptyTextInvisibleScalarCount(in textContent: String) -> Int {
  textContent.unicodeScalars.reduce(0) { count, scalar in
    count + (emptyTextInvisibleScalarValues.contains(scalar.value) ? 1 : 0)
  }
}

/// The canonical caret-anchor string seeded into otherwise-empty blocks (list items,
/// freshly converted headings) so the caret has a text anchor and decorations render.
/// Anything that decides "is this block visibly empty?" must ignore it — use the
/// helpers above rather than comparing against this constant directly.
public let emptyTextCaretAnchor = "\u{200B}"

/// Scalars treated as invisible when deciding whether text content is "visibly empty".
/// The canonical anchor is U+200B; the rest are joiner/BOM characters that can leak
/// in via paste or IME and must never count as user-visible content.
public let emptyTextInvisibleScalarValues: Set<UInt32> = [
  0x200B, // zero-width space
  0x200C, // zero-width non-joiner
  0x200D, // zero-width joiner
  0x2060, // word joiner
  0xFEFF  // zero-width no-break space / BOM
]

internal func rootTextContent() -> String {
  guard let root = getRoot() else { return "" }

  return root.getTextContent()
}

internal func canShowPlaceholder(isComposing: Bool) -> Bool {
  if !isRootTextContentEmpty(isEditorComposing: isComposing, trim: false) {
    return false
  }

  guard let root = getRoot() else { return false }

  let children = root.getChildren()
  if children.count > 1 {
    return false
  }

  for childNode in children {
    guard let childNode = childNode as? ElementNode else { return true }

    if childNode.type != NodeType.paragraph {
      // Allow placeholder for a single, empty heading (start-with-title UX)
      if childNode.type == NodeType.heading {
        let nodeChildren = childNode.getChildren()
        for nodeChild in nodeChildren {
          if !isTextNode(nodeChild) {
            return false
          }
        }
        return true
      }
      return false
    }

    let nodeChildren = childNode.getChildren()
    for nodeChild in nodeChildren {
      if !isTextNode(nodeChild) {
        return false
      }
    }
  }

  return true
}
