-- KnoxSystem tracking / verification log (extensible channels)
-- Console + optional file under Zomboid Lua logs. Add channels via register().
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Config"

KnoxSystem.Track = KnoxSystem.Track or {}

local Track = KnoxSystem.Track

--- Default config (overridden/merged from KS_Config.TrackLog if present).
local function cfg()
    local c = KnoxSystem.Config and KnoxSystem.Config.TrackLog
    if type(c) ~= "table" then
        c = {}
    end
    return c
end

local channels = {
    -- name -> { enabled = bool, desc = string }
    damage = { enabled = true, desc = "Melee hit full chain: weapon base → engine raw → weapon skill → Strength → Power → MeleeProf" },
    stress = { enabled = true, desc = "Armored Uncomfortable stress relief windows" },
    protection = { enabled = true, desc = "Armored protection mult sync + incoming hit defense" },
    strength = { enabled = false, desc = "DEPRECATED alias — use power" },
    power = { enabled = true, desc = "Power=hidden +N Strength (getPerkLevel); real vs effective logs" },
    stamina = { enabled = true, desc = "Personal Endurance/Stamina vs Fitness + endurance bar + drain delta" },
    zombie = { enabled = false, desc = "OFF: zombie stamp/observe/elite loot (suppressed)" },
    strength_apply = { enabled = true, desc = "Strength applications: fence/vault, muscle strain, shove, door/thump; real vs effective" },
    loot = { enabled = true, desc = "Spawned/container loot rarity check (Analyze colors)" },
    resilience = { enabled = true, desc = "Personal Resilience: post-infection resist rolls / clear System Infection" },
}

local ring = {}
local ringMax = 200
local ringI = 0
local fileFailLogged = false

function Track.isEnabled()
    local c = cfg()
    if c.enabled == false then return false end
    return true
end

function Track.isChannelOn(name)
    if not Track.isEnabled() then return false end
    if not name then return false end
    local c = cfg()
    if type(c.channels) == "table" and c.channels[name] ~= nil then
        return c.channels[name] and true or false
    end
    local ch = channels[name]
    return ch and ch.enabled ~= false
end

--- Register or update a channel for future tests.
--- opts: { enabled=bool, desc=string }
function Track.register(name, opts)
    if not name or name == "" then return false end
    opts = opts or {}
    local prev = channels[name] or {}
    channels[name] = {
        enabled = opts.enabled ~= nil and opts.enabled or (prev.enabled ~= false),
        desc = opts.desc or prev.desc or name,
    }
    local c = cfg()
    if type(c.channels) == "table" and c.channels[name] == nil then
        c.channels[name] = channels[name].enabled
    end
    return true
end

