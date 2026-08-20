-- Dimensional Storage (D. Storage) — bound ring containers
-- B42: ItemType=Container scripts; setWornItem needs ItemBodyLocation enum.
-- Skill max 8 (B42 bag Capacity ~49 hard cap). L9–L10 item scripts kept for future framework.
-- L1 right, L2 left, L3–8 both upgrade (+5 capacity/level). Live capacity clamped to 49.
-- On level-up: transfer contents old→new, delete old when empty.
-- Never ScriptItem:setIcon.

require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_SystemSkills"

KnoxSystem.DStorage = KnoxSystem.DStorage or {}

local NAME_T1 = "Dimensional Storage I"
local NAME_T2 = "Dimensional Storage II"
local BLOCK_MSG = "A system skill prevents this"
local ICON_ID = "KS_DStorage"
local ICON_TEX = "item_KS_DStorage"
local ICON_TEX_LEGACY = "Item_KS_DStorage"

local SKILL_MAX = 8
local CAPACITY_HARD_MAX = 49 -- B42 custom container ceiling

-- Capacity: L1–2 = 20; each level 3+ adds +5; skill max 8; live clamp 49
local function capacityForLevel(lvl)
    lvl = tonumber(lvl) or 0
    if lvl < 1 then return 20 end
    if lvl > SKILL_MAX then lvl = SKILL_MAX end
    local cap = 20 + math.max(0, lvl - 2) * 5
    if cap > CAPACITY_HARD_MAX then cap = CAPACITY_HARD_MAX end
    return cap
end

local function clampSkillLevel(lvl)
    lvl = tonumber(lvl) or 0
    if lvl < 0 then return 0 end
    if lvl > SKILL_MAX then return SKILL_MAX end
    return lvl
end

