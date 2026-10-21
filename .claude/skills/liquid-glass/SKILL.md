---
name: liquid-glass
description: Implement Liquid Glass with SwiftUI .glassEffect() and AppKit NSGlassEffectView on macOS 26+, with the material fallback Mito needs for its macOS 15 deployment target. Use when building or reviewing glass-based navigation UI.
source: rshankras/claude-code-apple-skills@9ffb831 skills/design/liquid-glass (MIT, adapted)
---

# Liquid Glass Design

Implement Apple's Liquid Glass design language in a macOS app. Covers SwiftUI (`.glassEffect()`) and AppKit (`NSGlassEffectView`).

## When This Skill Activates

- User wants glass/blur effects on views
- User asks about Liquid Glass or modern Apple design
- User needs transparent, interactive UI elements
- User wants morphing transitions between views

## Design Rules (WWDC25)

Liquid Glass is the material of the **navigation layer** — bars, toolbars, floating controls — never the content layer (tables, lists, rows in a scroll view).

| Rule | Detail |
|------|--------|
| **Never glass on glass** | Don't stack glass. Elements sitting ON glass don't get the material again — style them with fills and vibrancy. |
| **Two variants — never mix them** | **Regular** (default): works at any size, over anything, with adaptive legibility. **Clear**: only when ALL three hold — media-rich content underneath, a dimming layer is acceptable, and bold bright content sits above. Clear has no adaptive behaviors. One variant per interface. |
| **Tint only primary actions** | "When every element is tinted, nothing stands out." |
| **No steady-state intersections** | In resting layouts, content shouldn't sit half-under a glass element — reposition or scale the content instead. |
| **Strip decorated bars** | Remove customized bar backgrounds and borders; build hierarchy through layout and grouping, not decoration. Never group a symbol with a text label in one toolbar group. Action sheets spring from their source element. |

**Scroll edge effects** keep floating elements separated from scrolling content: soft (gradual fade) vs hard (denser, with a dividing line — the usual macOS choice for dense UI). One per view edge, and they're not decorative — don't add one where no floating UI elements exist.

**Shape system** — let containers do the math:

| Shape | Radius | Use |
|-------|--------|-----|
| Fixed | Constant | Standalone elements |
| Capsule | Half the element height | Buttons and compact controls |
| Concentric | Parent radius minus padding | Nested containers (inner radii auto-calculate); elements concentric with the window edge |

**Accessibility comes free at the system level**: Reduced Motion decreases lensing and elastic effects; Increased Contrast renders glass elements black/white with a contrasting border. (Lensing is how glass appears — it materializes by modulating how it bends light, and adaptive shadows flip small elements light/dark for legibility over any content.)

## Mito: Availability Fallback (required)

Mito deploys to macOS 15; every glass API here is macOS 26+. Each glass call sits behind `if #available(macOS 26, *)`, and the fallback is a material in the same shape — never a missing background:

```swift
extension View {
    @ViewBuilder
    func navigationGlass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

Text("Champ select")
    .padding()
    .navigationGlass(in: .capsule)
```

The same rule covers the other glass APIs: `.buttonStyle(.glass)` falls back to `.bordered`, `GlassEffectContainer` falls back to its plain content, `NSGlassEffectView` falls back to `NSVisualEffectView`. The examples below show only the macOS 26 branch.

## Quick Start (SwiftUI)

### Basic Glass Effect

```swift
import SwiftUI

Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()  // Capsule shape by default
```

### Custom Shape

```swift
Text("Hello")
    .padding()
    .glassEffect(in: .rect(cornerRadius: 16))

// Available shapes:
// .capsule (default)
// .rect(cornerRadius: CGFloat)
// .rect(corners: .concentric) or ConcentricRectangle() — radius derived from the container, keeps nested shapes concentric
// .circle
```

### Interactive Glass

```swift
Button("Click Me") {
    // action
}
.padding()
.glassEffect(.regular.interactive())
```

### Tinted Glass

```swift
Text("Important")
    .padding()
    .glassEffect(.regular.tint(.blue))
```

## Glass Configuration Options

