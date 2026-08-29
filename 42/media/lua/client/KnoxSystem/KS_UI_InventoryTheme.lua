-- KnoxSystem inventory theme v10
-- Blue chrome + rarity name colors (Item Rarity UI data + layout).
--
-- Name colors: AFTER vanilla renderdetails, repaint names (more reliable than
-- intercepting drawText on B42). Layout math from Item Rarity UI.
-- Blue: backgroundColor every frame + soft drawRect under pane/page.
require "KnoxSystem/KS_ModData"

KnoxSystem.UI = KnoxSystem.UI or {}

local BG = { r = 0.05, g = 0.114, b = 0.247, a = 0.94 }
local PATCH_VER = "11.6"

local TIERS = {
    legendary = { r = 1.0,  g = 0.5,  b = 0.0 },
    epic      = { r = 0.7,  g = 0.3,  b = 0.9 },
    rare      = { r = 0.4,  g = 0.6,  b = 1.0 },
    uncommon  = { r = 0.3,  g = 0.9,  b = 0.3 },
    common    = { r = 0.92, g = 0.92, b = 0.92 },
    crafted   = { r = 0.5,  g = 0.85, b = 0.85 },
    unknown   = { r = 0.55, g = 0.55, b = 0.55 },
    trash     = { r = 0.55, g = 0.55, b = 0.55 },
}

local RARITY_DOWN = {
    legendary = "epic", epic = "rare", rare = "uncommon",
    uncommon = "common", common = "common",
    crafted = "crafted", unknown = "unknown", trash = "trash",
}

local RARITY_UP = {
    trash = "common", unknown = "common", common = "uncommon",
    uncommon = "rare", rare = "epic", epic = "legendary", legendary = "legendary",
    crafted = "crafted", -- keep teal craft marker
}

local rarities = nil
local raritiesLower = nil
local dataLoaded = false
local _loggedAnalyzeOff = false

local function analyzeOn(player)
    player = player or (getPlayer and getPlayer()) or nil
    if not player then return false end
    if not KnoxSystem.Analyze or not KnoxSystem.Analyze.hasL1 then return true end -- if no Analyze, still color
    local ok, on = pcall(function() return KnoxSystem.Analyze.hasL1(player) end)
    return ok and on
end

local function isClothingItem(item)
    if not item then return false end
    -- Bags never take the clothing −1 tier (even if worn / Clothing-like)
    local cat = ""
    local ft = ""
    pcall(function()
        if item.getDisplayCategory then cat = tostring(item:getDisplayCategory() or ""):lower() end
    end)
    pcall(function() ft = tostring(item:getFullType() or ""):lower() end)
    if cat == "bag" or cat == "container" or cat:find("bag", 1, true)
        or ft:find("bag_", 1, true) or ft:find(".bag_", 1, true) then
        return false
    end
    local yes = false
    pcall(function()
        if instanceof(item, "InventoryContainer") then yes = true end
    end)
    if yes then
        return false
    end
    yes = false
    pcall(function()
        if instanceof(item, "Clothing") then yes = true end
    end)
    if yes then return true end
    if cat == "clothing" or cat == "accessory" or cat == "jewellery"
        or cat:find("cloth", 1, true) then
        return true
    end
    return false
end

