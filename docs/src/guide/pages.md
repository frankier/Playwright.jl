# Pages and tabs

A [`Page`](@ref) represents a tab or popup. One context can hold several pages.
Use [`new_page(ctx)`](@ref new_page) when those pages should share a browser
profile; see [Browser contexts and isolation](@ref) to choose the context's
lifetime.

## Two tabs in one context

```julia
using Playwright

playwright() do pw
    browser = launch(pw.chromium; headless = true)
    try
        ctx = new_context(browser)
        try
            first_tab = new_page(ctx)
            second_tab = new_page(ctx)
            goto!(first_tab, "https://example.com")
            goto!(second_tab, "https://example.com")

            open_tabs = pages(ctx)
            @assert first_tab in open_tabs && second_tab in open_tabs
        finally
            close!(ctx)  # closes both tabs
        end
    finally
        close!(browser)
    end
end
```

[`pages(ctx)`](@ref pages) returns the currently open pages, with no guaranteed
order. It is useful for inspecting tabs that already exist. Each page can be
used directly; there is no need to bring a tab to the front before interacting
with it.

## Catch a popup as it opens

When an action opens a new tab or popup, subscribe to the context's `:page`
event **before** the action. [`expect_event`](@ref) does both in one block, so
the event cannot be missed by a fast click:

```julia
# `ctx` owns `page`; the button opens a new tab.
popup = expect_event(ctx, :page) do
    click!(locator(page, "#open-popup"))
end
expect(popup; to_have_title = "Popup")
# close!(ctx) in the surrounding finally closes page and popup.
```

The popup also appears in `pages(ctx)` after it opens. Use the event when you
need to wait for a particular action's new page; a snapshot of `pages(ctx)`
cannot arrange the subscription before the action. See [Events](@ref) for other
supported events and waiting patterns.

## A persistent profile

[`launch_persistent_context`](@ref) starts a browser using a profile directory.
Its cookies and local storage can survive after the browser exits. It returns
the context, **already containing one page**. Use that page for the first tab
instead of opening an extra blank tab:

```julia
using Playwright

playwright() do pw
    ctx = launch_persistent_context(
        pw.chromium, joinpath(mktempdir(), "profile"); headless = true
    )
    try
        page = first(pages(ctx))
        goto!(page, "https://example.com")
        second_tab = new_page(ctx)  # only if another tab is needed
        goto!(second_tab, "https://example.com")
    finally
        close!(ctx)  # also shuts down the persistent browser
    end
end
```

For state to survive **another run**, use a stable directory in place of the
temporary one above, and launch again with the same path after closing `ctx`.
There is no separately returned `Browser` to close. For independent tests, use
fresh contexts instead of reusing a persistent profile.