| Option | Description | Example |
|--------|-------------|---------|
| `.regular` | Standard glass effect | `.glassEffect(.regular)` |
| `.clear` | Clear variant (see Design Rules) | `.glassEffect(.clear)` |
| `.identity` | No effect; toggle glass without changing identity | `.glassEffect(isOn ? .regular : .identity)` |
| `.tint(Color)` | Add color tint | `.glassEffect(.regular.tint(.orange))` |
| `.interactive()` | Scale, bounce, and shimmer on hover/click | `.glassEffect(.regular.interactive())` |

## Multiple Glass Effects

### GlassEffectContainer

When using multiple glass elements, wrap them in `GlassEffectContainer` for:
- Better rendering performance
- Proper blending between effects
- Morphing transitions

This is correctness, not just performance: glass can not sample other glass, so nearby glass elements must share ONE container to render and blend correctly.

```swift
GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "star.fill")
            .frame(width: 80, height: 80)
            .font(.system(size: 36))
            .glassEffect()

        Image(systemName: "heart.fill")
            .frame(width: 80, height: 80)
            .font(.system(size: 36))
            .glassEffect()
    }
}
```

**Spacing Parameter:**
- Controls when effects merge
- Smaller spacing = views must be closer to merge
- Larger spacing = effects merge at greater distances

### Uniting Glass Effects

Combine views into a single glass effect using `glassEffectUnion`:

```swift
@Namespace private var namespace

GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        ForEach(items.indices, id: \.self) { index in
            Image(systemName: items[index])
                .frame(width: 60, height: 60)
                .glassEffect()
                .glassEffectUnion(
                    id: index < 2 ? "group1" : "group2",
                    namespace: namespace
                )
        }
    }
}
```

## Morphing Transitions

Create fluid morphing effects when views appear/disappear.

### Setup

1. Create a namespace
2. Assign glass effect IDs
3. Use animations on state changes

```swift
struct MorphingToolbar: View {
    @State private var isExpanded = false
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 40.0) {
            HStack(spacing: 40.0) {
                // Always visible
                Image(systemName: "pencil")
                    .frame(width: 60, height: 60)
                    .glassEffect()
                    .glassEffectID("pencil", in: namespace)

                // Conditionally visible - will morph in/out
                if isExpanded {
                    Image(systemName: "eraser")
                        .frame(width: 60, height: 60)
                        .glassEffect()
                        .glassEffectID("eraser", in: namespace)

                    Image(systemName: "ruler")
                        .frame(width: 60, height: 60)
                        .glassEffect()
                        .glassEffectID("ruler", in: namespace)
                }
            }
        }

        Button("Toggle") {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .buttonStyle(.glass)
    }
}
```

## Button Styles

### Glass Button

```swift
Button("Standard") {
    // action
}
.buttonStyle(.glass)
```

### Glass Prominent Button

```swift
Button("Primary Action") {
    // action
}
.buttonStyle(.glassProminent)
```

## Advanced Techniques

### Background Extension

Extend a hero image beyond the safe area — the system mirrors and blurs it under bars and sidebars:

```swift
Image("hero")
    .backgroundExtensionEffect()
```

Or stretch content under sidebar or inspector:

```swift
NavigationSplitView {
    SidebarView()
} detail: {
    DetailView()
        .background {
            Image("wallpaper")
                .resizable()
                .ignoresSafeArea()
        }
}
```

### Toolbar Spacers

Split toolbar items into separate glass groups instead of customizing bar backgrounds:

```swift
.toolbar {
    ToolbarItem { editButton }
    ToolbarSpacer(.fixed)      // Visual break — starts a new glass group
    ToolbarItem { shareButton }
    ToolbarSpacer(.flexible)   // Pushes the following group apart
    ToolbarItem { doneButton }
}
```

### Scroll Edge Effect Style

```swift
ScrollView { content }
    .scrollEdgeEffectStyle(.hard, for: .top)  // Hard style for dense UI, mostly macOS
```

### Sheets

Remove custom `presentationBackground` modifiers — they interfere with the sheet's glass material and its morphing behavior.

## AppKit Implementation

### NSGlassEffectView

