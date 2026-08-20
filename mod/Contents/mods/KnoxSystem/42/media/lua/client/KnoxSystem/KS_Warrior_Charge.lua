-- Warrior: Charge (Phase 4.11)
-- 1) Drop current anim, lock controls
-- 2) 15 ticks: force sprint anim start (uncontrollable)
-- 3) Dash ticks = 20 + 5*level (level 0 = 20), sprint forward with collision
-- Zombie knockback also collision-checked
require "KnoxSystem/KS_Class"
require "KnoxSystem/KS_ModData"

KnoxSystem.Warrior = KnoxSystem.Warrior or {}
KnoxSystem.Warrior.Charge = KnoxSystem.Warrior.Charge or {}

local BASE_DMG = 0.8
local DMG_PER_LEVEL = 0.25
local XP_PER_ZOMBIE = 12.0
local STAMINA_COST = 0.20          -- target ~20% (approx via short sprint-exert burst)
local END_RADIUS = 1.67
local KNOCK_PATH = 1.15
local KNOCK_END = 1.7
local STEP_DASH = 0.22
local WINDUP_TICKS = 15            -- walk / walk-combat only (standing blocked)
local DASH_BASE_TICKS = 20
local DASH_TICKS_PER_LEVEL = 5
local KD_BASE = 0.20
local KD_PER_LEVEL = 0.05
-- Heavy sprint flags for this many DASH ticks (~1/3 of 0.5.31 cost: was 8 ticks × 4 pulses)
local STAMINA_EXERT_DASH_TICKS = 3
local STAMINA_EXERT_PULSES = 3 -- applySprintExertion calls per exert tick

local active = {} -- [playerNum] = state
local _loggedStatsMethods = false
local _vanillaWriteOk = nil
local moveHist = {} -- [playerNum] = { {x,y}, ... } recent positions for standing check

------------------------------------------------------------------------
local function floater(player, text)
    if not player or not text then return end
    pcall(function()
        if type(player.setHaloNote) == "function" then player:setHaloNote(tostring(text)) end
    end)
end

local function callIfFn(obj, name, ...)
    if not obj then return false end
    if type(obj[name]) ~= "function" then return false end
    local pack = { pcall(obj[name], obj, ...) }
    return pack[1] == true, pack[2]
end

local function ensureData(player)
    return KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
end

local function getStats(player)
    local st = nil
    pcall(function() st = player:getStats() end)
    return st
end

--- Endurance moodle level 0–4 (4 = harshest). Works when Stats API is fully sealed.
local function getEnduranceMoodleLevel(player)
    local level = 0
    pcall(function()
        local moodles = player:getMoodles()
        if not moodles then return end
        local mt = nil
        if MoodleType then
            mt = MoodleType.Endurance or MoodleType.ENDURANCE
        end
        if mt ~= nil and type(moodles.getMoodleLevel) == "function" then
            local v = moodles:getMoodleLevel(mt)
            if type(v) == "number" then level = v end
        end
    end)
    return level
end

--- Try a Stats/player method ONLY if type==function. Never field-index Stats (B42 crashes Break-on-Error).
local function tryMethodNum(obj, name)
    if not obj then return nil end
    local t = nil
    local okT = pcall(function() t = type(obj[name]) end)
    if not okT or t ~= "function" then return nil end
    local ok, v = pcall(obj[name], obj)
    if ok and type(v) == "number" then return v end
    return nil
end

local function tryMethodCall(obj, name, ...)
    if not obj then return false end
    local t = nil
    local okT = pcall(function() t = type(obj[name]) end)
    if not okT or t ~= "function" then return false end
    local pack = { pcall(obj[name], obj, ...) }
    return pack[1] == true
end

--- Read 0–1 endurance if any method exists. No field reads on Stats.
local function getVanillaEndurance(player)
    local st = getStats(player)
    local n = tryMethodNum(st, "getEndurance")
        or tryMethodNum(st, "getPcEndurance")
        or tryMethodNum(player, "getEndurance")
    return n
end

