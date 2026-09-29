# The input surface: the pointer and the keyboard at page level, plus the
# locator actions that are one generated wire call each.
#
# The generated channel layer already speaks the whole input protocol; what was
# missing was names. These are deliberately thin — a wrapper adds the timeout
# cascade, the locator's own selector and strictness, and nothing else — so that
# a reader can see the whole call on one screen.
#
# The split mirrors Playwright's own. `mouse_*!` and `keyboard_*!` address page
# coordinates and a global key queue, and are what a canvas needs: a drag is
# move, down, move…, up, with the intermediate moves the app's `mousemove`
# handler reads. The locator actions re-resolve a selector in the browser on
# every call and run the driver's actionability checks, which is what makes
# `click!` and `hover!` wait for the right moment.

# --- Shared argument shapes ------------------------------------------------

# `position` reaches the wire as the protocol's `{x, y}` object, and `to_wire`
# already knows how to encode a Dict. A `NamedTuple` is the spelling a caller
# is most likely to reach for, and a 2-tuple is the one they will reach for
# next, so both are normalised here rather than documented as a Dict.
position_dict(::Nothing) = nothing
position_dict(p::AbstractDict) = p
position_dict(p::Tuple{<:Real,<:Real}) = Dict{String,Any}("x" => p[1], "y" => p[2])

function position_dict(p::NamedTuple)
    (haskey(p, :x) && haskey(p, :y)) ||
        throw(ArgumentError("a position needs `x` and `y`, got $(keys(p))"))
    return Dict{String,Any}("x" => p.x, "y" => p.y)
end

# --- Page: the mouse -------------------------------------------------------

"""
    mouse_move!(page::Page, x, y; steps=nothing)

Move the mouse to `(x, y)`, in CSS pixels from the top-left of the page's
viewport.

`steps` splits the move into that many intermediate `mousemove` events. Omit it
for a single jump to the destination; set it when the page tracks positions, as
a canvas painting or drag handler does — a single move fires one event at the
end and the intermediate path is never seen.

```julia
mouse_move!(page, 100, 100)              # one event at (100, 100)
mouse_move!(page, 200, 150; steps = 10)  # ten events along the way
```

See [`mouse_down!`](@ref) and [`mouse_up!`](@ref) for the buttons, and
[`drag!`](@ref) when the target is an element rather than a coordinate.
"""
mouse_move!(page::Page, x::Real, y::Real; steps::Union{Real,Nothing} = nothing) =
    _page_mouse_move(page; x, y, steps)

"""
    mouse_down!(page::Page; button="left", click_count=nothing)

Press `button` — `"left"`, `"right"` or `"middle"` — and leave it held. Pair
with [`mouse_move!`](@ref) and [`mouse_up!`](@ref) to express a drag at page
coordinates.

`click_count` is the click number the page sees in the event's `detail`; leave
it `nothing` unless a handler distinguishes a double-click's second press.

```julia
mouse_move!(page, 100, 100)
mouse_down!(page; button = "right")
mouse_move!(page, 200, 150; steps = 10)
mouse_up!(page; button = "right")
```

A button left down leaks into every later action on the page, exactly as it
would for a real user, so the release is not optional.
"""
mouse_down!(
    page::Page;
    button::Union{AbstractString,Nothing} = "left",
    click_count::Union{Real,Nothing} = nothing,
) = _page_mouse_down(page; button, clickCount = click_count)

"""
    mouse_up!(page::Page; button="left", click_count=nothing)

Release a button held by [`mouse_down!`](@ref). See that function for the
button names and the `click_count` meaning.
"""
mouse_up!(
    page::Page;
    button::Union{AbstractString,Nothing} = "left",
    click_count::Union{Real,Nothing} = nothing,
) = _page_mouse_up(page; button, clickCount = click_count)

"""
    mouse_click!(page::Page, x, y; button="left", click_count=nothing, delay=nothing)

Move the mouse to `(x, y)` and click there, in one gesture.

This is a raw click at page coordinates, not [`click!`](@ref) on a locator: no
selector is resolved and none of the actionability checks run, so whatever is
under the point receives the event — a canvas, a chart, an overlay. Use it when
the target has no selector worth naming, or when the click has to land at a
particular point inside an element larger than a click.

`delay` is the pause between press and release, in milliseconds.

```julia
mouse_click!(page, 400, 300)                       # a plain click
mouse_click!(page, 400, 300; button = "right")     # a context menu
```
"""
mouse_click!(
    page::Page,
    x::Real,
    y::Real;
    button::Union{AbstractString,Nothing} = "left",
    click_count::Union{Real,Nothing} = nothing,
    delay::Union{Real,Nothing} = nothing,
) = _page_mouse_click(page; x, y, button, clickCount = click_count, delay)

