# Popover opened empty — ScrollView collapsed to zero height in `MenuBarExtra(.window)`

**Anchor:** `#popover-scroll-height` · **Date:** 2026-07-16 · **Area:** `PopoverView`

## Symptom

The popover opened showing only its header ("Usage · Updated just now") and footer
("Refresh"/"Quit") with an empty gap between them — no provider cards at all. The menu bar
label was simultaneously correct and live ("99%", "77%"), which made it look like a data
bug in the store.

It was not a data bug. The menu bar item's own accessibility label read
`Claude weekly, 99% left; Codex weekly, 77% left`, proving `providerOrder` was populated.
Measuring the live window settled it:

| Build | Popover size | Cards |
| --- | --- | --- |
| 1.0.9 (pre-multi-account) | 384 × **429** | yes |
| `main` @ `f4ed4b54` (post-#71) | 384 × **127** | no |

127pt is exactly header + footer + 19pt padding: **the card area contributed zero height.**
The visible gap measured ~40pt — the two 20pt `VStack` spacings with nothing between them.

## Root cause

PR #71 (multi-account) wrapped the card stack to cap tall multi-account popovers:

```swift
ScrollView(.vertical) { VStack(spacing: 20) { cards } }
    .frame(maxHeight: 640)
```

`MenuBarExtra(.window)` sizes its NSWindow to the content's **ideal** height, and a
`ScrollView` has no ideal height of its own — it's designed to accept whatever height is
proposed. Nothing proposes one here, so it resolved to ~0. `maxHeight:` did not save it:
it only sets a ceiling, never a floor.

## Fix

Measure the stack and pin an explicit height, keeping the cap as an upper bound:

```swift
@State private var cardsHeight: CGFloat = 0

ScrollView(.vertical) {
    VStack(spacing: 20) { cards }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardsHeight = $0 }
}
.frame(height: min(cardsHeight, 640))
```

Scroll content is laid out at its ideal height independent of the ScrollView's own frame, so
the measurement is correct on the first pass even while the frame is still zero — no feedback
loop, and the height then tracks content (verified 370pt with a 3-window stack, 429pt with 4).

## Why the tests and the harness both missed it

**This is the part worth remembering.** `PopoverRenderHarness` rendered a *perfect* popover,
cards and all — because `ImageRenderer` proposes a concrete size, so the ScrollView sizes
fine there. The bug exists **only in a real window**. The 228-test suite covers logic, not
layout, so it was green too.

Two green signals, one broken app. A layout regression in a self-sizing window is invisible to
both an offscreen renderer and a unit test — the only reliable check is the live window:

```bash
osascript -e 'tell application "System Events" to tell process "Headroom" \
  to click menu bar item 1 of menu bar 2'
osascript -e 'tell application "System Events" to tell process "Headroom" \
  to get {position, size} of window 1'
```

A popover measuring ~127pt tall is this bug; a healthy one tracks its content (≈370–640pt).