--- Write endurance via methods only. NO field assignment (crashes on this B42).
local function setVanillaEndurance(player, value)
    value = math.max(0, math.min(1, value))
    local st = getStats(player)
    if not st then return false, "no-stats" end

    if not _loggedStatsMethods then
        _loggedStatsMethods = true
        local function tname(obj, n)
            local t = "err"
            pcall(function() t = type(obj[n]) end)
            return tostring(t)
        end
        local csType = "no-global"
        pcall(function()
            if CharacterStat ~= nil then csType = type(CharacterStat) end
        end)
        print(string.format(
            "[KnoxSystem] Charge Stats probe: getEndurance=%s setEndurance=%s getPcEndurance=%s setPcEndurance=%s CharacterStat=%s moodle=%d",
            tname(st, "getEndurance"), tname(st, "setEndurance"),
            tname(st, "getPcEndurance"), tname(st, "setPcEndurance"),
            csType, getEnduranceMoodleLevel(player)))
    end

    local before = getVanillaEndurance(player)

    if tryMethodCall(st, "setEndurance", value) then
        local after = getVanillaEndurance(player)
        if after and math.abs(after - value) < 0.08 then return true, "setEndurance" end
        if after and before and math.abs(after - before) > 0.01 then return true, "setEndurance-delta" end
    end
    if tryMethodCall(st, "setPcEndurance", value) then
        local after = getVanillaEndurance(player)
        if after and math.abs(after - value) < 0.08 then return true, "setPcEndurance" end
    end
    if tryMethodCall(player, "setEndurance", value) then
        local after = getVanillaEndurance(player)
        if after and math.abs(after - value) < 0.08 then return true, "player.setEndurance" end
    end

    -- CharacterStat global (B42.13+) if present
    local csOk = false
    pcall(function()
        if CharacterStat == nil then return end
        local cs = CharacterStat.ENDURANCE or CharacterStat.Endurance or CharacterStat.endurance
        if cs == nil and type(CharacterStat.get) == "function" then
            cs = CharacterStat.get("Endurance") or CharacterStat.get("endurance")
        end
        if cs == nil then return end
        if type(cs.set) == "function" then cs:set(player, value); csOk = true; return end
        if type(cs.setValue) == "function" then cs:setValue(player, value); csOk = true; return end
        if type(cs.setCurrent) == "function" then cs:setCurrent(player, value); csOk = true; return end
        if type(CharacterStat.set) == "function" then CharacterStat.set(player, cs, value); csOk = true end
    end)
    if csOk then
        local after = getVanillaEndurance(player)
        if after and math.abs(after - value) < 0.08 then return true, "CharacterStat" end
        -- moodle-only success check
        return true, "CharacterStat-attempt"
    end

    return false, string.format("before=%s methods-nil moodle=%d",
        tostring(before), getEnduranceMoodleLevel(player))
end

--- Heavy sprint flags — same style that emptied the bar in 0.5.28, but only for a short window.
local function applySprintExertion(player)
    if not player then return end
    pcall(function() if type(player.setSprinting) == "function" then player:setSprinting(true) end end)
    pcall(function() if type(player.setRunning) == "function" then player:setRunning(true) end end)
    pcall(function() if type(player.setMoving) == "function" then player:setMoving(true) end end)
    pcall(function() if type(player.setJustMoved) == "function" then player:setJustMoved(true) end end)
    pcall(function()
        if type(player.setBeenMovingFor) == "function" then player:setBeenMovingFor(180) end
    end)
    pcall(function()
        if type(player.setMovedDelta) == "function" then player:setMovedDelta(1.0) end
    end)
    pcall(function()
        if type(player.setVariable) == "function" then
            player:setVariable("bSprint", "true")
            player:setVariable("bRunning", "true")
            player:setVariable("bMoving", "true")
            player:setVariable("Sprint", "true")
        end
    end)
    pcall(function()
        if type(player.exert) == "function" then player:exert(0.015) end
    end)
    pcall(function()
        if type(player.DoFootSteps) == "function" then player:DoFootSteps() end
    end)
end

local function pulseExertion(player)
    for _ = 1, STAMINA_EXERT_PULSES do
        applySprintExertion(player)
    end
end

--- Optional method write only — never write absolute 0.
local function tryDrainMethods(player, frac)
    local van = getVanillaEndurance(player)
    if van == nil then return false, "no-read" end
    frac = math.min(math.max(0, frac or STAMINA_COST), STAMINA_COST)
    return setVanillaEndurance(player, math.max(0, van - frac))
end

local function drainStamina(player, frac)
    local moodleBefore = getEnduranceMoodleLevel(player)
    local vanBefore = getVanillaEndurance(player)
    local vanOk, how = tryDrainMethods(player, frac)
    if not vanOk then how = "dash-heavy-exert" end
    print(string.format(
        "[KnoxSystem] Charge stamina start cost=%.2f vanilla=%s ok=%s via=%s moodle=%d dashExertTicks=%d pulses=%d",
        frac, tostring(vanBefore), tostring(vanOk), tostring(how),
        moodleBefore, STAMINA_EXERT_DASH_TICKS, STAMINA_EXERT_PULSES))
    return true
end

function KnoxSystem.Warrior.Charge.recoverStamina(_player, _dt)
end

