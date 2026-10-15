# Configuring and checking a browser context

Pass emulation and network settings to [`new_context`](@ref) when you create a
[`BrowserContext`](@ref). Its pages share those settings. Create another context
when a test needs a different profile; see [Browser contexts and isolation](@ref)
for ownership and cleanup. The same context keywords also work with
[`launch_persistent_context`](@ref).

## Viewport and device behavior

This example combines a narrow viewport, a device scale factor, a user agent,
mobile layout and touch input. It uses Chromium because `is_mobile` is not
supported by Firefox. These are individual options, not a built-in Julia device
registry. In particular, `is_mobile` does not choose a user agent for you.

```julia
using Playwright

playwright() do pw
    browser = launch(pw.chromium; headless = true)
    try
        ctx = new_context(browser;
            viewport = (width = 390, height = 844),
            device_scale_factor = 2,
            user_agent = "Playwright.jl mobile test",
            is_mobile = true,
            has_touch = true,
        )
        try
            page = new_page(ctx)
            goto!(page, "data:text/html,<meta name='viewport' content='width=device-width'>")
            observed = evaluate(page, """() => ({
                width: innerWidth,
                scale: devicePixelRatio,
                userAgent: navigator.userAgent,
                touchPoints: navigator.maxTouchPoints
            })""")
            @assert observed["width"] == 390
            @assert observed["scale"] == 2
            @assert observed["userAgent"] == "Playwright.jl mobile test"
            @assert observed["touchPoints"] > 0
        finally
            close!(ctx)
        end
    finally
        close!(browser)
    end
end
```

The viewport meta tag makes the page's CSS viewport width observable on mobile.
Without it, `innerWidth` can be wider than the configured viewport. Touch
capability does not send a tap by itself; use [`tap!`](@ref) to exercise a touch
action. For engine and platform differences, see [What differs between the
engines](@ref).

## Locale, time zone and color scheme

Set these when creating the context, then check the values the page sees. A
`data:` page is enough because none of these checks needs a server.

```julia
ctx = new_context(browser;
    locale = "fr-FR",
    timezone_id = "Europe/Paris",
    color_scheme = "dark",
)
try
    page = new_page(ctx)
    goto!(page, "data:text/html,ready")
    observed = evaluate(page, """() => ({
        language: navigator.language,
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        dark: matchMedia('(prefers-color-scheme: dark)').matches
    })""")
    @assert observed["language"] == "fr-FR"
    @assert observed["timeZone"] == "Europe/Paris"
    @assert observed["dark"]
finally
    close!(ctx)
end
```

This and the following shorter snippets assume `browser` was launched as in the
first example and is closed by its surrounding `finally` block.

## Permissions and offline mode

`permissions` is a list of permission names granted to the context. The browser
and origin still determine whether a particular web API is available. For a
Chromium test, you can grant notifications and check the page's permission
state. Set `offline = true` on a separate context and check its reported network
state without trying to load a remote page.

```julia
ctx = new_context(browser; permissions = ["notifications"])
try
    page = new_page(ctx)
    goto!(page, "http://localhost:8000/")  # your local test server
    @assert evaluate(page, "Notification.permission") == "granted"
finally
    close!(ctx)
end

offline_ctx = new_context(browser; offline = true)
try
    page = new_page(offline_ctx)
    goto!(page, "data:text/html,offline")
    @assert evaluate(page, "navigator.onLine") == false
finally
    close!(offline_ctx)
end
```

The notifications check needs an origin and browser that support that
permission; use a local server for a repeatable test. Offline mode affects
network requests made by pages in the context. See [The network](@ref) for
intercepting requests when a test needs a controlled response.

## Base URL and extra request headers

`base_url` resolves relative navigation URLs and scheme-less route globs.
`extra_http_headers` adds headers to requests from the context. With a local
test server on port 8000, this checks both the final URL and the outgoing
header through public methods:

```julia
ctx = new_context(browser;
    base_url = "http://127.0.0.1:8000",
    extra_http_headers = Dict("X-Test-Run" => "context-example"),
)
try
    page = new_page(ctx)
    req = expect_request(ctx, "**/settings") do
        goto!(page, "/settings")
    end
    @assert url(page) == "http://127.0.0.1:8000/settings"
    @assert headers(req)["x-test-run"] == "context-example"
finally
    close!(ctx)
end
```

The server must serve `/settings`; the snippet does not start one. See
[Navigation and page readiness](@ref) for `goto!` and [The network](@ref) for
request inspection and `base_url` matching.

All options on this page are **context creation** keywords. The public wrapper
does not expose context setters for them after creation. To change one during a
test, create a new context with the new options and open a page in it. Page
reads such as [`evaluate`](@ref), [`url`](@ref) and [`headers`](@ref) verify the
result; they do not change the context.
