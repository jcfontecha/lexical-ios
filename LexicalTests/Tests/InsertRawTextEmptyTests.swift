/*
 * Regression: insertRawText("") over a partial single-text-node selection must
 * delete the range cleanly. Swift's default split yields no parts for an empty
 * string (JS yields [""]), and the insertNodes([]) path it previously fell into
 * duplicated the parent's child key, producing selections anchored on removed
 * nodes and tripping the commit-time selection invariant.
 *
 * Regression: the same default split dropped empty pieces, so blank lines and
 * leading/trailing newlines vanished; every newline must become a line break.
 */

import XCTest
@testable import Lexical

class InsertRawTextEmptyTests: XCTestCase {
  func testInsertRawTextEmptyStringDeletesRangeWithoutDuplicatingChild() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor
    var textKey: NodeKey!
    var paraKey: NodeKey!
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      try root.getChildren().forEach { try $0.remove() }
      let p = ParagraphNode()
      let t = TextNode(text: "original text")
      try p.append([t])
      try root.append([p])
      textKey = t.key
      paraKey = p.key
    }
    try editor.update {
      let anchor = Point(key: textKey, offset: 0, type: .text)
      let focus = Point(key: textKey, offset: 8, type: .text)
      let sel = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
      getActiveEditorState()?.selection = sel
      try sel.insertRawText(text: "")
      guard let p = getNodeByKey(key: paraKey) as? ElementNode else {
        return XCTFail("paragraph missing")
      }
      let kids = p.getChildren().map(\.key)
      XCTAssertEqual(kids.count, Set(kids).count, "duplicate child keys: \(kids)")
      XCTAssertEqual(p.getTextContent(), " text")
    }
    try editor.read {
      guard let p = getNodeByKey(key: paraKey) as? ElementNode else {
        return XCTFail("paragraph missing after commit")
      }
      XCTAssertEqual(p.getTextContent(), " text")
    }
  }

  func testInsertRawTextKeepsEveryNewlineAsALineBreak() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor
    for (raw, expected) in [("x\n\ny", "ax\n\nyc"), ("\nx\n", "a\nx\nc")] {
      var textKey: NodeKey!
      var paraKey: NodeKey!
      try editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        try root.getChildren().forEach { try $0.remove() }
        let p = ParagraphNode()
        let t = TextNode(text: "abc")
        try p.append([t])
        try root.append([p])
        textKey = t.key
        paraKey = p.key
      }
      try editor.update {
        let anchor = Point(key: textKey, offset: 1, type: .text)
        let focus = Point(key: textKey, offset: 2, type: .text)
        let sel = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
        getActiveEditorState()?.selection = sel
        try sel.insertRawText(text: raw)
      }
      try editor.read {
        guard let p = getNodeByKey(key: paraKey) as? ElementNode else {
          return XCTFail("paragraph missing after commit")
        }
        XCTAssertEqual(p.getTextContent(), expected, "raw \(raw.debugDescription)")
        let lineBreaks = p.getChildren().filter { $0 is LineBreakNode }.count
        XCTAssertEqual(lineBreaks, raw.filter { $0 == "\n" }.count, "raw \(raw.debugDescription)")
      }
    }
  }
}
