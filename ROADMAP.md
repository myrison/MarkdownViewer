# Markdown Viewer Roadmap

## Priority Features

### ~~1. Copy-to-Clipboard Button on Code Blocks~~ ✅
**Appeal:** Very High | **Complexity:** Very Low

~~GitHub made this the expected behavior — a small clipboard icon that appears on hover over fenced code blocks. Developers copy code snippets constantly, and having to manually select text in a code block is friction everyone notices. Implementation is ~30 lines of JS/CSS injected into the existing HTML template to add a button on each `<pre><code>` block.~~

### 2. PDF / Print Export
**Appeal:** Very High | **Complexity:** Low–Medium

The #1 reason people open a markdown viewer is to produce a shareable artifact. `WKWebView` supports native macOS printing, which gives us both Print (Cmd+P) and "Save as PDF" essentially for free. A dedicated "Export PDF" option with better control over margins/headers would take slightly more work but `NSPrintOperation` handles most of it. Nearly every competitor has this.

### 3. Math/LaTeX Rendering (KaTeX)
**Appeal:** High | **Complexity:** Medium

Near-universal across competitors (Typora, Obsidian, MacDown, GitHub, iA Writer all support it). Any markdown file with `$E=mc^2$` or `$$\sum_{i=1}^{n}$$` currently renders as raw text. Implementation involves bundling KaTeX JS/CSS (~300KB), adding a small pre-processing step to identify `$...$` and `$$...$$` delimiters, and calling `katex.renderToString()`.

### 4. Document Statistics (Word Count, Reading Time)
**Appeal:** Medium–High | **Complexity:** Very Low

A subtle but universally appreciated feature — word count, character count, and estimated reading time displayed in a status bar or footer. Marked 2, Typora, iA Writer, and MarkView all have this. Implementation is trivial: a JS function that counts words in the rendered text content, divides by ~250 WPM for reading time, and displays it in a fixed-position footer or a native SwiftUI status bar below the WebView.

### ~~5. GitHub-Style Alerts / Callouts~~ ✅
**Appeal:** Medium–High (growing) | **Complexity:** Medium

~~The `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`, `> [!CAUTION]` syntax is increasingly standard — GitHub adopted it, Obsidian has callouts, and more README files use them every day. Currently these render as plain blockquotes, losing their visual meaning. Implementation requires post-processing blockquotes in the rendered HTML or extending the `MarkupWalker` to emit styled HTML for these patterns.~~

---

## Future Considerations

Lower priority items that may be worth revisiting later. Not on the immediate roadmap.

| Feature | Appeal | Complexity | Notes |
|---------|--------|------------|-------|
| Heading permalinks (hover link icon) | Medium | Very Low | Nice-to-have, not a gap users notice |
| Footnote support | Medium | Medium | Less commonly used in practice |
| Custom CSS / theme picker | Medium | Medium | Already have light/dark; full theming is more niche |
| Source view toggle (raw markdown) | Medium | Low | Useful but niche for a viewer-only app |
| Collapsible sections | Medium | Medium | Less standard, `<details>` HTML already works |