function Track.listChannels()
    local out = {}
    for k, v in pairs(channels) do
        out[#out + 1] = {
            name = k,
            enabled = Track.isChannelOn(k),
            desc = v.desc,
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function kvString(fields)
    if type(fields) ~= "table" then return "" end
    local keys = {}
    for k in pairs(fields) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = fields[k]
        if type(v) == "number" then
            -- trim noisy floats
            if v == math.floor(v) and math.abs(v) < 1e12 then
                parts[#parts + 1] = string.format("%s=%s", k, tostring(v))
            else
                parts[#parts + 1] = string.format("%s=%.4f", k, v)
            end
        else
            parts[#parts + 1] = string.format("%s=%s", k, tostring(v))
        end
    end
    if #parts == 0 then return "" end
    return " " .. table.concat(parts, " ")
end

local function pushRing(line)
    local c = cfg()
    local maxN = tonumber(c.maxRing) or ringMax
    if maxN < 10 then maxN = 10 end
    ringMax = maxN
    ringI = ringI + 1
    local idx = ((ringI - 1) % ringMax) + 1
    ring[idx] = line
end

local function writeFile(line)
    local c = cfg()
    if c.toFile == false then return end
    local name = c.fileName or "KnoxSystem_track.log"
    local ok, err = pcall(function()
        if not getFileWriter then return end
        -- append=true, createIfNull=true (B41/B42 getFileWriter(path, createIfNull, append) varies)
        local w = nil
        pcall(function() w = getFileWriter(name, true, true) end)
        if not w then
            pcall(function() w = getFileWriter(name, true, false) end)
        end
        if w then
            w:write(line .. "\n")
            w:close()
        end
    end)
    if not ok and not fileFailLogged then
        fileFailLogged = true
        print("[KnoxTrack] file write failed: " .. tostring(err))
    end
end

local function timestamp()
    local s = ""
    pcall(function()
        if getTimestampMs then
            s = string.format("t=%d", getTimestampMs())
        elseif getGameTime and getGameTime() and getGameTime().getWorldAgeHours then
            s = string.format("worldH=%.3f", getGameTime():getWorldAgeHours())
        else
            s = string.format("os=%d", os.time())
        end
    end)
    return s
end

--- Truncate track log file (and optional in-memory ring). Called on game start.
function Track.clear(opts)
    opts = opts or {}
    local clearRing = opts.ring ~= false
    if clearRing then
        ring = {}
        ringI = 0
    end
    local c = cfg()
    if c.toFile == false then
        print("[KnoxTrack] cleared ring (file logging off)")
        return
    end
    local name = c.fileName or "KnoxSystem_track.log"
    local ok, err = pcall(function()
        if not getFileWriter then return end
        -- createIfNull=true, append=false → overwrite/truncate
        local w = nil
        pcall(function() w = getFileWriter(name, true, false) end)
        if not w then
            pcall(function() w = getFileWriter(name, false, false) end)
        end
        if w then
            local header = string.format(
                "# KnoxSystem track log cleared %s version=%s\n",
                timestamp(),
                tostring(KnoxSystem and KnoxSystem.VERSION or "?")
            )
            w:write(header)
            w:close()
        end
    end)
    if ok then
        print(string.format("[KnoxTrack] log file cleared: %s", tostring(name)))
        fileFailLogged = false
    else
        print("[KnoxTrack] clear failed: " .. tostring(err))
    end
end

--- Print to in-game/debug console. style "red" uses DebugType error stream (red ERROR: prefix).
local function consolePrint(line, style)
    if style == "red" then
        local ok = false
        pcall(function()
            -- Prefer Mod channel error severity — shows as ERROR: (red) in debug console
            if DebugType and DebugType.Mod and DebugType.Mod.error then
                DebugType.Mod:error("%s", line)
                ok = true
                return
            end
            if DebugType and DebugType.Lua and DebugType.Lua.error then
                DebugType.Lua:error("%s", line)
                ok = true
                return
            end
        end)
        if ok then return end
        -- ANSI red fallback (some external terminals; ignored if not supported)
        print("\27[31m" .. tostring(line) .. "\27[0m")
        return
    end
    print(line)
end

local function shallowCopyWithoutStyle(t)
    local n = {}
    if type(t) ~= "table" then return n end
    for k, v in pairs(t) do
        if k ~= "_style" then n[k] = v end
    end
    return n
end

--- Log a tracking line on channel.
--- fields: optional flat table of numbers/strings for key=value suffix.
--- style (optional 4th arg or fields._style): "red" / "elite" → console ERROR severity (red)
function Track.log(channel, message, fields, style)
    if not Track.isChannelOn(channel) then return end
    message = message or ""
    -- Don't put _style into kv output
    local styleField = nil
    if type(fields) == "table" and fields._style then
        styleField = fields._style
        fields = shallowCopyWithoutStyle(fields)
    end
    local line = string.format(
        "[KnoxTrack/%s] %s | %s%s",
        tostring(channel),
        timestamp(),
        tostring(message),
        kvString(fields)
    )
    pushRing(line)
    local c = cfg()
    if c.toConsole ~= false then
        local useRed = style == "red" or style == "elite" or styleField == "red" or styleField == "elite"
        if not useRed and type(fields) == "table" then
            local e = fields.elite or fields.knoxElite
            if e == true or e == 1 or e == "1" or e == "true" then
                useRed = true
            end
        end
        if not useRed and type(message) == "string" then
            local m = message:lower()
            if m:find("elite", 1, true) then useRed = true end
        end
        consolePrint(line, useRed and "red" or nil)
    end
    writeFile(line)
end

function Track.logf(channel, fmt, ...)
    if not Track.isChannelOn(channel) then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    Track.log(channel, msg, nil)
end

--- Dump recent ring to console (for in-game verification).
function Track.dump(n)
    n = tonumber(n) or 50
    print(string.format("[KnoxTrack] dump last ~%d (ring has %d slots, writes=%d)", n, ringMax, ringI))
    local total = math.min(n, math.min(ringI, ringMax))
    if total <= 0 then
        print("[KnoxTrack] (empty)")
        return
    end
    -- print chronological
    local start = ringI - total + 1
    for i = start, ringI do
        local idx = ((i - 1) % ringMax) + 1
        if ring[idx] then print(ring[idx]) end
    end
end

function Track.status()
    print(string.format(
        "[KnoxTrack] enabled=%s console=%s file=%s fileName=%s",
        tostring(Track.isEnabled()),
        tostring(cfg().toConsole ~= false),
        tostring(cfg().toFile ~= false),
        tostring(cfg().fileName or "KnoxSystem_track.log")
    ))
    for _, ch in ipairs(Track.listChannels()) do
        print(string.format("  channel %-12s on=%s — %s", ch.name, tostring(ch.enabled), tostring(ch.desc)))
    end
end

-- Seed known channels into config table if missing
do
    local c = cfg()
    if KnoxSystem.Config then
        KnoxSystem.Config.TrackLog = KnoxSystem.Config.TrackLog or {}
        c = KnoxSystem.Config.TrackLog
        if c.enabled == nil then c.enabled = true end
        if c.toConsole == nil then c.toConsole = true end
        if c.toFile == nil then c.toFile = true end
        if c.fileName == nil then c.fileName = "KnoxSystem_track.log" end
        if c.maxRing == nil then c.maxRing = 200 end
        c.channels = c.channels or {}
        for name, meta in pairs(channels) do
            if c.channels[name] == nil then
                c.channels[name] = meta.enabled ~= false
            end
        end
    end
end

print("[KnoxSystem] KS_TrackLog loaded (damage, stress, protection, strength, stamina, zombie, loot; elite→red console)")
