# Frames and iframes

An `<iframe>` has its own document. A locator created from the page cannot
find elements inside it. Use [`frame_locator`](@ref) to cross the boundary,
then [`locator`](@ref) to select an element in that document.

The examples below assume `page` has loaded a checkout page with this frame
structure:

```html
<!-- Main document -->
<iframe id="checkout" name="checkout" src="/checkout-frame"></iframe>

<!-- /checkout-frame -->
<button id="pay">Pay</button>
<iframe id="receipt" name="receipt" src="/receipt-frame"></iframe>

<!-- /receipt-frame -->
<p id="status">Ready</p>
```

## Locate elements inside a frame

```julia
checkout = frame_locator(page, "iframe#checkout")
click!(locator(checkout, "#pay"))

# The second iframe is inside the first, so cross both boundaries.
receipt = frame_locator(checkout, "iframe#receipt")
status = locator(receipt, "#status")
expect(status; to_have_text = "Ready")
```

A `FrameLocator` and the locator made from it are lazy: constructing
them does not search the page or require the iframe to have loaded. Each
action or assertion resolves the selector chain when it runs. The `expect`
above waits for the receipt content, including when it appears after the
iframe loads. For a visible element without a known final text, use
`expect(status; to_be_visible = true)` instead.

## Resolve a frame for evaluation

Use [`content_frame`](@ref) when you need a [`Frame`](@ref) object. It resolves
the iframe element immediately, so wait for content first if the iframe may
not exist yet:

```julia
expect(status; to_have_text = "Ready")
checkout_frame = content_frame(checkout)
receipt_frame = content_frame(receipt)

evaluate(receipt_frame, "document.querySelector('#status').textContent")
content_frame(locator(page, "iframe#checkout")) === checkout_frame  # true
```

`evaluate` runs in the resolved frame's document. `content_frame` also accepts
a locator for an `<iframe>` element. Unlike a frame-scoped locator, a resolved
`Frame` represents one specific frame; resolve it again after the iframe is
replaced. `content_frame` raises if its selector finds no iframe.

## Inspect the frame tree

[`frames`](@ref) returns the page's main frame first, then descendant frames
in breadth-first order. Use [`parent_frame`](@ref) to establish relationships;
do not rely on the positions of sibling frames. [`frame_name`](@ref) reads the
iframe's `name` attribute, and [`url`](@ref) reads its current URL.

```julia
expect(status; to_have_text = "Ready")
all_frames = frames(page)
main = all_frames[1]
checkout_frame = content_frame(checkout)
receipt_frame = content_frame(receipt)

@assert parent_frame(main) === nothing
@assert parent_frame(checkout_frame) === main
@assert parent_frame(receipt_frame) === checkout_frame
@assert frame_name(checkout_frame) == "checkout"
@assert frame_name(receipt_frame) == "receipt"

for frame in all_frames
    println("name=$(frame_name(frame)), url=$(url(frame))")
end
```

`frames(page)` is a snapshot of the current tree. Call it again after frames
are added or removed. A frame's URL can change as it navigates; wait for the
content you need before reading it.

See [Locators](@ref) for selector behavior and [Waiting](@ref) for other
readiness checks.
