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

internal func textContentRemovingEmptyInvisibles(_ textContent: String) -> String {
  var text = String.UnicodeScalarView()
  for scalar in textContent.unicodeScalars where !emptyTextInvisibleScalarValues.contains(scalar.value) {
    text.append(scalar)
  }
  return String(text)
}

internal func isTextContentEmptyIgnoringEmptyInvisibles(_ textContent: String, trim: Bool = true) -> Bool {
  var text = textContentRemovingEmptyInvisibles(textContent)
  if trim {
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return text.isEmpty
}

private let emptyTextInvisibleScalarValues: Set<UInt32> = [
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
