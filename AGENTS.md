# Working on Playwright.jl

Playwright.jl provides a synchronous Julia API over the official Playwright
driver's JSON protocol. The package supports Julia 1.10 and later. Read the
current implementation, tests, README, and CI workflows before changing behavior.

## API design: discuss the tradeoff

Maintain a reasonable correspondence with the Playwright Python API while making
the API idiomatic Julia. This is a central design tradeoff, not a rule that either
side always wins.

When work involves API design, explicitly surface this tradeoff in questions,
plans, and specs before implementing the decision. Describe the Python behavior,
the proposed Julia interface, and the practical consequences of any divergence.
Present a few viable alternatives with their pros and cons so the maintainer can
resolve consequential choices rather than silently choosing one direction.
Routine changes that preserve an established interface can follow the existing
convention.

Use snake_case, multiple dispatch, and keyword arguments consistently with nearby
code. The existing naming rule gives calls that change what the page can observe
a `!` suffix. Check actual exports and implementations before documenting an API;
upstream Playwright support does not imply this binding exposes it.

## Planning and scope

Files under `tasks/` are secondary, semi-historical information. Confirm their
claims against current code and tests. They may be updated to reflect changes,
but stale plans do not override the implementation or the maintainer's direction.

Use the milestone spec/plan/checklist system when the maintainer explicitly asks
for a new milestone. Do not impose that process on every change. For a requested
milestone, inspect the existing milestone documents for structure and capture
design decisions, acceptance criteria, risks, and verification evidence.

During speccing or planning, surface adjacent concerns that interact with the
requested work. If planning reveals a bug, file a GitHub issue immediately, then
return to the main task. Check for an existing issue to avoid duplicates; include
the evidence, expected and actual behavior, and reproduction details when known.
Link the issue from the plan if it affects the work. If issue filing is blocked,
report that clearly rather than claiming the issue exists. Do not silently expand
the task to fix the discovered bug.

## Repository map and generated files

- `src/driver.jl`: pinned driver versions, installation, and subprocess setup.
- `src/transport.jl`, `src/connection.jl`, `src/objects.jl`, and
  `src/serializers.jl`: protocol transport and object machinery.
- `src/api/`: handwritten public API; `src/Playwright.jl`: module and exports.
- `protocol/spec/`: vendored upstream protocol; `gen/`: generator toolchain.
- `src/generated/channels.jl`: checked-in generated protocol layer.
- `test/`: hermetic tests, real-browser tests, and local fixtures.
- `docs/src/` and `docs/make.jl`: Documenter sources and navigation.
- `examples/`: runnable integrations with Julia web stacks.

Never edit `src/generated/` or vendored protocol files by hand. Change the
generator or refresh the pinned upstream spec, then regenerate:

```sh
julia --project=gen -e 'using Pkg; Pkg.instantiate()'
julia --project=gen gen/fetch_spec.jl        # only when refreshing the spec
julia --project=gen gen/generate.jl
julia --project=gen gen/generate.jl --check
```

An upstream version refresh starts with the pin in `src/driver.jl`; consult
`protocol/README.md`. Preserve the pinned generator and examples manifests unless
updating those dependencies is part of the task. Keep generator dependencies out
of the runtime environment. Use the formatter pinned in `gen/`; the root
`.JuliaFormatter.toml` excludes generated output because generation formats it.

```sh
julia --project=gen -e 'using JuliaFormatter; format(".", verbose = false)'
```

This command can modify files. Inspect the resulting diff and avoid unrelated
formatting churn. Do not commit browser caches, generated documentation, or test
and example artifacts; see `.gitignore`.

## Testing is part of the deliverable

Choose verification that demonstrates the changed behavior. For fixes, add a
regression test that would catch the bug. Use hermetic fake-driver tests for
protocol behavior and real-browser tests for behavior that needs a browser.
Preserve test include ordering: several files reuse helpers from earlier files
in `test/runtests.jl`.

```sh
# Hermetic suite: no Node.js or browsers required.
julia --project=. -e 'using Pkg; Pkg.test()'

# Real-browser suite, narrowed for a local feedback loop.
PLAYWRIGHT_JL_SMOKE=1 PLAYWRIGHT_JL_ENGINE=chromium julia --project=. -e 'using Pkg; Pkg.test()'

# Full local engine sweep; requires the engines to be available.
PLAYWRIGHT_JL_SMOKE=1 julia --project=. -e 'using Pkg; Pkg.test()'

# Documentation, including doctests; does not launch browsers.
julia --project=docs docs/make.jl
```

`PLAYWRIGHT_JL_ENGINE` accepts a single name or comma-separated names:
`chromium`, `firefox`, `webkit`, `chrome`, `msedge`. Chrome and Edge are Chromium
channels using installed browsers. WebKit on Windows is intentionally unsupported.
Browser setup is available through `julia bin/install.jl`; inspect its options
before installing engines or system dependencies.

Prefer driver-side waits and retrying assertions over fixed sleeps. Give
asynchronous test waits deadlines; reuse `test/waits.jl` and existing smoke-test
helpers. Do not hide failures behind new skips: engine divergences must be
explained in `docs/src/engines.md` and agree with the skip checks.

It is acceptable to defer tests to CI when that is more efficient, particularly
for other operating systems and the wider engine matrix. State which checks were
run locally and which were deferred. Watch the PR's CI through completion,
investigate failures, and fix failures caused by the change. Submitting a PR
without following its deferred checks is not completed verification. If access
or execution limits prevent watching CI, explicitly report the outstanding work.

Use `.github/workflows/CI.yml` as the current source for the test, driver, smoke,
examples, code-generation, and formatting checks. Public API changes also need
docstrings and reference coverage; Documenter treats warnings as errors.

## Delivery

Complete work through pull requests rather than direct changes to the default
branch. Keep each PR focused on the requested outcome. Describe the resulting
behavior, meaningful API choices, verification results, and any remaining limits.
Follow CI as described above, and distinguish observed results from expectations.
Agents may commit, push, and open pull requests autonomously within the requested
scope. Merging is done by a human; agents must not merge pull requests.
