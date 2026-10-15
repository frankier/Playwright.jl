# [Evaluating JavaScript](@id evaluation-guide)

[`evaluate`](@ref) runs JavaScript in the browser and copies its result back to
Julia. Use it to read page state that the locator and assertion APIs do not
expose. The JavaScript runs in the page's environment: it can read `window` and
`document`, but it cannot read Julia variables unless you pass them as an
argument.

```julia
# `page` is a Page opened by the surrounding test.
heading = evaluate(page, "document.querySelector('h1').textContent")
count = evaluate(page, "() => document.querySelectorAll('li').length")
```

The expression can be a JavaScript expression or a function. The driver
detects functions; use `is_function=true` or `false` only when you need to
override that detection. A returned JavaScript Promise is awaited before the
result is copied back:

```julia
status = evaluate(page, "async () => (await fetch('/status')).status")
```

## Pass values explicitly

Pass one Julia value as the third argument. For several values, put them in a
named tuple, tuple, vector or dictionary. A named tuple becomes a JavaScript
object, so its fields can be read by name:

```julia
threshold = 3
result = evaluate(page, "({limit, label}) => ({ok: limit > 2, label})",
                  (limit = threshold, label = "ready"))
# result == Dict("ok" => true, "label" => "ready")
```

The value is copied across the process boundary. Strings, numbers, booleans,
`nothing`/`missing` (JavaScript `null`/`undefined`), arrays, dictionaries,
named tuples, dates and regular expressions can be passed. Symbols become
strings. Results use Julia strings and booleans, `Float64` for JavaScript
numbers, `Vector{Any}` for arrays, and `Dict{String,Any}` for objects. For
example, `evaluate(page, "1 + 1")` returns `2.0`. JavaScript `null` returns
`nothing` and `undefined` returns `missing`.

Return a plain value from the expression when you need a copy. Some browser
values, such as DOM nodes and functions, cannot be converted to Julia; use a
[`JSHandle`](@ref) for those. BigInt, URL, typed arrays and Error objects are
also unsupported as copied results, so convert them in JavaScript first (for
example, `String(url)` or `Array.from(typedArray)`). See
[JavaScript handles](@ref) for retaining a browser value.

## Page, frame and locator

Page evaluation runs in its main frame. To run in an iframe, get a public
[`Frame`](@ref) through [`content_frame`](@ref):

```julia
child = content_frame(frame_locator(page, "iframe#details"))
child_title = evaluate(child, "document.title")
```

For one element, evaluate a [`Locator`](@ref). The matched element is the
function's **first** argument; an explicit value, if present, is the second:

```julia
field = locator(page, "#quantity")
value = evaluate(field, "el => el.value")
evaluate(field, "(el, newValue) => el.value = newValue", "7")
```

[`evaluate_all`](@ref) passes an array of all matches, including an empty
array when nothing matches. A single-locator evaluation raises if no element
matches. These calls run JavaScript directly; assigning `.value` does not fire
an `input` event. Use [`set_value!`](@ref) for ordinary form interaction, or
[`dispatch_event!`](@ref) if the script must notify page listeners. See
[Locators](@ref) for the locator-first forms and strictness rules.

For a selector you have not wrapped in a locator, the corresponding calls are
[`eval_on_selector`](@ref) and [`eval_on_selector_all`](@ref).