--- Preferred fullTypes for a skill level + slot ("front"=right, "back"=left).
local function candidatesFor(slot, skillLevel)
    skillLevel = clampSkillLevel(skillLevel)
    local list = {}
    if slot == "back" then
        if skillLevel >= 3 then
            list[#list + 1] = "KnoxSystem.KS_DimStorage_L" .. skillLevel
            list[#list + 1] = "Base.KS_DimStorage_L" .. skillLevel
        end
        -- L2+ uses left bag; L1-2 base types still valid until upgraded
        list[#list + 1] = "KnoxSystem.DimensionalStorageLeft"
        list[#list + 1] = "Base.KS_DimStorage_L"
        list[#list + 1] = "Base.Bag_FannyPackBack"
    else
        if skillLevel >= 3 then
            list[#list + 1] = "KnoxSystem.KS_DimStorage_R" .. skillLevel
            list[#list + 1] = "Base.KS_DimStorage_R" .. skillLevel
        end
        list[#list + 1] = "KnoxSystem.DimensionalStorage"
        list[#list + 1] = "Base.KS_DimStorage_R"
        list[#list + 1] = "Base.Bag_FannyPackFront"
    end
    return list
end

local function preferredType(slot, skillLevel)
    local c = candidatesFor(slot, skillLevel)
    return c[1]
end

local function tierOfFullType(ft)
    if not ft then return 0 end
    local n = string.match(ft, "KS_DimStorage_[RL](%d+)$")
    if n then return tonumber(n) or 0 end
    if ft:find("DimensionalStorageLeft", 1, true) then return 2 end
    if ft == "Base.KS_DimStorage_L" or ft:match("KS_DimStorage_L$") then return 2 end
    if ft:find("DimensionalStorage", 1, true) then return 1 end
    if ft == "Base.KS_DimStorage_R" or ft:match("KS_DimStorage_R$") then return 1 end
    if ft:find("FannyPack", 1, true) then return 0 end
    return 0
end

local createFailed = {}
local giveUpPrinted = {}
local grantedOnce = {}
local lastHalo = 0
local lastSyncedLevel = -1

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() else t = os.time() * 1000 end
    end)
    return t or 0
end

local function halo(player, msg)
    if not player then return end
    local t = nowMs()
    if lastHalo > 0 and (t - lastHalo) < 1200 then return end
    lastHalo = t
    msg = msg or BLOCK_MSG
    pcall(function()
        if type(player.setHaloNote) == "function" then
            player:setHaloNote(msg, 180, 220, 255, 80.0)
        end
    end)
end

local function bodyLoc(slot)
    local candidates
    if slot == "back" then
        candidates = {
            { "LEFT_RING_FINGER", "Left_RingFinger" },
            { "Left_RingFinger", "Left_RingFinger" },
            { "FANNY_PACK_BACK", "FannyPackBack" },
        }
    else
        candidates = {
            { "RIGHT_RING_FINGER", "Right_RingFinger" },
            { "Right_RingFinger", "Right_RingFinger" },
            { "FANNY_PACK_FRONT", "FannyPackFront" },
        }
    end
    for _, c in ipairs(candidates) do
        local enumName, fromStr = c[1], c[2]
        local loc = nil
        pcall(function()
            if ItemBodyLocation and ItemBodyLocation[enumName] then loc = ItemBodyLocation[enumName] end
        end)
        if loc then return loc end
        pcall(function()
            if ItemBodyLocation and ItemBodyLocation.FromString then
                loc = ItemBodyLocation.FromString(fromStr)
            end
        end)
        if loc then return loc end
    end
    return nil
end

local function fullTypeOf(item)
    local t = nil
    pcall(function() t = item:getFullType() end)
    return t
end

local function isLegacyFannyType(ft)
    return ft and ft:find("FannyPack", 1, true) ~= nil
end

local function isDStorageFullType(ft)
    if not ft then return false end
    if isLegacyFannyType(ft) then return false end
    if ft:find("DimensionalStorage", 1, true) then return true end
    if ft:find("KS_DimStorage_", 1, true) then return true end
    return false
end

local function isContainerItem(item)
    if not item then return false end
    local ok = false
    pcall(function()
        if instanceof and instanceof(item, "InventoryContainer") then ok = true end
    end)
    if ok then return true end
    pcall(function()
        if type(item.getInventory) == "function" and item:getInventory() ~= nil then ok = true end
    end)
    return ok
end

local function describeScript(typeName)
    local info = "missing"
    pcall(function()
        local sm = getScriptManager and getScriptManager() or nil
        if not sm then info = "no_SM"; return end
        local si = sm:getItem(typeName)
        if not si then info = "not_registered"; return end
        info = "registered"
    end)
    return info
end

local function tryCreate(typeName)
    if not typeName or createFailed[typeName] then return nil end
    local item = nil
    local ok = pcall(function()
        if InventoryItemFactory and InventoryItemFactory.CreateItem then
            item = InventoryItemFactory.CreateItem(typeName)
        elseif instanceItem then
            item = instanceItem(typeName)
        end
    end)
    if not ok or not item then
        createFailed[typeName] = true
        print(string.format("[KnoxSystem] DStorage: CreateItem FAIL %s script=%s",
            tostring(typeName), describeScript(typeName)))
        return nil
    end
    if not isContainerItem(item) then
        createFailed[typeName] = true
        print("[KnoxSystem] DStorage: not container " .. tostring(typeName))
        return nil
    end
    return item
end

local function createFromList(list)
    for _, t in ipairs(list) do
        local item = tryCreate(t)
        if item then return item, t end
    end
    return nil, nil
end

local function applyIcon(item)
    if not item then return end
    pcall(function()
        local md = item:getModData()
        if md then md.customInventoryIcon = ICON_TEX end
    end)
    pcall(function()
        if type(item.setIconsForTexture) ~= "function" or not ArrayList then return end
        local list = ArrayList.new()
        if list and list.add then
            list:add(ICON_ID)
            item:setIconsForTexture(list)
        end
    end)
    pcall(function()
        if not getTexture or type(item.setTexture) ~= "function" then return end
        local tex = getTexture(ICON_TEX) or getTexture(ICON_TEX_LEGACY) or getTexture(ICON_ID)
        if not tex then return end
        local nm = ""
        pcall(function()
            if tex.getName then nm = tostring(tex:getName() or "") end
        end)
        if nm:find("\\") or nm:find("/") or nm:find(":") then return end
        item:setTexture(tex)
    end)
end

local function tuneAndName(item, slot, skillLevel)
    if not item then return end
    local display = slot == "back" and NAME_T2 or NAME_T1
    local cap = capacityForLevel(skillLevel)
    pcall(function()
        if type(item.setCapacity) == "function" then item:setCapacity(cap) end
    end)
    pcall(function()
        if type(item.setWeightReduction) == "function" then item:setWeightReduction(100) end
    end)
    pcall(function()
        if type(item.setActualWeight) == "function" then item:setActualWeight(0.001) end
    end)
    pcall(function()
        if type(item.setWeight) == "function" then item:setWeight(0.001) end
    end)
    pcall(function()
        if type(item.setName) == "function" then item:setName(display) end
    end)
    pcall(function()
        if type(item.setCustomName) == "function" then item:setCustomName(true) end
    end)
    applyIcon(item)
    pcall(function()
        local md = item:getModData()
        md.knoxBound = true
        md.knoxDStorage = slot
        md.knoxDStorageLevel = skillLevel
        md.knoxNoDrop = true
        md.knoxNoLoot = true
        md.knoxDisplayName = display
        md.knoxNoCraft = true
        md.knoxNoForage = true
        md.knoxNoSpawn = true
    end)
    pcall(function()
        if type(item.setCanBeDropped) == "function" then item:setCanBeDropped(false) end
    end)
end

local function isOurItem(item)
    if not item then return false end
    local md = nil
    pcall(function() md = item:getModData() end)
    if md and md.knoxDStorage then return true end
    return isDStorageFullType(fullTypeOf(item))
end

local function findBySlot(player, slot)
    local found = nil
    pcall(function()
        local inv = player:getInventory()
        if not inv then return end
        local items = inv:getItems()
        if not items then return end
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local md = nil
            pcall(function() md = it:getModData() end)
            if md and md.knoxDStorage == slot then
                found = it
                return
            end
        end
    end)
    if found then return found end
    pcall(function()
        local loc = bodyLoc(slot)
        if not loc then return end
        local worn = player:getWornItems()
        if worn and worn.getItem then
            found = worn:getItem(loc)
            if found and not isOurItem(found) then found = nil end
        end
    end)
    return found
end

local function equipTo(player, item, slot)
    if not player or not item then return false end
    local loc = bodyLoc(slot)
    if not loc then return false end
    local ok = false
    pcall(function()
        local worn = player:getWornItems()
        if worn and type(worn.setItem) == "function" then
            worn:setItem(loc, item)
            ok = true
        end
    end)
    if ok then return true end
    pcall(function()
        if type(player.setWornItem) == "function" then
            player:setWornItem(loc, item)
            ok = true
        end
    end)
    return ok
end

local function clearWornSlot(player, slot)
    local loc = bodyLoc(slot)
    if not loc then return end
    pcall(function()
        local worn = player:getWornItems()
        if worn and worn.setItem then worn:setItem(loc, nil) end
    end)
    pcall(function()
        if type(player.setWornItem) == "function" then player:setWornItem(loc, nil) end
    end)
end

local function getWornInSlot(player, slot)
    local loc = bodyLoc(slot)
    if not loc then return nil end
    local it = nil
    pcall(function()
        local worn = player:getWornItems()
        if worn and worn.getItem then it = worn:getItem(loc) end
    end)
    return it
end

local function bagItemCount(bag)
    local n = 0
    pcall(function()
        if type(bag.getInventory) ~= "function" then return end
        local inv = bag:getInventory()
        if inv and inv.getItems then
            local items = inv:getItems()
            if items and items.size then n = items:size() end
        end
    end)
    return n
end

--- Move all items from src bag into dst bag (or player inv if dst full/fail).
local function transferBagContents(player, src, dst)
    if not src then return true end
    local moved = 0
    local failed = 0
    pcall(function()
        if type(src.getInventory) ~= "function" then return end
        local bagInv = src:getInventory()
        local dstInv = nil
        if dst and type(dst.getInventory) == "function" then
            dstInv = dst:getInventory()
        end
        local pinv = player and player:getInventory() or nil
        if not bagInv or not bagInv.getItems then return end
        local items = bagInv:getItems()
        if not items then return end
        local move = {}
        for i = 0, items:size() - 1 do
            move[#move + 1] = items:get(i)
        end
        for _, it in ipairs(move) do
            local okOne = false
            pcall(function()
                bagInv:Remove(it)
                if dstInv then
                    dstInv:AddItem(it)
                    okOne = true
                elseif pinv then
                    pinv:AddItem(it)
                    okOne = true
                end
            end)
            if okOne then moved = moved + 1 else failed = failed + 1 end
        end
    end)
    local left = bagItemCount(src)
    print(string.format("[KnoxSystem] DStorage: transfer moved=%d failed=%d left_in_old=%d",
        moved, failed, left))
    return left == 0 and failed == 0
end

local function removeItemCompletely(player, it)
    if not player or not it then return end
    for _, slot in ipairs({ "front", "back" }) do
        pcall(function()
            local loc = bodyLoc(slot)
            local worn = player:getWornItems()
            if worn and worn.getItem and loc and worn:getItem(loc) == it then
                worn:setItem(loc, nil)
            end
        end)
    end
    for _, name in ipairs({ "FANNY_PACK_FRONT", "FANNY_PACK_BACK", "FannyPackFront", "FannyPackBack" }) do
        pcall(function()
            local loc = nil
            if ItemBodyLocation and ItemBodyLocation[name] then loc = ItemBodyLocation[name] end
            if not loc and ItemBodyLocation and ItemBodyLocation.FromString then
                loc = ItemBodyLocation.FromString(name)
            end
            if not loc then return end
            local worn = player:getWornItems()
            if worn and worn.getItem and worn:getItem(loc) == it then
                worn:setItem(loc, nil)
            end
        end)
    end
    pcall(function()
        local inv = player:getInventory()
        if inv then inv:Remove(it) end
    end)
end

local function removeSlot(player, slot)
    local it = findBySlot(player, slot)
    local worn = getWornInSlot(player, slot)
    if worn and isOurItem(worn) then
        clearWornSlot(player, slot)
        it = worn
    end
    if it then
        -- dump to player if removing skill
        transferBagContents(player, it, nil)
        removeItemCompletely(player, it)
    end
end

--- True if bag should be replaced with a higher-tier script item for this skill level.
local function needsUpgrade(item, slot, skillLevel)
    if not item then return true end
    if not isOurItem(item) then return true end
    if not isContainerItem(item) then return true end
    local ft = fullTypeOf(item)
    if isLegacyFannyType(ft) then return true end
    local want = preferredType(slot, skillLevel)
    if ft == want then return false end
    -- Accept Base twin of same level
    if skillLevel >= 3 then
        local side = slot == "back" and "L" or "R"
        local suffix = side .. skillLevel
        if ft == "Base.KS_DimStorage_" .. suffix or ft == "KnoxSystem.KS_DimStorage_" .. suffix then
            return false
        end
    else
        if slot == "back" then
            if ft == "KnoxSystem.DimensionalStorageLeft" or ft == "Base.KS_DimStorage_L" then return false end
        else
            if ft == "KnoxSystem.DimensionalStorage" or ft == "Base.KS_DimStorage_R" then return false end
        end
    end
    -- Upgrade if stored level or type tier is below skill level (for L3+)
    local md = nil
    pcall(function() md = item:getModData() end)
    local bagLv = md and tonumber(md.knoxDStorageLevel) or tierOfFullType(ft)
    if skillLevel >= 3 and bagLv < skillLevel then return true end
    if skillLevel >= 3 and tierOfFullType(ft) < skillLevel and not isLegacyFannyType(ft) then
        -- numbered type lower than skill
        local n = tierOfFullType(ft)
        if n > 0 and n < skillLevel then return true end
    end
    -- Wrong side type
    if ft and isDStorageFullType(ft) then
        local isLeftType = ft:find("Left", 1, true) or ft:find("_L", 1, true)
        if slot == "front" and isLeftType then return true end
        if slot == "back" and not isLeftType and ft:find("_R", 1, true) then return true end
    end
    return false
end

local function ensureSlot(player, slot, levelNeeded, skillLevel, data)
    data = data or KnoxSystem.getPlayerData(player)
    local lvl = skillLevel or (data and KnoxSystem.SystemSkills.dStorageLevel(data) or 0)
    if lvl < levelNeeded then
        removeSlot(player, slot)
        return
    end

    local worn = getWornInSlot(player, slot)
    if worn and not isOurItem(worn) then
        clearWornSlot(player, slot)
        pcall(function()
            local inv = player:getInventory()
            if inv and not inv:contains(worn) then inv:AddItem(worn) end
        end)
        halo(player, BLOCK_MSG)
    end

    local existing = findBySlot(player, slot)
    if existing and not needsUpgrade(existing, slot, lvl) then
        tuneAndName(existing, slot, lvl)
        equipTo(player, existing, slot)
        return
    end

    local candidates = candidatesFor(slot, lvl)
    local item, usedType = createFromList(candidates)
    if not item then
        if not giveUpPrinted[slot] then
            giveUpPrinted[slot] = true
            print(string.format("[KnoxSystem] DStorage: NO BAG for %s (skill=%s)", slot, tostring(lvl)))
        end
        return
    end

    tuneAndName(item, slot, lvl)
    pcall(function() player:getInventory():AddItem(item) end)

    if existing then
        print(string.format("[KnoxSystem] DStorage: upgrade %s %s → %s (skill=%s)",
            slot, tostring(fullTypeOf(existing)), tostring(usedType), tostring(lvl)))
        local empty = transferBagContents(player, existing, item)
        if empty then
            removeItemCompletely(player, existing)
            print("[KnoxSystem] DStorage: old bag deleted (empty after transfer)")
        else
            -- Keep old until empty; try dump remainder to player then delete if clear
            transferBagContents(player, existing, nil)
            if bagItemCount(existing) == 0 then
                removeItemCompletely(player, existing)
                print("[KnoxSystem] DStorage: old bag deleted after player dump")
            else
                print("[KnoxSystem] DStorage: old bag KEPT (still has items)")
            end
        end
    end

    local eq = equipTo(player, item, slot)
    if not grantedOnce[slot .. ":" .. tostring(lvl)] then
        grantedOnce[slot .. ":" .. tostring(lvl)] = true
        print(string.format("[KnoxSystem] DStorage: granted %s via %s worn=%s cap=%s skill=%s",
            slot, tostring(usedType), tostring(eq), tostring(capacityForLevel(lvl)), tostring(lvl)))
    end
end

function KnoxSystem.DStorage.sync(player, data)
    if not player then return end
    data = data or KnoxSystem.getPlayerData(player)
    if not data then return end
    local lvl = clampSkillLevel(KnoxSystem.SystemSkills.dStorageLevel(data))
    if lvl ~= lastSyncedLevel then
        createFailed = {}
        giveUpPrinted = {}
        -- keep grantedOnce per level key
        lastSyncedLevel = lvl
        print(string.format("[KnoxSystem] DStorage: skill level now %s cap=%s — sync",
            tostring(lvl), tostring(capacityForLevel(lvl))))
    end
    if lvl >= 1 then
        ensureSlot(player, "front", 1, lvl, data)
    else
        removeSlot(player, "front")
    end
    if lvl >= 2 then
        ensureSlot(player, "back", 2, lvl, data)
    else
        removeSlot(player, "back")
    end
end

function KnoxSystem.DStorage.onPlayerUpdate(player)
    if not player then return end
    local data = KnoxSystem.getPlayerData(player)
    if not data then return end
    local lvl = KnoxSystem.SystemSkills.dStorageLevel(data)
    if lvl <= 0 then return end
    local t = nowMs()
    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    KnoxSystem.DStorage._last = KnoxSystem.DStorage._last or {}
    local last = KnoxSystem.DStorage._last[id] or 0
    if t > 0 and last > 0 and (t - last) < 2500 then return end
    KnoxSystem.DStorage._last[id] = t
    KnoxSystem.DStorage.sync(player, data)
end

function KnoxSystem.DStorage.onDeath(player)
    if not player then return end
    removeSlot(player, "front")
    removeSlot(player, "back")
end

function KnoxSystem.DStorage.isBoundItem(item)
    return isOurItem(item)
end

function KnoxSystem.DStorage.capacityForLevel(lvl)
    return capacityForLevel(lvl)
end

function KnoxSystem.DStorage.ownsSlot(player, slot)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return false end
    local lvl = KnoxSystem.SystemSkills.dStorageLevel(data)
    if slot == "front" then return lvl >= 1 end
    if slot == "back" then return lvl >= 2 end
    return false
end

function KnoxSystem.DStorage.isReservedLocation(player, loc)
    if not player or not loc then return false end
    local data = KnoxSystem.getPlayerData(player)
    if not data then return false end
    local lvl = KnoxSystem.SystemSkills.dStorageLevel(data)
    if lvl < 1 then return false end
    local front = bodyLoc("front")
    local back = bodyLoc("back")
    if lvl >= 1 and front and loc == front then return true end
    if lvl >= 2 and back and loc == back then return true end
    local s = tostring(loc)
    if lvl >= 1 and (s:find("Right_Ring") or s:find("RIGHT_RING") or s:find("FannyPackFront")) then return true end
    if lvl >= 2 and (s:find("Left_Ring") or s:find("LEFT_RING") or s:find("FannyPackBack")) then return true end
    return false
end

function KnoxSystem.DStorage.blockWear(player, item)
    if item and isOurItem(item) then return false end
    halo(player, BLOCK_MSG)
    return true
end

local wearPatched = false
function KnoxSystem.DStorage.patchWearActions()
    if wearPatched then return end
    wearPatched = true
    pcall(function()
        require "TimedActions/ISWearClothing"
        if not ISWearClothing or not ISWearClothing.isValid then return end
        local oldValid = ISWearClothing.isValid
        ISWearClothing.isValid = function(self)
            local ok = oldValid(self)
            if not ok then return false end
            local player = self.character or self.chr
            local item = self.item
            if not player or not item then return ok end
            if isOurItem(item) then return true end
            local loc = nil
            pcall(function()
                if type(item.getBodyLocation) == "function" then loc = item:getBodyLocation() end
            end)
            pcall(function()
                if not loc and type(item.canBeEquipped) == "function" then loc = item:canBeEquipped() end
            end)
            if loc and KnoxSystem.DStorage.isReservedLocation(player, loc) then
                KnoxSystem.DStorage.blockWear(player, item)
                return false
            end
            return true
        end
        print("[KnoxSystem] DStorage: patched ISWearClothing.isValid")
    end)
end

function KnoxSystem.DStorage.getTypes()
    return {
        capacity = {
            [1] = 20, [2] = 20, [3] = 25, [4] = 30, [5] = 35,
            [6] = 40, [7] = 45, [8] = 50, [9] = 55, [10] = 60,
        },
        front_l3 = "KnoxSystem.KS_DimStorage_R3",
        back_l3 = "KnoxSystem.KS_DimStorage_L3",
    }
end

function KnoxSystem.DStorage.probeScripts()
    local samples = {
        "KnoxSystem.DimensionalStorage",
        "KnoxSystem.DimensionalStorageLeft",
        "KnoxSystem.KS_DimStorage_R3",
        "KnoxSystem.KS_DimStorage_L3",
        "KnoxSystem.KS_DimStorage_R10",
        "KnoxSystem.KS_DimStorage_L10",
        "Base.KS_DimStorage_R5",
    }
    for _, ft in ipairs(samples) do
        print(string.format("[KnoxSystem] DStorage probe %s => %s", ft, describeScript(ft)))
    end
end

function KnoxSystem.DStorage.runFixup()
    createFailed = {}
    giveUpPrinted = {}
    grantedOnce = {}
    lastSyncedLevel = -1
    KnoxSystem.DStorage.probeScripts()
    local p = getPlayer and getPlayer() or nil
    if p then KnoxSystem.DStorage.sync(p) end
end

print("[KnoxSystem] KS_DStorage loaded (max10; L3-10 +5 cap; transfer on upgrade)")
