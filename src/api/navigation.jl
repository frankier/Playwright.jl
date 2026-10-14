# Navigation and page-level capture.

"""
    goto!(page::Page, url; timeout=nothing, wait_until="load") -> Union{Response,Nothing}

Navigate `page` to `url` and wait for the navigation to finish.

`wait_until` decides *what* counts as finished, cheapest first:

| `wait_until` | Returns once |
|---|---|
| `"commit"` | the response headers are in and navigation is committed |
| `"domcontentloaded"` | the `DOMContentLoaded` event fired |
| `"load"` (default) | the `load` event fired — subresources included |
| `"networkidle"` | the network has been quiet for 500ms |

`"networkidle"` is tempting and usually the wrong choice: on a page that polls,
it never arrives. Prefer the default and then assert on what you actually need
with [`expect`](@ref), which waits for that one thing rather than for the whole
page to go quiet.

```julia
goto!(page, "http://127.0.0.1:8000/")
expect(page; to_have_title = "Home")
```

`timeout` defaults to the navigation timeout in force for `page` — see
[`set_default_navigation_timeout!`](@ref) — and running out of it raises
[`TimeoutError`](@ref).
"""
function goto!(
    page::Page,
    url::AbstractString;
    timeout::MaybeTimeout = nothing,
    wait_until::AbstractString = "load",
)
    return _frame_goto(
        main_frame(page);
        url,
        timeout = resolve_navigation_timeout(page, timeout),
        waitUntil = wait_until,
    )
end

"""
    title(page::Page) -> String

Title of the document currently loaded in `page`.

A read, taken now. The assertion form waits, and is what a test should use:

```julia
title(page)                                   # "Home"
expect(page; to_have_title = "Home")          # waits for it to become "Home"
```

See [`expect`](@ref). The URL equivalent is [`url`](@ref).
"""
title(page::Page) = _frame_title(main_frame(page))

"""
    screenshot(page::Page; path, timeout=nothing) -> String

Capture a PNG screenshot of `page`, write it to `path`, and return `path`.

```julia
screenshot(page; path = "artifacts/checkout.png")   # -> "artifacts/checkout.png"
```

`path` is required. For a screenshot you want in memory rather than on disk,
call [`screenshot_bytes`](@ref) — the name says which one you get, so neither
function has to return `Union{String,Vector{UInt8}}` depending on whether a
keyword was passed. That is the artifact family's rule: **if you named a
destination you get the destination back. If you want bytes you call the
function that says bytes.**

The viewport only. For one element, pass a [`Locator`](@ref) or
[`ElementHandle`](@ref) instead. `timeout` defaults to the action timeout in
force for `page` — see [`set_default_timeout!`](@ref). For a failing test,
[`with_page`](@ref) captures one automatically, and [`pdf`](@ref) is the
Chromium-only print equivalent.
"""
function screenshot(page::Page; path::AbstractString, timeout::MaybeTimeout = nothing)
    write(path, screenshot_bytes(page; timeout))
    return path
end

"""
    screenshot_bytes(page::Page; timeout=nothing) -> Vector{UInt8}

Capture a PNG screenshot of `page` and return its bytes, touching no
filesystem — for attaching to a report, hashing, or inspecting in memory.

```julia
bytes = screenshot_bytes(page)
bytes[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]   # a PNG
```

See [`screenshot`](@ref) for the write-to-disk form, which returns the path.
"""
screenshot_bytes(page::Page; timeout::MaybeTimeout = nothing) =
    _page_screenshot(page; timeout = resolve_timeout(page, timeout), type = "png")

"""
    screenshot(element::Union{Locator,ElementHandle}; path, kwargs...) -> String

Capture one element, write its image to `path`, and return `path`. See
[`screenshot_bytes`](@ref) for the available image options and an in-memory
result.
"""
function screenshot(element::Union{Locator,ElementHandle}; path::AbstractString, kwargs...)
    write(path, screenshot_bytes(element; kwargs...))
    return path
end

"""
    screenshot_bytes(element::Union{Locator,ElementHandle}; timeout=nothing,
                     animations=nothing, caret=nothing, mask=nothing,
                     mask_color=nothing, omit_background=nothing, type="png",
                     quality=nothing, scale=nothing, style=nothing) -> Vector{UInt8}

Capture just the matched element and return its image bytes. A `Locator` waits
for an attached match and resolves it on each call; an `ElementHandle` captures
the element it already references. The screenshot call waits for the element to
be visible and stable. `timeout` uses the action timeout for the element.

`type` is `"png"` or `"jpeg"`; `quality` applies to JPEG. `mask` is a vector of
locators whose matching elements are covered by `mask_color`. The remaining
options map to Playwright's element screenshot options.
"""
function screenshot_bytes(
    element::ElementHandle;
    timeout::MaybeTimeout = nothing,
    animations::Union{AbstractString,Nothing} = nothing,
    caret::Union{AbstractString,Nothing} = nothing,
    mask::Union{AbstractVector{<:Locator},Nothing} = nothing,
    mask_color::Union{AbstractString,Nothing} = nothing,
    omit_background::Union{Bool,Nothing} = nothing,
    type::AbstractString = "png",
    quality::Union{Real,Nothing} = nothing,
    scale::Union{AbstractString,Nothing} = nothing,
    style::Union{AbstractString,Nothing} = nothing,
)
    wire_mask = mask === nothing ? nothing :
                [Dict("frame" => loc.frame, "selector" => loc.selector) for loc in mask]
    return _element_handle_screenshot(
        element;
        timeout = resolve_timeout(element, timeout),
        animations,
        caret,
        mask = wire_mask,
        maskColor = mask_color,
        omitBackground = omit_background,
        type,
        quality,
        scale,
        style,
    )
end

function screenshot_bytes(loc::Locator; timeout::MaybeTimeout = nothing, kwargs...)
    resolved = resolve_timeout(loc, timeout)
    handle = wait_for_selector(loc; state = :attached, timeout = resolved)
    try
        return screenshot_bytes(handle; timeout = resolved, kwargs...)
    finally
        dispose!(handle)
    end
end
