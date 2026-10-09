#!/usr/bin/lua5.3
-- Accumulate per-station Wi-Fi bytes for the current Ashgabat day.
-- iw counters reset when a station reconnects. /tmp is saved to flash hourly.

local offset = 5 * 3600
local now = os.time()
local day = os.date("!%Y-%m-%d", now + offset)
local state_dir = "/tmp/happvpn"
local volatile = state_dir .. "/usage-state.tsv"
local persistent = "/etc/happvpn/usage-state.tsv"
local current = state_dir .. "/usage-today.tsv"

os.execute("mkdir -p " .. state_dir)

local function read_state(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local values = {}
    for line in file:lines() do
        local record_day, mac, rx, tx, up, down =
            line:match("^(%d%d%d%d%-%d%d%-%d%d)\t([%x:]+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)$")
        if record_day and mac then
            values[mac:lower()] = {
                day = record_day, rx = tonumber(rx), tx = tonumber(tx),
                up = tonumber(up), down = tonumber(down)
            }
        end
    end
    file:close()
    return values
end

local state = read_state(volatile) or read_state(persistent) or {}
local pipe = io.popen("iw dev phy0-ap0 station dump 2>/dev/null", "r")
if not pipe then os.exit(1) end
local stations = {}
local mac
for line in pipe:lines() do
    local found = line:match("^Station ([%x:]+)")
    if found then
        mac = found:lower()
        stations[mac] = {rx = 0, tx = 0}
    elseif mac then
        local rx = line:match("^%s*rx bytes:%s*(%d+)")
        local tx = line:match("^%s*tx bytes:%s*(%d+)")
        if rx then stations[mac].rx = tonumber(rx) end
        if tx then stations[mac].tx = tonumber(tx) end
    end
end
pipe:close()

local function delta(value, previous)
    if not previous then return value end
    if value >= previous then return value - previous end
    return value -- Station counters restarted after reconnect.
end

for address, counters in pairs(stations) do
    local previous = state[address]
    local up_delta = delta(counters.rx, previous and previous.rx)
    local down_delta = delta(counters.tx, previous and previous.tx)
    local same_day = previous and previous.day == day
    state[address] = {
        day = day, rx = counters.rx, tx = counters.tx,
        up = (same_day and previous.up or 0) + up_delta,
        down = (same_day and previous.down or 0) + down_delta
    }
end

local addresses = {}
for address in pairs(state) do addresses[#addresses + 1] = address end
table.sort(addresses)

local function save(path, daily)
    local temporary = path .. ".tmp"
    local file = assert(io.open(temporary, "w"))
    for _, address in ipairs(addresses) do
        local record = state[address]
        if record.day == day then
            if daily then
                file:write(string.format("%s\t%s\t%.0f\t%.0f\n",
                    day, address, record.up, record.down))
            else
                file:write(string.format("%s\t%s\t%.0f\t%.0f\t%.0f\t%.0f\n",
                    day, address, record.rx, record.tx, record.up, record.down))
            end
        end
    end
    file:close()
    assert(os.rename(temporary, path))
end

save(volatile, false)
save(current, true)
os.execute("chmod 600 " .. volatile .. " " .. current)
local backup = io.open(persistent, "r")
local first_save = backup == nil
if backup then backup:close() end
if first_save or os.date("!%M", now + offset) == "00" then
    os.execute("cp " .. volatile .. " " .. persistent .. " && chmod 600 " .. persistent)
end
