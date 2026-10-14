# Read-only WebSocket observation. The driver reports text frames as UTF-8
# strings and binary frames as base64 strings, selected by the frame opcode.

@doc """
    WebSocket

A socket opened by a [`Page`](@ref), returned by
`expect_event(page, :websocket)` or a `with_events(page, :websocket)` stream.
Use [`url`](@ref) and [`is_closed`](@ref) for its state. Observe its traffic with
`with_events(socket, :framesent)` and `with_events(socket, :framereceived)`;
each event yields a [`WebSocketFrame`](@ref). The `:close` event yields the socket.
""" WebSocket

"""
    WebSocketFrame

One observed WebSocket frame. `opcode` is `1` for text or `2` for binary.
`payload` is a `String` for text or `Vector{UInt8}` for binary.
"""
struct WebSocketFrame
    payload::Union{String,Vector{UInt8}}
    opcode::Int
end

function web_socket_frame(params)
    opcode = Int(params["opcode"])
    data = String(params["data"])
    opcode in (1, 2) || throw(DriverError("unsupported WebSocket frame opcode $opcode"))
    return WebSocketFrame(opcode == 2 ? base64decode(data) : data, opcode)
end

"""    url(socket::WebSocket) -> String

The URL the page used to open this socket.
"""
url(socket::WebSocket) = socket.initializer["url"]::String

"""    is_closed(socket::WebSocket) -> Bool

Whether the socket has emitted `:close` or its protocol object has been disposed.
"""
function is_closed(socket::WebSocket)
    conn = socket.connection
    return lock(conn.lock) do
        get(socket.initializer, "isClosed", false) === true ||
        !haskey(conn.objects, socket.guid)
    end
end
