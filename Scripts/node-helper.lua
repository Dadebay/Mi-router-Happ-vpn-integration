#!/usr/bin/lua5.3
-- Rank saved Shadowsocks profiles or verify a local SOCKS listener end to end.
local base = "/etc/happvpn"

local function profile_exists(tag)
    if not tag:match("^ss%-%d+$") then return false end
    local file = io.open(base .. "/profiles/" .. tag .. ".json", "r")
    if not file then return false end
    file:close()
    return true
end

if arg[1] == "rank" then
    local input = io.open("/tmp/happvpn/probe-results.tsv", "r")
    if not input then os.exit(1) end
    local candidates = {}
    local now = os.time()
    for line in input:lines() do
        local tag, alive, delay, measured = line:match("^(ss%-%d+)%s+(%d)%s+(%d+)%s+(%d+)$")
        delay, measured = tonumber(delay), tonumber(measured)
        if tag and alive == "1" and delay and measured
            and delay >= 0 and measured <= now and now - measured <= 2700
            and profile_exists(tag) then
            candidates[#candidates + 1] = { tag = tag, delay = delay }
        end
    end
    input:close()
    table.sort(candidates, function(a, b)
        if a.delay == b.delay then return a.tag < b.tag end
        return a.delay < b.delay
    end)
    for index = 1, #candidates do print(candidates[index].tag) end
    os.exit(#candidates > 0 and 0 or 1)
end

if arg[1] ~= "check" then
    io.stderr:write("usage: node-helper.lua {rank|check PORT}\n")
    os.exit(2)
end

local port = tonumber(arg[2])
if not port or port < 1 or port > 65535 then os.exit(2) end
local socket = require("socket")
local client = assert(socket.tcp())
client:settimeout(10)

local function verify()
    assert(client:connect("127.0.0.1", port))
    assert(client:send(string.char(5, 1, 0)))
    assert(client:receive(2) == string.char(5, 0), "SOCKS handshake failed")
    local host = "api.ipify.org"
    assert(client:send(string.char(5, 1, 0, 3, #host) .. host .. string.char(0, 80)))
    local reply = assert(client:receive(4))
    assert(reply:byte(1) == 5 and reply:byte(2) == 0, "SOCKS connection failed")
    local kind = reply:byte(4)
    if kind == 1 then
        assert(client:receive(6))
    elseif kind == 3 then
        local size = assert(client:receive(1)):byte()
        assert(client:receive(size + 2))
    elseif kind == 4 then
        assert(client:receive(18))
    else
        error("Invalid SOCKS response")
    end
    assert(client:send("GET / HTTP/1.0\r\nHost: api.ipify.org\r\nConnection: close\r\n\r\n"))
    local response, _, partial = client:receive("*a")
    response = response or partial or ""
    assert(response:match("^HTTP/1%.[01] 200"), "IP service did not respond")
    local body = response:match("\r\n\r\n(.*)") or ""
    local ip = body:match("^%s*(%d+%.%d+%.%d+%.%d+)%s*$")
    assert(ip, "Invalid VPN exit address")
    for octet in ip:gmatch("%d+") do assert(tonumber(octet) <= 255) end
    return ip
end

local ok, result = pcall(verify)
client:close()
if not ok then
    io.stderr:write(tostring(result), "\n")
    os.exit(1)
end
print(result)