local function forwardVector(player)
    local dx, dy = 0, -1
    local got = false
    pcall(function()
        if type(player.getLookVector) == "function" and Vector2 then
            local v = player:getLookVector(Vector2.new())
            if v then
                local ox, x = callIfFn(v, "getX")
                local oy, y = callIfFn(v, "getY")
                if ox and oy then dx, dy, got = x, y, true end
            end
        end
    end)
    if not got then
        pcall(function()
            if type(player.getForwardDirection) == "function" then
                local v = player:getForwardDirection()
                if v then
                    local ox, x = callIfFn(v, "getX")
                    local oy, y = callIfFn(v, "getY")
                    if ox and oy then dx, dy, got = x, y, true end
                end
            end
        end)
    end
    if not got then
        pcall(function()
            local d = player:getDir()
            if not d then return end
            if type(d.dx) == "function" then dx, dy = d:dx(), d:dy(); return end
            local name = tostring(d)
            local map = {
                N = {0, -1}, NE = {0.707, -0.707}, E = {1, 0}, SE = {0.707, 0.707},
                S = {0, 1}, SW = {-0.707, 0.707}, W = {-1, 0}, NW = {-0.707, -0.707},
            }
            for k, v in pairs(map) do
                if name:find(k) then dx, dy = v[1], v[2]; break end
            end
        end)
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return 0, -1 end
    return dx / len, dy / len
end

local function canStartPose(player)
    if not player then return false, "no player" end
    local reason = nil
    pcall(function()
        if type(player.isSneaking) == "function" and player:isSneaking() then reason = "sneak"; return end
        if type(player.isSitOnGround) == "function" and player:isSitOnGround() then reason = "sit"; return end
        if type(player.isAsleep) == "function" and player:isAsleep() then reason = "rest"; return end
        if type(player.isClimbing) == "function" and player:isClimbing() then reason = "busy"; return end
        if type(player.isKnockedDown) == "function" and player:isKnockedDown() then reason = "down"; return end
        if type(player.isOnFloor) == "function" and player:isOnFloor() then reason = "down"; return end
    end)
    if reason then return false, reason end
    return true
end

local function isPlayerSprinting(player)
    local s = false
    pcall(function()
        if type(player.isSprinting) == "function" and player:isSprinting() then s = true end
    end)
    return s
end

local function isPlayerRunning(player)
    local r = false
    pcall(function()
        if type(player.isRunning) == "function" and player:isRunning() then r = true end
    end)
    return r
end

