/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import Lexical

class TextViewTests: XCTestCase {

  func testInitialise() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView
    XCTAssertTrue(textView.textStorage is TextStorage)
    XCTAssertTrue(textView.layoutManager is LayoutManager)
    XCTAssertNotNil(textView.editor)
  }

  func testGetNativeSelection() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor
    let textView = view.textView

    // Note that modifying the text view like this will break the reconciler. That's OK in this test
    // as it doesn't run the reconciler!

    textView.text = "Hello world"
    textView.isUpdatingNativeSelection = true // disable the selection feeding back to Lexical -- in this case we _just_ want a native selection
    textView.selectedRange = NSRange(location: 1, length: 4)
    textView.isUpdatingNativeSelection = false
    XCTAssertEqual(textView.selectedRange.location, 1, "Selection range should be 1")
    XCTAssertEqual(textView.selectedRange.length, 4, "Selection length should be 4")

    let selection = editor.getNativeSelection()
    guard let range = selection.range else {
      XCTFail("selection should have range")
      return
    }
    XCTAssertEqual(range.location, 1, "Fetched native selection range should be 1")
    XCTAssertEqual(range.length, 4, "Fetched native selection length should be 4")
    XCTAssertNotNil(selection.opaqueRange)
  }

  func testMoveNativeSelection() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor
    let textView = view.textView

    textView.text = "Hello world"
    textView.isUpdatingNativeSelection = true
    textView.selectedRange = NSRange(location: 1, length: 4)
    textView.isUpdatingNativeSelection = false

    let selection = editor.getNativeSelection()
    guard let range = selection.range else {
      XCTFail("selection should have range")
      return
    }
    XCTAssertEqual(range.location, 1)
    XCTAssertEqual(range.length, 4)

    editor.moveNativeSelection(type: .extend, direction: .backward, granularity: .character)

    let modifiedSelection = editor.getNativeSelection()
    guard let modifiedRange = modifiedSelection.range else {
      XCTFail("selection should have range")
      return
    }
    XCTAssertEqual(modifiedRange.location, 0)
    XCTAssertEqual(modifiedRange.length, 5)
  }

  func testUpdateNativeSelection() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    try textView.editor.update {
      createExampleNodeTree()
    }

    try textView.editor.getEditorState().read {
      let selection = RangeSelection(
        anchor: Point(key: "1", offset: 1, type: .text),
        focus: Point(key: "2", offset: 3, type: .text),
        format: TextFormat())

      try textView.updateNativeSelection(from: selection)
      XCTAssertEqual(textView.selectedRange.location, 1)
      XCTAssertEqual(textView.selectedRange.length, 8)

      let selection2 = RangeSelection(
        anchor: Point(key: "7", offset: 0, type: .element),
        focus: Point(key: "7", offset: 1, type: .element),
        format: TextFormat())

      try textView.updateNativeSelection(from: selection2)
      XCTAssertEqual(textView.selectedRange.location, 52)
      XCTAssertEqual(textView.selectedRange.length, 11)
    }
  }

  func testInsertTextUITextInputMethodWithNewLine() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    try textView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode(), let paragraphNode = rootNode.getFirstChild() as? ParagraphNode else {
        XCTFail("No root node")
        return
      }
      let textNode = TextNode()
      try textNode.setText("Hello world")
      try paragraphNode.append([textNode])
      let anchor = createPoint(key: "1", offset: 11, type: .text)
      let focus = createPoint(key: "1", offset: 11, type: .text)
      textView.editor.getEditorState().selection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
    }

    textView.selectedRange = NSRange(location: 11, length: 0)

    textView.insertText("\n")
    XCTAssertEqual(textView.text, "Hello world\n", "Should have inserted character in non-controlled mode")
    if let newParagraphNode = getNodeByKey(key: "2") as? ParagraphNode {
      XCTAssertEqual(newParagraphNode.key, "2")
      XCTAssertEqual(newParagraphNode.parent, kRootNodeKey)
      XCTAssertEqual(newParagraphNode.getChildren(), [])
    }

    textView.insertText("Hey")
    XCTAssertEqual(textView.text, "Hello world\nHey", "Should have inserted character in controller mode")
    if let newTextNode = getNodeByKey(key: "3") as? TextNode {
      XCTAssertEqual(newTextNode.key, "3")
      XCTAssertEqual(newTextNode.parent, "2")
      XCTAssertEqual(newTextNode.getTextPart(), "Hey")
    }

    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Expected range selection")
      return
    }
    XCTAssertEqual(selection.anchor.key, "3")
    XCTAssertEqual(selection.focus.key, "3")
    XCTAssertEqual(selection.anchor.offset, 3)
    XCTAssertEqual(selection.focus.offset, 3)
    XCTAssertEqual(selection.anchor.type, SelectionType.text)
  }

  func testInsertParagraphPublishesNativeSelectionAfterTextStorageLayout() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    view.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    view.layoutIfNeeded()
    let textView = view.textView

    try textView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode(),
        let paragraphNode = rootNode.getFirstChild() as? ParagraphNode
      else {
        XCTFail("No root node")
        return
      }

      let textNode = TextNode()
      try textNode.setText("Hello world")
      try paragraphNode.append([textNode])
      let point = createPoint(key: textNode.key, offset: 11, type: .text)
      textView.editor.getEditorState().selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
    }

    textView.selectedRange = NSRange(location: 11, length: 0)
    let initialSelectedRange = textView.selectedRange
    var publishedRanges: [NSRange] = []
    textView.nativeSelectionUpdateRecorder = { range in
      publishedRanges.append(range)
    }

    let sampler = TextStorageLayoutSelectionSampler(textView: textView)
    let previousLayoutDelegate = textView.layoutManager.delegate
    textView.layoutManager.delegate = sampler

    textView.insertText("\n")
    let finalSelectedRange = textView.selectedRange
    textView.nativeSelectionUpdateRecorder = nil
    textView.layoutManager.delegate = previousLayoutDelegate

    XCTAssertEqual(textView.text, "Hello world\n")
    XCTAssertEqual(finalSelectedRange, NSRange(location: 12, length: 0))
    XCTAssertEqual(publishedRanges.last, finalSelectedRange)
    XCTAssertFalse(sampler.samples.isEmpty, "Expected layout-time selection samples")
    XCTAssertTrue(
      sampler.samples.allSatisfy { !$0.textContainsNewLine || $0.selectedRange == initialSelectedRange },
      "Text storage should not publish native selection while editing: \(sampler.samples)"
    )
  }

  func testInsertParagraphNeverPublishesBeginningOfPreviousVisualLineSelection() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    view.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    view.layoutIfNeeded()
    let textView = view.textView

    try textView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode(),
        let firstParagraph = rootNode.getFirstChild() as? ParagraphNode
      else {
        XCTFail("No root node")
        return
      }

      let firstText = TextNode()
      try firstText.setText("Alpha")
      try firstParagraph.append([firstText])

      let secondParagraph = ParagraphNode()
      let secondText = TextNode()
      try secondText.setText("Title")
      try secondParagraph.append([secondText])
      try rootNode.append([secondParagraph])

      let point = createPoint(key: secondText.key, offset: 5, type: .text)
      textView.editor.getEditorState().selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
    }

    XCTAssertEqual(textView.text, "Alpha\nTitle")

    textView.selectedRange = NSRange(location: 11, length: 0)
    var published: [(text: String, range: NSRange)] = []
    textView.nativeSelectionUpdateRecorder = { range in
      published.append((textView.text, range))
    }

    textView.insertText("\n")
    textView.nativeSelectionUpdateRecorder = nil

    let finalSelectedRange = textView.selectedRange
    XCTAssertEqual(textView.text, "Alpha\nTitle\n")
    XCTAssertEqual(finalSelectedRange.location, 12)
    XCTAssertFalse(
      published.contains { $0.text.contains("Title\n") && $0.range == NSRange(location: 6, length: 0) },
      "Enter published the start of the previous visual line before settling: \(published)"
    )
    XCTAssertTrue(
      published.allSatisfy { !$0.text.contains("Title\n") || $0.range == finalSelectedRange },
      "Every post-insert native selection update should already point at the new line: \(published)"
    )
  }

  func testCaretRectUsesPendingNativeSelectionDuringTextStorageReconcile() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    view.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    view.layoutIfNeeded()
    let textView = view.textView

    textView.insertText("Title")
    textView.layoutIfNeeded()

    guard let textStorage = textView.textStorage as? TextStorage else {
      XCTFail("Expected Lexical TextStorage")
      return
    }

    textStorage.mode = .controllerMode
    textStorage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "\n")
    textStorage.mode = .none
    textView.layoutIfNeeded()

    textView.selectedRange = NSRange(location: 0, length: 0)
    guard let stalePosition = textView.position(from: textView.beginningOfDocument, offset: 0) else {
      XCTFail("Expected stale position")
      return
    }
    let staleCaret = textView.caretRect(for: stalePosition)

    textView.prepareForNativeSelectionDuringTextStorageEditing(NativeSelection(range: NSRange(location: 6, length: 0), affinity: .forward))
    let pendingCaret = textView.caretRect(for: stalePosition)
    textView.prepareForNativeSelectionDuringTextStorageEditing(nil)

    XCTAssertGreaterThan(pendingCaret.midY, staleCaret.midY + 2)
    XCTAssertLessThanOrEqual(pendingCaret.minX, 16)
  }

  func testCollapsedCaretRectUsesCurrentSelectionWhenAskedForStaleLineStartPositionAfterEnter() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    view.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    view.layoutIfNeeded()
    let textView = view.textView

    try textView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode(),
        let firstParagraph = rootNode.getFirstChild() as? ParagraphNode
      else {
        XCTFail("No root node")
        return
      }

      let firstText = TextNode()
      try firstText.setText("Alpha")
      try firstParagraph.append([firstText])

      let secondParagraph = ParagraphNode()
      let secondText = TextNode()
      try secondText.setText("Title")
      try secondParagraph.append([secondText])
      try rootNode.append([secondParagraph])

      let point = createPoint(key: secondText.key, offset: 5, type: .text)
      textView.editor.getEditorState().selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
    }

    textView.selectedRange = NSRange(location: 11, length: 0)
    textView.insertText("\n")
    textView.layoutIfNeeded()

    XCTAssertEqual(textView.text, "Alpha\nTitle\n")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 12, length: 0))

    guard let currentPosition = textView.selectedTextRange?.start,
      let staleLineStartPosition = textView.position(from: textView.beginningOfDocument, offset: 6)
    else {
      XCTFail("Expected native positions")
      return
    }

    let currentCaret = textView.caretRect(for: currentPosition)
    let stalePositionCaret = textView.caretRect(for: staleLineStartPosition)

    XCTAssertEqual(stalePositionCaret.minX, currentCaret.minX, accuracy: 0.5)
    XCTAssertEqual(stalePositionCaret.midY, currentCaret.midY, accuracy: 0.5)
  }

  func testDeleteBackwardDeletesNativeSelectedRangeInSingleTextNode() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    try textView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode(),
        let paragraphNode = rootNode.getFirstChild() as? ParagraphNode
      else {
        XCTFail("No root node")
        return
      }

      let textNode = TextNode()
      try textNode.setText("Hello world")
      try paragraphNode.append([textNode])
      let point = createPoint(key: textNode.key, offset: 11, type: .text)
      textView.editor.getEditorState().selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
    }

    textView.selectedRange = NSRange(location: 6, length: 5)
    textView.deleteBackward()

    XCTAssertEqual(textView.text, "Hello ")
    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Expected range selection")
      return
    }
    XCTAssertTrue(selection.isCollapsed())
    XCTAssertEqual(selection.anchor.offset, 6)
  }

  func testDeleteBackwardDeletesNativeSelectedRangeAcrossLineBreak() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    try textView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode(),
        let firstParagraph = rootNode.getFirstChild() as? ParagraphNode
      else {
        XCTFail("No root node")
        return
      }

      let firstText = TextNode()
      try firstText.setText("First")
      try firstParagraph.append([firstText])

      let secondParagraph = ParagraphNode()
      let secondText = TextNode()
      try secondText.setText("Second")
      try secondParagraph.append([secondText])
      try rootNode.append([secondParagraph])

      let point = createPoint(key: secondText.key, offset: 0, type: .text)
      textView.editor.getEditorState().selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
    }

    XCTAssertEqual(textView.text, "First\nSecond")

    textView.selectedRange = NSRange(location: 0, length: 6)
    textView.deleteBackward()

    XCTAssertFalse(textView.text.contains("First"))
    XCTAssertTrue(textView.text.contains("Second"))
    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Expected range selection")
      return
    }
    XCTAssertTrue(selection.isCollapsed())
  }

  func testDeleteBackwardDeletesEntireOnlyLineNativeSelection() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    try textView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode(),
        let paragraphNode = rootNode.getFirstChild() as? ParagraphNode
      else {
        XCTFail("No root node")
        return
      }

      let textNode = TextNode()
      try textNode.setText("Only line")
      try paragraphNode.append([textNode])
      let point = createPoint(key: textNode.key, offset: 9, type: .text)
      textView.editor.getEditorState().selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
    }

    XCTAssertEqual(textView.text, "Only line")

    textView.selectedRange = NSRange(location: 0, length: 9)
    XCTAssertNoThrow(textView.deleteBackward())
    XCTAssertEqual(textView.text, "")

    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Expected range selection")
      return
    }
    XCTAssertTrue(selection.isCollapsed())
    XCTAssertEqual(textView.selectedRange.length, 0)
  }

  // Test disabled due to iOS 16 UIPasteboard restrictions. I can't figure out a workaround right now. @amyworrall
  //  func testCut() throws {
  //    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
  //    let textView = view.textView
  //
  //    textView.insertText("Hello world")
  //    let anchor = createPoint(key: "1", offset: 6, type: .text)
  //    let focus = createPoint(key: "1", offset: 11, type: .text)
  //    textView.editor.getEditorState().selection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
  //
  //    textView.cut(nil)
  //
  //    try textView.editor.update {
  //      let itemSet = UIPasteboard.general.itemSet(withPasteboardTypes: ["x-lexical-nodes"])
  //      guard let data = UIPasteboard.general.data(forPasteboardType: "x-lexical-nodes", inItemSet: itemSet)?.last else {
  //        print("No data on pasteboard")
  //        return
  //      }
  //
  //      let json = try JSONDecoder().decode(SerializedNodeArray.self, from: data)
  //      if let node = json.nodeArray.first as? TextNode {
  //        let text = node.getText_dangerousPropertyAccess()
  //        XCTAssertEqual(String(describing: text), "world")
  //      } else {
  //        XCTFail("First (only) node in nodeArray was not TextNode")
  //      }
  //    }
  //  }

  // Test disabled due to iOS 16 UIPasteboard restrictions. I can't figure out a workaround right now. @amyworrall
  //  func testCopy() throws {
  //    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
  //    let textView = view.textView
  //
  //    textView.insertText("Hello world")
  //    let anchor = createPoint(key: "1", offset: 6, type: .text)
  //    let focus = createPoint(key: "1", offset: 11, type: .text)
  //    textView.editor.getEditorState().selection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
  //
  //    textView.copy(nil)
  //
  //    try textView.editor.update {
  //      let itemSet = UIPasteboard.general.itemSet(withPasteboardTypes: ["x-lexical-nodes"])
  //      guard let data = UIPasteboard.general.data(forPasteboardType: "x-lexical-nodes", inItemSet: itemSet)?.last else {
  //        print("No data on pasteboard")
  //        return
  //      }
  //
  //      let json = try JSONDecoder().decode(SerializedNodeArray.self, from: data)
  //      if let node = json.nodeArray.first as? TextNode {
  //        let text = node.getText_dangerousPropertyAccess()
  //        XCTAssertEqual(String(describing: text), "world")
  //      } else {
  //        XCTFail("First (only) node in nodeArray was not TextNode")
  //      }
  //    }
  //  }

  func testInsertPlainText() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    textView.insertText("Hello world")
    let anchor = createPoint(key: "1", offset: 11, type: .text)
    let focus = createPoint(key: "1", offset: 11, type: .text)
    textView.editor.getEditorState().selection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())

    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Need selection")
      return
    }

    try textView.editor.update {
      let text = "Text\nText"

      try insertPlainText(selection: selection, text: text)
    }

    try textView.editor.update {
      let nodemap = textView.editor.getEditorState().nodeMap
      print(nodemap)
      XCTAssertTrue((nodemap["0"] as? ParagraphNode)?.children.count == 1)
      XCTAssertTrue((nodemap["1"] as? TextNode)?.getTextPart() == "Hello worldText")
      XCTAssertTrue((nodemap["3"] as? TextNode)?.getTextPart() == "Text")
      XCTAssertTrue((nodemap["4"] as? ParagraphNode)?.children.count == 1)
    }
  }

  func testInsertPlainTextWithinternalNewlines() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    textView.insertText("Hello world")
    let anchor = createPoint(key: "1", offset: 11, type: .text)
    let focus = createPoint(key: "1", offset: 11, type: .text)
    textView.editor.getEditorState().selection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())

    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Need selection")
      return
    }

    try textView.editor.update {
      let text = "Text\n\n\n\nText"

      try insertPlainText(selection: selection, text: text)
    }

    try textView.editor.update {
      let nodemap = textView.editor.getEditorState().nodeMap
      print(nodemap)
      XCTAssertTrue((nodemap["0"] as? ParagraphNode)?.children.count == 1)
      XCTAssertTrue((nodemap["1"] as? TextNode)?.getTextPart() == "Hello worldText")
      XCTAssertTrue((nodemap["4"] as? ParagraphNode)?.children.count == 0)
      XCTAssertTrue((nodemap["6"] as? ParagraphNode)?.children.count == 0)
      XCTAssertTrue((nodemap["8"] as? ParagraphNode)?.children.count == 0)
      XCTAssertTrue((nodemap["10"] as? ParagraphNode)?.children.count == 1)
      XCTAssertTrue((nodemap["9"] as? TextNode)?.getTextPart() == "Text")
    }
  }

  func testInsertRTF() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    textView.insertText("Hello world")
    let anchor = createPoint(key: "1", offset: 11, type: .text)
    let focus = createPoint(key: "1", offset: 11, type: .text)
    textView.editor.getEditorState().selection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())

    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Need selection")
      return
    }

    try textView.editor.update {
      let text = NSMutableAttributedString(string: "Test\nText")
      text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single, range: NSRange(location: 0, length: text.length))

      try insertRTF(selection: selection, attributedString: text)
    }

    try textView.editor.update {
      let nodemap = textView.editor.getEditorState().nodeMap
      print(nodemap)
      XCTAssertTrue((nodemap["0"] as? ParagraphNode)?.children.count == 2)
      XCTAssertTrue((nodemap["1"] as? TextNode)?.getTextPart() == "Hello world")
      XCTAssertTrue((nodemap["2"] as? TextNode)?.getTextPart() == "Test")
      XCTAssertTrue((nodemap["2"] as? TextNode)?.format.underline ?? false)
      XCTAssertTrue((nodemap["3"] as? TextNode)?.getTextPart() == "Text")
      XCTAssertTrue((nodemap["3"] as? TextNode)?.format.underline ?? false)
      XCTAssertTrue((nodemap["4"] as? ParagraphNode)?.children.count == 1)
    }
  }

  func testShowPlaceholderTextWithPlaceholderLabel() {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView
    textView.setPlaceholderText("Enter Text", textColor: .lightGray, font: .systemFont(ofSize: 8))

    if let label = textView.subviews.first(where: { $0 is UILabel }) as? UILabel {
      XCTAssertTrue(!label.isHidden)
    }
  }

  func testShowPlaceholderTextWithPlaceholderLabelHidden() {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    textView.setPlaceholderText("Enter Text", textColor: .lightGray, font: .systemFont(ofSize: 8))
    textView.insertText("hello")
    textView.showPlaceholderText()

    if let label = textView.subviews.first(where: { $0 is UILabel }) as? UILabel {
      XCTAssertTrue(label.isHidden, "\(label)")
    }
  }

  func testShowPlaceholderLabelOnDeletion() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView
    textView.setPlaceholderText("Aa", textColor: .lightGray, font: .systemFont(ofSize: 8))

    textView.insertText("H")
    textView.showPlaceholderText()
    if let label = textView.subviews.first(where: { $0 is UILabel }) as? UILabel {
      XCTAssertTrue(label.isHidden)
    }

    try textView.editor.update {
      try onDeleteBackwardsFromUITextView(editor: textView.editor)
    }
    if let label = textView.subviews.first(where: { $0 is UILabel }) as? UILabel {
      XCTAssertTrue(!label.isHidden)
    }
  }

  func testShowPlaceholderTreatsZeroWidthTextAnchorAsEmpty() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView
    let placeholderFont = UIFont.boldSystemFont(ofSize: 24)
    textView.setPlaceholderText("Aa", textColor: .lightGray, font: placeholderFont)

    try textView.editor.update {
      guard let root = getRoot() else {
        XCTFail("Missing root")
        return
      }
      for child in root.getChildren() {
        try child.remove()
      }
      let paragraph = createParagraphNode()
      let anchor = createTextNode(text: "\u{200B}")
      try paragraph.append([anchor])
      try root.append([paragraph])
      let point = Point(key: anchor.key, offset: 0, type: .text)
      try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
    }

    textView.showPlaceholderText()

    if let label = textView.subviews.first(where: { $0 is UILabel }) as? UILabel {
      XCTAssertFalse(label.isHidden)
      XCTAssertEqual(label.font.pointSize, placeholderFont.pointSize, accuracy: 0.5)
    } else {
      XCTFail("Missing placeholder label")
    }
  }

  func testMeasuredCaretHeightUsesFontLineHeightInsteadOfParagraphSpacing() throws {
    let font = UIFont.systemFont(ofSize: 18)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 18
    paragraphStyle.paragraphSpacing = 32
    paragraphStyle.paragraphSpacingBefore = 24
    let layout = measuredCaretTestLayout(for: NSAttributedString(
      string: "List item",
      attributes: [
        .font: font,
        .paragraphStyle: paragraphStyle,
      ]))

    let rowSizedDefaultRect = CGRect(x: 42, y: 8, width: 2, height: 96)
    let measuredRect = measuredCaretRect(layout: layout, offset: 4, defaultRect: rowSizedDefaultRect)

    XCTAssertEqual(measuredRect.height, font.lineHeight, accuracy: 0.5)
    XCTAssertLessThan(measuredRect.height, rowSizedDefaultRect.height)
  }

  func testMeasuredCaretTracksFontSizeAcrossHeaderAndBodyRows() throws {
    let headerFont = UIFont.boldSystemFont(ofSize: 30)
    let bodyFont = UIFont.systemFont(ofSize: 16)
    let headerStyle = NSMutableParagraphStyle()
    headerStyle.paragraphSpacing = 36
    let bodyStyle = NSMutableParagraphStyle()
    bodyStyle.paragraphSpacingBefore = 18

    let text = NSMutableAttributedString(
      string: "Header\nBody",
      attributes: [
        .font: headerFont,
        .paragraphStyle: headerStyle,
      ])
    text.addAttributes(
      [
        .font: bodyFont,
        .paragraphStyle: bodyStyle,
      ],
      range: NSRange(location: 7, length: 4))

    let layout = measuredCaretTestLayout(for: text)

    let rowSizedDefaultRect = CGRect(x: 42, y: 8, width: 2, height: 96)

    XCTAssertEqual(measuredCaretRect(layout: layout, offset: 2, defaultRect: rowSizedDefaultRect).height, headerFont.lineHeight, accuracy: 0.5)
    XCTAssertEqual(measuredCaretRect(layout: layout, offset: 9, defaultRect: rowSizedDefaultRect).height, bodyFont.lineHeight, accuracy: 0.5)
  }

  func testMeasuredCaretAtHeadingLineEndUsesPreviousVisibleCharacterFont() throws {
    let headingFont = UIFont.boldSystemFont(ofSize: 34)
    let bodyFont = UIFont.systemFont(ofSize: 18)
    let headingStyle = NSMutableParagraphStyle()
    headingStyle.paragraphSpacing = 34
    let bodyStyle = NSMutableParagraphStyle()
    bodyStyle.paragraphSpacingBefore = 18

    let text = NSMutableAttributedString(
      string: "Subtitle\nBody",
      attributes: [
        .font: headingFont,
        .paragraphStyle: headingStyle,
      ])
    text.addAttributes(
      [
        .font: bodyFont,
        .paragraphStyle: bodyStyle,
      ],
      range: NSRange(location: 8, length: 5))

    let layout = measuredCaretTestLayout(for: text)
    let rowSizedDefaultRect = CGRect(x: 184, y: 8, width: 2, height: 104)
    let measuredRect = measuredCaretRect(layout: layout, offset: 8, defaultRect: rowSizedDefaultRect)

    XCTAssertEqual(measuredRect.height, headingFont.lineHeight, accuracy: 0.5)
    XCTAssertGreaterThan(measuredRect.height, bodyFont.lineHeight)
    XCTAssertLessThan(measuredRect.height, rowSizedDefaultRect.height)
    XCTAssertGreaterThanOrEqual(measuredRect.minY, 0)
  }

  func testMeasuredCaretAtEndUsesPreviousCharacterFont() throws {
    let font = UIFont.systemFont(ofSize: 22)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacing = 40
    let layout = measuredCaretTestLayout(for: NSAttributedString(
      string: "Done",
      attributes: [
        .font: font,
        .paragraphStyle: paragraphStyle,
      ]))

    let rowSizedDefaultRect = CGRect(x: 42, y: 8, width: 2, height: 96)

    XCTAssertEqual(measuredCaretRect(layout: layout, offset: 4, defaultRect: rowSizedDefaultRect).height, font.lineHeight, accuracy: 0.5)
  }

  func testMeasuredCaretAtDocumentEndUsesGlyphLinePositionWhenTextDoesNotEndInLineBoundary() throws {
    let font = UIFont.boldSystemFont(ofSize: 34)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacing = 44
    let layout = measuredCaretTestLayout(for: NSAttributedString(
      string: "Heading",
      attributes: [
        .font: font,
        .paragraphStyle: paragraphStyle,
      ]))

    let rowSizedDefaultRect = CGRect(x: 42, y: 0, width: 2, height: 120)
    let measuredRect = measuredCaretRect(layout: layout, offset: 7, defaultRect: rowSizedDefaultRect)
    let expectedY = usedLineMidY(layout: layout, characterOffset: 6) - font.lineHeight / 2

    XCTAssertEqual(measuredRect.height, font.lineHeight, accuracy: 0.5)
    XCTAssertEqual(measuredRect.minY, expectedY, accuracy: 0.5)
    XCTAssertNotEqual(measuredRect.midY, rowSizedDefaultRect.midY, accuracy: 0.5)
  }

  func testMeasuredCaretAfterTrailingLineBoundaryUsesLogicalNextLinePosition() throws {
    let font = UIFont.systemFont(ofSize: 18)
    let layout = measuredCaretTestLayout(for: NSAttributedString(
      string: "Body\n",
      attributes: [.font: font]))

    let extraLineDefaultRect = CGRect(x: 42, y: 120, width: 2, height: 44)
    let measuredRect = measuredCaretRect(layout: layout, offset: 5, defaultRect: extraLineDefaultRect)

    XCTAssertEqual(measuredRect.height, font.lineHeight, accuracy: 0.5)
    XCTAssertEqual(measuredRect.midY, font.lineHeight + font.lineHeight / 2, accuracy: 0.5)
    XCTAssertNotEqual(measuredRect.midY, extraLineDefaultRect.midY, accuracy: 0.5)
  }

  func testMeasuredCaretDoesNotInheritSubtleDefaultVerticalOffset() throws {
    let font = UIFont.systemFont(ofSize: 18)
    let layout = measuredCaretTestLayout(for: NSAttributedString(
      string: "Body\n",
      attributes: [.font: font]))
    let expectedMidY = font.lineHeight + font.lineHeight / 2
    let subtlyLowDefaultRect = CGRect(x: 42, y: expectedMidY - font.lineHeight / 2 + 0.75, width: 2, height: font.lineHeight)

    let measuredRect = TextView.fontMetricsCaretRect(
      atCharacterOffset: 5,
      defaultRect: subtlyLowDefaultRect,
      usesDefaultVerticalMetrics: true,
      textStorage: layout.textStorage,
      layoutManager: layout.layoutManager,
      textContainer: layout.textContainer,
      textContainerInset: .zero)

    XCTAssertEqual(measuredRect.height, font.lineHeight, accuracy: 0.5)
    XCTAssertEqual(measuredRect.midY, expectedMidY, accuracy: 0.1)
  }

  func testMeasuredCaretOnEmptySecondLineUsesTextInsetAndParagraphIndent() throws {
    let headingFont = UIFont.boldSystemFont(ofSize: 30)
    let bodyFont = UIFont.systemFont(ofSize: 18)
    let headingStyle = NSMutableParagraphStyle()
    let indentedEmptyLineStyle = NSMutableParagraphStyle()
    indentedEmptyLineStyle.firstLineHeadIndent = 40
    indentedEmptyLineStyle.headIndent = 40

    let text = NSMutableAttributedString(
      string: "Title\n\u{200B}",
      attributes: [
        .font: headingFont,
        .paragraphStyle: headingStyle,
      ])
    text.addAttributes(
      [
        .font: bodyFont,
        .paragraphStyle: indentedEmptyLineStyle,
      ],
      range: NSRange(location: 6, length: 1))

    let layout = measuredCaretTestLayout(for: text)
    let leftEdgeDefaultRect = CGRect(x: 0, y: 52, width: 2, height: 64)
    let measuredRect = measuredCaretRect(layout: layout, offset: 6, defaultRect: leftEdgeDefaultRect)

    XCTAssertEqual(measuredRect.height, bodyFont.lineHeight, accuracy: 0.5)
    XCTAssertEqual(measuredRect.minX, layout.textContainer.lineFragmentPadding + 40, accuracy: 0.5)
    XCTAssertGreaterThan(measuredRect.minX, leftEdgeDefaultRect.minX)
  }

  func testMeasuredCaretOnContentSecondLineUsesLinePrefixWidth() throws {
    let headingFont = UIFont.boldSystemFont(ofSize: 30)
    let text = NSMutableAttributedString(
      string: "Title\nHeading content",
      attributes: [.font: headingFont])

    let layout = measuredCaretTestLayout(for: text)
    let lineStartDefaultRect = CGRect(x: 0, y: 52, width: 2, height: 64)
    let topLineMiddle = measuredCaretRect(
      layout: measuredCaretTestLayout(for: NSAttributedString(string: "Heading content", attributes: [.font: headingFont])),
      offset: 7,
      defaultRect: lineStartDefaultRect)
    let embeddedLineMiddle = measuredCaretRect(layout: layout, offset: 13, defaultRect: lineStartDefaultRect)
    let embeddedLineEnd = measuredCaretRect(layout: layout, offset: 21, defaultRect: lineStartDefaultRect)

    XCTAssertEqual(embeddedLineMiddle.height, headingFont.lineHeight, accuracy: 0.5)
    XCTAssertEqual(embeddedLineMiddle.minX, topLineMiddle.minX, accuracy: 0.5)
    XCTAssertGreaterThan(embeddedLineMiddle.minX, lineStartDefaultRect.minX)
    XCTAssertGreaterThan(embeddedLineEnd.minX, embeddedLineMiddle.minX)
  }

  func testMeasuredCaretRecoversSecondLineYWhenTextKitReturnsEmptyFragments() throws {
    let headingFont = UIFont.boldSystemFont(ofSize: 30)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacing = 6
    let text = NSMutableAttributedString(
      string: "Title\nHeading content",
      attributes: [
        .font: headingFont,
        .paragraphStyle: paragraphStyle,
      ])

    let layout = measuredCaretTestLayout(for: text, width: 0)
    let staleTopDefaultRect = CGRect(x: 0, y: 0, width: 2, height: 64)
    let measuredRect = measuredCaretRect(layout: layout, offset: 6, defaultRect: staleTopDefaultRect)

    XCTAssertEqual(measuredRect.height, headingFont.lineHeight, accuracy: 0.5)
    XCTAssertEqual(measuredRect.minY, headingFont.lineHeight + paragraphStyle.paragraphSpacing, accuracy: 0.5)
    XCTAssertGreaterThan(measuredRect.minY, staleTopDefaultRect.minY)
  }

  func testMeasuredCaretFallbackIncludesCurrentParagraphSpacingBefore() throws {
    let headingFont = UIFont.boldSystemFont(ofSize: 30)
    let firstLineStyle = NSMutableParagraphStyle()
    firstLineStyle.paragraphSpacing = 6
    let embeddedHeadingStyle = NSMutableParagraphStyle()
    embeddedHeadingStyle.paragraphSpacingBefore = 12
    embeddedHeadingStyle.paragraphSpacing = 6

    let text = NSMutableAttributedString(
      string: "Title\nEmbedded heading",
      attributes: [
        .font: headingFont,
        .paragraphStyle: firstLineStyle,
      ])
    text.addAttributes(
      [
        .font: headingFont,
        .paragraphStyle: embeddedHeadingStyle,
      ],
      range: NSRange(location: 6, length: 16))

    let layout = measuredCaretTestLayout(for: text, width: 0)
    let staleTopDefaultRect = CGRect(x: 0, y: 0, width: 2, height: 64)
    let measuredRect = measuredCaretRect(layout: layout, offset: 6, defaultRect: staleTopDefaultRect)

    XCTAssertEqual(measuredRect.height, headingFont.lineHeight, accuracy: 0.5)
    XCTAssertEqual(
      measuredRect.minY,
      headingFont.lineHeight + firstLineStyle.paragraphSpacing + embeddedHeadingStyle.paragraphSpacingBefore,
      accuracy: 0.5)
  }

  private func measuredCaretRect(
    layout: (textStorage: NSTextStorage, layoutManager: NSLayoutManager, textContainer: NSTextContainer),
    offset: Int,
    defaultRect: CGRect
  ) -> CGRect {
    TextView.fontMetricsCaretRect(
      atCharacterOffset: offset,
      defaultRect: defaultRect,
      textStorage: layout.textStorage,
      layoutManager: layout.layoutManager,
      textContainer: layout.textContainer,
      textContainerInset: .zero)
  }

  private func measuredCaretTestLayout(
    for attributedString: NSAttributedString,
    width: CGFloat = 320
  ) -> (textStorage: NSTextStorage, layoutManager: NSLayoutManager, textContainer: NSTextContainer) {
    let textStorage = NSTextStorage(attributedString: attributedString)
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(size: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
    layoutManager.ensureLayout(for: textContainer)
    return (textStorage, layoutManager, textContainer)
  }

  private func usedLineMidY(
    layout: (textStorage: NSTextStorage, layoutManager: NSLayoutManager, textContainer: NSTextContainer),
    characterOffset: Int
  ) -> CGFloat {
    let glyphIndex = layout.layoutManager.glyphIndexForCharacter(at: characterOffset)
    return layout.layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil).midY
  }

  func testBasicInsertStrategy() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView
    textView.insertText("hello")
    textView.insertText("\n")
    textView.insertText("world")
    let nodeMap = textView.editor.getEditorState().nodeMap

    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Need selection")
      return
    }

    try textView.editor.update {
      let nodes = nodeMap.compactMap({ $0.value }).filter({ isElementNode(node: $0) })
      _ = try insertGeneratedNodes(editor: textView.editor, nodes: nodes, selection: selection)
      XCTAssertTrue(nodes.count == 3)
      XCTAssertTrue((nodeMap["0"] as? ParagraphNode)?.children.count == 1)
    }
  }

  func testInsertEllipsis() throws {
    // iOS handles an ellipsis autocorrection by calling replaceCharacters(in:with:) on the text storage twice, each
    // time replacing one of the previous dots with empty string, then finally calling insertText on the text view
    // to insert the ellipsis. Let's simulate this.

    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView
    guard let textStorage = textView.textStorage as? TextStorage else {
      XCTFail()
      return
    }

    textView.insertText("He..")
    textStorage.replaceCharacters(in: NSRange(location: 3, length: 1), with: NSAttributedString(string: ""))
    textStorage.replaceCharacters(in: NSRange(location: 2, length: 1), with: NSAttributedString(string: ""))
    textView.insertText("…")
    XCTAssertEqual(textView.text, "He…")
  }

  func testMarkedTextCompositionCanUpdateAndCommitAfterNewline() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    textView.insertText("Before")
    textView.insertText("\n")
    textView.setMarkedText("s", selectedRange: NSRange(location: 0, length: 1))
    textView.setMarkedText("す", selectedRange: NSRange(location: 0, length: 1))
    textView.setMarkedText("すs", selectedRange: NSRange(location: 1, length: 1))
    textView.setMarkedText("すし", selectedRange: NSRange(location: 0, length: 2))
    textView.unmarkText()
    textView.insertText(" ")
    textView.setMarkedText("m", selectedRange: NSRange(location: 0, length: 1))
    textView.setMarkedText("も", selectedRange: NSRange(location: 0, length: 1))
    textView.setMarkedText("もじ", selectedRange: NSRange(location: 0, length: 2))
    textView.unmarkText()

    XCTAssertEqual(textView.text, "Before\nすし もじ")
    XCTAssertEqual(textView.selectedRange, NSRange(location: "Before\nすし もじ".lengthAsNSString(), length: 0))
    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Expected a range selection after committing marked text")
      return
    }
    XCTAssertTrue(selection.isCollapsed())
    XCTAssertNil(textView.editor.compositionKey)
  }

  func testMarkedTextCompositionCanReplaceSelectedNativeTextAndContinueTyping() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let textView = view.textView

    textView.insertText("Hello world")
    textView.selectedRange = NSRange(location: 6, length: 5)
    textView.setMarkedText("s", selectedRange: NSRange(location: 0, length: 1))
    textView.setMarkedText("世", selectedRange: NSRange(location: 0, length: 1))
    textView.setMarkedText("世界", selectedRange: NSRange(location: 0, length: 2))
    textView.unmarkText()
    textView.insertText("!")

    XCTAssertEqual(textView.text, "Hello 世界!")
    XCTAssertEqual(textView.selectedRange, NSRange(location: "Hello 世界!".lengthAsNSString(), length: 0))
    guard let selection = textView.editor.getEditorState().selection as? RangeSelection else {
      XCTFail("Expected a range selection after replacing marked text")
      return
    }
    XCTAssertTrue(selection.isCollapsed())
    XCTAssertNil(textView.editor.compositionKey)
  }

}

private final class TextStorageLayoutSelectionSampler: NSObject, NSLayoutManagerDelegate {
  struct Sample: CustomStringConvertible {
    let selectedRange: NSRange
    let textContainsNewLine: Bool

    var description: String {
      "range=\(NSStringFromRange(selectedRange)) hasNewline=\(textContainsNewLine)"
    }
  }

  private weak var textView: UITextView?
  private(set) var samples: [Sample] = []

  init(textView: UITextView) {
    self.textView = textView
  }

  func layoutManager(
    _ layoutManager: NSLayoutManager,
    didCompleteLayoutFor textContainer: NSTextContainer?,
    atEnd layoutFinishedFlag: Bool
  ) {
    guard let textView else { return }
    samples.append(Sample(
      selectedRange: textView.selectedRange,
      textContainsNewLine: textView.text.contains("\n")
    ))
  }
}
