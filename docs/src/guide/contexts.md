# Browser contexts and isolation

A [`BrowserContext`](@ref) is an isolated browser profile. Each context has its
own cookies, local storage, permissions, and context options. Pages in the same
context share that profile; pages in different contexts do not. Session storage
belongs to a tab, so do not use it to pass state between pages.

Create **one context per test** when the test needs to control its profile or
use several pages. This gives every test a clean start without launching a new
browser process. A scenario with two independent users can create two contexts
in the same browser.

## An isolated page

For a test that needs only one page and no context options, let
[`new_page(browser)`](@ref new_page) create an implicit context:

```julia
using Playwright

playwright() do pw
    browser = launch(pw.chromium; headless = true)
    try
        page = new_page(browser)
        try
            goto!(page, "https://example.com")
            expect(page; to_have_title = "Example Domain")
        finally
            close!(page)  # also closes this page's implicit context
        end
    finally
        close!(browser)
    end
end
```

Another `new_page(browser)` gets a separate context, so it does not inherit the
first page's cookies or local storage. [`with_page`](@ref) handles the page
cleanup for the same pattern:

```julia
playwright() do pw
    browser = launch(pw.chromium; headless = true)
    try
        with_page(browser, "https://example.com") do page
            expect(page; to_have_title = "Example Domain")
        end  # closes the page and its implicit context, even if the block throws
    finally
        close!(browser)
    end
end
```

## A context you own

Create the context explicitly when pages should share cookies and local storage,
or when you need options such as `locale`, `viewport`, or `record_video`:

```julia
playwright() do pw
    browser = launch(pw.chromium; headless = true)
    try
        ctx = new_context(browser; locale = "en-US")
        try
            page = new_page(ctx)
            goto!(page, "https://example.com")
            expect(page; to_have_title = "Example Domain")
        finally
            close!(ctx)  # closes every page in this context
        end
    finally
        close!(browser)
    end
end
```

`new_page(ctx)` joins the existing context. Closing that page closes only the
page; **you still close `ctx`**. Likewise, `with_page(ctx, url) do page ... end`
closes its page but leaves `ctx` open for other pages or later work in the same
test. Close the context in `finally` so an assertion failure cannot leave it
open. [`contexts(browser)`](@ref contexts) lists the currently open contexts and
can help spot a leak.

See [Pages and tabs](@ref) for multiple pages and popups in one context, and
[Artifacts](@ref) for the `with_page` screenshot and trace options. To combine
viewport, locale, permissions and network settings, see
[Configuring and checking a browser context](@ref).