--- Protective / combat armor (not shirts, pants, underwear, socks, etc.)
local function isArmorItem(item, catL, ftL, nameL)
    catL = catL or ""
    ftL = ftL or ""
    nameL = nameL or ""
    if item then
        pcall(function()
            if item.getDisplayCategory and catL == "" then
                catL = tostring(item:getDisplayCategory() or ""):lower()
            end
            if item.getFullType and ftL == "" then
                ftL = tostring(item:getFullType() or ""):lower()
            end
            if item.getName and nameL == "" then
                nameL = tostring(item:getName() or ""):lower()
            end
        end)
    end
    local blob = catL .. " " .. ftL .. " " .. nameL

    -- Soft clothing — still gets rarity downshift even if "crafted"
    if blob:find("underpants", 1, true) or blob:find("underwear", 1, true)
        or blob:find("boxers", 1, true) or blob:find("briefs", 1, true)
        or blob:find("bra_", 1, true) or blob:find("bra-", 1, true)
        or blob:find("socks", 1, true) or blob:find("stockings", 1, true)
        or blob:find("tshirt", 1, true) or blob:find("t-shirt", 1, true)
        or blob:find("shirt_", 1, true) or blob:find("shirt -", 1, true)
        or blob:find("trousers", 1, true) or blob:find("pants", 1, true)
        or blob:find("shorts_", 1, true) or blob:find("skirt", 1, true)
        or blob:find("dress_", 1, true) or blob:find("longjohn", 1, true)
        or blob:find("jumper", 1, true) or blob:find("sweater", 1, true)
        or blob:find("hoodie", 1, true) then
        -- Exception: bullet pants / armor trousers keep armor treatment
        if not (blob:find("bullet", 1, true) or blob:find("armor", 1, true)
            or blob:find("armour", 1, true) or blob:find("metal", 1, true)
            or blob:find("chainmail", 1, true) or blob:find("ballistic", 1, true)) then
            return false
        end
    end

    if catL:find("protective", 1, true) or catL:find("armor", 1, true)
        or catL:find("armour", 1, true) then
        return true
    end

    local keys = {
        "armor", "armour", "bulletproof", "bullet_vest", "vest_bullet",
        "cuirass", "greave", "vambrace", "gorget", "shoulderpad",
        "chainmail", "hazmat", "ballistic", "thighmetal", "thighscrap",
        "metalhelmet", "metalarmour", "metalarmor", "knee_pad", "kneepad",
        "elbowpad", "elbow_pad", "shinpad", "bodyarmour", "bodyarmor",
        "spikedpad", "tirearmor", "scrapmetal", "articulated",
    }
    for i = 1, #keys do
        if blob:find(keys[i], 1, true) then return true end
    end
    return false
end

local function demoteRarity(label)
    return RARITY_DOWN[label] or label or "common"
end

local function promoteRarity(label)
    return RARITY_UP[label] or label or "common"
end

local function loadData()
    if dataLoaded and rarities then return true end
    rarities = {}
    raritiesLower = {}
    local data = nil
    local ok, res = pcall(function() return require "KnoxSystem/KS_ItemRarityData" end)
    if ok and type(res) == "table" then data = res end
    if type(data) ~= "table" then data = KnoxSystem.ItemRarityData end
    if type(data) ~= "table" then
        print("[KnoxSystem] rarity data load FAILED")
        dataLoaded = true
        return false
    end
    local n = 0
    for ft, row in pairs(data) do
        if type(ft) == "string" and type(row) == "table" and type(row.rarity) == "string" then
            local ent = {
                chance = tonumber(row.chance) or 0,
                rarity = tostring(row.rarity),
            }
            rarities[ft] = ent
            raritiesLower[string.lower(ft)] = ent
            -- also index bare type without module
            local bare = string.match(ft, "%.([^%.]+)$")
            if bare then
                raritiesLower[string.lower(bare)] = raritiesLower[string.lower(bare)] or ent
            end
            n = n + 1
        end
    end
    dataLoaded = true
    print(string.format("[KnoxSystem] rarity data loaded types=%d", n))
    return n > 0
end

local function lookupRow(ft)
    if not ft or not rarities then return nil end
    local row = rarities[ft]
    if row then return row end
    if raritiesLower then
        row = raritiesLower[string.lower(ft)]
        if row then return row end
        if not string.find(ft, ".", 1, true) then
            row = raritiesLower["base." .. string.lower(ft)]
            if row then return row end
        end
    end
    return nil
