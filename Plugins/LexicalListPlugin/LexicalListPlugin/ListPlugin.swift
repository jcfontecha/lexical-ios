/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Lexical
import UIKit

extension CommandType {
  public static let insertUnorderedList = CommandType(rawValue: "insertUnorderedList")
  public static let insertOrderedList = CommandType(rawValue: "insertOrderedList")
  public static let removeList = CommandType(rawValue: "removeList")
}

open class ListPlugin: Plugin {
  public init() {}

  weak var editor: Editor?

  public func setUp(editor: Editor) {
    self.editor = editor
    do {
      try editor.registerNode(nodeType: NodeType.list, class: ListNode.self)
      try editor.registerNode(nodeType: NodeType.listItem, class: ListItemNode.self)

      _ = editor.registerCommand(
        type: .insertUnorderedList,
        listener: { [weak editor] payload in
          guard let editor else { return false }
          try? insertList(editor: editor, listType: .bullet)
          return true
        })

      _ = editor.registerCommand(
        type: .insertOrderedList,
        listener: { [weak editor] payload in
          guard let editor else { return false }
          try? insertList(editor: editor, listType: .number)
          return true
        })

      // Custom drawing registration for list bullets
      // This works for empty list items because:
      // 1. ListItemNode.getAttributedStringAttributes() creates ListItemAttribute even for empty items
      // 2. The forced layout update in MarkdownEditor triggers TextKit to process list structure
      // 3. Custom drawing is called for any paragraph with ListItemAttribute, empty or not
      try editor.registerCustomDrawing(customAttribute: .listItem, layer: .text, granularity: .contiguousParagraphs) {
        attributeKey, attributeValue, layoutManager, characterRange, expandedCharRange, glyphRange, rect, firstLineFragment in

        guard let attributeValue = attributeValue as? ListItemAttribute, let textStorage = layoutManager.textStorage as? TextStorage else {
          return
        }

        // we only want to do the drawing if we're the first character in a paragraph.
        // We could optimise this in the future by either (1) hooking in to TextKit string normalisation, or (2) subclassing
        // NSParagraphStyle
        if characterRange.location != 0 && (textStorage.string as NSString).substring(with: NSRange(location: characterRange.location - 1, length: 1)) != "\n" {
          return
        }
        
        // For empty list items that only contain zero-width space, ensure we still draw the bullet
        let textAtRange = (textStorage.string as NSString).substring(with: characterRange)
        let isZeroWidthSpaceOnly = textAtRange == "\u{200B}"

        let isFirstLine = (glyphRange.location == 0)

        var attributes = textStorage.attributes(at: characterRange.location, effectiveRange: nil)

        var spacingBefore = 0.0
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle, let mutableParagraphStyle = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle {
          mutableParagraphStyle.headIndent = 0
          mutableParagraphStyle.firstLineHeadIndent = 0
          mutableParagraphStyle.tailIndent = 0
          spacingBefore = isFirstLine ? 0 : paragraphStyle.paragraphSpacingBefore
          mutableParagraphStyle.paragraphSpacingBefore = 0
          attributes[.paragraphStyle] = mutableParagraphStyle
        }
        attributes.removeValue(forKey: .underlineStyle)
        attributes.removeValue(forKey: .strikethroughStyle)
        
        // Only apply bullet styling to actual bullet characters (•), not numbers
        var verticalOffset: CGFloat = 0.0
        if attributeValue.listItemCharacter == "•" {
          // Make bullet font larger than the text font using configurable values
          if let currentFont = attributes[.font] as? UIFont {
            let sizeIncrease = (attributes[.bulletSizeIncrease] as? CGFloat) ?? 3.0
            let weightRawValue = (attributes[.bulletWeight] as? CGFloat) ?? UIFont.Weight.medium.rawValue
            let weight = UIFont.Weight(rawValue: weightRawValue)
            attributes[.font] = UIFont.systemFont(ofSize: currentFont.pointSize + sizeIncrease, weight: weight)
          }
          
          // Apply vertical offset to compensate for larger bullet font
          verticalOffset = (attributes[.bulletVerticalOffset] as? CGFloat) ?? 0.0
        }
        let bulletDrawRect = firstLineFragment.inset(by: UIEdgeInsets(
          top: spacingBefore + verticalOffset, 
          left: attributeValue.characterIndentationPixels, 
          bottom: 0, 
          right: 0
        ))

        attributeValue.listItemCharacter.draw(in: bulletDrawRect, withAttributes: attributes)
      }
    } catch {
      print("\(error)")
    }
  }

  public func tearDown() {
  }
}