"""
    mouse_wheel!(page::Page, delta_x, delta_y)

Scroll by `(delta_x, delta_y)` pixels. Positive `delta_y` scrolls down, positive
`delta_x` scrolls right.

The wheel event goes to whatever is under the mouse's **current** position, so
move there first when a particular element should receive the scroll:

```julia
mouse_move!(page, 400, 300)   # over the plot
mouse_wheel!(page, 0, -500)   # zoom in, for an app that reads the wheel
```

For moving the document instead, [`scroll_into_view_if_needed!`](@ref) scrolls
an element into view.
"""
mouse_wheel!(page::Page, delta_x::Real, delta_y::Real) =
    _page_mouse_wheel(page; deltaX = delta_x, deltaY = delta_y)

# --- Page: the keyboard ----------------------------------------------------

"""
    keyboard_press!(page::Page, key; delay=nothing)

Press and release `key`: one key (`"a"`, `"Enter"`, `"ArrowLeft"`) or a chord
joined with `+` (`"Control+A"`, `"Shift+Tab"`).

The page's focused element receives it, so focus the target first — with
[`focus!`](@ref) on its locator, or a [`click!`](@ref). Without focus the key
reaches the document, which is right for a global shortcut and wrong for a
field.

`delay` pauses between the press and the release, in milliseconds.

```julia
keyboard_press!(page, "Control+A")
keyboard_press!(page, "Backspace")     # ...and the field is cleared
```
"""
keyboard_press!(page::Page, key::AbstractString; delay::Union{Real,Nothing} = nothing) =
    _page_keyboard_press(page; key = String(key), delay)

"""
    keyboard_type!(page::Page, text; delay=nothing)

Type `text` one character at a time, each firing its own `keydown`, `keypress`
and `keyup`. `delay` is the pause between characters, in milliseconds.

Use this when the page listens for the keys themselves — a search box that
queries on every keystroke, a widget that reads `keydown`. To set a field's
value without any of that, use [`set_value!`](@ref) on its locator, which is
faster and fires a single `input` event.

```julia
keyboard_type!(page, "hello"; delay = 20)
```
"""
keyboard_type!(page::Page, text::AbstractString; delay::Union{Real,Nothing} = nothing) =
    _page_keyboard_type(page; text = String(text), delay)

"""
    keyboard_down!(page::Page, key)

Hold `key` down, for a chord that spans other calls. Pair it with
[`keyboard_up!`](@ref).

Modifier state is real and persists: a `Control` never released is still held
for the next action, which is the same trap a real keyboard sets.

```julia
keyboard_down!(page, "Shift")
mouse_click!(page, 100, 100)   # a shift-click
keyboard_up!(page, "Shift")
```

For a chord inside one call, [`keyboard_press!`](@ref) is shorter and cannot
leak.
"""
keyboard_down!(page::Page, key::AbstractString) =
    _page_keyboard_down(page; key = String(key))

"""
    keyboard_up!(page::Page, key)

Release a key held by [`keyboard_down!`](@ref).
"""
keyboard_up!(page::Page, key::AbstractString) = _page_keyboard_up(page; key = String(key))

"""
    keyboard_insert_text!(page::Page, text)

Insert `text` with no key events at all, as an input method or a paste would.
Only an `input` event fires.

This is the right verb for text that is not made of keystrokes — emoji, a
combining sequence, a whole word arriving at once. For per-key events use
[`keyboard_type!`](@ref); to set a field's value outright use
[`set_value!`](@ref).

```julia
keyboard_insert_text!(page, "🙂")
```
"""
keyboard_insert_text!(page::Page, text::AbstractString) =
    _page_keyboard_insert_text(page; text = String(text))

# --- Locator: the pointer and the keyboard ---------------------------------

"""
    hover!(loc::Locator; timeout=nothing)

Move the mouse over the matched element, waiting for it to be actionable first.

This is what fires the page's `:hover` CSS and its `mouseenter` handlers, so it
is how a tooltip is opened:

```julia
hover!(locator(page, "#chart"))
expect(locator(page, "#tooltip"); to_be_visible = true)
```

`timeout` covers the wait and defaults to the [`set_default_timeout!`](@ref)
cascade; an element that never becomes hoverable raises [`TimeoutError`](@ref).
"""
hover!(loc::Locator; timeout::MaybeTimeout = nothing) = _frame_hover(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    timeout = resolve_timeout(loc, timeout),
)