--- True when planted (idle stand or standing combat) — NOT walk / run / sprint.
--- Uses recent world-position samples (B42 isPlayerMoving can lie while idle).
local function trackPlayerMotion(player)
    if not player then return end
    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local x, y = player:getX(), player:getY()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local h = moveHist[id]
    if not h then
        h = {}
        moveHist[id] = h
    end
    h[#h + 1] = { x = x, y = y }
    while #h > 20 do table.remove(h, 1) end
end

--- Distance moved over recent samples (tiles).
local function recentMoveDistance(player)
    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local h = moveHist[id]
    if not h or #h < 4 then return 0 end
    local a, b = h[1], h[#h]
    local dx, dy = (b.x - a.x), (b.y - a.y)
    return math.sqrt(dx * dx + dy * dy)
end

--- Must be walking / running / sprinting — pure stand / stand-aim blocked.
local function isAllowedToChargeMove(player)
    if not player then return false end
    if isPlayerSprinting(player) then return true end
    if isPlayerRunning(player) then return true end

    -- Real displacement over last ~20 frames (~0.3+ tiles ≈ walking)
    local dist = recentMoveDistance(player)
    if dist >= 0.28 then return true end

    -- Secondary: engine flags only if also some displacement
    local flagMove = false
    pcall(function()
        if type(player.isPlayerMoving) == "function" and player:isPlayerMoving() then flagMove = true end
    end)
    pcall(function()
        if type(player.isMoving) == "function" and player:isMoving() then flagMove = true end
    end)
    if flagMove and dist >= 0.12 then return true end

    return false
end

local function isStationaryStance(player)
    return not isAllowedToChargeMove(player)
end

local function isStandingCombat(player)
    local aim = false
    pcall(function()
        if type(player.isAiming) == "function" and player:isAiming() then aim = true end
    end)
    pcall(function()
        if type(player.getVariableBoolean) == "function" and player:getVariableBoolean("bAiming") then aim = true end
    end)
    return aim and isStationaryStance(player)
end

--- Lock player input so Charge owns movement.
--- mode: "hard" | "standing_windup" | "exert" (sprint drain can run; no blockMovement)
local function setControlLock(player, lock, mode)
    if not player then return end
    mode = mode or "hard"
    local soft = (mode == "standing_windup" or mode == "exert")

    if lock and soft then
        -- Do NOT block/ignore movement — engine sprint endurance needs a live controller
        pcall(function()
            if type(player.setBlockMovement) == "function" then player:setBlockMovement(false) end
        end)
        pcall(function()
            if type(player.setIgnoreMovement) == "function" then player:setIgnoreMovement(false) end
        end)
        pcall(function()
            if type(player.setIgnoreAimingInput) == "function" then player:setIgnoreAimingInput(true) end
        end)
        -- Keep WASD from fighting Charge path without freezing locomote accounting
        pcall(function()
            if type(player.setIgnoreInputs) == "function" and mode == "exert" then
                -- leave inputs alone during exert so sprint drain bills
            elseif type(player.setIgnoreInputs) == "function" then
                player:setIgnoreInputs(false)
            end
        end)
        return
    end

    pcall(function()
        if type(player.setBlockMovement) == "function" then player:setBlockMovement(lock) end
    end)
    pcall(function()
        if type(player.setIgnoreMovement) == "function" then player:setIgnoreMovement(lock) end
    end)
    pcall(function()
        if type(player.setIgnoreAimingInput) == "function" then player:setIgnoreAimingInput(lock) end
    end)
    pcall(function()
        if type(player.setIgnoreInputs) == "function" then player:setIgnoreInputs(lock) end
    end)
    if lock then
        pcall(function()
            if type(player.setPath2) == "function" then player:setPath2(nil) end
        end)
        pcall(function()
            if type(player.getPathFindBehavior2) == "function" then
                local pb = player:getPathFindBehavior2()
                if pb and type(pb.reset) == "function" then pb:reset() end
            end
        end)
    end
end

--- Hard drop of walk / aim / combat / attack anims
local function dropOtherAnims(player)
    pcall(function() if type(player.setSneaking) == "function" then player:setSneaking(false) end end)
    pcall(function() if type(player.nullifyAiming) == "function" then player:nullifyAiming() end end)
    pcall(function() if type(player.setAiming) == "function" then player:setAiming(false) end end)
    pcall(function() if type(player.setForceShove) == "function" then player:setForceShove(false) end end)
    pcall(function() if type(player.setIsAiming) == "function" then player:setIsAiming(false) end end)
    pcall(function()
        if type(player.setVariable) == "function" then
            player:setVariable("bAiming", "false")
            player:setVariable("bAttack", "false")
            player:setVariable("bShoving", "false")
            player:setVariable("bClimbing", "false")
            player:setVariable("bVaulting", "false")
            player:setVariable("bMelee", "false")
            player:setVariable("bCancelAutoWalk", "true")
        end
    end)
    pcall(function()
        if type(player.clearVariable) == "function" then
            player:clearVariable("bAttack")
            player:clearVariable("AttackType")
        end
    end)
    pcall(function()
        if type(player.setBumpType) == "function" then player:setBumpType("") end
    end)
end

--- Force sprint locomote as hard as B42 allows (no AnimationPlayer method indexing — Kahlua throws)
local function forceSprintAnim(player)
    if not player then return end
    dropOtherAnims(player)

    -- Core sprint flags
    callIfFn(player, "setSprinting", true)
    callIfFn(player, "setRunning", true)
    callIfFn(player, "setMoving", true)

    pcall(function()
        if type(player.setVariable) == "function" then
            player:setVariable("bSprint", "true")
            player:setVariable("bRunning", "true")
            player:setVariable("bMoving", "true")
            player:setVariable("bAiming", "false")
            player:setVariable("bAttack", "false")
            player:setVariable("Sprint", "true")
            player:setVariable("Running", "true")
            player:setVariable("Moving", "true")
            player:setVariable("WalkSpeed", "1")
        end
    end)

    pcall(function()
        if type(player.setJustMoved) == "function" then player:setJustMoved(true) end
    end)
    pcall(function()
        if type(player.setMovedDelta) == "function" then player:setMovedDelta(1.0) end
    end)
    pcall(function()
        if type(player.setMomentumScalar) == "function" then player:setMomentumScalar(1.0) end
    end)

    -- IsoPlayer PlayAnim only if exposed as a real Lua function (never index AnimationPlayer.*)
    if type(player.PlayAnim) == "function" then
        pcall(function() player:PlayAnim("Sprint") end)
        pcall(function() player:PlayAnim("Run") end)
    end
    if type(player.playAnim) == "function" then
        pcall(function() player:playAnim("Sprint") end)
    end

    pcall(function()
        if type(player.reportEvent) == "function" then
            player:reportEvent("EventSprint")
        end
    end)
end

--- Standing / standing-combat only: exit idle/aim into sprint (no read-only anim vars)
local function forceSprintFromStanding(player)
    if not player then return end
    -- Clear aim via APIs only — do NOT setVariable("Aim") (read-only in B42)
    pcall(function() if type(player.nullifyAiming) == "function" then player:nullifyAiming() end end)
    pcall(function() if type(player.setAiming) == "function" then player:setAiming(false) end end)
    pcall(function() if type(player.setIsAiming) == "function" then player:setIsAiming(false) end end)
    pcall(function()
        if type(player.setVariable) == "function" then
            player:setVariable("bAiming", "false")
            player:setVariable("bIdle", "false")
            player:setVariable("bMoving", "true")
            player:setVariable("bRunning", "true")
            player:setVariable("bSprint", "true")
            player:setVariable("WalkSpeed", "1")
        end
    end)
    callIfFn(player, "setRunning", true)
    callIfFn(player, "setSprinting", true)
    callIfFn(player, "setMoving", true)
    pcall(function()
        if type(player.setJustMoved) == "function" then player:setJustMoved(true) end
    end)
    pcall(function()
        if type(player.setMovedDelta) == "function" then player:setMovedDelta(1.0) end
    end)
end

local function clearSprintAnim(player)
    if not player then return end
    callIfFn(player, "setSprinting", false)
    pcall(function()
        if type(player.setVariable) == "function" then
            player:setVariable("bSprint", "false")
            player:setVariable("Sprint", "false")
        end
    end)
end

local function pathToShort(player, tx, ty, tz)
    local ok = false
    local ix, iy, iz = math.floor(tx), math.floor(ty), math.floor(tz)
    pcall(function()
        if type(player.pathToLocation) == "function" then
            player:pathToLocation(ix, iy, iz)
            ok = true
        end
    end)
    if not ok then
        pcall(function()
            if type(player.getPathFindBehavior2) == "function" then
                local pb = player:getPathFindBehavior2()
                if pb and type(pb.pathToLocation) == "function" then
                    pb:pathToLocation(ix, iy, iz)
                    ok = true
                end
            end
        end)
    end
    return ok
end

local function clearPath(player)
    pcall(function()
        if type(player.setPath2) == "function" then player:setPath2(nil) end
    end)
    pcall(function()
        if type(player.getPathFindBehavior2) == "function" then
            local pb = player:getPathFindBehavior2()
            if pb and type(pb.reset) == "function" then pb:reset() end
        end
    end)
end

local function faceDir(player, dx, dy)
    pcall(function()
        if type(player.faceLocationF) == "function" then
            player:faceLocationF(player:getX() + dx * 4, player:getY() + dy * 4)
        elseif type(player.faceLocation) == "function" then
            player:faceLocation(player:getX() + dx * 4, player:getY() + dy * 4)
        end
    end)
end

local function setPos(obj, nx, ny)
    callIfFn(obj, "setX", nx)
    callIfFn(obj, "setY", ny)
    callIfFn(obj, "setLx", nx)
    callIfFn(obj, "setLy", ny)
end

local function isWorldBlocked(fx, fy, tx, ty, z)
    local cell = getCell()
    if not cell then return true end
    local iz = math.floor(z or 0)
    local fromSq, toSq = nil, nil
    pcall(function()
        fromSq = cell:getGridSquare(math.floor(fx), math.floor(fy), iz)
        toSq = cell:getGridSquare(math.floor(tx), math.floor(ty), iz)
    end)
    if not toSq then return true end

    local function flagTrue(sq, methodName)
        if not sq or type(sq[methodName]) ~= "function" then return false end
        local ok, res = pcall(sq[methodName], sq)
        return ok and res and true or false
    end

    if flagTrue(toSq, "isSolid") then return true end
    if flagTrue(toSq, "isSolidTrans") then return true end

    if type(toSq.getVehicleContainer) == "function" then
        local ok, veh = pcall(toSq.getVehicleContainer, toSq)
        if ok and veh then return true end
    end

    if fromSq then
        if type(fromSq.isBlockedTo) == "function" then
            local ok, res = pcall(fromSq.isBlockedTo, fromSq, toSq)
            if ok and res then return true end
        end
        if type(fromSq.getWallTo) == "function" then
            local ok, w = pcall(fromSq.getWallTo, fromSq, toSq)
            if ok and w then return true end
        end
        if type(fromSq.getDoorTo) == "function" then
            local ok, d = pcall(fromSq.getDoorTo, fromSq, toSq)
            if ok and d then
                local open = true
                if type(d.IsOpen) == "function" then
                    local o2, r = pcall(d.IsOpen, d)
                    if o2 then open = r and true or false end
                elseif type(d.isOpen) == "function" then
                    local o2, r = pcall(d.isOpen, d)
                    if o2 then open = r and true or false end
                end
                if not open then return true end
            end
        end
        if type(fromSq.getWindowTo) == "function" then
            local ok, w = pcall(fromSq.getWindowTo, fromSq, toSq)
            if ok and w then
                local open = false
                if type(w.IsOpen) == "function" then
                    local o2, r = pcall(w.IsOpen, w)
                    if o2 then open = r and true or false end
                end
                if not open then return true end
            end
        end
        if type(fromSq.getHoppableTo) == "function" then
            local ok, h = pcall(fromSq.getHoppableTo, fromSq, toSq)
            if ok and h then return true end
        end
    end

    if type(cell.getVehicles) == "function" then
        local okV, vehicles = pcall(cell.getVehicles, cell)
        if okV and vehicles and type(vehicles.size) == "function" and type(vehicles.get) == "function" then
            local okS, n = pcall(vehicles.size, vehicles)
            if okS and type(n) == "number" then
                for i = 0, n - 1 do
                    local okG, v = pcall(vehicles.get, vehicles, i)
                    if okG and v then
                        local okx, vx = callIfFn(v, "getX")
                        local oky, vy = callIfFn(v, "getY")
                        if okx and oky and math.abs(vx - tx) < 1.6 and math.abs(vy - ty) < 1.6 then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function moveWithCollision(obj, dx, dy, strength, z)
    if not obj then return false end
    local zx, zy = obj:getX(), obj:getY()
    local steps = 6
    local lastX, lastY = zx, zy
    local moved = false
    for i = 1, steps do
        local t = i / steps
        local tx = zx + dx * strength * t
        local ty = zy + dy * strength * t
        if isWorldBlocked(lastX, lastY, tx, ty, z) then break end
        lastX, lastY = tx, ty
        moved = true
    end
    if moved and (math.abs(lastX - zx) > 0.001 or math.abs(lastY - zy) > 0.001) then
        setPos(obj, lastX, lastY)
        return true
    end
    return false
end

local function knockbackZombie(zombie, dx, dy, strength, doKnockdown, z)
    if not zombie then return end
    moveWithCollision(zombie, dx, dy, strength, z or 0)
    callIfFn(zombie, "setStaggerBack", true)
    if doKnockdown then
        callIfFn(zombie, "setKnockedDown", true)
        pcall(function()
            if type(zombie.setHitReaction) == "function" then zombie:setHitReaction("Shotgun") end
        end)
    end
end

local function damageZombie(zombie, player, dmg)
    if not zombie then return false end
    local ok = false
    pcall(function()
        local w = nil
        if type(player.getPrimaryHandItem) == "function" then w = player:getPrimaryHandItem() end
        if type(zombie.Hit) == "function" then
            ok = pcall(function() zombie:Hit(w, player, dmg, false, 1.0) end)
            if not ok then ok = pcall(function() zombie:Hit(w, player, dmg, false, 1.0, false) end) end
        end
    end)
    if not ok then
        pcall(function()
            if type(zombie.getHealth) == "function" and type(zombie.setHealth) == "function" then
                local h = zombie:getHealth()
                if h then zombie:setHealth(math.max(0, h - dmg * 0.15)); ok = true end
            end
        end)
    end
    return ok
end

local function eachZombieNear(cell, cx, cy, z, radius, fn)
    if not cell then return end
    local r = math.ceil(radius)
    local z0 = math.floor(z)
    for ix = math.floor(cx) - r, math.floor(cx) + r do
        for iy = math.floor(cy) - r, math.floor(cy) + r do
            local square = nil
            pcall(function() square = cell:getGridSquare(ix, iy, z0) end)
            if square and type(square.getMovingObjects) == "function" then
                local moving = square:getMovingObjects()
                if moving and type(moving.size) == "function" then
                    for i = 0, moving:size() - 1 do
                        local obj = moving:get(i)
                        if obj and instanceof(obj, "IsoZombie") then
                            local zx, zy = obj:getX(), obj:getY()
                            local ddx, ddy = zx - cx, zy - cy
                            if (ddx * ddx + ddy * ddy) <= (radius * radius) then
                                fn(obj, ddx, ddy)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function knockdownChance(level)
    local lv = math.max(0, tonumber(level) or 0)
    return math.min(0.85, KD_BASE + lv * KD_PER_LEVEL)
end

local function dashTicksForLevel(level)
    local lv = math.max(0, tonumber(level) or 0)
    return DASH_BASE_TICKS + lv * DASH_TICKS_PER_LEVEL
end

local function finishCharge(st, reason)
    local player = st.player
    local cell = getCell()
    local ex, ey = player:getX(), player:getY()
    local kdChance = st.kdChance or KD_BASE
    local kdCount = 0

    eachZombieNear(cell, ex, ey, st.z, END_RADIUS, function(zom, zdx, zdy)
        local len = math.sqrt(zdx * zdx + zdy * zdy)
        local kx, ky = st.dx, st.dy
        if len > 0.05 then kx, ky = zdx / len, zdy / len end
        local doKd = (ZombRand(0, 1000) / 1000.0) < kdChance
        if doKd then kdCount = kdCount + 1 end
        knockbackZombie(zom, kx, ky, KNOCK_END, doKd, st.z)
        local zid = tostring(zom)
        pcall(function()
            if type(zom.getOnlineID) == "function" then zid = tostring(zom:getOnlineID()) end
        end)
        if not st.hitIds[zid] then
            st.hitIds[zid] = true
            if damageZombie(zom, player, st.dmg * 0.5) then
                st.hitCount = st.hitCount + 1
            end
        end
    end)

    if (st.hitCount or 0) > 0 then
        KnoxSystem.Class.addSkillXp(player, "Charge", st.hitCount * XP_PER_ZOMBIE, "charge_hit")
    end

    clearSprintAnim(player)
    setControlLock(player, false)
    floater(player, "*huff*")
    local moodleEnd = getEnduranceMoodleLevel(player)
    print(string.format(
        "[KnoxSystem] Charge end reason=%s hits=%d kd=%d dashTicks=%d/%d moodle=%d->%d",
        tostring(reason), st.hitCount or 0, kdCount, st.dashTicks or 0, st.dashMax or 0,
        st.moodleStart or -1, moodleEnd))
end

------------------------------------------------------------------------
function KnoxSystem.Warrior.Charge.getLevel(player)
    local data = ensureData(player)
    return KnoxSystem.Class.getSkillLevel(data, "Charge")
end

function KnoxSystem.Warrior.Charge.canUse(player)
    if not player then return false, "no player" end
    local data = ensureData(player)
    if not KnoxSystem.Class.isWarrior(data) then return false, "not warrior" end
    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    if active[id] then return false, "busy" end
    local ok, reason = canStartPose(player)
    if not ok then return false, reason end

    -- Standing / stand-aim: blocked (must be walking / running / sprinting)
    if not isAllowedToChargeMove(player) then
        print(string.format(
            "[KnoxSystem] Charge blocked standing dist=%.3f sprint=%s run=%s",
            recentMoveDistance(player), tostring(isPlayerSprinting(player)), tostring(isPlayerRunning(player))))
        return false, "standing"
    end

    -- Winded gate: Endurance moodle only (no stamina amount check)
    -- 0 none, 1 out of breath, 2 winded, 3 heavy, 4 exhausted
    local moodle = getEnduranceMoodleLevel(player)
    if moodle >= 2 then
        print(string.format("[KnoxSystem] Charge blocked moodle Endurance=%d", moodle))
        return false, "endurance"
    end
    return true
end

function KnoxSystem.Warrior.Charge.activate(player)
    local ok, reason = KnoxSystem.Warrior.Charge.canUse(player)
    if not ok then
        if reason == "endurance" then floater(player, "Too winded to Charge")
        elseif reason == "not warrior" then floater(player, "Charge requires Warrior")
        elseif reason == "busy" then floater(player, "Already charging")
        elseif reason == "standing" then floater(player, "Must be moving to Charge")
        elseif reason == "sneak" then floater(player, "Can't Charge while sneaking")
        elseif reason == "sit" then floater(player, "Can't Charge while sitting")
        elseif reason == "rest" then floater(player, "Can't Charge while resting")
        elseif reason == "down" then floater(player, "Can't Charge on the ground")
        else floater(player, "Can't Charge (" .. tostring(reason) .. ")")
        end
        return false
    end

    local level = math.max(0, KnoxSystem.Warrior.Charge.getLevel(player))
    local dmg = BASE_DMG + level * DMG_PER_LEVEL
    local kd = knockdownChance(level)
    local dashMax = dashTicksForLevel(level)

    drainStamina(player, STAMINA_COST)
    pcall(function()
        if KnoxSystem.Stats and KnoxSystem.Stats.logStamina then
            KnoxSystem.Stats.logStamina(player, "charge_activate")
        end
    end)

    local dx, dy = forwardVector(player)
    local z = player:getZ() or 0
    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)

    local alreadySprint = isPlayerSprinting(player)
    -- Sprint: instant dash. Walk / walk-combat: 15 tick windup. Standing blocked in canUse.
    local windup = alreadySprint and 0 or WINDUP_TICKS

    setControlLock(player, true, "hard")
    dropOtherAnims(player)
    forceSprintAnim(player)
    faceDir(player, dx, dy)

    active[id] = {
        player = player,
        dx = dx, dy = dy,
        z = z,
        dmg = dmg,
        kdChance = kd,
        hitIds = {},
        hitCount = 0,
        ticks = 0,
        phase = windup > 0 and "windup" or "dash",
        windupLeft = windup,
        dashTicks = 0,
        dashMax = dashMax,
        level = level,
        moodleStart = getEnduranceMoodleLevel(player),
    }

    print(string.format(
        "[KnoxSystem] Charge START L%d windup=%d dashMax=%d sprint=%s moodle=%d moveDist=%.3f dashExert=%d",
        level, windup, dashMax, tostring(alreadySprint),
        getEnduranceMoodleLevel(player), recentMoveDistance(player), STAMINA_EXERT_DASH_TICKS))
    return true
end

function KnoxSystem.Warrior.Charge.onPlayerUpdate(player)
    if not player then return end
    trackPlayerMotion(player)

    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local st = active[id]
    if not st then return end

    st.ticks = (st.ticks or 0) + 1

    local mul = 1
    pcall(function()
        if getGameTime and getGameTime().getMultiplier then
            mul = math.max(0.5, math.min(3, getGameTime():getMultiplier()))
        end
    end)

    ----------------------------------------------------------------
    -- WINDUP: no stamina bill (tiny bob only); hard lock
    ----------------------------------------------------------------
    if st.phase == "windup" then
        setControlLock(player, true, "hard")
        forceSprintAnim(player)
        faceDir(player, st.dx, st.dy)

        st.windupLeft = (st.windupLeft or 0) - 1
        local px, py = player:getX(), player:getY()
        local step = (((st.ticks % 2) == 0) and 0.02 or -0.01) * mul
        local nx = px + st.dx * step
        local ny = py + st.dy * step
        if not isWorldBlocked(px, py, nx, ny, st.z) then
            setPos(player, nx, ny)
        end
        pcall(function()
            if type(player.DoFootSteps) == "function" then player:DoFootSteps() end
        end)

        if st.windupLeft <= 0 then
            st.phase = "dash"
            st.dashTicks = 0
            print(string.format("[KnoxSystem] Charge windup done → dash for %d ticks (exert first %d)",
                st.dashMax, STAMINA_EXERT_DASH_TICKS))
        end
        if st.ticks > WINDUP_TICKS + 10 then
            finishCharge(st, "windup_timeout")
            active[id] = nil
        end
        return
    end

    ----------------------------------------------------------------
    -- DASH: first STAMINA_EXERT_DASH_TICKS bill stamina via sprint exert;
    -- rest of dash hard-locked (movement continues, bar stops dumping)
    ----------------------------------------------------------------
    clearPath(player)
    st.dashTicks = (st.dashTicks or 0) + 1
    local onExert = st.dashTicks <= STAMINA_EXERT_DASH_TICKS

    if onExert then
        setControlLock(player, true, "exert")
        forceSprintAnim(player)
        pulseExertion(player)
    else
        setControlLock(player, true, "hard")
        forceSprintAnim(player)
        pcall(function() if type(player.setSprinting) == "function" then player:setSprinting(true) end end)
    end
    faceDir(player, st.dx, st.dy)

    local px, py = player:getX(), player:getY()
    local step = STEP_DASH * mul
    local nx = px + st.dx * step
    local ny = py + st.dy * step

    if isWorldBlocked(px, py, nx, ny, st.z) then
        finishCharge(st, "blocked")
        active[id] = nil
        return
    end

    setPos(player, nx, ny)
    pcall(function()
        if type(player.DoFootSteps) == "function" then player:DoFootSteps() end
    end)

    local cell = getCell()
    eachZombieNear(cell, nx, ny, st.z, 1.15, function(zom)
        local zid = tostring(zom)
        pcall(function()
            if type(zom.getOnlineID) == "function" then zid = tostring(zom:getOnlineID()) end
        end)
        knockbackZombie(zom, st.dx, st.dy, KNOCK_PATH, false, st.z)
        if not st.hitIds[zid] then
            st.hitIds[zid] = true
            if damageZombie(zom, player, st.dmg) then
                st.hitCount = st.hitCount + 1
            end
        end
    end)

    if st.dashTicks >= (st.dashMax or DASH_BASE_TICKS) then
        finishCharge(st, "dash_complete")
        active[id] = nil
        return
    end
end

function KnoxSystem.Warrior.Charge.unlockZombie(_z) end
function KnoxSystem.Warrior.Charge.unlockIfStunned(_z) end
function KnoxSystem.Warrior.Charge.onWeaponHit(_a, _t) end