```swift
import AppKit

// Create glass effect view
let glassView = NSGlassEffectView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
glassView.cornerRadius = 16.0
glassView.tintColor = NSColor.systemBlue.withAlphaComponent(0.3)

// Create content
let label = NSTextField(labelWithString: "Glass Content")
label.translatesAutoresizingMaskIntoConstraints = false

// Set content view
glassView.contentView = label

// Constrain to the glass view: the label *is* the content view
NSLayoutConstraint.activate([
    label.centerXAnchor.constraint(equalTo: glassView.centerXAnchor),
    label.centerYAnchor.constraint(equalTo: glassView.centerYAnchor)
])
```

`style` picks `.regular` (default) or `.clear`. On macOS 27, set `effectIsInteractive = true` when the glass backs or contains interactive controls; macOS 26 has no equivalent, so leave the glass static there.

### NSGlassEffectContainerView

```swift
// Create container
let container = NSGlassEffectContainerView(frame: bounds)
container.spacing = 40.0

// Create content view
let contentView = NSView(frame: container.bounds)
container.contentView = contentView

// Add glass views to content
let glass1 = NSGlassEffectView(frame: NSRect(x: 20, y: 50, width: 150, height: 100))
let glass2 = NSGlassEffectView(frame: NSRect(x: 190, y: 50, width: 150, height: 100))

contentView.addSubview(glass1)
contentView.addSubview(glass2)
```

## Common Patterns

### Floating Action Bar

```swift
struct FloatingActionBar: View {
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 16) {
                ForEach(actions) { action in
                    Button {
                        action.perform()
                    } label: {
                        Image(systemName: action.icon)
                            .font(.title2)
                    }
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive())
                    .glassEffectID(action.id, in: namespace)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}
```

### Card with Glass Effect

For a card floating above content (e.g. overlaid on a map). Cards inside a scrolling list are content-layer — don't use glass there. Note the icon uses a fill, not a second `glassEffect`: elements on glass never get glass again.

```swift
struct GlassCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .frame(width: 50, height: 50)
                .background(.blue.opacity(0.15), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}
```

## Best Practices

1. **Use GlassEffectContainer** for multiple glass views
   - Improves rendering performance
   - Enables morphing transitions

2. **Apply glass effect last** in modifier chain
   - After frame, padding, and content modifiers

3. **Choose appropriate spacing** in containers
   - Controls when effects blend together

4. **Use animations** for state changes
   - Enables smooth morphing transitions

5. **Add interactivity** for clickable elements
   - `.interactive()` for buttons and controls

6. **Tint sparingly** — reserve tint for the primary action
   - See Design Rules: tinting everything makes nothing stand out

7. **Consistent shapes** across your app
   - Establish a shape language (all capsules, or all rounded rects)

## Checklist

### SwiftUI
- [ ] Every glass call behind `if #available(macOS 26, *)` with a `.regularMaterial` fallback
- [ ] Wrap multiple glass views in `GlassEffectContainer`
- [ ] Add `@Namespace` for morphing transitions
- [ ] Use `.glassEffectID()` on views that appear/disappear
- [ ] Add `.interactive()` for clickable elements
- [ ] Use `.buttonStyle(.glass)` for glass buttons
- [ ] Test animations for smooth morphing

### AppKit
- [ ] `NSGlassEffectView` behind `if #available(macOS 26, *)`, `NSVisualEffectView` otherwise
- [ ] Multiple glass views share one `NSGlassEffectContainerView`
- [ ] `effectIsInteractive` only behind `if #available(macOS 27, *)`

### General
- [ ] Glass only on the navigation layer — never on content (tables, lists)
- [ ] No glass stacked on glass; one variant (Regular or Clear) per interface
- [ ] Only the primary action is tinted
- [ ] Consider performance with many glass effects
- [ ] Support both light and dark appearances

## References

### SwiftUI
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)
- [SwiftUI GlassEffectContainer](https://developer.apple.com/documentation/SwiftUI/GlassEffectContainer)

### AppKit
- [AppKit NSGlassEffectView](https://developer.apple.com/documentation/AppKit/NSGlassEffectView)

