-- KnoxSystem shared bootstrap + ModData helpers (Phase 0)
-- Design SoT: /opt/data/workspace/pz-system-apocalypse/design/moddata_schema.yaml

KnoxSystem = KnoxSystem or {}
KnoxSystem.VERSION = "0.5.158"
KnoxSystem.MOD_ID = "KnoxSystem"
KnoxSystem.MODDATA_KEY = "KnoxSystem"
KnoxSystem.SCHEMA_VERSION = 1

local function defaultPlayerData()
    return {
        schema_version = KnoxSystem.SCHEMA_VERSION,
        personal_level = 0,
        personal_xp = 0,
        skill_points_unspent = 0,
        stat_power = 0,      -- personal Power (renamed from Strength)
        stat_strength = 0,   -- legacy; migrated → stat_power
        stat_endurance = 0,
        stat_mind = 0,
        stat_resilience = 0,
        skill_analyze = 0,
        skill_d_storage = 0,
        class_id = nil,
        class_locked = false,
        class_skills = {},
        mana_current = 0,
        mana_max_cache = 0,
        sp_cart_skills = {},
        sp_cart_stats = {},
        initialized = false,
        init_source = "new_game",
    }
end

function KnoxSystem.getPlayerData(player)
    if not player then return nil end
    local md = player:getModData()
    local data = md[KnoxSystem.MODDATA_KEY]
    if type(data) ~= "table" then
        data = defaultPlayerData()
        md[KnoxSystem.MODDATA_KEY] = data
    end
    if not data.schema_version or data.schema_version < KnoxSystem.SCHEMA_VERSION then
        data.schema_version = KnoxSystem.SCHEMA_VERSION
    end
    -- Migrate personal Strength → Power (keep vanilla Strength perk name untouched)
    pcall(function()
        local p = tonumber(data.stat_power)
        local legacy = tonumber(data.stat_strength)
        if p == nil or p == 0 then
            if legacy and legacy > 0 then
                data.stat_power = legacy
            else
                data.stat_power = p or 0
            end
        end
        data.stat_power = tonumber(data.stat_power) or 0
        if data.stat_power < 0 then data.stat_power = 0 end

        -- ≥0.5.128: Power max 10 @ 2 SP. If save still has Power > 10 (old 1 SP/lv max20),
        -- refund ALL Power ranks at 1 SP each and reset Power to 0 (one-shot).
        if not data._powerOver10Refund_v0128 then
            local before = data.stat_power
            if before > 10 then
                local refund = before -- 1 SP per level (old cost)
                data.skill_points_unspent = (tonumber(data.skill_points_unspent) or 0) + refund
                data.stat_power = 0
                data.stat_strength = 0
                -- Drop pending Power in cart so it cannot re-apply old ranks for free
                if type(data.sp_cart_stats) == "table" then
                    data.sp_cart_stats.Power = nil
                    data.sp_cart_stats.Strength = nil
                end
                print(string.format(
                    "[KnoxSystem] Power over-cap refund: Power %d -> 0, +%d SP (1 SP/lv old rate); unspent now %d",
                    before, refund, data.skill_points_unspent
                ))
                if KnoxSystem.Track and KnoxSystem.Track.log then
                    pcall(function()
                        KnoxSystem.Track.log("power", "overcap_refund", {
                            beforePower = before,
                            refundSp = refund,
                            unspentAfter = data.skill_points_unspent,
                            note = "Power>10 one-shot; 1 SP per level; reset to 0",
                        })
                    end)
                end
            end
            data._powerOver10Refund_v0128 = true
        end

        -- Soft clamp after refund (should already be ≤10)
        if data.stat_power > 10 then data.stat_power = 10 end
        data.stat_strength = data.stat_power
        local e = tonumber(data.stat_endurance) or 0
        if e < 0 then e = 0 end
        if e > 10 then e = 10 end
        data.stat_endurance = e
    end)
    return data
end

function KnoxSystem.ensurePlayerInitialized(player, source)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return nil end
    if data.initialized then return data end
    data.initialized = true
    data.init_source = source or "new_game"
    data.personal_level = data.personal_level or 0
    data.personal_xp = data.personal_xp or 0
    data.skill_points_unspent = data.skill_points_unspent or 0
    print(string.format("[KnoxSystem] Player ModData initialized (%s) v%s",
        tostring(data.init_source), KnoxSystem.VERSION))
    return data
end

print(string.format("[KnoxSystem] shared loaded v%s", KnoxSystem.VERSION))
