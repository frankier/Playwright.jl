using Base64: base64encode

@testset "WebSocket observation" begin
    f = event_fixture()
    socket = expect_event(f.page, :websocket) do
        send_create(
            f.fake,
            "page@1",
            "WebSocket",
            "socket@1",
            Dict{String,Any}("url" => "ws://example.test/ws"),
        )
        @test timedwait(
            () -> Playwright.lookup_object(f.conn, "socket@1") !== nothing,
            5.0,
        ) === :ok
        send_event(
            f.fake,
            "page@1",
            "webSocket",
            Dict("webSocket" => Dict("guid" => "socket@1")),
        )
    end
    @test socket isa WebSocket
    @test url(socket) == "ws://example.test/ws"
    @test !is_closed(socket)

    with_events(socket, :framesent) do sent
        with_events(socket, :framereceived) do received
            send_event(
                f.fake,
                socket.guid,
                "frameSent",
                Dict("opcode" => 1, "data" => "hello"),
            )
            send_event(
                f.fake,
                socket.guid,
                "frameReceived",
                Dict("opcode" => 2, "data" => base64encode(UInt8[0x00, 0xff])),
            )
            outgoing = next_event(sent; timeout = 5_000)
            incoming = next_event(received; timeout = 5_000)
            @test outgoing isa WebSocketFrame
            @test outgoing.opcode == 1
            @test outgoing.payload == "hello"
            @test incoming.opcode == 2
            @test incoming.payload == UInt8[0x00, 0xff]
        end
    end
    @test subscription_count(f.conn) == 0

    closed = expect_event(socket, :close) do
        send_event(f.fake, socket.guid, "close")
    end
    @test closed === socket
    @test is_closed(socket)
    shutdown!(f.fake)
end
