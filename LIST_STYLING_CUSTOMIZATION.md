# List Styling Customization

This fork includes improved list styling with customizable margins and spacing.

## New Theme Properties

The `Theme` class now includes three new properties for customizing list appearance:

### `listBulletMargin: Double`
- **Default**: `16.0` points
- **Description**: The left margin for list bullets
- **Effect**: Controls how far bullets are positioned from the left edge

### `listBulletTextSpacing: Double`
- **Default**: `20.0` points  
- **Description**: The spacing between bullets and text
- **Effect**: Controls the gap between the bullet character and the text content

### `indentSize: Double` (existing)
- **Default**: `40.0` points
- **Description**: The width of each indentation level
- **Effect**: Controls how much each nested level is indented

## Usage Example

```swift
let theme = Theme()

// Customize list appearance
theme.listBulletMargin = 20.0        // More left margin
theme.listBulletTextSpacing = 24.0   // More space between bullet and text
theme.indentSize = 32.0              // Smaller indent levels

// Apply theme to editor
editor.setTheme(theme)
```

## Visual Layout

```
[listBulletMargin] • [listBulletTextSpacing] Text content
[listBulletMargin + indentSize] • [listBulletTextSpacing] Nested item
```

For example, with default values:
- Bullet position: 16pt from left
- Text position: 36pt from left (16 + 20)
- Nested bullet: 56pt from left (16 + 40)
- Nested text: 76pt from left (16 + 40 + 20)

## Migration from Original

The original implementation positioned bullets very close to the left edge with inconsistent spacing. This update provides:

1. **Better visual balance** with proper left margins
2. **Consistent spacing** between bullets and text
3. **Full customization** via theme properties
4. **Backward compatibility** with existing code

## Technical Details

The changes are implemented in:
- `Theme.swift`: Added new properties
- `ListItemNode.swift`: Updated bullet positioning and text padding calculations

The bullet position is calculated as:
```swift
bulletPosition = theme.listBulletMargin + (indentLevel * theme.indentSize)
```

The text padding is calculated as:
```swift
textPadding = theme.listBulletMargin + theme.listBulletTextSpacing + (indentLevel * theme.indentSize)
```