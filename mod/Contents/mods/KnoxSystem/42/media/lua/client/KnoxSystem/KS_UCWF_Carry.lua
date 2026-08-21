-- KnoxSystem UCWF client glue (author format from MusicManiac UCWF examples)
-- Loads only on SP / MP_Client — not on dedicated server.
-- Event name: recomputeCarryWeight_KnoxPower (UCWF convention)

local function gameMode()
	if not isClient() and not isServer() then
		return "SP"
	elseif isClient() then
		return "MP_Client"
	end
	return "MP_Server"
end

local gameMode = gameMode()

if gameMode == "MP_Server" then
	print("KnoxSystem_UCWF | Detected " .. gameMode .. " environment, skipping the file")
	return
else
	print("KnoxSystem_UCWF | Detected " .. gameMode .. " environment, loading the file")
end

--- Fire weight recalculation when Power (or other carry drivers) change.
local function recomputeCarryWeight_KnoxPower(character)
	if gameMode == "SP" then
		print(
			"KnoxSystem_UCWF | recomputeCarryWeight_KnoxPower | Detected "
				.. gameMode
				.. " environment, recomputing carry weight directly"
		)
		local ok, err = pcall(function()
			local fw = rawget(_G, "UnifiedCarryWeightFramework")
			if type(fw) ~= "table" then
				fw = require("UnifiedCarryWeightFramework")
			end
			if type(fw) == "table" and type(fw.recomputeAll) == "function" then
				fw.recomputeAll()
			end
		end)
		if not ok then
			print("KnoxSystem_UCWF | recomputeAll error: " .. tostring(err))
		end
		-- Layer Knox Power after UCWF base calc
		if character and KnoxSystem and KnoxSystem.Power and KnoxSystem.Power.syncCarry then
			pcall(function() KnoxSystem.Power.syncCarry(character) end)
		elseif KnoxSystem and KnoxSystem.Power and KnoxSystem.Power.syncCarry and getPlayer then
			pcall(function() KnoxSystem.Power.syncCarry(getPlayer()) end)
		end
	elseif gameMode == "MP_Client" then
		print(
			"KnoxSystem_UCWF | recomputeCarryWeight_KnoxPower | Detected "
				.. gameMode
				.. " environment, sending command to server to recalculate carry weight"
		)
		local player = character
		if not player and getPlayer then player = getPlayer() end
		if player and sendClientCommand then
			sendClientCommand(player, "UCWF", "update_weight", {})
		end
	end
end

-- Expose so SP cart / Power buy can fire the named recompute
if not KnoxSystem then KnoxSystem = {} end
KnoxSystem.UCWF = KnoxSystem.UCWF or {}
KnoxSystem.UCWF.recomputeCarryWeight_KnoxPower = recomputeCarryWeight_KnoxPower
KnoxSystem.UCWF.gameMode = gameMode

-- Level-up / perk events sometimes used by other mods; safe no-ops if missing
if Events.LevelPerk then
	Events.LevelPerk.Remove(recomputeCarryWeight_KnoxPower)
	Events.LevelPerk.Add(recomputeCarryWeight_KnoxPower)
end

print("KnoxSystem_UCWF | client glue ready (gameMode=" .. tostring(gameMode) .. ")")
