# Unit tests for src/driver.jl (hermetic — no downloads).

@testset "driver" begin
    @testset "artifact driver command" begin
        cmd = Playwright.driver_cmd("run-driver")
        @test cmd.exec == [
            Playwright.NodeJS_24_jll.node().exec[1],
            Playwright.playwright_core_jll.cli,
            "run-driver",
        ]
        @test cmd.env == Playwright.NodeJS_24_jll.node().env
        @test isfile(cmd.exec[1])
        @test isfile(cmd.exec[2])
        package = Playwright.JSON.parsefile(joinpath(dirname(cmd.exec[2]), "package.json"))
        @test package["version"] == Playwright.PLAYWRIGHT_VERSION
        @test Playwright.driver_cmd("install", "chromium").exec[3:end] ==
              ["install", "chromium"]
    end

    # --- Install ergonomics -----------------------------------------------

    @testset "browser names default, and typos are caught before downloading" begin
        @test Playwright.browsers_from_args(String[]) == ["chromium", "firefox"]
        @test Playwright.browsers_from_args(["chromium"]) == ["chromium"]
        @test Playwright.browsers_from_args(["Firefox"]) == ["firefox"]
        @test Playwright.browsers_from_args(["chromium", "webkit"]) ==
              ["chromium", "webkit"]
        # The branded names are installable too -- as system packages, not as
        # Playwright downloads (D3a).
        @test Playwright.browsers_from_args(["chrome"]) == ["chrome"]
        @test Playwright.browsers_from_args(["msedge"]) == ["msedge"]
        # A typo must fail here rather than after a few hundred MB of download.
        @test_throws ArgumentError Playwright.browsers_from_args(["edge"])
        @test_throws ArgumentError Playwright.browsers_from_args(["chromium", "safari"])
        # ...and the default list is not aliased, so a caller mutating the
        # result cannot change what the next caller gets.
        first_call = Playwright.browsers_from_args(String[])
        push!(first_call, "webkit")
        @test Playwright.browsers_from_args(String[]) == ["chromium", "firefox"]
    end

    @testset "browsers_path reports the PLAYWRIGHT_BROWSERS_PATH override" begin
        restore = get(ENV, "PLAYWRIGHT_BROWSERS_PATH", nothing)
        try
            delete!(ENV, "PLAYWRIGHT_BROWSERS_PATH")
            @test Playwright.browsers_path() === nothing
            ENV["PLAYWRIGHT_BROWSERS_PATH"] = "/tmp/somewhere"
            @test Playwright.browsers_path() == "/tmp/somewhere"
        finally
            restore === nothing ? delete!(ENV, "PLAYWRIGHT_BROWSERS_PATH") :
            (ENV["PLAYWRIGHT_BROWSERS_PATH"] = restore)
        end
    end

    @testset "with_deps reaches the driver's command line" begin
        # SC 7. Asserted on the command rather than by running it: the whole
        # point of --with-deps is that it invokes the distribution's package
        # manager, which a test suite must not do.
        @test Playwright.install_args(["webkit"], false) == ["install", "webkit"]
        @test Playwright.install_args(["webkit"], true) ==
              ["install", "--with-deps", "webkit"]
        @test Playwright.install_args(["chromium", "firefox"], false) ==
              ["install", "chromium", "firefox"]
    end

    @testset "with_deps off Linux is refused before anything is downloaded" begin
        # D3: the driver has nothing to do there, so a script that passes it is
        # confused about what it is running on -- and saying so beats a silent
        # no-op that leaves the caller believing dependencies were installed.
        # The OS is a parameter rather than read from Sys, so the two platforms
        # this developer cannot run are asserted on every platform.
        @test_throws ArgumentError Playwright.check_with_deps(true, :windows)
        @test_throws ArgumentError Playwright.check_with_deps(true, :macos)
        @test Playwright.check_with_deps(true, :linux) === nothing
        # false is fine everywhere, including the platform this runs on.
        @test Playwright.check_with_deps(false, :windows) === nothing
        @test Playwright.check_with_deps(false, :macos) === nothing
        @test Playwright.check_with_deps(false, :linux) === nothing

        err = try
            Playwright.check_with_deps(true, :macos)
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("with_deps", err.msg)
        @test occursin("Linux", err.msg)
    end

    @testset "a branded name warns that it is a system-wide install" begin
        # SC 8 / D3a. `playwright install chrome` does not download a browser
        # into PLAYWRIGHT_BROWSERS_PATH -- it installs Google Chrome as a
        # system package, with apt on Linux. An installer that silently invokes
        # sudo apt because someone typed a browser name is not acceptable
        # behaviour; saying so first is.
        #
        # No install is performed here: the warning is its own function
        # precisely so it can be asserted without one.
        for name in ("chrome", "msedge")
            logs = Test.collect_test_logs() do
                Playwright.warn_branded_install([name], :linux)
            end[1]
            @test length(logs) == 1
            @test logs[1].level == Base.CoreLogging.Warn
            msg = string(logs[1].message)
            @test occursin(name, msg)
            @test occursin("system", msg)
            @test occursin("root", msg)          # Linux says it needs root
        end

        # Off Linux it is still system-wide, but root is not the mechanism.
        logs = Test.collect_test_logs() do
            Playwright.warn_branded_install(["chrome"], :macos)
        end[1]
        @test length(logs) == 1
        @test occursin("system", string(logs[1].message))

        # The bundled engines say nothing at all -- a warning on every ordinary
        # install is a warning nobody reads.
        for browsers in (["chromium"], ["chromium", "firefox", "webkit"], String[])
            logs = Test.collect_test_logs() do
                Playwright.warn_branded_install(browsers, :linux)
            end[1]
            @test isempty(logs)
        end
    end

    @testset "bin/install.jl parses --with-deps" begin
        # The flag has to be stripped from the browser names, or it reaches
        # browsers_from_args and is rejected as an unknown browser.
        @test Playwright.install_args_from_cli(["--with-deps", "webkit"]) ==
              (["webkit"], true)
        @test Playwright.install_args_from_cli(["webkit", "--with-deps"]) ==
              (["webkit"], true)
        @test Playwright.install_args_from_cli(["webkit"]) == (["webkit"], false)
        @test Playwright.install_args_from_cli(String[]) == (["chromium", "firefox"], false)
        @test_throws ArgumentError Playwright.install_args_from_cli(["--jazz"])
    end

    @testset "the default install is still exactly two browsers" begin
        # SC 11 / D2. WebKit is opt-in: a first-time user following the README
        # does not pay for a third browser download to run the quick-start
        # example. launch() self-heals for the engine they actually ask for.
        @test Playwright.DEFAULT_BROWSERS == ["chromium", "firefox"]
        @test length(Playwright.DEFAULT_BROWSERS) == 2
    end

    @testset "bin/install.jl is present and parses" begin
        script = joinpath(pkgdir(Playwright), "bin", "install.jl")
        @test isfile(script)
        # Parsing it here means a syntax error shows up in the suite rather
        # than the first time someone runs it in CI.
        @test Meta.parseall(read(script, String)) isa Expr
    end
end
