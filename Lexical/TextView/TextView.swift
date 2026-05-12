/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

protocol LexicalTextViewDelegate: NSObjectProtocol {
  func textViewDidBeginEditing(textView: TextView)
  func textViewDidEndEditing(textView: TextView)
  func textViewShouldChangeText(_ textView: UITextView, range: NSRange, replacementText text: String) -> Bool
  @available(iOS, deprecated: 17.0, message: "Use textView(_:primaryActionFor:defaultAction:) with UITextItem instead")
  func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool
}

/// Protocol for customizing cursor appearance
@objc public protocol TextViewCursorDelegate: NSObjectProtocol {
  /// Called to determine the cursor height for a given position
  /// - Parameters:
  ///   - textView: The text view requesting cursor customization
  ///   - position: The text position where the cursor will be displayed
  ///   - defaultRect: The default cursor rect calculated by the system
  /// - Returns: The desired cursor rect, or nil to use the default
  @objc optional func textView(_ textView: TextView, cursorRectFor position: UITextPosition, defaultRect: CGRect) -> CGRect
}

/// Lexical's subclass of UITextView. Note that using this can be dangerous, if you make changes that Lexical does not expect.
@objc public class TextView: UITextView {
  public let editor: Editor

  internal let pasteboard = UIPasteboard.general
  internal let pasteboardIdentifier = "x-lexical-nodes"
  internal var isUpdatingNativeSelection = false
  internal var layoutManagerDelegate: LayoutManagerDelegate

  // This is to work around a UIKit issue where, in situations like autocomplete, UIKit changes our selection via
  // private methods, and the first time we find out is when our delegate method is called. @amyworrall
  internal var interceptNextSelectionChangeAndReplaceWithRange: NSRange?
  internal var nativeSelectionUpdateRecorder: ((NSRange) -> Void)?
  private var pendingNativeSelectionDuringTextStorageEditing: NSRange?
  weak var lexicalDelegate: LexicalTextViewDelegate?
  @objc public weak var cursorDelegate: TextViewCursorDelegate?
  private var placeholderLabel: UILabel

  private let useInputDelegateProxy: Bool
  private let inputDelegateProxy: InputDelegateProxy

  fileprivate var textViewDelegate: TextViewDelegate = TextViewDelegate()

  // MARK: - Init

  init(editorConfig: EditorConfig, featureFlags: FeatureFlags) {
    let textStorage = TextStorage()
    let layoutManager = LayoutManager()
    layoutManagerDelegate = LayoutManagerDelegate()
    layoutManager.delegate = layoutManagerDelegate

    let textContainer = TextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    textContainer.widthTracksTextView = true

    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)

    var reconcilerSanityCheck = featureFlags.reconcilerSanityCheck

    #if targetEnvironment(simulator)
    reconcilerSanityCheck = false
    #endif

    editor = Editor(
      featureFlags: FeatureFlags(reconcilerSanityCheck: reconcilerSanityCheck),
      editorConfig: editorConfig)
    textStorage.editor = editor
    placeholderLabel = UILabel(frame: .zero)

    useInputDelegateProxy = featureFlags.proxyTextViewInputDelegate
    inputDelegateProxy = InputDelegateProxy()

    super.init(frame: .zero, textContainer: textContainer)

    if useInputDelegateProxy {
      inputDelegateProxy.targetInputDelegate = self.inputDelegate
      super.inputDelegate = inputDelegateProxy
    }

    delegate = textViewDelegate
    textContainerInset = UIEdgeInsets(top: 8.0, left: 5.0, bottom: 8.0, right: 5.0)

