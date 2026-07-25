/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import Lexical

private final class ZeroLengthTestNode: Node {
  override init() {
    super.init()
  }

  override required init(_ key: NodeKey?) {
    super.init(key)
  }

  required init(from decoder: Decoder) throws {
    try super.init(from: decoder)
  }

  override class func getType() -> NodeType {
    NodeType(rawValue: "zero-length-test")
  }

  override func clone() -> Self {
    Self(key)
  }
}

@MainActor
final class LayoutGeometryTests: XCTestCase {
  private func makeView(
    theme: Theme = Theme(),
    width: CGFloat = 240,
    height: CGFloat = 160,
    inset: UIEdgeInsets = .zero
  ) -> LexicalView {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: theme, plugins: []),
      featureFlags: FeatureFlags()
    )
    view.frame = CGRect(x: 0, y: 0, width: width, height: height)
    view.setTextContainerInset(inset)
    view.layoutIfNeeded()
    return view
  }

  private func finishLayout(_ view: LexicalView) {
    view.setNeedsLayout()
    view.layoutIfNeeded()
    if let textContainer = view.layoutManager.textContainers.first {
      view.layoutManager.ensureLayout(for: textContainer)
    }
  }

  private func drainMainQueue() {
    let drained = expectation(description: "main queue drained")
    DispatchQueue.main.async {
      drained.fulfill()
    }
    wait(for: [drained], timeout: 1)
  }

  func testFirstBlockTopSpacingChangesDocumentLayoutHeight() throws {
    func measurement(topSpacing: CGFloat) throws -> (
      geometry: NodeGeometry,
      usedHeight: CGFloat
    ) {
      let theme = Theme()
      theme.setBlockLevelAttributes(
        .paragraph,
        value: BlockLevelAttributes(paddingTop: topSpacing)
      )
      let view = makeView(theme: theme)
      var key = ""
      try view.editor.update {
        let root = try XCTUnwrap(getRoot())
        try root.getChildren().forEach { try $0.remove() }
        let paragraph = ParagraphNode()
        key = paragraph.key
        try paragraph.append([TextNode(text: "First block")])
        try root.append([paragraph])
      }
      finishLayout(view)
      let geometry = try XCTUnwrap(view.geometry(forNodeKey: key))
      let container = try XCTUnwrap(view.layoutManager.textContainers.first)
      return (geometry, view.layoutManager.usedRect(for: container).height)
    }

    let base = try measurement(topSpacing: 0)
    let spaced = try measurement(topSpacing: 30)
    XCTAssertEqual(spaced.geometry.rect.height - base.geometry.rect.height, 30, accuracy: 0.5)
    XCTAssertEqual(spaced.usedHeight - base.usedHeight, 30, accuracy: 0.5)
  }

  func testEmptyFirstBlockTopSpacingChangesExtraLineFragmentHeight() throws {
    func measurement(topSpacing: CGFloat) throws -> CGFloat {
      let theme = Theme()
      theme.setBlockLevelAttributes(
        .paragraph,
        value: BlockLevelAttributes(paddingTop: topSpacing)
      )
      let view = makeView(theme: theme)
      var key = ""
      try view.editor.update {
        let root = try XCTUnwrap(getRoot())
        try root.getChildren().forEach { try $0.remove() }
        let paragraph = ParagraphNode()
        key = paragraph.key
        try root.append([paragraph])
      }
      finishLayout(view)
      return try XCTUnwrap(view.geometry(forNodeKey: key)).rect.height
    }

    let baseHeight = try measurement(topSpacing: 0)
    let spacedHeight = try measurement(topSpacing: 30)
    XCTAssertEqual(spacedHeight - baseHeight, 30, accuracy: 0.5)
  }

  func testBatchedGeometryLaysOutOffscreenBlocksAndEmptyEdges() throws {
    let view = makeView(height: 80)
    var keys: [NodeKey] = []
    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }

      let emptyFirst = ParagraphNode()
      keys.append(emptyFirst.key)
      try root.append([emptyFirst])

      for index in 0..<80 {
        let paragraph = ParagraphNode()
        keys.append(paragraph.key)
        try paragraph.append([
          TextNode(text: "Offscreen paragraph \(index) with enough text to occupy a line")
        ])
        try root.append([paragraph])
      }

      let emptyLast = ParagraphNode()
      keys.append(emptyLast.key)
      try root.append([emptyLast])
    }
    let geometries = view.geometries(
      forNodeKeys: [keys[0], keys[40], keys[keys.count - 1]]
    )
    XCTAssertEqual(geometries.count, 3)
    XCTAssertGreaterThan(try XCTUnwrap(geometries[keys[0]]).rect.height, 0)
    XCTAssertGreaterThan(
      try XCTUnwrap(geometries[keys[40]]).rect.minY,
      view.bounds.maxY
    )
    XCTAssertGreaterThan(
      try XCTUnwrap(geometries[keys[keys.count - 1]]).rect.height,
      0
    )
  }

  func testEmptyTopLevelParagraphsUseExactlyTheirOwnLineFragment() throws {
    func geometries(texts: [String]) throws -> [NodeGeometry] {
      let view = makeView()
      var keys: [NodeKey] = []
      try view.editor.update {
        let root = try XCTUnwrap(getRoot())
        try root.getChildren().forEach { try $0.remove() }
        for text in texts {
          let paragraph = ParagraphNode()
          keys.append(paragraph.key)
          if !text.isEmpty {
            try paragraph.append([TextNode(text: text)])
          }
          try root.append([paragraph])
        }
      }
      finishLayout(view)
      let result = view.geometries(forNodeKeys: keys)
      return try keys.map { try XCTUnwrap(result[$0]) }
    }

    let trailing = try geometries(texts: ["Previous", ""])
    XCTAssertFalse(trailing[0].rect.intersects(trailing[1].rect))
    XCTAssertEqual(trailing[1].rect.minY, trailing[0].rect.maxY, accuracy: 0.5)
    XCTAssertEqual(trailing[1].rect.height, trailing[0].rect.height, accuracy: 0.5)

    let middle = try geometries(texts: ["Before", "", "After"])
    XCTAssertFalse(middle[0].rect.intersects(middle[1].rect))
    XCTAssertFalse(middle[1].rect.intersects(middle[2].rect))
    XCTAssertEqual(middle[1].rect.minY, middle[0].rect.maxY, accuracy: 0.5)
    XCTAssertEqual(middle[2].rect.minY, middle[1].rect.maxY, accuracy: 0.5)
  }

  func testZeroLengthNodeMidDocumentUsesItsFollowingLineFragment() throws {
    let view = makeView()
    var beforeKey = ""
    var emptyKey = ""
    var afterKey = ""
    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }
      let paragraph = ParagraphNode()
      let before = TextNode(text: "Before")
      beforeKey = before.key
      let empty = ZeroLengthTestNode()
      emptyKey = empty.key
      let after = TextNode(text: "After")
      afterKey = after.key
      try paragraph.append([before, LineBreakNode(), empty, after])
      try root.append([paragraph])
    }
    finishLayout(view)

    let geometries = view.geometries(
      forNodeKeys: [beforeKey, emptyKey, afterKey]
    )
    let before = try XCTUnwrap(geometries[beforeKey])
    let empty = try XCTUnwrap(geometries[emptyKey])
    let after = try XCTUnwrap(geometries[afterKey])
    XCTAssertEqual(empty.characterRange.length, 0)
    XCTAssertFalse(before.rect.intersects(empty.rect))
    XCTAssertEqual(empty.rect, after.rect)
  }

  func testTrailingNewlineUsesExtraLineFragmentAndCompoundBlocksUseAllLines() throws {
    let view = makeView(width: 180)
    var quoteKey = ""
    var codeKey = ""
    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }

      let quote = QuoteNode()
      quoteKey = quote.key
      try quote.append([
        TextNode(text: "Quote first line"),
        LineBreakNode(),
        TextNode(text: "Quote second line"),
      ])
      try root.append([quote])

      let code = CodeNode()
      codeKey = code.key
      try code.append([
        TextNode(text: "code first line"),
        LineBreakNode(),
        TextNode(text: "code second line"),
        LineBreakNode(),
      ])
      try root.append([code])
    }
    finishLayout(view)

    let geometries = view.geometries(forNodeKeys: [quoteKey, codeKey])
    let quote = try XCTUnwrap(geometries[quoteKey])
    let code = try XCTUnwrap(geometries[codeKey])
    XCTAssertGreaterThan(quote.rect.height, 20)
    XCTAssertGreaterThan(code.rect.height, quote.rect.height)

    let extraRect = view.layoutManager.extraLineFragmentRect.offsetBy(
      dx: view.textView.textContainerInset.left,
      dy: view.textView.textContainerInset.top
    )
    let convertedExtraRect = view.textView.convert(extraRect, to: view)
    XCTAssertTrue(code.rect.intersects(convertedExtraRect))
  }

  func testGeometryReflowsAfterWidthChangeAndConvertsInsetAndOffset() throws {
    let inset = UIEdgeInsets(top: 13, left: 17, bottom: 0, right: 9)
    let view = makeView(width: 320, height: 100, inset: inset)
    var key = ""
    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }
      let paragraph = ParagraphNode()
      key = paragraph.key
      try paragraph.append([
        TextNode(
          text: "A deliberately long paragraph that wraps several times when the editor becomes narrow."
        )
      ])
      try root.append([paragraph])
    }
    finishLayout(view)

    let wide = try XCTUnwrap(view.geometry(forNodeKey: key))
    XCTAssertEqual(wide.rect.minX, inset.left, accuracy: 0.5)
    XCTAssertEqual(wide.rect.minY, inset.top, accuracy: 0.5)

    view.frame.size.width = 120
    finishLayout(view)
    let narrow = try XCTUnwrap(view.geometry(forNodeKey: key))
    XCTAssertGreaterThan(narrow.rect.height, wide.rect.height)

    view.textView.contentOffset = CGPoint(x: 0, y: 11)
    finishLayout(view)
    let scrolled = try XCTUnwrap(view.geometry(forNodeKey: key))
    XCTAssertEqual(scrolled.rect.minY, narrow.rect.minY - 11, accuracy: 0.5)
  }

  func testScrollingWithoutListenersDoesNotForceWholeContainerLayout() throws {
    let view = makeView(height: 80)
    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }
      for index in 0..<100 {
        let paragraph = ParagraphNode()
        try paragraph.append([TextNode(text: "Paragraph \(index)")])
        try root.append([paragraph])
      }
    }
    view.layoutIfNeeded()
    let forcedLayoutsBeforeScroll =
      view.layoutManager.forcedWholeContainerLayoutCount

    view.textView.contentOffset = CGPoint(x: 0, y: 60)
    view.textView.setNeedsLayout()
    view.textView.layoutIfNeeded()

    XCTAssertEqual(
      view.layoutManager.forcedWholeContainerLayoutCount,
      forcedLayoutsBeforeScroll
    )
  }

  func testLayoutListenerCoalescesAndAllowsGeometryQueryWithoutReentrancy() throws {
    let view = makeView()
    var paragraphKey = ""
    var textKey = ""
    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }
      let paragraph = ParagraphNode()
      paragraphKey = paragraph.key
      let text = TextNode(text: "Before")
      textKey = text.key
      try paragraph.append([text])
      try root.append([paragraph])
    }
    finishLayout(view)

    let callback = expectation(description: "post-layout callback")
    let noSecondCallback = expectation(description: "no reentrant callback")
    noSecondCallback.isInverted = true
    var changes: [LexicalLayoutChange] = []
    var insideCallback = false
    let remove = view.registerLayoutListener { change in
      XCTAssertFalse(insideCallback)
      insideCallback = true
      changes.append(change)
      XCTAssertNotNil(view.geometry(forNodeKey: paragraphKey))
      insideCallback = false
      if changes.count == 1 {
        callback.fulfill()
      } else {
        noSecondCallback.fulfill()
      }
    }
    defer { remove() }

    try view.editor.update {
      let text: TextNode = try XCTUnwrap(getNodeByKey(key: textKey))
      try text.setText("After one")
    }
    try view.editor.update {
      let text: TextNode = try XCTUnwrap(getNodeByKey(key: textKey))
      try text.setText("After two, still coalesced")
    }
    finishLayout(view)
    view.layoutManager.didCompleteLayoutPass(layoutFinished: true)

    wait(for: [callback], timeout: 1)
    wait(for: [noSecondCallback], timeout: 0.1)
    XCTAssertEqual(changes.map(\.generation), [1])
  }

  func testWidthChangeNotifiesRegisteredLayoutListener() {
    let view = makeView(width: 240)
    var changes: [LexicalLayoutChange] = []
    let remove = view.registerLayoutListener { changes.append($0) }
    defer { remove() }

    view.frame.size.width = 180
    view.setNeedsLayout()
    view.layoutIfNeeded()
    drainMainQueue()

    XCTAssertEqual(changes.map(\.generation), [1])
    XCTAssertNil(changes[0].affectedCharacterRange)
  }

  func testStyleOnlyEditingAndPartialLayoutDoNotPublishGeneration() throws {
    let view = makeView()
    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }
      let paragraph = ParagraphNode()
      try paragraph.append([TextNode(text: "Styled")])
      try root.append([paragraph])
    }
    finishLayout(view)
    var changes: [LexicalLayoutChange] = []
    let remove = view.registerLayoutListener { changes.append($0) }
    defer { remove() }

    view.textStorage.mode = .controllerMode
    view.textStorage.addAttribute(
      .foregroundColor,
      value: UIColor.red,
      range: NSRange(location: 0, length: view.textStorage.length)
    )
    view.textStorage.mode = .none
    view.layoutManager.didCompleteLayoutPass(layoutFinished: true)
    drainMainQueue()
    XCTAssertTrue(changes.isEmpty)

    view.layoutManager.recordGeometryInvalidation(
      affectedCharacterRange: NSRange(
        location: 0,
        length: view.textStorage.length
      )
    )
    view.layoutManager.didCompleteLayoutPass(layoutFinished: false)
    drainMainQueue()
    XCTAssertTrue(changes.isEmpty)

    view.layoutManager.didCompleteLayoutPass(layoutFinished: true)
    drainMainQueue()
    XCTAssertEqual(changes.map(\.generation), [1])
  }

  func testListenerRemovalStopsDeliveryAndNewEventsUseNewGenerations() {
    let view = makeView()
    var changes: [LexicalLayoutChange] = []
    let remove = view.registerLayoutListener { changes.append($0) }

    view.layoutManager.noteExternalGeometryChange()
    drainMainQueue()
    view.layoutManager.noteExternalGeometryChange()
    drainMainQueue()
    XCTAssertEqual(changes.map(\.generation), [1, 2])

    remove()
    view.layoutManager.noteExternalGeometryChange()
    drainMainQueue()
    XCTAssertEqual(changes.map(\.generation), [1, 2])
  }

  func testDetachedNodeHasNoRangeOrGeometry() throws {
    let view = makeView()
    var key = ""
    try view.editor.update {
      let root = try XCTUnwrap(getRoot())
      try root.getChildren().forEach { try $0.remove() }
      let paragraph = ParagraphNode()
      key = paragraph.key
      try paragraph.append([TextNode(text: "Removed")])
      try root.append([paragraph])
    }
    finishLayout(view)
    XCTAssertNotNil(view.editor.characterRange(forNodeKey: key))
    XCTAssertNotNil(view.geometry(forNodeKey: key))

    try view.editor.update {
      try getNodeByKey(key: key)?.remove()
    }
    XCTAssertNil(view.editor.characterRange(forNodeKey: key))
    XCTAssertNil(view.geometry(forNodeKey: key))
  }
}