"""
    dblclick!(loc::Locator; timeout=nothing)

Double-click the matched element, waiting for it to be actionable first.

One gesture, not two [`click!`](@ref) calls: the two presses arrive close enough
together for the page to see a `dblclick`, which two separate calls cannot
guarantee.

```julia
dblclick!(locator(page, "#row-3"))
```
"""
dblclick!(loc::Locator; timeout::MaybeTimeout = nothing) = _frame_dblclick(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    timeout = resolve_timeout(loc, timeout),
)

"""
    drag!(source::Locator, target; timeout=nothing, source_position=nothing,
          target_position=nothing, steps=nothing, force=nothing)

Drag `source` onto `target` with the mouse, performing the HTML5
drag-and-drop handshake the page's `dragstart`/`drop` handlers expect.

`target` is a [`Locator`](@ref) in the same frame, or a selector string for one.
`source_position` and `target_position` are `(x, y)` offsets inside each
element, given as a `NamedTuple` or a `Dict`; `steps` splits the move into
intermediate events.

```julia
drag!(locator(page, "#card"), locator(page, "#lane-2"))
drag!(locator(page, "#slider"),
      "#track";
      source_position = (x = 5, y = 5),
      target_position = (x = 300, y = 5),
      steps = 20)
```

This is the element-to-element form. For a freehand drag at page coordinates —
a canvas brush stroke — press, move and release with
[`mouse_move!`](@ref), [`mouse_down!`](@ref) and [`mouse_up!`](@ref); the
intermediate moves are what a painting handler reads.
"""
function drag!(source::Locator, target::Locator; kwargs...)
    if frame(target) !== frame(source)
        throw(
            ArgumentError(
                "drag! needs source and target in the same frame; " *
                "`$(selector(source))` and `$(selector(target))` are in different " *
                "ones. Resolve both through the same page or frame.",
            ),
        )
    end
    return drag_and_drop!(source, target.selector; kwargs...)
end

drag!(source::Locator, target::AbstractString; kwargs...) =
    drag_and_drop!(source, String(target); kwargs...)

# The shared body. Target arrives as a selector string, already checked to be
# in `source`'s frame when it came in as a Locator.
function drag_and_drop!(
    source::Locator,
    target::AbstractString;
    timeout::MaybeTimeout = nothing,
    source_position = nothing,
    target_position = nothing,
    steps::Union{Real,Nothing} = nothing,
    force::Union{Bool,Nothing} = nothing,
)
    return _frame_drag_and_drop(
        source.frame;
        source = source.selector,
        target = target,
        strict = source.strict,
        timeout = resolve_timeout(source, timeout),
        sourcePosition = position_dict(source_position),
        targetPosition = position_dict(target_position),
        steps,
        force,
    )
end

"""
    focus!(loc::Locator; timeout=nothing)

Give the matched element keyboard focus, scrolling it into view first.

A later [`keyboard_press!`](@ref) or [`keyboard_type!`](@ref) goes to whatever
is focused, so this is how a page-level key is aimed at a field:

```julia
focus!(locator(page, "#search"))
keyboard_type!(page, "makie")
```
"""
focus!(loc::Locator; timeout::MaybeTimeout = nothing) = _frame_focus(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    timeout = resolve_timeout(loc, timeout),
)

"""
    press!(loc::Locator, key; timeout=nothing, delay=nothing)

Focus the matched element, then press `key` — one key or a `+`-joined chord, as
[`keyboard_press!`](@ref) takes. `delay` pauses between press and release, in
milliseconds.

This is the element-scoped form of [`keyboard_press!`](@ref): it saves the
[`focus!`](@ref) call and re-resolves the selector with the driver's
actionability wait.

```julia
press!(locator(page, "#search"), "Enter")
press!(locator(page, "#editor"), "Control+A")
```
"""
press!(
    loc::Locator,
    key::AbstractString;
    timeout::MaybeTimeout = nothing,
    delay::Union{Real,Nothing} = nothing,
) = _frame_press(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    key = String(key),
    delay,
    timeout = resolve_timeout(loc, timeout),
)

"""
    type!(loc::Locator, text; timeout=nothing, delay=nothing)

Type `text` into the matched element one character at a time, focusing it first.
`delay` pauses between characters, in milliseconds.

The element-scoped form of [`keyboard_type!`](@ref), for a field whose listeners
need the individual keys. To set the value outright, prefer
[`set_value!`](@ref), which is one event and no per-key waiting.

```julia
type!(locator(page, "#search"), "julia"; delay = 20)
```
"""
type!(
    loc::Locator,
    text::AbstractString;
    timeout::MaybeTimeout = nothing,
    delay::Union{Real,Nothing} = nothing,
) = _frame_type(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    text = String(text),
    delay,
    timeout = resolve_timeout(loc, timeout),
)

