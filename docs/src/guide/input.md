# Input actions

Use a [`Locator`](@ref) when the page has an element you can name. Use page
keyboard and mouse calls when the interaction depends on focus or coordinates,
such as a shortcut or a canvas gesture. See [Locators](@ref) for selectors and
[Waiting](@ref) for waits and timeouts.

| Task | Call |
|---|---|
| Replace a text field's value | [`set_value!`](@ref) |
| Send individual keys to a field | [`type!`](@ref), [`press!`](@ref) |
| Check or clear a checkbox | [`check!`](@ref), [`uncheck!`](@ref) |
| Choose from a `<select>` | [`select_option!`](@ref) |
| Focus or hover over an element | [`focus!`](@ref), [`hover!`](@ref) |
| Click or double-click an element | [`click!`](@ref), [`dblclick!`](@ref) |
| Send a shortcut to the focused element | [`keyboard_press!`](@ref) |
| Click, drag or scroll at page coordinates | [`mouse_click!`](@ref), [`mouse_move!`](@ref), [`mouse_down!`](@ref), [`mouse_up!`](@ref), [`mouse_wheel!`](@ref) |
| Drag one element onto another | [`drag!`](@ref) |
| Tap an element in a touch context | [`tap!`](@ref) |

## Fill a form

This example is a complete script. The `data:` page keeps the form local, so
you can run it after installing the browser as described in
[Getting started](@ref). In an application test, replace `goto!` with your
application URL and use its selectors.

```julia
using Playwright
using Base64

html = """
<input id="name" placeholder="Name">
<input id="terms" type="checkbox">
<select id="size"><option value="s">Small</option><option value="l">Large</option></select>
<button id="submit" onclick="document.querySelector('#result').textContent =
    document.querySelector('#name').value">Submit</button>
<output id="result"></output>
"""

playwright() do pw
    browser = launch(pw.chromium; headless = true)
    try
        page = new_page(browser)
        goto!(page, "data:text/html;base64," * base64encode(html))

        set_value!(locator(page, "#name"), "Ada")
        check!(locator(page, "#terms"))
        select_option!(locator(page, "#size"), (label = "Large",))
        click!(locator(page, "#submit"))
        expect(locator(page, "#result"); to_have_text = "Ada")
    finally
        close!(browser)
    end
end
```

[`set_value!`](@ref) replaces the whole value and fires an `input` event. Use
[`type!`](@ref) when the application responds to each keystroke, and
[`press!`](@ref) for a key or chord aimed at a particular element:

```julia
set_value!(locator(page, "#name"), "")
type!(locator(page, "#name"), "Ada"; delay = 20)  # individual key events
press!(locator(page, "#name"), "Enter")
uncheck!(locator(page, "#terms"))
```

The last block uses `page` from the form example and can be placed before its
`finally`. A bare string passed to [`select_option!`](@ref) matches an option
value or visible label; `(label = "Large",)` specifies the label explicitly.
For file inputs, see [Files, dialogs and uploads](@ref).

## Shortcuts and pointer gestures

Page keyboard calls go to the element that currently has focus. The following
block can also be placed before `finally` in the form example:

```julia
focus!(locator(page, "#name"))
keyboard_press!(page, "Control+A")
keyboard_type!(page, "Grace")
expect(locator(page, "#name"); to_have_value = "Grace")

hover!(locator(page, "#submit"))
mouse_click!(page, 10, 10)               # CSS pixels from the viewport's top left
mouse_move!(page, 100, 100)
mouse_down!(page)
mouse_move!(page, 200, 150; steps = 20) # intermediate mousemove events
mouse_up!(page)
mouse_move!(page, 200, 150)
mouse_wheel!(page, 0, 300)              # wheel goes to the current pointer position
```

For application shortcuts, focus the intended target first and pass the chord
to [`keyboard_press!`](@ref), for example `"Control+S"`. For a modified click,
hold and release the modifier with [`keyboard_down!`](@ref) and
[`keyboard_up!`](@ref). Coordinate calls do not resolve a selector or wait for
an element to become actionable. When there is an element to target, prefer its
locator; [`drag!`](@ref) handles an element-to-element HTML5 drag:

```julia
drag!(locator(page, "#card"), locator(page, "#lane-2"))
```

## Touch

Create the context with `has_touch = true` **before** creating the page. Then
[`tap!`](@ref) can act on a locator:

```julia
playwright() do pw
    browser = launch(pw.chromium; headless = true)
    try
        ctx = new_context(browser; has_touch = true)
        page = new_page(ctx)
        goto!(page, "data:text/html,<button id=touch>Tap me</button>")
        tap!(locator(page, "#touch"))
    finally
        close!(browser)
    end
end
```

Actionability checks vary by action. For example, [`click!`](@ref) waits for
visibility, stability and the ability to receive pointer events, while
[`focus!`](@ref) and [`select_option!`](@ref) have their own conditions. See the
individual API entries and [Waiting](@ref) when an action times out.
