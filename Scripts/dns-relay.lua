local socket = require('socket')
local udp = assert(socket.udp())
assert(udp:setsockname('127.0.0.1', 5354))
udp:settimeout(1)

local upstream

local function disconnect()
    if upstream then upstream:close() end
    upstream = nil
end

local function connect()
    local tcp = assert(socket.tcp())
    tcp:settimeout(8)
    local ok, err = pcall(function()
        assert(tcp:connect('127.0.0.1', 1080))
        assert(tcp:send(string.char(5, 1, 0)))
        assert(tcp:receive(2) == string.char(5, 0), 'SOCKS authentication failed')
        assert(tcp:send(string.char(5, 1, 0, 1, 1, 1, 1, 1, 0, 53)))
        local reply = assert(tcp:receive(10))
        assert(reply:byte(2) == 0, 'SOCKS connection rejected')
    end)
    if not ok then tcp:close(); error(err) end
    upstream = tcp
end

local function query_over_vpn(request)
    if #request < 12 or #request > 4096 then return nil, 'invalid DNS packet size' end
    for attempt = 1, 2 do
        local ok, response = pcall(function()
            if not upstream then connect() end
            assert(upstream:send(string.pack('>I2', #request) .. request))
            local length = string.unpack('>I2', assert(upstream:receive(2)))
            assert(length >= 12 and length <= 4096, 'invalid upstream DNS response size')
            return assert(upstream:receive(length))
        end)
        if ok then return response end
        disconnect()
        if attempt == 2 then return nil, response end
    end
end

local last_error = 0
while true do
    local request, client_ip, client_port = udp:receivefrom()
    if request then
        local response, err = query_over_vpn(request)
        if response then
            udp:sendto(response, client_ip, client_port)
        elseif socket.gettime() - last_error > 30 then
            io.stderr:write('HappVPN DNS relay: ', tostring(err), '\n')
            last_error = socket.gettime()
        end
    end
end