"""
    check!(loc::Locator; timeout=nothing)

Check the matched checkbox or radio input, waiting for it to be actionable
first. Checking an already-checked box is a no-op, not an error.

```julia
check!(locator(page, "#terms"))
is_checked(locator(page, "#terms"))   # true
```

The assertion form is `expect(loc; to_be_checked = true)` — see
[`expect`](@ref).
"""
check!(loc::Locator; timeout::MaybeTimeout = nothing) = _frame_check(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    timeout = resolve_timeout(loc, timeout),
)

"""
    uncheck!(loc::Locator; timeout=nothing)

Clear the matched checkbox, waiting for it to be actionable first. The inverse
of [`check!`](@ref); unchecking a box that is already clear is a no-op.
"""
uncheck!(loc::Locator; timeout::MaybeTimeout = nothing) = _frame_uncheck(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    timeout = resolve_timeout(loc, timeout),
)

"""
    select_option!(loc::Locator, values...; timeout=nothing) -> Vector{String}

Select options in the matched `<select>`, matching each given value against an
option's value **or** its visible label, as a user clicking it would. Returns
the values that ended up selected.

```julia
select_option!(locator(page, "#size"), "Large")          # by label
select_option!(locator(page, "#size"), "l")              # by value
select_option!(locator(page, "#pick"), "a", "c")         # a multi-select
select_option!(locator(page, "#pick"))                   # clear it
```

To be unambiguous about which of value, label or index you mean, pass a
`NamedTuple` or `Dict` with one of those keys:

```julia
select_option!(locator(page, "#size"), (label = "Large",))
select_option!(locator(page, "#size"), (index = 2,))
```

The element-scoped equivalent of assigning to `.value` plus dispatching a
`change`; unlike [`set_value!`](@ref), it runs the driver's actionability checks
and fires the events a real selection does.
"""
function select_option!(loc::Locator, values...; timeout::MaybeTimeout = nothing)
    options = [select_option_spec(value) for value in values]
    selected = _frame_select_option(
        loc.frame;
        selector = loc.selector,
        strict = loc.strict,
        timeout = resolve_timeout(loc, timeout),
        options,
    )
    return selected === nothing ? String[] : String[String(value) for value in selected]
end

# A bare string matches an option by value or label, which is Playwright's
# `valueOrLabel`. A NamedTuple or Dict passes its keys straight through, which
# is how a caller says `index` or disambiguates a value from a label.
select_option_spec(value::AbstractString) =
    Dict{String,Any}("valueOrLabel" => String(value))
select_option_spec(value::AbstractDict) =
    Dict{String,Any}(String(key) => item for (key, item) in value)
select_option_spec(value::NamedTuple) =
    Dict{String,Any}(String(key) => item for (key, item) in pairs(value))

"""
    tap!(loc::Locator; timeout=nothing)

Tap the matched element with a touch, waiting for it to be actionable first.

Touch is a property of the context, not the call: the page has to have been
created under one built `has_touch = true`, or the driver rejects the tap.
```julia
ctx = new_context(browser; has_touch = true)
tap!(locator(new_page(ctx), "#button"))
```
"""
tap!(loc::Locator; timeout::MaybeTimeout = nothing) = _frame_tap(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    timeout = resolve_timeout(loc, timeout),
)

"""
    blur!(loc::Locator; timeout=nothing)

Remove keyboard focus from the matched element, firing its `blur` handler.

```julia
focus!(locator(page, "#name"))
blur!(locator(page, "#name"))
```
"""
blur!(loc::Locator; timeout::MaybeTimeout = nothing) = _frame_blur(
    loc.frame;
    selector = loc.selector,
    strict = loc.strict,
    timeout = resolve_timeout(loc, timeout),
)

"""
    scroll_into_view_if_needed!(loc::Locator; timeout=nothing)

Scroll the matched element into view, if it is not already there.

It stops as soon as the element is visible rather than aligning it to the top or
the centre, so it is a precondition for a later action rather than a way to pose
the page.

```julia
scroll_into_view_if_needed!(locator(page, "#footer"))
```

The protocol exposes this on `ElementHandle` rather than on `Frame`, so this
waits for the element to be attached, then scrolls the handle. `timeout` bounds
each half.
"""
function scroll_into_view_if_needed!(loc::Locator; timeout::MaybeTimeout = nothing)
    resolved = resolve_timeout(loc, timeout)
    handle = wait_for_selector(loc; timeout = resolved)
    handle === nothing ||
        _element_handle_scroll_into_view_if_needed(handle; timeout = resolved)
    return nothing
end
