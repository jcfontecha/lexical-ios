/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import Lexical
@testable import LexicalListPlugin

@MainActor
final class ListGeometryTests: XCTestCase {
  func testMultiItemAndNestedListGeometryUsesAllLineFragments() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags()
    )
    view.frame = CGRect(x: 0, y: 0, width: 180, height: 100)
    view.layoutIfNeeded()
    var outerKey = ""
    var firstItemKey = ""
    var nestedKey = ""

    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }

      let outer = ListNode(listType: .bullet, start: 1)
      outerKey = outer.key

      let first = ListItemNode()
      firstItemKey = first.key
      try first.append([
        TextNode(text: "A first list item long enough to wrap across multiple lines")
      ])
      try outer.append([first])

      let second = ListItemNode()
      try second.append([TextNode(text: "Second item")])
      let nested = ListNode(listType: .number, start: 1)
      nestedKey = nested.key
      let nestedItem = ListItemNode()
      try nestedItem.append([TextNode(text: "Nested item")])
      try nested.append([nestedItem])
      try second.append([nested])
      try outer.append([second])

      let third = ListItemNode()
      try third.append([TextNode(text: "Third item")])
      try outer.append([third])
      try root.append([outer])
    }

    view.setNeedsLayout()
    view.layoutIfNeeded()
    let geometries = view.geometries(
      forNodeKeys: [outerKey, firstItemKey, nestedKey]
    )
    let outer = try XCTUnwrap(geometries[outerKey])
    let first = try XCTUnwrap(geometries[firstItemKey])
    let nested = try XCTUnwrap(geometries[nestedKey])

    XCTAssertGreaterThan(outer.rect.height, first.rect.height)
    XCTAssertTrue(outer.rect.contains(first.rect))
    XCTAssertTrue(outer.rect.contains(nested.rect))
    XCTAssertGreaterThan(first.rect.height, 20)
    XCTAssertLessThan(nested.rect.height, outer.rect.height)
    XCTAssertGreaterThan(nested.rect.minY, outer.rect.minY)
    XCTAssertNotEqual(nested.rect, outer.rect)
  }
}
