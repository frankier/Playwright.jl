# The driver and Node.js runtime are provided by Julia artifacts. Keep the
# protocol pin aligned with the exact playwright_core_jll compat in Project.toml.

"Pinned Playwright protocol version, matching playwright_core_jll."
const PLAYWRIGHT_VERSION = "1.64.1"

function default_os()
    Sys.iswindows() ? :windows :
    Sys.isapple() ? :macos :
    Sys.islinux() ? :linux : error("unsupported OS for the Playwright driver")
end

"""
    driver_cmd(args...) -> Cmd

Run the artifact-provided Playwright CLI with NodeJS_24_jll's executable and
runtime environment. Browser installation remains the driver's responsibility.
"""
function driver_cmd(args::AbstractString...)
    return `$(NodeJS_24_jll.node()) $(playwright_core_jll.cli) $args`
end

"""
    install(; browsers=["chromium", "firefox"])

Install `browsers` using the artifact-provided Playwright driver
into the standard Playwright browser cache via the driver's own installer.
Safe to call repeatedly — already installed browsers are reused.

`browsers` names engines the driver understands: `"chromium"`, `"firefox"`,
`"webkit"`. [`launch`](@ref) calls this for you the first time an engine turns
out to be missing, so an explicit `install` is for the case where you want the
download to happen *now* — in a CI step of its own, say, rather than inside the
first test.

```julia
install()                                          # both engines
install(; browsers = ["chromium"])                 # just one
install(; browsers = ["webkit"], with_deps = true) # Linux, and needs root
```

`with_deps = true` additionally installs the system libraries the browsers
need, by asking the driver to run the distribution's package manager. WebKit is
the engine that does not ship its own world: on a stock Ubuntu, `install`
succeeds without it and the browser then fails to *launch* on a missing shared
library. It needs root, and it is Linux-only — on Windows and macOS it raises
`ArgumentError` rather than silently doing nothing, because a script that
passes it there is confused about what it is running on.

`"chrome"` and `"msedge"` are accepted, and are **not** downloads: Playwright
installs Google Chrome and Microsoft Edge as *system packages*. That is a
machine-wide change requiring root on Linux, so it warns before it starts.

Set `PLAYWRIGHT_BROWSERS_PATH` to put the browsers somewhere cacheable rather
than in the default per-user cache. From outside a Julia session, the same
thing is `julia bin/install.jl`, which works from a bare checkout — the case a
package carrying Playwright.jl as a *test* dependency hits in CI.
"""
function install(;
    browsers::Vector{String} = copy(DEFAULT_BROWSERS),
    with_deps::Bool = false,
)
    # Validate before invoking the driver or any package manager.
    check_with_deps(with_deps, default_os())
    warn_branded_install(browsers, default_os())
    @info "Installing browsers via Playwright driver" browsers with_deps
    run(driver_cmd(install_args(browsers, with_deps)...))
    return nothing
end

"The driver arguments an install performs. A seam: the command is asserted."
install_args(browsers, with_deps::Bool) =
    with_deps ? ["install", "--with-deps", browsers...] : ["install", browsers...]

"""
Refuse `with_deps` anywhere but Linux, naming the platform (D3).

`os` is a parameter rather than read from `Sys` so that the two platforms the
developer cannot run are asserted from the one they can.
"""
function check_with_deps(with_deps::Bool, os::Symbol)
    (with_deps && os !== :linux) && throw(
        ArgumentError(
            "with_deps = true is Linux-only; this is $os. The driver installs " *
            "system libraries through the distribution's package manager, and " *
            "there is no equivalent step on Windows or macOS — the browsers " *
            "there ship what they need. Drop the keyword.",
        ),
    )
    return nothing
end

"The two browser names that are system packages rather than downloads (D3a)."
const BRANDED_BROWSERS = ("chrome", "msedge")

"""
Warn, once, that a branded name means a system-wide install (D3a).

`playwright install chrome` does not put a browser in
`PLAYWRIGHT_BROWSERS_PATH` — it installs Google Chrome through apt, a `.dmg` or
an `.exe`. An installer that invokes `sudo apt` because someone typed a browser
name without saying so first is not acceptable behaviour.
"""
function warn_branded_install(browsers, os::Symbol)
    branded = [b for b in browsers if b in BRANDED_BROWSERS]
    isempty(branded) && return nothing
    root = os === :linux ? " This needs root: re-run under `sudo -E`." : ""
    @warn "Installing $(join(branded, " and ")) changes this machine system-wide. " *
          "Playwright does not download these into PLAYWRIGHT_BROWSERS_PATH — it " *
          "installs the real Google Chrome or Microsoft Edge through the system " *
          "package manager, outside any cache this package controls.$root " *
          "If you only wanted a browser to test with, `chromium` is the bundled " *
          "build and needs no system change."
    return nothing
end

# --- Install ergonomics ----------------------------------------------------

"""
    browsers_path() -> Union{String,Nothing}

Where browsers are installed to and looked up from, or `nothing` when the
Playwright default cache is in use (`~/.cache/ms-playwright` on Linux,
`~/Library/Caches/ms-playwright` on macOS, `%USERPROFILE%\\AppData\\Local\\ms-playwright`
on Windows).

Set `PLAYWRIGHT_BROWSERS_PATH` to override it. The driver reads the variable
itself, and both [`install`](@ref) and the driver process started by
[`playwright`](@ref) inherit this process's environment, so setting it in
`ENV` — or in the shell before starting Julia — is enough for installing *and*
launching to agree on the location.

Worth pointing at a project-local directory in CI, where a cache you control is
easier to key and restore than one in the home directory.
"""
browsers_path() = get(ENV, "PLAYWRIGHT_BROWSERS_PATH", nothing)

"The browsers installed when the caller does not say otherwise."
const DEFAULT_BROWSERS = ["chromium", "firefox"]

"""
    browsers_from_args(args) -> Vector{String}

Browser names from a command line, defaulting to [`DEFAULT_BROWSERS`](@ref)
when none are given. Used by `bin/install.jl`. Unknown names are rejected here
rather than after a download has already started.
"""
function browsers_from_args(args)
    isempty(args) && return copy(DEFAULT_BROWSERS)
    # chrome and msedge are here because a *user* may reasonably want
    # `julia bin/install.jl chrome` (D3a). They are system installs, and
    # warn_branded_install says so before anything happens.
    known = ("chromium", "firefox", "webkit", BRANDED_BROWSERS...)
    names = String[]
    for arg in args
        name = lowercase(String(arg))
        name in known || throw(
            ArgumentError(
                "unknown browser `$name`. Choose from: " * join(known, ", ") * ".",
            ),
        )
        push!(names, name)
    end
    return names
end

"""
    install_args_from_cli(args) -> (browsers, with_deps)

Split a `bin/install.jl` command line into browser names and the `--with-deps`
flag. The flag has to come out before [`browsers_from_args`](@ref) sees it, or
it is rejected as an unknown browser name.
"""
function install_args_from_cli(args)
    rest = String[]
    with_deps = false
    for arg in args
        a = String(arg)
        if a == "--with-deps"
            with_deps = true
        elseif startswith(a, "-")
            throw(ArgumentError("unknown option `$a`. The only flag is --with-deps."))
        else
            push!(rest, a)
        end
    end
    return browsers_from_args(rest), with_deps
end
