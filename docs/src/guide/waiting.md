# Waiting

Browsers are asynchronous and pages are slow in ways that vary run to run. The
whole difficulty of browser testing is deciding *when* to look. There are two
answers, and only one of them works.

For the distinction between a navigation milestone and a ready application,
see [Navigation and page readiness](@ref).

```julia
sleep(2)                                             # hope
wait_for_selector(page, "#late"; state = :visible)    # know
```

A `sleep` is wrong in both directions at once: too short on a loaded CI runner,
and wasted on every run where the page was fast. The cost compounds — a suite
of two hundred tests with a two-second sleep each spends seven minutes doing
nothing.

## Wait driver-side

The action, assertion and explicit DOM waits below run in the driver, not in
Julia. The driver re-checks their conditions as the page changes. `retry_until`
is the exception: it polls from Julia.

| Call | Waits for |
|---|---|
| [`expect`](@ref) | an assertion to hold — see [Assertions](@ref) |
| [`wait_for_selector`](@ref) | an element to reach a DOM state |
| [`wait_for_function`](@ref) | a JavaScript predicate to go truthy |
| [`retry_until`](@ref) | anything else, polled from Julia |
| [`click!`](@ref) and other locator actions | action-specific prerequisites; see [Input actions](@ref) |

Actions waiting on their own is the part that is easy to miss. For example, a
button that appears or becomes enabled later needs no wait before `click!`:

```julia
click!(locator(page, "#submit"))  # retries until the button can be clicked
```

The click resolves its locator again as needed, then waits for the relevant
checks. It does **not** wait for the page's asynchronous response to the click;
use [`expect`](@ref) for that:

```julia
click!(locator(page, "#submit"))
expect(locator(page, "#status"); to_have_text = "Saved")
```

### What actionable means

The driver applies only the checks needed for the requested action:

| Check | Meaning and example |
|---|---|
| Attached | The selector resolves to an element still in the DOM. A locator is lazy; constructing one does not wait. |
| Visible | The element has a non-empty box and is not `visibility: hidden`. Visibility alone does not mean it can be clicked. |
| Stable | Its box has stopped moving across animation frames, so a pointer action will not chase an animation. |
| Receives events | The action point hits the element, rather than an overlay covering it. |
| Enabled | The control is not disabled. A disabled button can become enabled later. |
| Editable | A field can accept input: it is enabled and not read-only. |

[`click!`](@ref), [`dblclick!`](@ref), [`check!`](@ref),
[`uncheck!`](@ref) and [`tap!`](@ref) need a visible, stable target that
receives events and is enabled. [`hover!`](@ref) needs visibility, stability
and event reception, but not enabledness. [`set_value!`](@ref) needs a visible,
enabled, editable field; it does not need to receive pointer events.
[`select_option!`](@ref) waits for a visible, enabled select. Keyboard actions
such as [`press!`](@ref) resolve and focus an element, but do not require the
pointer checks. [`dispatch_event!`](@ref) sends a synthetic event without
pointer actionability checks. Page-coordinate [`mouse_click!`](@ref) has no
locator to check.

An overlay covering a button illustrates the distinction:

```julia
click!(locator(page, "#submit"))  # waits for the overlay to stop intercepting it
```

Waiting only for `#submit` to become visible would not solve this: it can be
visible *under* the overlay. If the overlay never leaves, the click times out;
inspect the call log in [Errors and timeouts](@ref).

Strict locators (the default) must resolve to one element. If a selector
matches several, choose a more specific selector or use [`nth`](@ref); waiting
longer will not make an ambiguous action valid. See [Locators](@ref) for
strictness and [Errors and timeouts](@ref) for timeout failures.

### Reads and assertions

[`count`](@ref) returns a snapshot immediately. Reads such as
[`text_content`](@ref) may wait for a matching element, but read its value
once; they do not retry until the value is what you wanted. For asynchronous
results, use a retrying assertion:

```julia
expect(locator(page, "#status"); to_have_text = "Saved")
expect(locator(page, ".result"; strict = false); to_have_count = 3)
```

`expect` retries its condition and raises [`AssertionFailure`](@ref) if it
never holds. See [Assertions](@ref) for the supported matchers.

## `wait_for_selector`

```julia
wait_for_selector(page, "#late"; state = :visible)
wait_for_selector(page, "#spinner"; state = :hidden)
```

`state` is one of `:attached`, `:detached`, `:visible` or `:hidden`. The
driver's default is `:attached`; pass `state = :visible` when the element must
also be shown. This waits for a DOM state, not for enabledness, stability or
an unobstructed click target. Use an action when those checks are what you need.

It returns an [`ElementHandle`](@ref) (or `nothing` for `:detached` and
`:hidden`), and raises [`TimeoutError`](@ref) if the state never arrives. It
works on a `Page`, a `Frame` or a `Locator`.

## `wait_for_function`

For a condition that is about the page rather than about one element:

```julia
wait_for_function(page, "() => window.appReady === true")
wait_for_function(page, "n => document.querySelectorAll('li').length >= n", 3)
```

The expression is evaluated in the browser until it returns something truthy.
`polling` chooses between `"raf"` (every animation frame, the default) and a
number of milliseconds.

This is the tool for application-level readiness — a framework that sets a flag
when it has hydrated, say. It sees the page's own state, which no DOM selector
can.

## `retry_until`

The escape hatch, and the only one of these that polls from the Julia side.
Use it when the condition is not about the page at all.

```julia
retry_until(; timeout = 60_000, interval = 200, on_error = :retry) do
    HTTP.get(url).status == 200
end
```

Two keywords carry the weight:

| Keyword | Values | Meaning |
|---|---|---|
| `on_timeout` | `:throw` (default), `:false` | raise [`AssertionFailure`](@ref), or return `false` |
| `on_error` | `:throw` (default), `:retry` | propagate a predicate exception, or treat it as "not yet" |

`on_error = :retry` is the one that makes waiting for a server possible. While
a web framework is starting, a request does not return a bad status — it throws
*connection refused*. Treating that exception as "not yet" is the difference
between a wait that works and a wait that crashes on its first attempt:

```julia
# examples/common.jl, near enough
function wait_for_server(url; timeout = 60_000)
    ok = retry_until(; timeout, interval = 200, on_error = :retry, on_timeout = :false) do
        HTTP.get(url; retry = false, status_exception = true)
        true
    end
    ok || error("server at $url did not come up within $(timeout)ms")
end
```

The [Genie.jl](@ref) example measures what this is worth: 25 seconds between
`up()` returning and the first request being answered, on an idle workstation.
A `sleep` long enough to cover that is a `sleep` paid on every other example
forever. [WGLMakie.jl](@ref) does the same for rendering, where a cold first
paint took 57.9 seconds.

`on_timeout = :false` is what lets a check sit inside `@test` and report a
`Test.Fail` rather than an `Error`, so the testset summary reads correctly:

```julia
@test retry_until(page; on_timeout = :false) do
    length(console_messages(page)) >= 3
end
```

Prefer [`expect`](@ref) whenever it fits. `retry_until` makes a round trip per
attempt, so it can miss a state that flickers between polls. `expect` re-checks
inside the browser, so it cannot.

## How long each wait gets

Every `timeout` keyword falls back through a chain: the call's own keyword, then
the page's setting, then the context's, then 30 seconds. Set it once on the
context with [`set_default_timeout!`](@ref):

```julia
ctx = new_context(browser)
set_default_timeout!(ctx, 2_000)       # a missing element fails in 2 s
```

See [Errors and timeouts](@ref) for the whole cascade, and for what happens when
the budget runs out.