end
function KnoxSystem.UI.getItemRarityColor(itemOrFullType)
    if not dataLoaded then loadData() end
    local ft = itemOrFullType
    local item = nil
    if type(itemOrFullType) ~= "string" then
        item = itemOrFullType
        ft = nil
        pcall(function() ft = item:getFullType() end)
    end

    local name, cat, typeCat = "", "", ""
    if item then
        pcall(function() name = tostring(item:getName() or "") end)
        pcall(function()
            if item.getDisplayCategory then cat = tostring(item:getDisplayCategory() or "") end
        end)
        pcall(function()
            if item.getCategory then typeCat = tostring(item:getCategory() or "") end
        end)
    end
    local catL = cat:lower()
    local nameL = name:lower()
    local ftL = tostring(ft or ""):lower()
    local blob = catL .. " " .. nameL .. " " .. ftL .. " " .. typeCat:lower()

    -- --- Category / type overrides (applied after base table, before clothing demote) ---

    -- Junk / memento
    if catL == "junk" or catL == "memento"
        or catL:find("junk", 1, true) or catL:find("memento", 1, true) then
        return TIERS.trash, "trash", -1
    end

    local label = "unknown"
    local chance = -1
    local row = lookupRow(ft)
    if row then
        label = row.rarity
        chance = row.chance
    elseif not ft then
        label = "common"
    end

    -- Military / ALICE backpacks: pin to loot tiers (never crafted/unknown)
    -- Vanilla often shows displayName "Military Backpack" for Army/Desert/etc.
    if ftL:find("alicepack", 1, true) or ftL:find("bag_military", 1, true)
        or nameL:find("military backpack", 1, true) or nameL:find("alice pack", 1, true)
        or nameL:find("alicepack", 1, true) then
        if ftL:find("desert", 1, true) or nameL:find("desert", 1, true) then
            label = "uncommon" -- Bag_ALICEpack_DesertCamo
        elseif ftL:find("army", 1, true) or nameL:find("army", 1, true) then
            label = "rare" -- Bag_ALICEpack_Army
        elseif ftL:find("bag_military", 1, true) and not ftL:find("alice", 1, true) then
            label = "uncommon" -- Bag_Military
        elseif ftL:find("alicepack", 1, true) then
            label = "epic" -- Base.Bag_ALICEpack
        else
            -- name-only "Military Backpack" → treat as Army (most common military pack name)
            label = "rare"
        end
    end

    local function isWeaponItem()
        if not item then return false end
        local w = false
        pcall(function()
            if instanceof(item, "HandWeapon") then w = true end
            if not w and instanceof(item, "InventoryItem") and item.IsWeapon and item:IsWeapon() then w = true end
        end)
        if w then return true end
        if catL:find("weapon", 1, true) or typeCat:lower():find("weapon", 1, true) then return true end
        if blob:find("weapon", 1, true) then return true end
        return false
    end

    -- Food → common
    if catL == "food" or catL:find("food", 1, true) or typeCat:lower() == "food" then
        label = "common"
    end

    -- Cooking → common, unless also a weapon (rolling pin, etc.)
    if catL == "cooking" or catL:find("cooking", 1, true) or blob:find("cooking", 1, true) then
        if not isWeaponItem() then
            label = "common"
        end
    end

    -- Recipes → at least rare
    local isRecipe = catL == "recipe" or catL:find("recipe", 1, true)
        or ftL:find("recipe", 1, true) or nameL:find("recipe", 1, true)
        or ftL:find("recipeclipping", 1, true) or blob:find("recipeclipping", 1, true)
    if isRecipe then
        local order = { trash = 0, unknown = 0, common = 1, crafted = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }
        if (order[label] or 0) < 3 then
            label = "rare"
        end
    end

    -- VHS: default common; explicit rare whitelist only (not all skill tapes).
    -- Almost all share fullType Base.VHS_Retail — match display/media titles.
    local isVhs = ftL:find("vhs", 1, true) or nameL:find("vhs", 1, true)
        or catL:find("vhs", 1, true)
        or (catL == "media" and nameL:find("tape", 1, true))
        or (catL == "entertainment" and (nameL:find("vhs", 1, true) or ftL:find("vhs", 1, true)))
        or ftL == "base.vhs_retail" or ftL == "base.vhs_home"
    if isVhs then
        -- Rare titles (user lock). Series names cover all listed episodes.
        local rareVhsNeedles = {
            -- Series (all episodes rare)
            "woodcraft",
            "cook show",
            "the cook show",
            "carzone",
            "exposure survival",
            -- Named rare tapes
            "mother's boy",
            "mothers boy",
            "dead wrong",
            "z-squad",
            "zsquad",
            "no. 9",
            "nof vid",
            "granny nani",
            "tailoring 101",
            "oscc",
            "stock cars",
            "mathematical quadratic",
            "algebraic configuration",
            "grady v king",
            "combat wound",
            "rmfa",
            "muldraugh av club",
            "tv repair",
            "basic gun handling",
            "tree planting",
            "knox gun owner",
            "gun owners club",
            "crop pests",
            "crop pest",
            "growing herbs",
            "growing fruit",
            "fruit and veg",
            "petting zoo",
            "day on the farm",
            "from ore to store",
            "ore to store",
            "making sushi",
            "sushi at home",
            "how electricity works",
            "emergency first aid",
            "rosewood medical",
            "better fishing",
            "jason master",
            "knapping",
            "ancient art",
            "working clay",
            "pottery for anyone",
            "stitch in time",
            "adefope fencing",
            "adefipe fencing",
            "fencing special",
            "home welding",
            "welding guide",
        }
        local mediaBlob = nameL .. " " .. ftL
        pcall(function()
            if not item then return end
            if item.getMediaData then
                local md = item:getMediaData()
                if md then
                    local parts = { tostring(md) }
                    pcall(function() if md.getTitle then parts[#parts + 1] = tostring(md:getTitle() or "") end end)
                    pcall(function() if md.getId then parts[#parts + 1] = tostring(md:getId() or "") end end)
                    pcall(function() if md.getTranslatedTitle then parts[#parts + 1] = tostring(md:getTranslatedTitle() or "") end end)
                    pcall(function() if md.getCategory then parts[#parts + 1] = tostring(md:getCategory() or "") end end)
                    pcall(function() if md.getSubtitle then parts[#parts + 1] = tostring(md:getSubtitle() or "") end end)
                    pcall(function()
                        if md.getLines then
                            local lines = md:getLines()
                            if lines and lines.size then
                                for i = 0, math.min(lines:size() - 1, 20) do
                                    parts[#parts + 1] = tostring(lines:get(i) or "")
                                end
                            end
                        end
                    end)
                    mediaBlob = mediaBlob .. " " .. table.concat(parts, " "):lower()
                end
            end
        end)
        -- Normalize curly apostrophes
        mediaBlob = mediaBlob:gsub("’", "'"):gsub("‘", "'")

        local isRareVhs = false
        for i = 1, #rareVhsNeedles do
            if mediaBlob:find(rareVhsNeedles[i], 1, true) then
                isRareVhs = true
                break
            end
        end
        -- "No 9" / "No.9" without period variants (avoid bare "no 9" false positives on random text)
        if not isRareVhs then
            if mediaBlob:find("no 9", 1, true) or mediaBlob:find("no9", 1, true) then
                if mediaBlob:find("weld", 1, true) or mediaBlob:find("metal", 1, true)
                    or mediaBlob:find("vid", 1, true) or nameL:find("no", 1, true) then
                    isRareVhs = true
                end
            end
        end

        label = isRareVhs and "rare" or "common"
    end

    -- Ammo: loose=common, box/carton=uncommon, case=rare; rifle calibers +1 tier
    local isAmmo = catL == "ammo" or catL:find("ammo", 1, true)
        or ftL:find("bullets", 1, true) or ftL:find("shells", 1, true)
        or nameL:find("round", 1, true) or nameL:find("shell", 1, true)
        or nameL:find("ammo", 1, true) or ftL:find("ammo", 1, true)
    if isAmmo then
        local isCase = nameL:find("case", 1, true) or ftL:find("case", 1, true)
            or nameL:find("crate", 1, true) or ftL:find("crate", 1, true)
        local isBox = nameL:find("box", 1, true) or ftL:find("box", 1, true)
            or nameL:find("carton", 1, true) or ftL:find("carton", 1, true)
        if isCase then
            label = "rare"
        elseif isBox then
            label = "uncommon"
        else
            label = "common"
        end
        local isRifle = nameL:find("rifle", 1, true) or ftL:find("rifle", 1, true)
            or nameL:find(".223", 1, true) or ftL:find("223", 1, true)
            or nameL:find(".308", 1, true) or ftL:find("308", 1, true)
            or nameL:find("5.56", 1, true) or ftL:find("556", 1, true)
            or nameL:find("7.62", 1, true) or ftL:find("762", 1, true)
            or nameL:find("shotgun", 1, true) or ftL:find("shotgun", 1, true)
            or ftL:find("shotgunshells", 1, true) or nameL:find("shotgun shell", 1, true)
        if isRifle then
            label = ({
                common = "uncommon",
                uncommon = "rare",
                rare = "epic",
                epic = "legendary",
                legendary = "legendary",
            })[label] or label
        end
    end

    -- Boxes of nails / screws → rare
    local isNailScrewBox = (ftL:find("nailsbox", 1, true) or ftL:find("screwsbox", 1, true)
        or ((nameL:find("nail", 1, true) or nameL:find("screw", 1, true))
            and (nameL:find("box", 1, true) or ftL:find("box", 1, true))))
        and not (ftL:find("carton", 1, true) or nameL:find("carton", 1, true))
    if isNailScrewBox or ftL == "base.nailsbox" or ftL == "base.screwsbox" then
        label = "rare"
    end
    -- Cartons of nails/screws stay higher if already epic in data; floor rare
    if ftL:find("nailscarton", 1, true) or ftL:find("screwscarton", 1, true)
        or ((nameL:find("nail", 1, true) or nameL:find("screw", 1, true)) and nameL:find("carton", 1, true)) then
        local order = { trash = 0, unknown = 0, common = 1, crafted = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }
        if (order[label] or 0) < 3 then label = "rare" end
    end

    -- Dimensional Storage: canonical types + legacy fanny-bound + name
    local isDStore = false
    if ftL:find("bag_dimensional_storage", 1, true) or ftL:find("dimensional_storage", 1, true) then
        isDStore = true
    end
    if item then
        pcall(function()
            local md = item:getModData()
            if md and md.knoxDStorage then isDStore = true end
        end)
    end
    if not isDStore then
        if nameL:find("dimensional storage", 1, true) or nameL:find("d. storage", 1, true) then
            isDStore = true
        end
    end
    if isDStore then
        label = "rare" -- system bag; never fanny common / crafted
    end

    -- Cigarettes: loose=common, pack=uncommon, carton=rare
    local isCig = nameL:find("cigar", 1, true) or ftL:find("cigar", 1, true)
        or nameL:find("cigarette", 1, true) or ftL:find("cigarette", 1, true)
    if isCig then
        if nameL:find("carton", 1, true) or ftL:find("carton", 1, true) then
            label = "rare"
        elseif nameL:find("pack", 1, true) or ftL:find("pack", 1, true) then
            label = "uncommon"
        else
            label = "common"
        end
    end

    -- All jewellery / jewelry → common (watches excluded unless Jewellery category)
    local isJewel = catL == "jewellery" or catL == "jewelry" or catL:find("jewel", 1, true)
    local isWatch = nameL:find("watch", 1, true) or ftL:find("watch", 1, true)
    if not isJewel and not isWatch then
        if nameL:find("necklace", 1, true) or nameL:find("earring", 1, true)
            or nameL:find("bracelet", 1, true) or nameL:find("amulet", 1, true)
            or nameL:find("bangle", 1, true)
            or (nameL:find("ring", 1, true) and not nameL:find("keyring", 1, true))
            or ftL:find("necklace", 1, true) or ftL:find("earring", 1, true)
            or ftL:find("ring_", 1, true) or ftL:find("bracelet", 1, true) then
            isJewel = true
        end
    end
    if isJewel then
        label = "common"
    end

    -- Walkie-talkies (incl. tactical) → rare
    if ftL:find("walkietalkie", 1, true) or nameL:find("walkie", 1, true)
        or nameL:find("walky", 1, true) then
        label = "rare"
    end

    -- Tissues: loose = trash; box = common (before general First Aid +1)
    local isTissueBox = ftL:find("tissuebox", 1, true)
        or ((nameL:find("tissue", 1, true) or ftL:find("tissue", 1, true))
            and (nameL:find("box", 1, true) or ftL:find("box", 1, true)))
    local isTissueLoose = (not isTissueBox) and (
        ftL == "base.tissue"
        or ftL:find("tissue", 1, true)
        or nameL:find("tissue", 1, true)
    )
    if isTissueLoose then
        label = "trash"
    elseif isTissueBox then
        label = "common"
    else
        -- Splint: fixed rare (after First Aid +1 would make table-epic → legendary)
        local isSplint = (ftL:find("splint", 1, true) or nameL:find("splint", 1, true))
            and not (ftL:find("splinter", 1, true) or nameL:find("splinter", 1, true))
        if isSplint then
            label = "rare"
        else
        -- First Aid / medical supplies → +1 rarity tier (not literature/skill books)
        local isBook = catL:find("literature", 1, true) or catL:find("skillbook", 1, true)
            or ftL:find("book", 1, true) or nameL:find("book", 1, true)
            or ftL:find("magazine", 1, true)
        local isFirstAid = false
        if not isBook then
            if catL == "firstaid" or catL:find("firstaid", 1, true) or catL:find("first aid", 1, true)
                or catL == "medical" or catL:find("medical", 1, true) then
                isFirstAid = true
            end
            if not isFirstAid then
                local needles = {
                    "firstaidkit", "firstaid", "bandage", "alcoholwipe", "alcoholwipes",
                    "disinfectant", "sutureneedle", "suture", "cottonball",
                    "cottonballs", "adhesivebandage", "bandaid", "band-aid",
                    "tweezers", "coldpack", "cold pack", "scalpel",
                    "pillsbeta", "pillssleeping", "pillsantidep", "pillsvitamins",
                    "alcoholbandage", "alcoholedcotton",
                }
                for i = 1, #needles do
                    if ftL:find(needles[i], 1, true) or nameL:find(needles[i], 1, true) then
                        isFirstAid = true
                        break
                    end
                end
                if not isFirstAid and (ftL == "base.pills" or nameL == "pills"
                    or nameL:find("painkill", 1, true) or nameL:find("analgesic", 1, true)) then
                    isFirstAid = true
                end
                if not isFirstAid and (nameL:find("alcohol wipe", 1, true)
                    or nameL:find("suture needle", 1, true)
                    or nameL:find("cotton ball", 1, true)
                    or nameL:find("adhesive bandage", 1, true)
                    or nameL:find("first aid", 1, true)) then
                    isFirstAid = true
                end
            end
        end
        if isFirstAid then
            label = promoteRarity(label)
        end
        end -- not splint
    end

    -- Plastic bags + tote bags → always common
    if ftL:find("plasticbag", 1, true) or nameL:find("plastic bag", 1, true)
        or nameL:find("plasticbag", 1, true)
        or ftL:find("totebag", 1, true) or nameL:find("tote bag", 1, true)
        or nameL:find("totebag", 1, true) or ftL:find("tote_bag", 1, true) then
        label = "common"
    end

    -- Skill books Vol I–V (Base.BookCarpentry1 … BookAiming5): fixed rarities
    -- Exclude hollow/fancy/fiction/sets (no trailing skill volume digit).
    do
        local vol = nil
        if not ftL:find("hollowbook", 1, true) and not ftL:find("bookfancy", 1, true)
            and not ftL:find("book_", 1, true) then
            -- base.bookcarpentry3 / base.bookmetalwelding5 / base.bookflintknapping1
            vol = tonumber(string.match(ftL, "%.book[%a]+([1-5])$"))
            if not vol then
                vol = tonumber(string.match(ftL, "book[%a]+([1-5])$"))
            end
            if not vol and item then
                pcall(function()
                    -- Some builds expose trained level band via script; prefer fullType.
                    if type(item.getModData) == "function" then
                        local md = item:getModData()
                        if md and md.knoxSkillBookVol then
                            vol = tonumber(md.knoxSkillBookVol)
                        end
                    end
                end)
            end
            if not vol then
                -- Display names: "Carpentry Vol. 3", "Vol 5", "Volume IV" rare
                vol = tonumber(string.match(nameL, "vol%.?%s*([1-5])"))
                    or tonumber(string.match(nameL, "volume%s*([1-5])"))
            end
        end
        if vol and vol >= 1 and vol <= 5 then
            label = ({
                [1] = "common",
                [2] = "uncommon",
                [3] = "rare",
                [4] = "epic",
                [5] = "legendary",
            })[vol] or label
        end
    end

    if item and isClothingItem(item) and not isDStore and not isJewel
        and not isArmorItem(item, catL, ftL, nameL) then
        label = demoteRarity(label)
    end
    return TIERS[label] or TIERS.unknown, label, chance
end

function KnoxSystem.UI.itemRarityRGB(item)
    local c = KnoxSystem.UI.getItemRarityColor(item)
    return c.r, c.g, c.b
end

function KnoxSystem.UI.itemRarityLabel(item)
    local _, label = KnoxSystem.UI.getItemRarityColor(item)
    return label
end

local function isUiVisible(self)
    if not self then return false end
    local vis = true
    pcall(function()
        if type(self.getIsVisible) == "function" then
            vis = self:getIsVisible() and true or false
        elseif type(self.isVisible) == "function" then
            vis = self:isVisible() and true or false
        elseif self.visible ~= nil then
            vis = self.visible and true or false
        end
    end)
    if not vis then return false end
    -- Collapsed / zero size = don't paint ghost panels
    local w, h = 0, 0
    pcall(function()
        w = self.width or (self.getWidth and self:getWidth()) or 0
        h = self.height or (self.getHeight and self:getHeight()) or 0
    end)
    if w < 8 or h < 8 then return false end
    return true
end

local function paintBlue(self)
    if not isUiVisible(self) then return end
    -- backgroundColor ONLY — full-pane drawRect left a ghost box when inv closed (Issue31)
    pcall(function()
        self.backgroundColor = { r = BG.r, g = BG.g, b = BG.b, a = 0.92 }
    end)
end

local function hookPrerender(cls, label)
    if not cls or type(cls.prerender) ~= "function" then return false end
    if cls["_knoxBg" .. PATCH_VER] then return true end
    cls["_knoxBg" .. PATCH_VER] = true
    local old = cls.prerender
    cls.prerender = function(self, ...)
        local r = old(self, ...)
        -- After vanilla so we win color reset; only when actually shown
        if isUiVisible(self) then
            paintBlue(self)
            if self.inventoryPane and isUiVisible(self.inventoryPane) then
                paintBlue(self.inventoryPane)
            end
        end
        return r
    end
    print("[KnoxSystem] blue bg hook: " .. tostring(label))
    return true
end

--- Repaint item names in rarity colors (Item Rarity UI row layout).
local function paintRarityNames(self)
    if not self or not self.itemslist then return end
    if not analyzeOn() then
        if not _loggedAnalyzeOff then
            _loggedAnalyzeOff = true
            print("[KnoxSystem] rarity names OFF (Analyze L1 not unlocked)")
        end
        return
    end
    if not dataLoaded then loadData() end

    local y = 0
    local headerHgt = self.headerHgt or 16
    local itemHgt = self.itemHgt or 18
    local yScroll = 0
    pcall(function() yScroll = self:getYScroll() or 0 end)
    local height = self.height or 200
    pcall(function() height = self:getHeight() or height end)
    local fontHgt = self.fontHgt or 12
    local textDY = (itemHgt - fontHgt) / 2
    local nameX = (self.column2 or 32) + 8
    local nameMaxW = 180
    if self.column3 and self.column2 then
        nameMaxW = math.max(60, (self.column3 - self.column2) - 12)
    end
    local font = self.font or (UIFont and UIFont.Small) or nil
    local maxStack = 50
    pcall(function()
        if ISInventoryPane and ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER then
            maxStack = ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER
        end
    end)

    for _, v in ipairs(self.itemslist) do
        if v.items then
            local count = 0
            for idx, item in ipairs(v.items) do
                count = count + 1
                local topOfItem = y * itemHgt + yScroll
                if topOfItem + itemHgt >= 0 and topOfItem <= height then
                    if idx == 1 and item then
                        local name = nil
                        pcall(function() name = item:getName() end)
                        if name and name ~= "" then
                            local col = KnoxSystem.UI.getItemRarityColor(item)
                            local drawY = (y * itemHgt) + headerHgt + textDY
                            local tw = nameMaxW
                            pcall(function()
                                if getTextManager and font then
                                    tw = math.min(nameMaxW, getTextManager():MeasureStringX(font, name) + 10)
                                end
                            end)
                            -- Cover vanilla white name, then draw colored
                            pcall(function()
                                if self.drawRect then
                                    self:drawRect(nameX - 2, drawY - 1, tw, math.max(12, fontHgt + 2), 0.92, BG.r, BG.g, BG.b)
                                end
                            end)
                            pcall(function()
                                if self.drawText then
                                    if font then
                                        self:drawText(name, nameX, drawY, col.r, col.g, col.b, 1, font)
                                    else
                                        self:drawText(name, nameX, drawY, col.r, col.g, col.b, 1)
                                    end
                                end
                            end)
                        end
                    end
                end
                y = y + 1
                if idx == 1 and self.collapsed and v.name and self.collapsed[v.name] then
                    break
                end
                if count > maxStack then break end
            end
        end
    end
end

local function hookRenderDetails()
    pcall(function() require "ISUI/ISInventoryPane" end)
    if not ISInventoryPane then
        print("[KnoxSystem] ISInventoryPane missing")
        return false
    end
    if ISInventoryPane._knoxRarityPaint == PATCH_VER then return true end

    local hooked = false

    -- Primary: renderdetails (Item Rarity UI path)
    if type(ISInventoryPane.renderdetails) == "function" then
        local original = ISInventoryPane.renderdetails
        ISInventoryPane.renderdetails = function(self, doDragged, ...)
            local result = original(self, doDragged, ...)
            if not doDragged then
                pcall(function() paintRarityNames(self) end)
            end
            return result
        end
        print("[KnoxSystem] rarity hook: renderdetails " .. PATCH_VER)
        hooked = true
    end

    -- Also try renderdetails alias / render
    if type(ISInventoryPane.renderDetails) == "function" and not ISInventoryPane._knoxRarityPaintRD then
        ISInventoryPane._knoxRarityPaintRD = true
        local original = ISInventoryPane.renderDetails
        ISInventoryPane.renderDetails = function(self, doDragged, ...)
            local result = original(self, doDragged, ...)
            if not doDragged then pcall(function() paintRarityNames(self) end) end
            return result
        end
        print("[KnoxSystem] rarity hook: renderDetails " .. PATCH_VER)
        hooked = true
    end

    -- Fallback: intercept drawText during renderdetails-style pass via doDrawItem
    if type(ISInventoryPane.doDrawItem) == "function" and not ISInventoryPane._knoxRarityDoDraw then
        ISInventoryPane._knoxRarityDoDraw = true
        local original = ISInventoryPane.doDrawItem
        ISInventoryPane.doDrawItem = function(self, y, item, alt, ...)
            local inv = nil
            if item then
                inv = item.item or item
                if type(inv) == "table" and inv.items then inv = inv.items[1] end
            end
            local col = nil
            if inv and analyzeOn() then
                col = KnoxSystem.UI.getItemRarityColor(inv)
            end
            local origDT = self.drawText
            if col and type(origDT) == "function" then
                self.drawText = function(sp, text, x, yy, r, g, b, a, font)
                    -- Recolor near-white / grey name text
                    if r and g and b and r > 0.45 and g > 0.45 and b > 0.45 and math.abs(r - g) < 0.15 then
                        r, g, b = col.r, col.g, col.b
                    end
                    return origDT(sp, text, x, yy, r, g, b, a, font)
                end
            end
            local res = original(self, y, item, alt, ...)
            self.drawText = origDT
            return res
        end
        print("[KnoxSystem] rarity hook: doDrawItem " .. PATCH_VER)
        hooked = true
    end

    ISInventoryPane._knoxRarityPaint = PATCH_VER
    if not hooked then
        print("[KnoxSystem] WARNING: no inventory draw hooks found")
    end
    return hooked
end

function KnoxSystem.UI._patchInventoryTheme()
    loadData()
    pcall(function() require "ISUI/ISInventoryPage" end)
    pcall(function() require "ISUI/ISInventoryPane" end)
    pcall(function() require "ISUI/InventoryWindow/ISInventoryPage" end)
    pcall(function() require "ISUI/InventoryWindow/ISInventoryPane" end)

    hookPrerender(ISInventoryPage, "ISInventoryPage")
    hookPrerender(ISInventoryPane, "ISInventoryPane")
    hookRenderDetails()
end

Events.OnGameStart.Add(function()
    KnoxSystem.UI._patchInventoryTheme()
    if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("loot") then
        local n = 0
        if rarities then for _ in pairs(rarities) do n = n + 1 end end
        KnoxSystem.Track.log("loot", "rarity_ready", {
            types = n,
            method = "post_paint_names",
            analyzeOn = analyzeOn() and 1 or 0,
            ver = PATCH_VER,
        })
    end
end)

local ticks = 0
Events.OnPlayerUpdate.Add(function(player)
    if not player then return end
    ticks = ticks + 1
    if ticks == 2 or ticks == 90 then
        KnoxSystem.UI._patchInventoryTheme()
    end
end)

pcall(function() KnoxSystem.UI._patchInventoryTheme() end)
print("[KnoxSystem] KS_UI_InventoryTheme loaded v" .. PATCH_VER)