    setUpPlaceholderLabel()
    registerRichText(editor: editor)
  }

  /// This init method is used for unit tests
  convenience init() {
    self.init(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("\(#function) has not been implemented")
  }

  override public func layoutSubviews() {
    super.layoutSubviews()

    placeholderLabel.frame.origin = CGPoint(x: textContainer.lineFragmentPadding * 1.5 + textContainerInset.left, y: textContainerInset.top)
    placeholderLabel.sizeToFit()
  }

  override public var inputDelegate: UITextInputDelegate? {
    get {
      if useInputDelegateProxy {
        return inputDelegateProxy.targetInputDelegate
      } else {
        return super.inputDelegate
      }
    }
    set {
      if useInputDelegateProxy {
        inputDelegateProxy.targetInputDelegate = newValue
      } else {
        super.inputDelegate = newValue
      }
    }
  }

  // MARK: - Incoming events

  override public func deleteBackward() {
    editor.log(.UITextView, .verbose, "deleteBackward()")

    let previousSelectedRange = selectedRange

    inputDelegateProxy.isSuspended = true // do not send selection changes during deleteBackwards, to not confuse third party keyboards
    defer {
      inputDelegateProxy.isSuspended = false
    }

    if previousSelectedRange.length > 0 {
      syncLexicalSelectionFromNativeRange(previousSelectedRange)
    }

    editor.dispatchCommand(type: .deleteCharacter, payload: true)
    syncNativeSelectionFromLexical()
    editor.frontend?.showPlaceholderText()

    if previousSelectedRange.length > 0 {
      // Expect new selection to be on the start of selection
      if selectedRange.location != previousSelectedRange.location || selectedRange.length != 0 {
        inputDelegateProxy.sendSelectionChangedIgnoringSuspended(self)
      }
    } else {
      // Expect new selection to be somewhere before selection -- we could calculate this by considering
      // unicode characters, but it would be complex. Let's do a best effort, since this situation is rare anyway.
      if selectedRange.length != 0 || selectedRange.location >= previousSelectedRange.location {
        inputDelegateProxy.sendSelectionChangedIgnoringSuspended(self)
      }
    }
  }

  override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(paste(_:)) {
      if pasteboard.hasStrings {
        return true
      } else if !(pasteboard.data(forPasteboardType: LexicalConstants.pasteboardIdentifier)?.isEmpty ?? true) {
        return true
      } else if #available(iOS 14.0, *) {
        if !(pasteboard.data(forPasteboardType: (UTType.utf8PlainText.identifier))?.isEmpty ?? true) {
          return true
        }
      } else {
        if !(pasteboard.data(forPasteboardType: (kUTTypeUTF8PlainText as String))?.isEmpty ?? true) {
          return true
        }
      }
      return super.canPerformAction(action, withSender: sender)
    } else {
      return super.canPerformAction(action, withSender: sender)
    }
  }

  override public func copy(_ sender: Any?) {
    editor.dispatchCommand(type: .copy, payload: pasteboard)
  }

  override public func cut(_ sender: Any?) {
    editor.dispatchCommand(type: .cut, payload: pasteboard)
  }

  override public func paste(_ sender: Any?) {
    editor.dispatchCommand(type: .paste, payload: pasteboard)
  }

  override public func insertText(_ text: String) {
    editor.log(.UITextView, .verbose, "Text view selected range \(String(describing: self.selectedRange))")

    let expectedSelectionLocation = selectedRange.location + text.lengthAsNSString()

    inputDelegateProxy.isSuspended = true // do not send selection changes during insertText, to not confuse third party keyboards
    defer {
      inputDelegateProxy.isSuspended = false
    }

    guard let textStorage = textStorage as? TextStorage else {
      // This should never happen, we will always have a custom text storage.
      editor.log(.TextView, .error, "Missing custom text storage")
      return
    }

    textStorage.mode = TextStorageEditingMode.controllerMode
    _ = editor.dispatchCommand(type: .insertText, payload: text)
    textStorage.mode = TextStorageEditingMode.none

    // Structural paragraph insertion can legally keep the native range at the
    // same UTF-16 location (for example exiting an empty list item into an empty
    // paragraph with a zero-width text anchor). Treating that as an unexpected
    // UIKit selection change pushes the editor back to an element selection and
    // makes the caret briefly jump to stale/default geometry.
    if text == "\n" || text == "\u{2029}" {
      syncNativeSelectionFromLexical()
      return
    }

    // check if we need to send a selectionChanged (i.e. something unexpected happened)
    if selectedRange.length != 0 || selectedRange.location != expectedSelectionLocation {
      inputDelegateProxy.sendSelectionChangedIgnoringSuspended(self)
    }
  }

  // MARK: Marked text

  override public func setAttributedMarkedText(_ markedText: NSAttributedString?, selectedRange: NSRange) {
    editor.log(.UITextView, .verbose)
    if let markedText {
      setMarkedTextInternal(markedText.string, selectedRange: selectedRange)
    } else {
      unmarkText()
    }
  }

  override public func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
    editor.log(.UITextView, .verbose)
    if let markedText {
      setMarkedTextInternal(markedText, selectedRange: selectedRange)
    } else {
      unmarkText()
    }
  }

  private func setMarkedTextInternal(_ markedText: String, selectedRange: NSRange) {
    editor.log(.TextView, .verbose)
    guard let textStorage = textStorage as? TextStorage else {
      // This should never happen, we will always have a custom text storage.
      editor.log(.TextView, .error, "Missing custom text storage")
      super.setMarkedText(markedText, selectedRange: selectedRange)
      return
    }

    if markedText.isEmpty, let markedRange = editor.getNativeSelection().markedRange {
      textStorage.replaceCharacters(in: markedRange, with: "")
      return
    }

    let markedTextOperation = MarkedTextOperation(
      createMarkedText: true,
      selectionRangeToReplace: editor.getNativeSelection().markedRange ?? self.selectedRange,
      markedTextString: markedText,
      markedTextInternalSelection: selectedRange)

    let behaviourModificationMode = UpdateBehaviourModificationMode(suppressReconcilingSelection: true, suppressSanityCheck: true, markedTextOperation: markedTextOperation)

    textStorage.mode = TextStorageEditingMode.controllerMode
    defer {
      textStorage.mode = TextStorageEditingMode.none
    }
    do {
      // set composition key
      try editor.read {
        guard let selection = try getSelection() as? RangeSelection else {
          editor.log(.TextView, .error, "Could not get selection in setMarkedTextInternal()")
          throw LexicalError.invariantViolation("should have selection when starting marked text")
        }

        editor.compositionKey = selection.anchor.key
      }

      // insert text
      try onInsertTextFromUITextView(text: markedText, editor: editor, updateMode: behaviourModificationMode)
    } catch {
      let language = textInputMode?.primaryLanguage
      editor.log(.TextView, .error, "exception thrown, lang \(String(describing: language)): \(String(describing: error))")
      unmarkTextWithoutUpdate()
      return
    }
  }

  internal func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange) {
    editor.log(.TextView, .verbose)
    isUpdatingNativeSelection = true
    super.setAttributedMarkedText(markedText, selectedRange: selectedRange)
    interceptNextSelectionChangeAndReplaceWithRange = nil
    onSelectionChange(editor: editor)
    isUpdatingNativeSelection = false
    editor.compositionKey = nil
    showPlaceholderText()
  }

  override public func unmarkText() {
    editor.log(.UITextView, .verbose)
    let previousMarkedRange = editor.getNativeSelection().markedRange
    let oldIsUpdatingNative = isUpdatingNativeSelection
    isUpdatingNativeSelection = true
    super.unmarkText()
    isUpdatingNativeSelection = oldIsUpdatingNative
    if let previousMarkedRange {
      // find all nodes in selection. Mark dirty. Reconcile. This should correct all the attributes to be what we expect.
      do {
        try editor.update {
          guard let anchor = try pointAtStringLocation(previousMarkedRange.location, searchDirection: .forward, rangeCache: editor.rangeCache),
            let focus = try pointAtStringLocation(previousMarkedRange.location + previousMarkedRange.length, searchDirection: .forward, rangeCache: editor.rangeCache)
          else {
            return
          }

          let markedRangeSelection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
          _ = try markedRangeSelection.getNodes().map { node in
            internallyMarkNodeAsDirty(node: node, cause: .userInitiated)
          }

          let committedSelection = RangeSelection(anchor: focus, focus: focus, format: TextFormat())
          getActiveEditorState()?.selection = committedSelection
          editor.compositionKey = nil
        }
      } catch {}
    }
  }

  internal func unmarkTextWithoutUpdate() {
    editor.log(.TextView, .verbose)
    super.unmarkText()
  }

  // MARK: - Lexical internal

  internal func presentDeveloperFacingError(message: String) {
    let alert = UIAlertController(title: "Lexical Error", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
    if let rootViewController = self.window?.rootViewController {
      rootViewController.present(alert, animated: true, completion: nil)
    }
  }

  internal func updateNativeSelection(from selection: RangeSelection) throws {
    isUpdatingNativeSelection = true
    defer { isUpdatingNativeSelection = false }
    let nativeSelection = try createNativeSelection(from: selection, editor: editor)

    if let range = nativeSelection.range {
      nativeSelectionUpdateRecorder?(range)
      selectedRange = range
    }
  }

  internal func resetSelectedRange() {
    selectedRange = NSRange(location: 0, length: 0)
  }

  func defaultClearEditor() throws {
    editor.resetEditor(pendingEditorState: nil)
    editor.dispatchCommand(type: .clearEditor)
  }

  func setPlaceholderText(_ text: String, textColor: UIColor, font: UIFont) {
    placeholderLabel.text = text
    placeholderLabel.textColor = textColor
    placeholderLabel.font = font
    self.font = font

    showPlaceholderText()
  }

  func showPlaceholderText() {
    var shouldShow = false
    do {
      try editor.read {
        shouldShow = isRootTextContentEmpty(isEditorComposing: editor.isComposing(), trim: false)
      }
      if !shouldShow {
        hidePlaceholderLabel()
        return
      }
      try editor.read {
        if canShowPlaceholder(isComposing: editor.isComposing()) {
          placeholderLabel.isHidden = false
          layoutIfNeeded()
        }
      }
    } catch {}
  }

  // MARK: - Private

  private func setUpPlaceholderLabel() {
    placeholderLabel.backgroundColor = .clear
    placeholderLabel.isHidden = true
    placeholderLabel.isAccessibilityElement = false
    placeholderLabel.numberOfLines = 1
    addSubview(placeholderLabel)
  }

  fileprivate func hidePlaceholderLabel() {
    placeholderLabel.isHidden = true
  }

  override public func becomeFirstResponder() -> Bool {
    let r = super.becomeFirstResponder()
    if r == true {
      onSelectionChange(editor: editor)
    }
    return r
  }
  
  // MARK: - Cursor Geometry

  @objc public func measuredCaretRect(for position: UITextPosition) -> CGRect {
    caretRect(for: position)
  }

  override public func caretRect(for position: UITextPosition) -> CGRect {
    let pendingNativeSelectionRange = pendingNativeSelectionDuringTextStorageEditing
    let nativeSelectionRange = selectedRange
    let currentInsertionPosition = nativeSelectionRange.length == 0
      ? self.position(from: beginningOfDocument, offset: nativeSelectionRange.location)
      : nil
    let measuringPosition = currentInsertionPosition ?? position
    let defaultRect = pendingNativeSelectionRange.map { provisionalCaretRect(for: $0.location) }
      ?? super.caretRect(for: measuringPosition)

    // Check if delegate wants to customize the cursor
    if let customRect = cursorDelegate?.textView?(self, cursorRectFor: position, defaultRect: defaultRect) {
      return customRect
    }

    let cursorLocation = pendingNativeSelectionRange?.location
      ?? currentInsertionPosition.map { _ in nativeSelectionRange.location }
      ?? offset(from: beginningOfDocument, to: position)
    return fontMetricsCaretRect(
      atCharacterOffset: cursorLocation,
      defaultRect: defaultRect,
      usesDefaultVerticalMetrics: pendingNativeSelectionRange == nil)
  }

  internal func prepareForNativeSelectionDuringTextStorageEditing(_ nativeSelection: NativeSelection?) {
    pendingNativeSelectionDuringTextStorageEditing = nativeSelection?.range
  }

  private func provisionalCaretRect(for location: Int) -> CGRect {
    let height = font?.lineHeight ?? typingAttributesFontLineHeight() ?? 17
    return CGRect(
      x: textContainerInset.left + textContainer.lineFragmentPadding,
      y: textContainerInset.top,
      width: 2,
      height: height
    )
  }

  private func typingAttributesFontLineHeight() -> CGFloat? {
    (typingAttributes[.font] as? UIFont)?.lineHeight
  }

  internal func fontMetricsCaretRect(
    atCharacterOffset cursorLocation: Int,
    defaultRect: CGRect,
    usesDefaultVerticalMetrics: Bool = false
  ) -> CGRect {
    guard let textStorage = textStorage as? TextStorage else { return defaultRect }
    return Self.fontMetricsCaretRect(
      atCharacterOffset: cursorLocation,
      defaultRect: defaultRect,
      usesDefaultVerticalMetrics: usesDefaultVerticalMetrics,
      textStorage: textStorage,
      layoutManager: layoutManager,
      textContainer: textContainer,
      textContainerInset: textContainerInset)
  }

  private func syncNativeSelectionFromLexical() {
    try? editor.read {
      guard let selection = try? getSelection() as? RangeSelection else { return }
      try? updateNativeSelection(from: selection)
    }
    syncTypingAttributesFromCaret()
  }

  internal func syncTypingAttributesFromCaret() {
    guard let textStorage = textStorage as? TextStorage,
      textStorage.length > 0
    else {
      return
    }

    let text = textStorage.string as NSString
    guard let location = Self.caretAttributeLocation(for: selectedRange.location, text: text) else {
      return
    }

    typingAttributes = textStorage.attributes(at: location, effectiveRange: nil)
  }

  private func syncLexicalSelectionFromNativeRange(_ range: NSRange) {
    try? editor.update {
      let nativeSelection = NativeSelection(range: range, affinity: .forward)
      guard let editorState = getActiveEditorState() else { return }

      if !(try getSelection() is RangeSelection) {
        guard let newSelection = RangeSelection(nativeSelection: nativeSelection) else {
          return
        }
        editorState.selection = newSelection
      }

      guard let selection = try getSelection() as? RangeSelection else { return }
      try selection.applyNativeSelection(nativeSelection)
    }
  }

  internal static func fontMetricsCaretRect(
    atCharacterOffset cursorLocation: Int,
    defaultRect: CGRect,
    usesDefaultVerticalMetrics: Bool = false,
    textStorage: NSTextStorage,
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer,
    textContainerInset: UIEdgeInsets
  ) -> CGRect {
    guard let characterLocation = caretAttributeLocation(for: cursorLocation, text: textStorage.string as NSString),
          let font = textStorage.attribute(.font, at: characterLocation, effectiveRange: nil) as? UIFont else {
      return defaultRect
    }

    var rect = defaultRect
    rect.size.height = font.lineHeight

    let glyphLocation = min(characterLocation, max(textStorage.length - 1, 0))
    guard textStorage.length > 0, glyphLocation >= 0 else {
      return verticallyCenter(rect, in: defaultRect, minimumY: textContainerInset.top)
    }

    layoutManager.ensureLayout(for: textContainer)
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: glyphLocation)
    guard glyphIndex < layoutManager.numberOfGlyphs else {
      return verticallyCenter(rect, in: defaultRect, minimumY: textContainerInset.top)
    }

    let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    let usedLineFragmentRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    let fallbackLineMidY = caretLineMidY(
      atCharacterOffset: cursorLocation,
      characterLocation: characterLocation,
      textStorage: textStorage)
    rect.origin.x = caretX(
      atCharacterOffset: cursorLocation,
      characterLocation: characterLocation,
      glyphIndex: glyphIndex,
      textStorage: textStorage,
      layoutManager: layoutManager,
      textContainer: textContainer,
      textContainerInset: textContainerInset,
      fallbackX: rect.origin.x)
    let text = textStorage.string as NSString
    if cursorLocation >= textStorage.length,
       textStorage.length > 0,
       isLineBoundary(text.character(at: textStorage.length - 1)) {
      rect.origin.y = textContainerInset.top + fallbackLineMidY - rect.height / 2
      rect.origin.y = max(rect.origin.y, textContainerInset.top + max(lineFragmentRect.minY, 0))
      return rect
    }
    // Centre the caret on the visual glyph line, not the used rect midpoint.
    // TextKit stretches `usedLineFragmentRect` downward by the paragraph's
    // lineSpacing (added as bottom padding below the rendered glyph run), so
    // `usedLineFragmentRect.midY` sits ~lineSpacing/2 below the actual
    // cap-height centre of the line. Aligning to the top of the used rect
    // plus half the font's lineHeight keeps the caret visually centred on
    // the rendered characters, including in non-last paragraphs and softly
    // wrapped lines where the used rect carries trailing lineSpacing.
    let lineMidY: CGFloat
    if usedLineFragmentRect.isEmpty {
      lineMidY = fallbackLineMidY
    } else {
      lineMidY = usedLineFragmentRect.minY + rect.height / 2
    }
    rect.origin.y = textContainerInset.top + lineMidY - rect.height / 2
    rect.origin.y = max(rect.origin.y, textContainerInset.top + max(lineFragmentRect.minY, 0))

    return rect
  }

  private static func caretLineMidY(
    atCharacterOffset cursorLocation: Int,
    characterLocation: Int,
    textStorage: NSTextStorage
  ) -> CGFloat {
    let text = textStorage.string as NSString
    guard text.length > 0 else { return 0 }

    let targetLineStart = lineStartLocation(containing: cursorLocation, text: text)
    var lineStart = 0
    var y: CGFloat = 0

    while lineStart < targetLineStart {
      let lineEnd = nextLineBoundary(startingAt: lineStart, text: text)
      y += lineAdvance(
        atCharacterLocation: max(lineStart, min(lineEnd, text.length - 1)),
        textStorage: textStorage)
      lineStart = min(lineEnd + 1, text.length)
    }

    if targetLineStart > 0 {
      let paragraphStyle = textStorage.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
      y += paragraphStyle?.paragraphSpacingBefore ?? 0
    }

    let currentLineHeight = lineHeight(
      atCharacterLocation: characterLocation,
      textStorage: textStorage)
    return y + currentLineHeight / 2
  }

  private static func nextLineBoundary(startingAt startLocation: Int, text: NSString) -> Int {
    var location = max(startLocation, 0)
    while location < text.length {
      if isLineBoundary(text.character(at: location)) {
        return location
      }
      location += 1
    }
    return text.length
  }

  private static func lineAdvance(atCharacterLocation characterLocation: Int, textStorage: NSTextStorage) -> CGFloat {
    // Vertical advance per laid-out line, matching how TextKit positions the
    // next line fragment. TextKit places each fragment at the previous
    // fragment's used origin + lineHeight + lineSpacing (always) + paragraphSpacing
    // (when crossing a paragraph boundary). The previous version of this
    // method omitted lineSpacing, so the fallback caret math disagreed with
    // the rendered TextKit position by `lineSpacing` per intervening line.
    // When the caret rect for an empty/anchored block switched between the
    // TextKit usedRect path and this fallback path (e.g. as ZWSP anchors
    // were inserted/elided between successive Enter presses), the caret
    // appeared to jump up or down by N * lineSpacing — perceived as a
    // glitchy cursor on Enter.
    let paragraphStyle = textStorage.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
    return lineHeight(atCharacterLocation: characterLocation, textStorage: textStorage)
      + (paragraphStyle?.lineSpacing ?? 0)
      + (paragraphStyle?.paragraphSpacing ?? 0)
  }

  private static func lineHeight(atCharacterLocation characterLocation: Int, textStorage: NSTextStorage) -> CGFloat {
    let font = textStorage.attribute(.font, at: characterLocation, effectiveRange: nil) as? UIFont
    let paragraphStyle = textStorage.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
    return max(font?.lineHeight ?? LexicalConstants.defaultFont.lineHeight, paragraphStyle?.minimumLineHeight ?? 0)
  }

  private static func caretX(
    atCharacterOffset cursorLocation: Int,
    characterLocation: Int,
    glyphIndex: Int,
    textStorage: NSTextStorage,
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer,
    textContainerInset: UIEdgeInsets,
    fallbackX: CGFloat
  ) -> CGFloat {
    let text = textStorage.string as NSString
    let paragraphStyle = textStorage.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
    let lineStartX = textContainerInset.left + textContainer.lineFragmentPadding + (paragraphStyle?.firstLineHeadIndent ?? 0)

    if cursorLocation <= 0 {
      return lineStartX
    }

    let targetOffset = min(max(cursorLocation, 0), textStorage.length)
    let hardLineStart = lineStartLocation(containing: targetOffset, text: text)

    // Find the start of the *visual* line containing the caret. A paragraph
    // can wrap into multiple visual lines without any hard line-break
    // character; if we measure the prefix from the paragraph's hard line
    // start the caret on the second visual line is offset by the full
    // first-line width and lands off-screen. Ask TextKit for the actual
    // line fragment instead.
    var visualLineStart = hardLineStart
    if textStorage.length > 0, glyphIndex >= 0, glyphIndex < layoutManager.numberOfGlyphs {
      var lineFragmentGlyphRange = NSRange(location: 0, length: 0)
      _ = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineFragmentGlyphRange)
      if lineFragmentGlyphRange.length > 0 {
        let lineCharacterRange = layoutManager.characterRange(forGlyphRange: lineFragmentGlyphRange, actualGlyphRange: nil)
        // The visual line start sits inside (or equal to) the hard line
        // start, never before it.
        visualLineStart = max(visualLineStart, lineCharacterRange.location)
      }
    }

    // Pick the right indent: paragraphs apply `firstLineHeadIndent` to their
    // first visual line and `headIndent` to subsequent (soft-wrapped) visual
    // lines. Quotes and similar blocks rely on this to keep wrapped text
    // visually indented at the same margin as the first line.
    let isFirstVisualLine = visualLineStart <= hardLineStart
    let lineIndent: CGFloat = isFirstVisualLine
      ? (paragraphStyle?.firstLineHeadIndent ?? 0)
      : (paragraphStyle?.headIndent ?? 0)
    let visualLineLeftX = textContainerInset.left + textContainer.lineFragmentPadding + lineIndent

    guard targetOffset > visualLineStart else {
      return visualLineLeftX
    }

    let characterRange = NSRange(location: visualLineStart, length: targetOffset - visualLineStart)
    if characterRange.length > 0 {
      let linePrefix = textStorage.attributedSubstring(from: characterRange)
      let measuredWidth = linePrefix.boundingRect(
        with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      ).width
      let computedX = visualLineLeftX + measuredWidth
      if computedX.isFinite {
        return computedX
      }
    }

    let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
    let computedX = textContainerInset.left + textContainer.lineFragmentPadding + glyphLocation.x
    if computedX.isFinite {
      return computedX
    }

    return fallbackX <= textContainerInset.left + textContainer.lineFragmentPadding ? lineStartX : fallbackX
  }

  private static func lineStartLocation(containing cursorLocation: Int, text: NSString) -> Int {
    guard cursorLocation > 0 else { return 0 }
    var location = min(cursorLocation, text.length)
    while location > 0 {
      let previous = text.character(at: location - 1)
      if isLineBoundary(previous) {
        return location
      }
      location -= 1
    }
    return 0
  }

  private static func caretAttributeLocation(for cursorLocation: Int, text: NSString) -> Int? {
    let textLength = text.length
    guard textLength > 0 else { return nil }
    if cursorLocation < textLength {
      let characterLocation = max(cursorLocation, 0)
      if cursorLocation > 0, isLineBoundary(text.character(at: characterLocation)) {
        return cursorLocation - 1
      }
      return characterLocation
    }
    return textLength - 1
  }

  private static func isLineBoundary(_ character: unichar) -> Bool {
    character == 0x000A || character == 0x2028 || character == 0x2029
  }

  private static func verticallyCenter(_ rect: CGRect, in defaultRect: CGRect, minimumY: CGFloat) -> CGRect {
    var rect = rect
    rect.origin.y = defaultRect.midY - rect.height / 2
    rect.origin.y = max(rect.origin.y, minimumY)
    return rect
  }
}

