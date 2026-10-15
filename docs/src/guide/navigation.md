# Navigation and page readiness

Navigation changes the document in a page. The point at which the browser has
loaded that document is often earlier than the point at which your application
is ready to use. Choose a navigation milestone, then wait for the specific
content or state your test needs.

## Open a page explicitly

[`goto!`](@ref) navigates a [`Page`](@ref) and returns the main resource's
[`Response`](@ref), or `nothing` when there is no response (for example, an
`about:blank` navigation). You can inspect the response when the HTTP result
matters:

```julia
using Test
using Playwright

playwright() do pw
    browser = launch(pw.chromium; headless = true)
    try
        page = new_page(browser)
        response = goto!(page, "https://example.com"; wait_until = "load")
        @test response !== nothing && status(response) == 200
        expect(page; to_have_title = "Example Domain")
    finally
        close!(browser)
    end
end
```

`wait_until` selects when `goto!` returns:

| Value | Navigation milestone |
|---|---|
| `"commit"` | Response headers have arrived and navigation is committed. The document may not have been parsed yet. |
| `"domcontentloaded"` | The document has been parsed and `DOMContentLoaded` has fired. |
| `"load"` (default) | The `load` event has fired, including load-event subresources. |
| `"networkidle"` | Network activity has stopped for 500 ms. |

Use `"commit"` or `"domcontentloaded"` when you intend to wait for a specific
page condition afterward. The default `"load"` is a useful general milestone,
but it does not mean that data fetched later or a client-rendered view is ready.
Avoid `"networkidle"` as a general readiness check: polling and other ongoing
requests can keep it from arriving. Wait for the state that matters instead.

## Follow an action that navigates

A click can start navigation. After the action, assert the destination URL or
content with [`expect`](@ref). These assertions retry while the page changes:

```julia
click!(locator(page, "a[href='/checkout']"))
expect(page; to_have_url = r"/checkout$")
expect(locator(page, "h1"); to_have_text = "Checkout")
```

`to_have_url` accepts a string or a regular expression. A URL assertion tells
you where the page went; a content assertion tells you whether the part your
test needs has appeared. A plain [`url`](@ref) or [`title`](@ref) read takes the
value immediately, so prefer `expect` when the result can arrive later.

## Wait for application readiness

Even after `"load"`, JavaScript can fetch data, render components, or hydrate
controls. Wait for a visible element when it represents readiness, or for a
page-defined condition when no selector expresses it:

```julia
goto!(page, "https://example.com/app")
wait_for_selector(page, "#dashboard"; state = :visible)
wait_for_function(page, "() => window.appReady === true")
```

Use whichever condition your application actually provides; both calls wait
until it holds or their timeout expires. See [Waiting](@ref) for selector
states and other ways to wait.

## Timeout budgets

`goto!` uses the navigation timeout. Set it with
[`set_default_navigation_timeout!`](@ref) on a page or context, or pass a
`timeout` keyword to one `goto!` call. Actions such as [`click!`](@ref),
assertions, `wait_for_selector`, and `wait_for_function` use the action timeout
set by [`set_default_timeout!`](@ref). Both defaults are 30 seconds; a
navigation without its own setting falls back to the action timeout setting.
Timeout values are in milliseconds.

```julia
set_default_navigation_timeout!(page, 60_000)
set_default_timeout!(page, 5_000)
goto!(page, "https://example.com/app"; timeout = 10_000)
expect(locator(page, "#dashboard"); to_be_visible = true)
```

The explicit `goto!` timeout here is 10 seconds; the assertion gets the
5-second action budget. See [Errors and timeouts](@ref) for the full timeout
cascade.
