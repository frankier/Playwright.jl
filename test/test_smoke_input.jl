# Real gestures, on every engine in SMOKE_ENGINES.
#
# The hermetic input tests prove a wrapper sent the right protocol call; only a
# browser can prove the page's handlers ran. Every assertion here reads state
# the page itself maintained — a stroke count on `window`, a status paragraph —
# so a mouse event that never arrived cannot pass by being merely well-formed.

@testset "input ($(eng))" for eng in SMOKE_ENGINES
    with_fixture_server() do base_url
        playwright() do pw
            browser = launch(engine(pw, eng); headless = true)
            page = new_page(browser)
            goto!(page, "$base_url/input.html")

            # Viewport-relative centre of an element, which is the coordinate
            # space the page-level mouse functions speak.
            function centre(selector)
                rect = evaluate(
                    page,
                    """(sel) => {
                      const r = document.querySelector(sel).getBoundingClientRect();
                      return {x: r.x + r.width / 2, y: r.y + r.height / 2};
                    }""",
                    selector,
                )
                return (rect["x"], rect["y"])
            end

            @testset "the mouse triple paints on a canvas" begin
                # `steps` is the whole point: a painting handler reads the
                # intermediate `mousemove` events a single jump does not send.
                x, y = centre("#pad")
                mouse_move!(page, x - 80, y - 60)
                mouse_down!(page)
                mouse_move!(page, x - 80 + 160, y - 60 + 80; steps = 20)
                mouse_up!(page)

                @test evaluate(page, "window.paint.strokes") > 0
                @test evaluate(page, "window.paint.moves") >= 20
                @test evaluate(
                    page,
                    """() => {
                      const pad = document.getElementById("pad");
                      const d = pad.getContext("2d").getImageData(
                        0, 0, pad.width, pad.height).data;
                      let black = 0;
                      for (let i = 0; i < d.length; i += 4) {
                        if (d[i] < 50 && d[i+1] < 50 && d[i+2] < 50) black++;
                      }
                      return black;
                    }""",
                ) > 0
            end

            @testset "hover! runs the page's mouseenter handler" begin
                hover!(locator(page, "#hover-target"))
                @test text_content(locator(page, "#hover-status")) == "hovered"
            end

            @testset "dblclick! is one gesture the page reads as a double" begin
                dblclick!(locator(page, "#dbl"))
                @test text_content(locator(page, "#dbl-status")) == "1"
            end

            @testset "focus! and blur! fire the page's handlers" begin
                field = locator(page, "#focusfield")
                focus!(field)
                @test text_content(locator(page, "#focus-status")) == "focused"
                blur!(field)
                @test text_content(locator(page, "#focus-status")) == "blurred"
            end

            @testset "press! and type! carry keys to the element" begin
                field = locator(page, "#keyfield")
                evaluate(
                    page,
                    "() => { window.keyed = []; document.getElementById('key-log').textContent = ''; }",
                )
                press!(field, "Enter")
                @test evaluate(page, "window.keyed") == ["Enter"]

                type!(field, "abc"; delay = 1)
                @test input_value(field) == "abc"
                @test evaluate(page, "window.keyed") == ["Enter", "a", "b", "c"]
            end

            @testset "check! and uncheck! flip the box" begin
                box = locator(page, "#box")
                check!(box)
                @test is_checked(box)
                uncheck!(box)
                @test !is_checked(box)
            end

            @testset "select_option! selects by label and clears a multi-select" begin
                size = locator(page, "#size")
                selected = select_option!(size, "Large")
                @test selected == ["l"]
                @test input_value(size) == "l"
                @test text_content(locator(page, "#size-status")) == "l"

                pick = locator(page, "#pick")
                @test select_option!(pick, "a", "c") == ["a", "c"]
                @test sort(
                    evaluate(
                        page,
                        "() => Array.from(document.querySelector('#pick').selectedOptions).map(o => o.value)",
                    ),
                ) == ["a", "c"]
                @test select_option!(pick) == String[]
            end

            @testset "drag! drops the source on the target" begin
                # Fresh page: an earlier action's scroll can leave the source
                # and target in awkward places relative to each other.
                goto!(page, "$base_url/input.html")
                drag!(locator(page, "#drag-source"), locator(page, "#drop-target"))
                @test text_content(locator(page, "#drop-status")) == "source"
            end

            @testset "mouse_click! lands at the coordinates" begin
                scroll_into_view_if_needed!(locator(page, "#coord"))
                x, y = centre("#coord")
                mouse_click!(page, x, y)
                @test text_content(locator(page, "#coord-status")) == "0:1"
            end

            @testset "mouse_wheel! scrolls what is under the pointer" begin
                scroll_into_view_if_needed!(locator(page, "#scroller"))
                x, y = centre("#scroller")
                mouse_move!(page, x, y)
                mouse_wheel!(page, 0, 200)
                scrolled =
                    retry_until(; timeout = 5_000, interval = 50, on_timeout = :false) do
                        evaluate(page, "document.querySelector('#scroller').scrollTop") > 0
                    end
                @test scrolled
            end

            @testset "the page-level keyboard reaches the focused field" begin
                field = locator(page, "#keyfield")
                evaluate(
                    page,
                    "() => { window.keyed = []; document.getElementById('key-log').textContent = ''; document.getElementById('keyfield').value = ''; }",
                )
                focus!(field)
                keyboard_press!(page, "a")
                @test evaluate(page, "window.keyed") == ["a"]
                keyboard_down!(page, "Shift")
                keyboard_insert_text!(page, "b")
                keyboard_up!(page, "Shift")
                @test input_value(field) == "ab"
            end

            @testset "scroll_into_view_if_needed! brings a far element into view" begin
                evaluate(page, "() => window.scrollTo(0, 0)")
                before = evaluate(
                    page,
                    "() => document.querySelector('#far').getBoundingClientRect().top",
                )
                @test before > 720   # below the default viewport

                scroll_into_view_if_needed!(locator(page, "#far"))
                after = evaluate(
                    page,
                    "() => document.querySelector('#far').getBoundingClientRect().top",
                )
                @test 0 <= after < 720
            end

            @testset "tap! fires a touch click" begin
                touch_ctx = new_context(browser; has_touch = true)
                try
                    touch_page = new_page(touch_ctx)
                    goto!(touch_page, "$base_url/input.html")
                    tap!(locator(touch_page, "#tap"))
                    @test text_content(locator(touch_page, "#tap-status")) == "tapped"
                finally
                    close!(touch_ctx)
                end
            end

            close!(browser)
        end
    end
end
