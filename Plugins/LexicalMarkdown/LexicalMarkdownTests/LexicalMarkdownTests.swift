/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest

@testable import Lexical
@testable import LexicalListPlugin
@testable import LexicalMarkdown

class LexicalMarkdownTests: XCTestCase {
  var lexicalView: LexicalView?
  var editor: Editor? {
    get {
      return lexicalView?.editor
    }
  }

  override func setUp() {
    lexicalView = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
  }

  override func tearDown() {
    lexicalView = nil
  }

  private func markdown(buildNode: () throws -> Node) throws -> String {
    guard let editor else {
      throw LexicalError.invariantViolation("Expected editor")
    }

    var result = ""
    try editor.update {
      let node = try buildNode()
      guard let root = getRoot() else {
        throw LexicalError.invariantViolation("Expected root node")
      }
      try root.getChildren().forEach { try $0.remove() }
      try root.append([node])
      result = try LexicalMarkdown.generateMarkdown(from: node)
    }
    return result
  }

  func testGenerateMarkdownForSingleParagraphHeadingAndQuote() throws {
    XCTAssertEqual(
      try markdown {
        let paragraph = ParagraphNode()
        try paragraph.append([TextNode(text: "Paragraph")])
        return paragraph
      },
      "Paragraph"
    )

    XCTAssertEqual(
      try markdown {
        let heading = HeadingNode(tag: .h2)
        try heading.append([TextNode(text: "Heading")])
        return heading
      },
      "## Heading"
    )

    XCTAssertEqual(
      try markdown {
        let quote = QuoteNode()
        try quote.append([TextNode(text: "Quote")])
        return quote
      },
      "> Quote"
    )
  }

  func testGenerateMarkdownForMultilineCodeBlock() throws {
    XCTAssertEqual(
      try markdown {
        let code = CodeNode()
        try code.append([
          TextNode(text: "let first = 1"),
          LineBreakNode(),
          TextNode(text: "let second = 2"),
        ])
        return code
      },
      """
      ```
      let first = 1
      let second = 2
      ```
      """
    )
  }

  func testGenerateMarkdownForMultiItemList() throws {
    XCTAssertEqual(
      try markdown {
        let list = ListNode(listType: .bullet, start: 1)
        let firstItem = ListItemNode()
        try firstItem.append([TextNode(text: "First")])
        let secondItem = ListItemNode()
        try secondItem.append([TextNode(text: "Second")])
        try list.append([firstItem, secondItem])
        return list
      },
      """
      - First
      - Second
      """
    )
  }

  func testGenerateMarkdownForEmptySupportedBlocks() throws {
    XCTAssertEqual(try markdown { ParagraphNode() }, "")
    XCTAssertEqual(try markdown { HeadingNode(tag: .h1) }, "# ")
    XCTAssertEqual(try markdown { QuoteNode() }, "")
    XCTAssertEqual(
      try markdown { CodeNode() },
      """
      ```

      ```
      """
    )

    XCTAssertEqual(
      try markdown {
        let list = ListNode(listType: .bullet, start: 1)
        let emptyItem = ListItemNode()
        try emptyItem.append([TextNode(text: emptyTextCaretAnchor)])
        try list.append([emptyItem])
        return list
      },
      "- "
    )
  }

  func testGenerateMarkdownPreservesInlineFormatting() throws {
    XCTAssertEqual(
      try markdown {
        let paragraph = ParagraphNode()
        let bold = TextNode(text: "bold")
        try bold.setBold(true)
        let italic = TextNode(text: "italic")
        try italic.setItalic(true)
        try paragraph.append([
          TextNode(text: "Plain, "),
          bold,
          TextNode(text: " and "),
          italic,
        ])
        return paragraph
      },
      "Plain, **bold** and *italic*"
    )
  }

  func testGenerateMarkdownStripsCaretAnchor() throws {
    XCTAssertEqual(
      try markdown {
        let paragraph = ParagraphNode()
        try paragraph.append([
          TextNode(text: "\(emptyTextCaretAnchor)Visible\(emptyTextCaretAnchor)")
        ])
        return paragraph
      },
      "Visible"
    )

    XCTAssertEqual(
      try markdown {
        let paragraph = ParagraphNode()
        try paragraph.append([TextNode(text: "Persian\u{200C}text")])
        return paragraph
      },
      "Persian\u{200C}text"
    )
  }

  func testGenerateMarkdownThrowsForUnsupportedTopLevelNode() throws {
    guard let editor else {
      return XCTFail("Expected editor")
    }

    var unsupportedNodeKey: NodeKey?
    try editor.update {
      guard let root = getRoot() else {
        throw LexicalError.invariantViolation("Expected root node")
      }
      try root.getChildren().forEach { try $0.remove() }
      let unsupportedNode = TextNode(text: "Unsupported")
      try root.append([unsupportedNode])
      unsupportedNodeKey = unsupportedNode.key
    }

    XCTAssertThrowsError(
      try editor.read {
        guard
          let unsupportedNodeKey,
          let unsupportedNode = getNodeByKey(key: unsupportedNodeKey)
        else {
          throw LexicalError.invariantViolation("Expected unsupported node")
        }
        _ = try LexicalMarkdown.generateMarkdown(from: unsupportedNode)
      }
    )
  }

  func testListWithInlineStyles() throws {
    guard let editor = self.editor else {
      XCTFail("no editor")
      return
    }
    try editor.update {
      guard let rootNode = getRoot()
      else {
        XCTFail("should have root node")
        return
      }

      try rootNode.getChildren().forEach { node in
        try node.remove()
      }

      // Root level
      let list = ListNode(listType: .bullet, start: 1)

      let item1 = ListItemNode()
      try item1.append([TextNode(text: "Item 1")])

      let item2 = ListItemNode()
      let boldText = TextNode(text: "2")
      try boldText.setBold(true)
      try item2.append([TextNode(text: "Item "), boldText])

      try list.append([item1, item2])
      try rootNode.append([list])
    }

    let markdownString = try LexicalMarkdown.generateMarkdown(from: editor, selection: nil)
    let comparison = """
      - Item 1
      - Item **2**
      """
    XCTAssertEqual(markdownString, comparison)
  }
}
