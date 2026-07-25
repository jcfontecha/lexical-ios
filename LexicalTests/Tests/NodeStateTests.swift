/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import Lexical

final class NodeStateTests: XCTestCase {
  private struct Metadata: Codable, Equatable {
    let label: String
    let count: Int
  }

  private func makeView() -> LexicalView {
    LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags()
    )
  }

  private func firstParagraph() throws -> ParagraphNode {
    guard let paragraph = getRoot()?.getFirstChild() as? ParagraphNode else {
      throw LexicalError.internal("Expected first paragraph")
    }
    return paragraph
  }

  func testDefaultOmissionAndTypedSetGet() throws {
    let view = makeView()
    let key = NodeStateKey(
      "dev.lexical-ios.tests.metadata",
      defaultValue: Metadata(label: "", count: 0)
    )

    try view.editor.read {
      XCTAssertEqual(
        try firstParagraph().getState(key),
        Metadata(label: "", count: 0)
      )
    }

    try view.editor.update {
      _ = try firstParagraph().setState(
        key,
        Metadata(label: "saved", count: 3)
      )
      XCTAssertEqual(
        try firstParagraph().getState(key),
        Metadata(label: "saved", count: 3)
      )
    }

    var json = try view.editor.getEditorState().toJSON()
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )
    var root = try XCTUnwrap(object["root"] as? [String: Any])
    var children = try XCTUnwrap(root["children"] as? [[String: Any]])
    var state = try XCTUnwrap(children.first?["$"] as? [String: Any])
    XCTAssertEqual(state["dev.lexical-ios.tests.metadata"] as? [String: AnyHashable], [
      "label": "saved",
      "count": 3,
    ])

    try view.editor.update {
      _ = try firstParagraph().setState(
        key,
        Metadata(label: "", count: 0)
      )
    }

    json = try view.editor.getEditorState().toJSON()
    object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )
    root = try XCTUnwrap(object["root"] as? [String: Any])
    children = try XCTUnwrap(root["children"] as? [[String: Any]])
    state = children.first?["$"] as? [String: Any] ?? [:]
    XCTAssertNil(state["dev.lexical-ios.tests.metadata"])
    XCTAssertNil(children.first?["$"])
  }

  func testWritableClonePreservesHistoryWithCopyOnWriteState() throws {
    let view = makeView()
    let key = NodeStateKey<String?>(
      "dev.lexical-ios.tests.history",
      defaultValue: nil
    )

    try view.editor.update {
      _ = try firstParagraph().setState(key, "before")
    }
    let previousEditorState = view.editor.getEditorState()

    try view.editor.update {
      _ = try firstParagraph().setState(key, "after")
    }

    try previousEditorState.read {
      XCTAssertEqual(try firstParagraph().getState(key), "before")
    }
    try view.editor.read {
      XCTAssertEqual(try firstParagraph().getState(key), "after")
    }
  }

  func testSettingEqualValueDoesNotCreateWritableCloneOrDirtyNode() throws {
    let view = makeView()
    let key = NodeStateKey(
      "dev.lexical-ios.tests.equal-no-op",
      defaultValue: 0
    )

    try view.editor.update {
      _ = try firstParagraph().setState(key, 42)
    }

    try view.editor.update {
      let paragraph = try firstParagraph()
      let result = try paragraph.setState(key, 42)
      XCTAssertTrue(result === paragraph)
      XCTAssertFalse(paragraph.isDirty())
    }
  }

  func testUnknownStateSurvivesEditorStateDecodeEncode() throws {
    let view = makeView()
    let json = """
      {
        "root": {
          "$": {
            "dev.future.root": {
              "enabled": true,
              "values": [1, 2.5, null]
            }
          },
          "children": [
            {
              "$": {
                "dev.future.paragraph": {
                  "nested": {"value": "kept"}
                }
              },
              "children": [],
              "direction": null,
              "format": "",
              "indent": 0,
              "type": "paragraph",
              "version": 1
            }
          ],
          "direction": null,
          "format": "",
          "indent": 0,
          "type": "root",
          "version": 1
        }
      }
      """

    let editorState = try EditorState.fromJSON(json: json, editor: view.editor)
    let encoded = try editorState.toJSON()
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
    )
    let root = try XCTUnwrap(object["root"] as? [String: Any])
    let rootState = try XCTUnwrap(root["$"] as? [String: Any])
    let futureRoot = try XCTUnwrap(rootState["dev.future.root"] as? [String: Any])
    XCTAssertEqual(futureRoot["enabled"] as? Bool, true)
    XCTAssertEqual(futureRoot["values"] as? [AnyHashable], [1, 2.5, NSNull()])

    let children = try XCTUnwrap(root["children"] as? [[String: Any]])
    let paragraphState = try XCTUnwrap(children.first?["$"] as? [String: Any])
    let futureParagraph = try XCTUnwrap(
      paragraphState["dev.future.paragraph"] as? [String: Any]
    )
    XCTAssertEqual(
      futureParagraph["nested"] as? [String: String],
      ["value": "kept"]
    )
  }

  func testCopyAndSerializedClipboardRoundTripPreserveState() throws {
    let view = makeView()
    let key = NodeStateKey<String?>(
      "dev.lexical-ios.tests.clipboard",
      defaultValue: nil
    )

    try view.editor.update {
      let paragraph = try firstParagraph()
      try paragraph.append([TextNode(text: "copy me")])
      _ = try paragraph.setState(key, "persistent")
    }

    try view.editor.update {
      let copiedNodes = try generateArrayFromSelectedNodes(
        editor: view.editor,
        selection: nil
      ).nodes
      let copiedParagraph = try XCTUnwrap(copiedNodes.first as? ParagraphNode)
      XCTAssertEqual(copiedParagraph.getState(key), "persistent")

      let encoded = try JSONEncoder().encode(copiedNodes)
      let decoded = try JSONDecoder().decode(SerializedNodeArray.self, from: encoded)
      let decodedParagraph = try XCTUnwrap(
        decoded.nodeArray.first as? ParagraphNode
      )
      XCTAssertEqual(decodedParagraph.getState(key), "persistent")
    }
  }
}
