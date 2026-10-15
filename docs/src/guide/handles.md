# JavaScript handles

[`evaluate`](@ref) copies a result into Julia. [`evaluate_handle`](@ref) keeps
the result in the browser and returns a [`JSHandle`](@ref) referring to it.
Use a handle when the value cannot be copied, such as a DOM node or a function,
or when you need to work repeatedly with the same browser object. A handle
holds a browser-side reference until it is disposed or its page closes.

## Work within a handle's lifetime

The do-block form of `evaluate_handle` calls [`dispose!`](@ref) when the block
ends, including when it throws. You can evaluate against the handle; the
handle's value is the function's first argument:

```julia
name = evaluate_handle(page, "() => window.app") do app
    evaluate(app, "app => app.name")
end
# `app` has been disposed; `name` is an ordinary Julia value.
```

You can also pass a handle as an explicit argument to page or frame
evaluation. To pass the handle together with other values, wrap them in a
named tuple:

```julia
evaluate_handle(page, "() => document.querySelector('#chart')") do chart
    evaluate(page, "({element, scale}) => element.clientWidth * scale",
             (element = chart, scale = 2))
end
```

When a handle must outlive one block, dispose it in `finally`:

```julia
app = evaluate_handle(page, "() => window.app")
try
    ready = evaluate(page, "app => app.ready", app)
finally
    dispose!(app)
end
```

Do not use a handle after disposal. Disposing releases its browser reference;
it does not remove the underlying JavaScript object from the page.

## Element handles and changing pages

[`element_handle`](@ref) resolves a [`Locator`](@ref) immediately and returns
an [`ElementHandle`](@ref), or `nothing` if there is no match. Check for
`nothing` before passing it to `evaluate`:

```julia
chart = element_handle(locator(page, "#chart"))
if chart !== nothing
    try
        width = evaluate(page, "el => el.getBoundingClientRect().width", chart)
    finally
        dispose!(chart)
    end
end
```

[`wait_for_selector`](@ref) returns an element handle when you need to wait
for the element first. Dispose that handle too. A locator resolves the element
again on each use, while an element handle stays tied to the particular node
it found. If the page re-renders or navigates, that node can become detached
or its execution context can disappear. Prefer locators for normal reads and
actions; acquire a fresh handle when you need a browser reference to a current
element. See [Locators](@ref) and [Waiting](@ref).
