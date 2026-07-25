/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import Lexical

class AttributesUtilsTests: XCTestCase {
  func testGetLexicalAttributes() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let textNode = TextNode()
      try textNode.setText("hello world")

      let paragraphNode = ParagraphNode()
      try paragraphNode.append([textNode])

      guard let editorState = getActiveEditorState(),
        let rootNode: RootNode = try editorState.getRootNode()?.getWritable()
      else {
        XCTFail("should have editor state")
        return
      }

      try rootNode.append([paragraphNode])

      let attributes = AttributeUtils.getLexicalAttributes(
        from: textNode,
        state: editorState,
        theme: editor.getTheme()
      )

      for attributeDict in attributes {
        if let font = attributeDict[.font] as? UIFont {
          XCTAssertTrue(font.familyName == "Helvetica", "Node font attribute is incorrect")
        }
      }
    }
  }

  private func firstFontInAttributedString(attrStr: NSAttributedString) -> UIFont {
    let font = attrStr.attribute(.font, at: 0, effectiveRange: nil)
    return font as? UIFont ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
  }

  func testattributedStringByAddingStyles() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let textNode = TextNode()
      try textNode.setText("hello world")

      let paragraphNode = ParagraphNode()
      try paragraphNode.append([textNode])

      guard let editorState = getActiveEditorState(),
        let rootNode: RootNode = try editorState.getRootNode()?.getWritable()
      else {
        XCTFail("should have editor state")
        return
      }

      try rootNode.append([paragraphNode])

      let attributedString = NSMutableAttributedString(string: textNode.getTextPart())

      let styledAttrStr = AttributeUtils.attributedStringByAddingStyles(attributedString, from: textNode, state: editorState, theme: editor.getTheme())
      let font = firstFontInAttributedString(attrStr: styledAttrStr)

      XCTAssertTrue(font.familyName == "Helvetica", "TextNode's attributes should take priority over all parent node's attributes")
    }
  }

  func testApplyBoldStyles() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let textNode = TextNode()
      try textNode.setText("hello world")
      textNode.format.bold = true

      let paragraphNode = ParagraphNode()
      try paragraphNode.append([textNode])

      guard let editorState = getActiveEditorState(),
        let rootNode: RootNode = try editorState.getRootNode()?.getWritable()
      else {
        XCTFail("should have editor state")
        return
      }

      try rootNode.append([paragraphNode])
      let attributedString = NSMutableAttributedString(string: textNode.getTextPart())
      let styledAttrStr = AttributeUtils.attributedStringByAddingStyles(attributedString, from: textNode, state: editorState, theme: editor.getTheme())
      let font = firstFontInAttributedString(attrStr: styledAttrStr)

      XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold), "Font should contain the bold trait")

      textNode.format.bold = false
      // let attributedString = NSMutableAttributedString(string: textNode.getTextPart())
      let newStyledAttrStr = AttributeUtils.attributedStringByAddingStyles(attributedString, from: textNode, state: editorState, theme: editor.getTheme())
      let newFont = firstFontInAttributedString(attrStr: newStyledAttrStr)

      XCTAssertFalse(newFont.fontDescriptor.symbolicTraits.contains(.traitBold), "Font should not contain the bold trait")
    }
  }

  func testApplyItalicStyles() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let textNode = TextNode()
      try textNode.setText("hello world")
      textNode.format.italic = true

      let paragraphNode = ParagraphNode()
      try paragraphNode.append([textNode])

      guard let editorState = getActiveEditorState(),
        let rootNode: RootNode = try editorState.getRootNode()?.getWritable()
      else {
        XCTFail("should have editor state")
        return
      }

      try rootNode.append([paragraphNode])
      let attributedString = NSMutableAttributedString(string: textNode.getTextPart())
      let styledAttrStr = AttributeUtils.attributedStringByAddingStyles(attributedString, from: textNode, state: editorState, theme: editor.getTheme())
      let font = firstFontInAttributedString(attrStr: styledAttrStr)

      XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitItalic), "Font should contain the italic trait")

      textNode.format.italic = false
      let newStyledAttrStr = AttributeUtils.attributedStringByAddingStyles(attributedString, from: textNode, state: editorState, theme: editor.getTheme())
      let newFont = firstFontInAttributedString(attrStr: newStyledAttrStr)

      XCTAssertFalse(newFont.fontDescriptor.symbolicTraits.contains(.traitItalic), "Font should not contain the italic trait")
    }
  }

  func testApplyBoldAndItalicStyles() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let textNode = TextNode()
      try textNode.setText("hello world")
      textNode.format.bold = true
      textNode.format.italic = true

      let paragraphNode = ParagraphNode()
      try paragraphNode.append([textNode])

      guard let editorState = getActiveEditorState(),
        let rootNode: RootNode = try editorState.getRootNode()?.getWritable()
      else {
        XCTFail("should have editor state")
        return
      }

      try rootNode.append([paragraphNode])
      let attributedString = NSMutableAttributedString(string: textNode.getTextPart())
      let styledAttrStr = AttributeUtils.attributedStringByAddingStyles(attributedString, from: textNode, state: editorState, theme: editor.getTheme())
      let font = firstFontInAttributedString(attrStr: styledAttrStr)

      XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold), "Font should contain the bold trait")
      XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitItalic), "Font should contain the italic trait")

      textNode.format.bold = false
      let newStyledAttrStr = AttributeUtils.attributedStringByAddingStyles(attributedString, from: textNode, state: editorState, theme: editor.getTheme())
      let newFont = firstFontInAttributedString(attrStr: newStyledAttrStr)

      XCTAssertFalse(newFont.fontDescriptor.symbolicTraits.contains(.traitBold), "Font should not contain the bold trait")
      XCTAssertTrue(newFont.fontDescriptor.symbolicTraits.contains(.traitItalic), "Font should contain the italic trait")
    }
  }

  func testFontUpdate() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor
    try editor.update {
      let testAttributeNode = TestAttributesNode()

      let paragraphNode = ParagraphNode()
      try paragraphNode.append([testAttributeNode])

      guard let editorState = getActiveEditorState(),
        let rootNode: RootNode = try editorState.getRootNode()?.getWritable()
      else {
        XCTFail("should have editor state")
        return
      }

      try rootNode.append([paragraphNode])

      let attributedString = NSMutableAttributedString(string: "Hello World")
      let styledAttrStr = AttributeUtils.attributedStringByAddingStyles(attributedString, from: testAttributeNode, state: editorState, theme: editor.getTheme())
      let font = firstFontInAttributedString(attrStr: styledAttrStr)

      XCTAssertEqual(font.familyName, "Arial", "Font attribute is incorrect")
      XCTAssertTrue(font.pointSize == 10, "Font size is incorrect")
      XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold), "Font should not contain the bold trait")
    }
  }

  func testThemeForRootNode() throws {
    let rootAttributes: [NSAttributedString.Key: Any] = [
      .fontFamily: "Arial",
      .fontSize: 18 as Float,
    ]

    let theme = Theme()
    theme.root = rootAttributes
    let view = LexicalView(editorConfig: EditorConfig(theme: theme, plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let paragraphNode = ParagraphNode()
      let textNode = TextNode()
      try textNode.setText("Testing Theme!")

      try paragraphNode.append([textNode])

      guard let editorState = getActiveEditorState(),
        let rootNode: RootNode = try editorState.getRootNode()?.getWritable()
      else {
        XCTFail("should have editor state")
        return
      }

      try rootNode.append([paragraphNode])
    }

    let attributedString = view.textView.attributedText
    if let attribute = attributedString?.attribute(.font, at: 1, effectiveRange: nil) as? UIFont {
      XCTAssertEqual(attribute.familyName, "Arial")
      XCTAssertEqual(attribute.pointSize, 18)
    }
  }

  func testThemeForHeadingNode() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let headingNode = HeadingNode(tag: .h1)
      let textNode = TextNode()
      try textNode.setText("Testing HeadingNode!")

      try headingNode.append([textNode])
      guard let editorState = getActiveEditorState(),
        let rootNode: RootNode = try editorState.getRootNode()?.getWritable()
      else {
        XCTFail("should have editor state")
        return
      }

      try rootNode.append([headingNode])
    }

    let attributedString = view.textView.attributedText
    if let attribute = attributedString?.attribute(.font, at: 1, effectiveRange: nil) as? UIFont {
      XCTAssertEqual(attribute.familyName, "Helvetica")
      XCTAssertEqual(attribute.pointSize, 36)
    }
  }

  private func themeForBlockTests() -> Theme {
    let theme = Theme()
    theme.setBlockLevelAttributes(.code, value: BlockLevelAttributes(marginTop: 5, marginBottom: 3, paddingTop: 6, paddingBottom: 4))
    return theme
  }

  func testBlockLevelAttributesPreserveAsymmetricBaseParagraphSpacing() throws {
    let baseSpacingBefore: CGFloat = 5
    let baseSpacingAfter: CGFloat = 17
    let blockAttributes = BlockLevelAttributes(
      marginTop: 2,
      marginBottom: 7,
      paddingTop: 3,
      paddingBottom: 4
    )
    let expectedSpacingBefore = baseSpacingBefore + 5
    let expectedSpacingAfter = baseSpacingAfter + 11

    func makeTheme() -> Theme {
      let theme = Theme()
      theme.code = [
        .paragraphSpacingBefore: baseSpacingBefore,
        .paragraphSpacing: baseSpacingAfter,
      ]
      theme.setBlockLevelAttributes(.code, value: blockAttributes)
      return theme
    }

    func makeView(lines: [String], trailingNewline: Bool, followedByParagraph: Bool) throws -> (LexicalView, NodeKey) {
      let view = LexicalView(
        editorConfig: EditorConfig(theme: makeTheme(), plugins: []),
        featureFlags: FeatureFlags()
      )
      var codeNodeKey = ""

      try view.editor.update {
        guard let rootNode = getRoot() else {
          XCTFail("should have root node")
          return
        }

        try rootNode.getChildren().forEach { try $0.remove() }

        let codeNode = CodeNode()
        codeNodeKey = codeNode.key
        for (index, line) in lines.enumerated() {
          if index > 0 {
            try codeNode.append([LineBreakNode()])
          }
          try codeNode.append([TextNode(text: line)])
        }
        if trailingNewline {
          try codeNode.append([LineBreakNode()])
        }
        try rootNode.append([codeNode])

        if followedByParagraph {
          let paragraphNode = ParagraphNode()
          try paragraphNode.append([TextNode(text: "after")])
          try rootNode.append([paragraphNode])
        }
      }

      return (view, codeNodeKey)
    }

    func reapplyBlockAttributes(in view: LexicalView, codeNodeKey: NodeKey) throws {
      try view.editor.update {
        guard let codeNode: CodeNode = getNodeByKey(key: codeNodeKey) else {
          XCTFail("should have code node")
          return
        }
        try codeNode.setLanguage(codeNode.getLanguage())
      }
    }

    func clearBlockAttributes(in view: LexicalView, codeNodeKey: NodeKey) throws {
      view.editor.getTheme().setBlockLevelAttributes(
        .code,
        value: BlockLevelAttributes(
          marginTop: 0,
          marginBottom: 0,
          paddingTop: 0,
          paddingBottom: 0
        )
      )
      try reapplyBlockAttributes(in: view, codeNodeKey: codeNodeKey)
    }

    func paragraphStyle(in view: LexicalView, at location: Int) throws -> NSParagraphStyle {
      guard let attributedText = view.textView.attributedText,
        let style = attributedText.attribute(
          .paragraphStyle,
          at: location,
          effectiveRange: nil
        ) as? NSParagraphStyle
      else {
        throw LexicalError.internal("Expected paragraph style at \(location)")
      }
      return style
    }

    let (singleView, singleCodeNodeKey) = try makeView(
      lines: ["single"],
      trailingNewline: false,
      followedByParagraph: true
    )
    var singleStyle = try paragraphStyle(in: singleView, at: 0)
    XCTAssertEqual(singleStyle.paragraphSpacingBefore, expectedSpacingBefore)
    XCTAssertEqual(singleStyle.paragraphSpacing, expectedSpacingAfter)

    try reapplyBlockAttributes(in: singleView, codeNodeKey: singleCodeNodeKey)
    singleStyle = try paragraphStyle(in: singleView, at: 0)
    XCTAssertEqual(singleStyle.paragraphSpacingBefore, expectedSpacingBefore)
    XCTAssertEqual(singleStyle.paragraphSpacing, expectedSpacingAfter)

    try clearBlockAttributes(in: singleView, codeNodeKey: singleCodeNodeKey)
    singleStyle = try paragraphStyle(in: singleView, at: 0)
    XCTAssertEqual(singleStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(singleStyle.paragraphSpacing, baseSpacingAfter)

    let (multiView, multiCodeNodeKey) = try makeView(
      lines: ["first", "second"],
      trailingNewline: false,
      followedByParagraph: true
    )
    var firstStyle = try paragraphStyle(in: multiView, at: 0)
    var lastStyle = try paragraphStyle(in: multiView, at: 6)
    XCTAssertEqual(firstStyle.paragraphSpacingBefore, expectedSpacingBefore)
    XCTAssertEqual(firstStyle.paragraphSpacing, baseSpacingAfter)
    XCTAssertEqual(lastStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(lastStyle.paragraphSpacing, expectedSpacingAfter)

    try reapplyBlockAttributes(in: multiView, codeNodeKey: multiCodeNodeKey)
    firstStyle = try paragraphStyle(in: multiView, at: 0)
    lastStyle = try paragraphStyle(in: multiView, at: 6)
    XCTAssertEqual(firstStyle.paragraphSpacingBefore, expectedSpacingBefore)
    XCTAssertEqual(firstStyle.paragraphSpacing, baseSpacingAfter)
    XCTAssertEqual(lastStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(lastStyle.paragraphSpacing, expectedSpacingAfter)

    try clearBlockAttributes(in: multiView, codeNodeKey: multiCodeNodeKey)
    firstStyle = try paragraphStyle(in: multiView, at: 0)
    lastStyle = try paragraphStyle(in: multiView, at: 6)
    XCTAssertEqual(firstStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(firstStyle.paragraphSpacing, baseSpacingAfter)
    XCTAssertEqual(lastStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(lastStyle.paragraphSpacing, baseSpacingAfter)

    let (trailingView, trailingCodeNodeKey) = try makeView(
      lines: ["first", "second"],
      trailingNewline: true,
      followedByParagraph: false
    )
    firstStyle = try paragraphStyle(in: trailingView, at: 0)
    XCTAssertEqual(firstStyle.paragraphSpacingBefore, expectedSpacingBefore)
    guard var extraLineStyle = trailingView.textStorage.extraLineFragmentAttributes?[.paragraphStyle] as? NSParagraphStyle else {
      XCTFail("Expected extra-line-fragment paragraph style")
      return
    }
    XCTAssertEqual(extraLineStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(extraLineStyle.paragraphSpacing, expectedSpacingAfter)

    try reapplyBlockAttributes(in: trailingView, codeNodeKey: trailingCodeNodeKey)
    extraLineStyle = try XCTUnwrap(
      trailingView.textStorage.extraLineFragmentAttributes?[.paragraphStyle] as? NSParagraphStyle
    )
    XCTAssertEqual(extraLineStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(extraLineStyle.paragraphSpacing, expectedSpacingAfter)

    try clearBlockAttributes(in: trailingView, codeNodeKey: trailingCodeNodeKey)
    firstStyle = try paragraphStyle(in: trailingView, at: 0)
    extraLineStyle = try XCTUnwrap(
      trailingView.textStorage.extraLineFragmentAttributes?[.paragraphStyle] as? NSParagraphStyle
    )
    XCTAssertEqual(firstStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(firstStyle.paragraphSpacing, baseSpacingAfter)
    XCTAssertEqual(extraLineStyle.paragraphSpacingBefore, baseSpacingBefore)
    XCTAssertEqual(extraLineStyle.paragraphSpacing, baseSpacingAfter)
  }

  func testBlockLevelAttributesSimpleCase() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: themeForBlockTests(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let paragraphNode = ParagraphNode()
      let textNode = TextNode()
      try textNode.setText("Para1")
      try paragraphNode.append([textNode])

      let codeLine1 = TextNode(text: "line1")
      let lineBreak = LineBreakNode()
      let codeLine2 = TextNode(text: "line2")
      let codeNode = CodeNode()
      try codeNode.append([codeLine1, lineBreak, codeLine2])

      guard let rootNode = getRoot() else {
        XCTFail("should have root node")
        return
      }

      try rootNode.getChildren().forEach { node in
        try node.remove()
      }

      try rootNode.append([paragraphNode, codeNode])
    }

    guard let attributedString = view.textView.attributedText else {
      XCTFail("No attr string")
      return
    }
    XCTAssertEqual(attributedString.string, "Para1\nline1\nline2")

    // test that line1 gets the spacing before
    if let attribute = attributedString.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 11, "Expected combination of paddingtop and margintop")
      XCTAssertEqual(attribute.paragraphSpacing, 0, "Expected no spacing after")
    } else {
      XCTFail("no para style")
    }
    // this is the first character of line2
    if let attribute = attributedString.attribute(.paragraphStyle, at: 12, effectiveRange: nil) as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 0, "Expected no spacing before")
      XCTAssertEqual(attribute.paragraphSpacing, 7, "Expected spacing after")
    } else {
      XCTFail("no para style")
    }
  }

  func testBlockLevelAttributesEmptyLineEndOfBlock() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: themeForBlockTests(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let paragraphNode = ParagraphNode()
      let textNode = TextNode()
      try textNode.setText("Para1")
      try paragraphNode.append([textNode])

      let codeLine1 = TextNode(text: "line1")
      let lineBreak = LineBreakNode()
      let codeNode = CodeNode()
      try codeNode.append([codeLine1, lineBreak])

      let paraNode2 = ParagraphNode()
      let textNode2 = TextNode(text: "text2")
      try paraNode2.append([textNode2])

      guard let rootNode = getRoot() else {
        XCTFail("should have root node")
        return
      }

      try rootNode.getChildren().forEach { node in
        try node.remove()
      }

      try rootNode.append([paragraphNode, codeNode, paraNode2])
    }

    guard let attributedString = view.textView.attributedText else {
      XCTFail("No attr string")
      return
    }
    XCTAssertEqual(attributedString.string, "Para1\nline1\n\ntext2")

    // test that line1 gets the spacing before
    if let attribute = attributedString.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 11, "Expected combination of paddingtop and margintop")
      XCTAssertEqual(attribute.paragraphSpacing, 0, "Expected no spacing after")
    } else {
      XCTFail("no para style")
    }
    // this is a newline character that should contain the styling for the end of the code block
    if let attribute = attributedString.attribute(.paragraphStyle, at: 12, effectiveRange: nil) as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 0, "Expected no spacing before")
      XCTAssertEqual(attribute.paragraphSpacing, 7, "Expected spacing after")
    } else {
      XCTFail("no para style")
    }

    XCTAssertNil(view.textStorage.extraLineFragmentAttributes, "Should have no extra line fragment attributes due to not ending in newline")
  }

  func testBlockLevelAttributesEmptyLineEndOfDocument() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: themeForBlockTests(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let paragraphNode = ParagraphNode()
      let textNode = TextNode()
      try textNode.setText("Para1")
      try paragraphNode.append([textNode])

      let codeLine1 = TextNode(text: "line1")
      let lineBreak = LineBreakNode()
      let codeNode = CodeNode()
      try codeNode.append([codeLine1, lineBreak])

      guard let rootNode = getRoot() else {
        XCTFail("should have root node")
        return
      }

      try rootNode.getChildren().forEach { node in
        try node.remove()
      }

      try rootNode.append([paragraphNode, codeNode])
    }

    guard let attributedString = view.textView.attributedText else {
      XCTFail("No attr string")
      return
    }
    XCTAssertEqual(attributedString.string, "Para1\nline1\n")

    // test that line1 gets the spacing before
    if let attribute = attributedString.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 11, "Expected combination of paddingtop and margintop")
      XCTAssertEqual(attribute.paragraphSpacing, 0, "Expected no spacing after")
    } else {
      XCTFail("no para style")
    }
    // this is a newline character that the LineBreakNode corresponds to.
    if let attribute = attributedString.attribute(.paragraphStyle, at: 11, effectiveRange: nil) as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 11, "Expected spacing before, since this line break is the same paragraph as line1")
      XCTAssertEqual(attribute.paragraphSpacing, 0, "Expected no spacing after, since that's handled by the extra line fragment attributes")
    } else {
      XCTFail("no para style")
    }

    XCTAssertNotNil(view.textStorage.extraLineFragmentAttributes, "Should have extra line fragment attributes")
    if let attribute = view.textStorage.extraLineFragmentAttributes?[.paragraphStyle] as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 0, "Expected no spacing before")
      XCTAssertEqual(attribute.paragraphSpacing, 7, "Expected spacing after")
    } else {
      XCTFail("no para style in extra line fragment attribs")
    }
  }

  func testBlockLevelAttributesEmptyParagraphEndOfDocument() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: themeForBlockTests(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      let paragraphNode = ParagraphNode()
      let textNode = TextNode()
      try textNode.setText("Para1")
      try paragraphNode.append([textNode])

      let codeLine1 = TextNode(text: "line1")
      let lineBreak = LineBreakNode()
      let codeNode = CodeNode()
      try codeNode.append([codeLine1, lineBreak])

      let paraNode2 = ParagraphNode()
      let textNode2 = TextNode(text: "")
      try paraNode2.append([textNode2])

      guard let rootNode = getRoot() else {
        XCTFail("should have root node")
        return
      }

      try rootNode.getChildren().forEach { node in
        try node.remove()
      }

      try rootNode.append([paragraphNode, codeNode, paraNode2])
    }

    guard let attributedString = view.textView.attributedText else {
      XCTFail("No attr string")
      return
    }
    XCTAssertEqual(attributedString.string, "Para1\nline1\n\n")

    // test that line1 gets the spacing before
    if let attribute = attributedString.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 11, "Expected combination of paddingtop and margintop")
      XCTAssertEqual(attribute.paragraphSpacing, 0, "Expected no spacing after")
    } else {
      XCTFail("no para style")
    }
    // this is a newline character that should contain the styling for the end of the code block
    if let attribute = attributedString.attribute(.paragraphStyle, at: 12, effectiveRange: nil) as? NSParagraphStyle {
      XCTAssertEqual(attribute.paragraphSpacingBefore, 0, "Expected no spacing before")
      XCTAssertEqual(attribute.paragraphSpacing, 7, "Expected spacing after")
    } else {
      XCTFail("no para style")
    }

    XCTAssertNotNil(view.textStorage.extraLineFragmentAttributes, "Should have extra line fragment attributes")
  }
}