private class TextViewDelegate: NSObject, UITextViewDelegate {
  public func textViewDidChangeSelection(_ textView: UITextView) {
    guard let textView = textView as? TextView else { return }

    if textView.isUpdatingNativeSelection {
      return
    }

    if let interception = textView.interceptNextSelectionChangeAndReplaceWithRange {
      textView.interceptNextSelectionChangeAndReplaceWithRange = nil
      textView.selectedRange = interception
      return
    }

    onSelectionChange(editor: textView.editor)
    textView.syncTypingAttributesFromCaret()
  }

  public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    guard let textView = textView as? TextView else { return false }

    textView.hidePlaceholderLabel()
    if let lexicalDelegate = textView.lexicalDelegate {
      return lexicalDelegate.textViewShouldChangeText(textView, range: range, replacementText: text)
    }

    return true
  }

  public func textViewDidBeginEditing(_ textView: UITextView) {
    guard let textView = textView as? TextView else { return }
    textView.lexicalDelegate?.textViewDidBeginEditing(textView: textView)
  }

  public func textViewDidEndEditing(_ textView: UITextView) {
    guard let textView = textView as? TextView else { return }
    textView.lexicalDelegate?.textViewDidEndEditing(textView: textView)
  }

  @available(iOS, deprecated: 17.0, message: "Use textView(_:primaryActionFor:defaultAction:) with UITextItem instead")
  public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
    guard let textView = textView as? TextView else { return false }

    let nativeSelection = NativeSelection(range: characterRange, affinity: .backward)
    try? textView.editor.update {
      guard let selection = try getSelection() as? RangeSelection else {
        // TODO: cope with non range selections. Should just make a range selection here
        return
      }
      try selection.applyNativeSelection(nativeSelection)
    }
    let handledByLexical = textView.editor.dispatchCommand(type: .linkTapped, payload: URL)

    if handledByLexical {
      return false
    }

    if !textView.isEditable {
      return true
    }

    return textView.lexicalDelegate?.textView(textView, shouldInteractWith: URL, in: characterRange, interaction: interaction) ?? false
  }
}
