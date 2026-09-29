# The input surface, at the wire.
#
# Hermetic: every wrapper here is a generated protocol call plus the timeout
# cascade, so the question a unit test can answer is exactly the one that
# matters — did the right method go to the right object with the right
# parameters. Real gestures are in test_smoke_input.jl, because a mouse event
# that never reaches the browser cannot be checked from here.

@testset "input surface" begin
    @testset "positions accept the spellings a caller reaches for" begin
        @test Playwright.position_dict(nothing) === nothing
        @test Playwright.position_dict((x = 3, y = 4)) == Dict("x" => 3, "y" => 4)
        @test Playwright.position_dict((7, 8)) == Dict("x" => 7, "y" => 8)
        @test Playwright.position_dict(Dict("x" => 1, "y" => 2)) == Dict("x" => 1, "y" => 2)
        @test_throws ArgumentError Playwright.position_dict((x = 1,))
    end

    # --- Page: the mouse ---------------------------------------------------

    @testset "mouse_move! sends the point and the step count" begin
        f = timeout_fixture()
        sent = waiting_request(f.fake, () -> mouse_move!(f.page, 10, 20; steps = 5))
        @test sent["guid"] == "page@1"
        @test sent["method"] == "mouseMove"
        @test sent["params"]["x"] == 10
        @test sent["params"]["y"] == 20
        @test sent["params"]["steps"] == 5
        shutdown!(f.fake)
    end

    @testset "mouse_move! omits steps when not asked for one" begin
        f = timeout_fixture()
        sent = waiting_request(f.fake, () -> mouse_move!(f.page, 1, 2))
        @test !haskey(sent["params"], "steps")
        shutdown!(f.fake)
    end

    @testset "mouse_down! and mouse_up! default to the left button" begin
        f = timeout_fixture()
        down = waiting_request(f.fake, () -> mouse_down!(f.page))
        @test down["guid"] == "page@1"
        @test down["method"] == "mouseDown"
        @test down["params"]["button"] == "left"
        @test !haskey(down["params"], "clickCount")

        up = waiting_request(
            f.fake,
            () -> mouse_up!(f.page; button = "right", click_count = 2),
        )
        @test up["method"] == "mouseUp"
        @test up["params"]["button"] == "right"
        @test up["params"]["clickCount"] == 2
        shutdown!(f.fake)
    end

    @testset "mouse_click! carries the point, the button and the delay" begin
        f = timeout_fixture()
        sent = waiting_request(
            f.fake,
            () -> mouse_click!(f.page, 30, 40; button = "middle", delay = 25),
        )
        @test sent["guid"] == "page@1"
        @test sent["method"] == "mouseClick"
        @test sent["params"]["x"] == 30
        @test sent["params"]["y"] == 40
        @test sent["params"]["button"] == "middle"
        @test sent["params"]["delay"] == 25
        @test !haskey(sent["params"], "clickCount")
        shutdown!(f.fake)
    end

    @testset "mouse_wheel! sends both deltas" begin
        f = timeout_fixture()
        sent = waiting_request(f.fake, () -> mouse_wheel!(f.page, -12, 240))
        @test sent["guid"] == "page@1"
        @test sent["method"] == "mouseWheel"
        @test sent["params"]["deltaX"] == -12
        @test sent["params"]["deltaY"] == 240
        shutdown!(f.fake)
    end

    # --- Page: the keyboard ------------------------------------------------

    @testset "keyboard_press! sends the key and an optional delay" begin
        f = timeout_fixture()
        sent =
            waiting_request(f.fake, () -> keyboard_press!(f.page, "Control+A"; delay = 10))
        @test sent["guid"] == "page@1"
        @test sent["method"] == "keyboardPress"
        @test sent["params"]["key"] == "Control+A"
        @test sent["params"]["delay"] == 10
        shutdown!(f.fake)
    end

    @testset "keyboard_type! sends the text" begin
        f = timeout_fixture()
        sent = waiting_request(f.fake, () -> keyboard_type!(f.page, "hello"))
        @test sent["method"] == "keyboardType"
        @test sent["params"]["text"] == "hello"
        @test !haskey(sent["params"], "delay")
        shutdown!(f.fake)
    end

    @testset "keyboard_down!, keyboard_up! and keyboard_insert_text! hit their methods" begin
        f = timeout_fixture()
        for (fname, method, key) in
            ((keyboard_down!, "keyboardDown", "key"), (keyboard_up!, "keyboardUp", "key"))
            sent = waiting_request(f.fake, () -> fname(f.page, "Shift"))
            @test sent["method"] == method
            @test sent["params"][key] == "Shift"
        end
        sent = waiting_request(f.fake, () -> keyboard_insert_text!(f.page, "🙂"))
        @test sent["method"] == "keyboardInsertText"
        @test sent["params"]["text"] == "🙂"
        shutdown!(f.fake)
    end

    # --- Locators: the timeout cascade and the selector --------------------

    @testset "hover! resolves the timeout cascade" begin
        f = timeout_fixture()
        set_default_timeout!(f.page, 1_234)
        loc = locator(f.page, "#tip"; strict = false)
        sent = waiting_request(f.fake, () -> hover!(loc))
        @test sent["guid"] == "frame@1"
        @test sent["method"] == "hover"
        @test sent["params"]["selector"] == "#tip"
        @test sent["params"]["strict"] == false
        @test sent["params"]["timeout"] == 1_234
        shutdown!(f.fake)
    end

    @testset "the locator actions each hit their own method" begin
        f = timeout_fixture()
        loc = locator(f.page, "#x")
        cases = [
            (() -> dblclick!(loc), "dblclick"),
            (() -> focus!(loc), "focus"),
            (() -> check!(loc), "check"),
            (() -> uncheck!(loc), "uncheck"),
            (() -> tap!(loc), "tap"),
            (() -> blur!(loc), "blur"),
        ]
        for (action, method) in cases
            sent = waiting_request(f.fake, action)
            @test sent["method"] == method
            @test sent["guid"] == "frame@1"
            @test sent["params"]["selector"] == "#x"
            @test sent["params"]["strict"] == true
        end
        shutdown!(f.fake)
    end

    @testset "press! and type! carry the key or text and the delay" begin
        f = timeout_fixture()
        loc = locator(f.page, "#editor")
        pressed = waiting_request(
            f.fake,
            () -> press!(loc, "Control+A"; delay = 5, timeout = 2_000),
        )
        @test pressed["method"] == "press"
        @test pressed["params"]["key"] == "Control+A"
        @test pressed["params"]["delay"] == 5
        @test pressed["params"]["timeout"] == 2_000

        typed = waiting_request(f.fake, () -> type!(loc, "julia"; delay = 7))
        @test typed["method"] == "type"
        @test typed["params"]["text"] == "julia"
        @test typed["params"]["delay"] == 7
        shutdown!(f.fake)
    end

    # --- The compound actions ---------------------------------------------

    @testset "drag! sends both selectors and both positions" begin
        f = timeout_fixture()
        source = locator(f.page, "#card")
        target = locator(f.page, "#lane"; strict = false)
        sent = waiting_request(
            f.fake,
            () -> drag!(
                source,
                target;
                source_position = (x = 5, y = 6),
                target_position = Dict("x" => 50, "y" => 60),
                steps = 20,
                force = true,
            ),
        )
        @test sent["guid"] == "frame@1"
        @test sent["method"] == "dragAndDrop"
        @test sent["params"]["source"] == "#card"
        @test sent["params"]["target"] == "#lane"
        @test sent["params"]["strict"] == true
        @test sent["params"]["sourcePosition"] == Dict("x" => 5, "y" => 6)
        @test sent["params"]["targetPosition"] == Dict("x" => 50, "y" => 60)
        @test sent["params"]["steps"] == 20
        @test sent["params"]["force"] == true
        shutdown!(f.fake)
    end

    @testset "drag! takes a selector string for the target" begin
        f = timeout_fixture()
        sent = waiting_request(f.fake, () -> drag!(locator(f.page, "#card"), "#lane"))
        @test sent["method"] == "dragAndDrop"
        @test sent["params"]["target"] == "#lane"
        @test !haskey(sent["params"], "sourcePosition")
        @test !haskey(sent["params"], "steps")
        shutdown!(f.fake)
    end

    @testset "drag! refuses two locators in different frames" begin
        f = timeout_fixture()
        source = locator(f.frame, "#card")
        target = locator(f.childframe, "#lane")
        err = try
            drag!(source, target)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("same frame", err.msg)
        @test !isready(f.fake.client_messages)
        shutdown!(f.fake)
    end

    @testset "select_option! maps bare strings to valueOrLabel" begin
        f = timeout_fixture()
        picked = Ref{Any}(nothing)
        waiting_request(
            f.fake,
            () -> (picked[] = select_option!(locator(f.page, "#size"), "Large"));
            result = Dict{String,Any}("values" => ["l"]),
        )
        @test picked[] == ["l"]
        shutdown!(f.fake)

        # A second fixture for the wire shape: waiting_request consumed the
        # first fixture's only message above.
        f = timeout_fixture()
        sent = waiting_request(
            f.fake,
            () -> select_option!(locator(f.page, "#size"), "Large", (index = 2,));
            result = Dict{String,Any}("values" => ["l"]),
        )
        @test sent["method"] == "selectOption"
        @test sent["params"]["options"] ==
              [Dict("valueOrLabel" => "Large"), Dict("index" => 2)]
        shutdown!(f.fake)
    end

    @testset "select_option! with no values sends an empty list" begin
        f = timeout_fixture()
        sent = waiting_request(
            f.fake,
            () -> select_option!(locator(f.page, "#pick"));
            result = Dict{String,Any}("values" => String[]),
        )
        @test sent["params"]["options"] == []
        shutdown!(f.fake)
    end

    @testset "scroll_into_view_if_needed! waits, then scrolls the handle" begin
        f = timeout_fixture()
        send_create(f.fake, "frame@1", "ElementHandle", "handle@1")
        @test timedwait(
            () -> Playwright.lookup_object(f.fake.connection, "handle@1") !== nothing,
            5.0,
        ) === :ok

        task = @async scroll_into_view_if_needed!(locator(f.page, "#far"); timeout = 5_000)
        awaited = next_message(f.fake)
        @test awaited["guid"] == "frame@1"
        @test awaited["method"] == "waitForSelector"
        @test awaited["params"]["selector"] == "#far"
        @test awaited["params"]["timeout"] == 5_000
        reply_ok(
            f.fake,
            awaited["id"],
            Dict{String,Any}("element" => Dict("guid" => "handle@1")),
        )

        scrolled = next_message(f.fake)
        @test scrolled["guid"] == "handle@1"
        @test scrolled["method"] == "scrollIntoViewIfNeeded"
        @test scrolled["params"]["timeout"] == 5_000
        reply_ok(f.fake, scrolled["id"], Dict{String,Any}())

        @test await(task) === nothing
        shutdown!(f.fake)
    end
end
