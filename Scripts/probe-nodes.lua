#!/usr/bin/lua5.3
-- Lightweight TCP reachability test. This is not a VPN authentication test.
local socket = require("socket")
local input = io.open("/etc/happvpn/probes.tsv", "r")
if not input then os.exit(0) end

local output = "/tmp/happvpn/probe-results.tsv"
local file = assert(io.open(output .. ".tmp", "w"))
for line in input:lines() do
    local tag, address, port = line:match("^([%w%-]+)\t([%w%.%-%:]+)\t(%d+)$")
    port = tonumber(port)
    if tag and address and port and port > 0 and port < 65536 then
        local client = socket.tcp()
        client:settimeout(2)
        local started = socket.gettime()
        local ok = client:connect(address, port)
        local delay = math.floor((socket.gettime() - started) * 1000 + 0.5)
        client:close()
        file:write(string.format("%s\t%d\t%d\t%d\n",
            tag, ok and 1 or 0, ok and delay or 0, os.time()))
    end
end
input:close()
file:close()
assert(os.rename(output .. ".tmp", output))
