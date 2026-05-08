/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit
import XCTest

@testable import Lexical
@testable import LexicalListPlugin

class ListItemNodeTests: XCTestCase {
  var view: LexicalView?

  var editor: Editor? {
    get {
      return view?.editor
    }
  }

  override func setUp() {
    view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
  }

  override func tearDown() {
    view = nil
  }

  func testInsertParagraphInMiddleOfListItemSplitsIntoSiblingItems() throws {
    guard let editor else {
      XCTFail("Editor unexpectedly nil")
      return
    }

    try editor.update {
      guard
        let editorState = getActiveEditorState(),
        let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      for child in rootNode.getChildren() {
        try child.remove()
      }

      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode()
      let text = TextNode(text: "first")
      try item.append([text])
      try list.append([item])
      try rootNode.append([list])

      let point = Point(key: text.key, offset: 2, type: .text)
      editorState.selection = RangeSelection(anchor: point, focus: point, format: TextFormat())

      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected range selection")
        return
      }
      try selection.insertParagraph()

      XCTAssertEqual(list.getChildrenSize(), 2)
      let firstItem = list.getChildAtIndex(index: 0) as? ListItemNode
      let secondItem = list.getChildAtIndex(index: 1) as? ListItemNode
      XCTAssertEqual(firstItem?.getTextContent().replacingOccurrences(of: "\n", with: ""), "fi")
      XCTAssertEqual(secondItem?.getTextContent().replacingOccurrences(of: "\u{200B}", with: ""), "rst")
    }
  }

  func testInsertParagraphFromEmptyListItemExitsToTextAnchoredParagraph() throws {
    guard let editor else {
      XCTFail("Editor unexpectedly nil")
      return
    }

    try editor.update {
      guard
        let editorState = getActiveEditorState(),
        let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      for child in rootNode.getChildren() {
        try child.remove()
      }

      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode()
      let anchor = TextNode(text: "\u{200B}")
      try item.append([anchor])
      try list.append([item])
      try rootNode.append([list])

      let point = Point(key: anchor.key, offset: 0, type: .text)
      editorState.selection = RangeSelection(anchor: point, focus: point, format: TextFormat())

      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected range selection")
        return
      }
      try selection.insertParagraph()

      let paragraph = rootNode.getFirstChild() as? ParagraphNode
      XCTAssertNotNil(paragraph)
      XCTAssertEqual(rootNode.getChildrenSize(), 1)
      XCTAssertEqual(paragraph?.getTextContent(), "\u{200B}")

      let updatedSelection = try XCTUnwrap(getSelection() as? RangeSelection)
      XCTAssertEqual(updatedSelection.anchor.type, .text)
      XCTAssertEqual(updatedSelection.anchor.offset, 0)
      XCTAssertTrue(try updatedSelection.anchor.getNode().getParent() === paragraph)
    }
  }

  func testInsertParagraphAtVisibleEndBeforeTrailingAnchorCreatesSingleEmptyItemThatThenExits() throws {
    guard let editor else {
      XCTFail("Editor unexpectedly nil")
      return
    }

    try editor.update {
      guard
        let editorState = getActiveEditorState(),
        let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      for child in rootNode.getChildren() {
        try child.remove()
      }

      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode()
      let text = TextNode(text: "Item\u{200B}")
      try item.append([text])
      try list.append([item])
      try rootNode.append([list])

      let point = Point(key: text.key, offset: 4, type: .text)
      editorState.selection = RangeSelection(anchor: point, focus: point, format: TextFormat())

      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected range selection")
        return
      }

      try selection.insertParagraph()

      XCTAssertEqual(list.getChildrenSize(), 2)
      let listChildren = list.getChildren()
      let firstItem = listChildren[0] as? ListItemNode
      let secondItem = listChildren[1] as? ListItemNode
      XCTAssertEqual((firstItem?.getFirstChild() as? TextNode)?.getTextPart(), "Item")
      XCTAssertEqual(secondItem?.getTextContent(), "\u{200B}")

      try selection.insertParagraph()

      XCTAssertEqual(rootNode.getChildrenSize(), 2)
      let rootChildren = rootNode.getChildren()
      XCTAssertTrue(rootChildren[0] is ListNode)
      XCTAssertTrue(rootChildren[1] is ParagraphNode)

      let paragraph = rootChildren[1] as? ParagraphNode
      XCTAssertEqual(paragraph?.getTextContent(), "\u{200B}")
    }
  }

  func testInsertParagraphFromListItemWithMultipleInvisibleAnchorsExitsList() throws {
    guard let editor else {
      XCTFail("Editor unexpectedly nil")
      return
    }

    try editor.update {
      guard
        let editorState = getActiveEditorState(),
        let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      for child in rootNode.getChildren() {
        try child.remove()
      }

      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode()
      let anchor = TextNode(text: "\u{200B}\u{200B}")
      try item.append([anchor])
      try list.append([item])
      try rootNode.append([list])

      let point = Point(key: anchor.key, offset: 0, type: .text)
      editorState.selection = RangeSelection(anchor: point, focus: point, format: TextFormat())

      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected range selection")
        return
      }
      try selection.insertParagraph()

      let paragraph = rootNode.getFirstChild() as? ParagraphNode
      XCTAssertNotNil(paragraph)
      XCTAssertEqual(rootNode.getChildrenSize(), 1)
      XCTAssertEqual(paragraph?.getTextContent(), "\u{200B}\u{200B}")
    }
  }

  func testInsertParagraphFromWhitespaceOnlyListItemExitsList() throws {
    let whitespaceOnlyTextCases = [
      " ",
      "\t",
      "\n",
      "\u{00A0}",
      "\u{200B} ",
      "\u{200B}\t",
      "\u{FEFF}",
      "\u{2060}",
      "\u{200C}",
      "\u{200D}",
      "\u{200B}\u{FEFF}\u{2060} \t"
    ]

    for text in whitespaceOnlyTextCases {
      guard let editor else {
        XCTFail("Editor unexpectedly nil")
        return
      }

      try editor.update {
        guard
          let editorState = getActiveEditorState(),
          let rootNode = editorState.getRootNode()
        else {
          XCTFail("should have editor state")
          return
        }

        for child in rootNode.getChildren() {
          try child.remove()
        }

        let list = ListNode(listType: .bullet, start: 1)
        let item = ListItemNode()
        let anchor = TextNode(text: text)
        try item.append([anchor])
        try list.append([item])
        try rootNode.append([list])

        let point = Point(key: anchor.key, offset: 0, type: .text)
        editorState.selection = RangeSelection(anchor: point, focus: point, format: TextFormat())

        guard let selection = try getSelection() as? RangeSelection else {
          XCTFail("Expected range selection")
          return
        }
        try selection.insertParagraph()

        XCTAssertEqual(rootNode.getChildrenSize(), 1, "\(text.debugDescription) should exit and remove the list")
        let paragraph = rootNode.getFirstChild() as? ParagraphNode
        XCTAssertNotNil(paragraph, "\(text.debugDescription) should become a paragraph")
      }
    }
  }

  func testDeletingParagraphBelowListAndPressingEnterTwiceExitsList() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [ListPlugin()]),
      featureFlags: FeatureFlags(proxyTextViewInputDelegate: true))
    let editor = view.editor
    let textView = view.textView

    try editor.update {
      guard
        let editorState = getActiveEditorState(),
        let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      for child in rootNode.getChildren() {
        try child.remove()
      }

      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode()
      let itemText = TextNode(text: "Item")
      try item.append([itemText])
      try list.append([item])
      let paragraph = ParagraphNode()
      let paragraphText = TextNode(text: "Below")
      try paragraph.append([paragraphText])
      try rootNode.append([list, paragraph])

      let paragraphEnd = Point(key: paragraphText.key, offset: 5, type: .text)
      editorState.selection = RangeSelection(anchor: paragraphEnd, focus: paragraphEnd, format: TextFormat())
    }

    textView.layoutIfNeeded()
    let paragraphRange = (textView.text as NSString).range(of: "Below")
    XCTAssertNotEqual(paragraphRange.location, NSNotFound)
    textView.selectedRange = NSRange(location: paragraphRange.upperBound, length: 0)

    for _ in 0..<5 {
      textView.deleteBackward()
    }
    textView.deleteBackward()

    try editor.read {
      let rootNode = try XCTUnwrap(getActiveEditorState()?.getRootNode())
      let selectionInList = try XCTUnwrap(getSelection() as? RangeSelection)
      XCTAssertEqual(selectionInList.anchor.offset, 4)
      XCTAssertEqual(try selectionInList.anchor.getNode().getTextContent(), "Item")
      XCTAssertEqual((rootNode.getFirstChild() as? ListNode)?.getChildrenSize(), 1)
      XCTAssertNil(rootNode.getChildAtIndex(index: 1))
    }

    textView.insertText("\n")

    try editor.read {
      let rootNode = try XCTUnwrap(getActiveEditorState()?.getRootNode())
      let list = try XCTUnwrap(rootNode.getFirstChild() as? ListNode)
      XCTAssertEqual(list.getChildrenSize(), 2)
      let emptyItem = try XCTUnwrap(list.getChildAtIndex(index: 1) as? ListItemNode)
      XCTAssertEqual(emptyItem.getTextContent(), "\u{200B}")
    }

    textView.insertText("\n")

    try editor.read {
      let rootNode = try XCTUnwrap(getActiveEditorState()?.getRootNode())
      let list = try XCTUnwrap(rootNode.getFirstChild() as? ListNode)
      XCTAssertEqual(rootNode.getChildrenSize(), 2)
      XCTAssertTrue(rootNode.getChildAtIndex(index: 0) is ListNode)
      let exitedParagraph = try XCTUnwrap(rootNode.getChildAtIndex(index: 1) as? ParagraphNode)
      XCTAssertEqual(exitedParagraph.getTextContent(), "\u{200B}")
      XCTAssertEqual(list.getChildrenSize(), 1)
    }
  }

  func testTextViewNewlineDoesNotPublishStaleNativeSelectionAfterEmptyListExit() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [ListPlugin()]),
      featureFlags: FeatureFlags(proxyTextViewInputDelegate: true))
    let editor = view.editor
    let textView = view.textView

    try editor.update {
      guard
        let editorState = getActiveEditorState(),
        let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      for child in rootNode.getChildren() {
        try child.remove()
      }

      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode()
      let anchor = TextNode(text: "\u{200B}")
      try item.append([anchor])
      try list.append([item])
      try rootNode.append([list])

      let point = Point(key: anchor.key, offset: 0, type: .text)
      editorState.selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
    }

    let inputDelegate = SelectionChangeRecorder()
    textView.inputDelegate = inputDelegate
    textView.selectedRange = NSRange(location: 0, length: 0)
    inputDelegate.selectionDidChangeCount = 0

    textView.insertText("\n")

    XCTAssertEqual(inputDelegate.selectionDidChangeCount, 0)

    try editor.read {
      guard
        let editorState = getActiveEditorState(),
        let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      let paragraph = rootNode.getFirstChild() as? ParagraphNode
      XCTAssertNotNil(paragraph)
      XCTAssertEqual(rootNode.getChildrenSize(), 1)
      XCTAssertEqual(paragraph?.getTextContent(), "\u{200B}")

      let updatedSelection = try XCTUnwrap(getSelection() as? RangeSelection)
      XCTAssertEqual(updatedSelection.anchor.type, .text)
      XCTAssertEqual(updatedSelection.anchor.offset, 0)
      XCTAssertTrue(try updatedSelection.anchor.getNode().getParent() === paragraph)
    }
  }

  func testItemCharacterWithNestedNumberedList() throws {
    guard let editor else {
      XCTFail("Editor unexpectedly nil")
      return
    }

    try editor.update {
      guard
        let editorState = getActiveEditorState(),
        let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      /*
       1. Item 1
       1. Nested item 1
       2. Nested item 2
       2. Item 2
       */

      // Root level
      let list = ListNode(listType: .number, start: 1)

      let item1 = ListItemNode()
      try item1.append([TextNode(text: "Item 1")])

      let item2 = ListItemNode()
      try item2.append([TextNode(text: "Item 2")])

      // Nested level
      let nestedList = ListNode(listType: .number, start: 1)

      let nestedListItem = ListItemNode()
      try nestedListItem.append([nestedList])

      let nestedItem1 = ListItemNode()
      try nestedItem1.append([TextNode(text: "Nested item 1")])

      let nestedItem2 = ListItemNode()
      try nestedItem2.append([TextNode(text: "Nested item 2")])

      try nestedList.append([nestedItem1, nestedItem2])

      // Putting it together
      try list.append([item1, nestedListItem, item2])
      try rootNode.append([list])

      // Assertions
      let theme = editor.getTheme()

      let item1Attrs = item1.getAttributedStringAttributes(theme: theme)[.listItem] as? ListItemAttribute
      XCTAssertEqual(item1Attrs?.listItemCharacter, "1.")

      let item2Attrs = item2.getAttributedStringAttributes(theme: theme)[.listItem] as? ListItemAttribute
      XCTAssertEqual(item2Attrs?.listItemCharacter, "2.")

      let nestedItem1Attrs = nestedItem1.getAttributedStringAttributes(theme: theme)[.listItem] as? ListItemAttribute
      XCTAssertEqual(nestedItem1Attrs?.listItemCharacter, "1.")

      let nestedItem2Attrs = nestedItem2.getAttributedStringAttributes(theme: theme)[.listItem] as? ListItemAttribute
      XCTAssertEqual(nestedItem2Attrs?.listItemCharacter, "2.")
    }
  }
}

private final class SelectionChangeRecorder: NSObject, UITextInputDelegate {
  var selectionDidChangeCount = 0

  func selectionWillChange(_ textInput: UITextInput?) {}

  func selectionDidChange(_ textInput: UITextInput?) {
    selectionDidChangeCount += 1
  }

  func textWillChange(_ textInput: UITextInput?) {}

  func textDidChange(_ textInput: UITextInput?) {}

  @available(iOS 18.4, *)
  func conversationContext(_ context: UIConversationContext?, didChange textInput: (any UITextInput)?) {}
}
