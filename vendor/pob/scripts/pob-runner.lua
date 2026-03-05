-- pob-runner.lua: Headless PoB simulation runner
-- Usage (from vendor/pob/origin/src):
--   luajit ../../scripts/pob-runner.lua xml [--skill "Name"] < build.xml > result.json
--   luajit ../../scripts/pob-runner.lua json items.json passives.json > result.json
--
-- Requires: LUA_PATH set to include runtime/lua, LUA_CPATH set to include lua_modules

-- Guard: must be run from within PoB src directory (HeadlessWrapper.lua expects it)
local f = io.open("HeadlessWrapper.lua", "r")
if not f then
	io.stderr:write("ERROR: Must run from vendor/pob/origin/src directory\n")
	os.exit(1)
end
f:close()

-- Redirect print() to stderr so PoB's ConPrintf output does not pollute JSON on stdout
local _print = print
print = function(...)
	local args = { ... }
	for i = 1, #args do
		if i > 1 then io.stderr:write("\t") end
		io.stderr:write(tostring(args[i]))
	end
	io.stderr:write("\n")
end

-- Stub required by Launch.lua before HeadlessWrapper provides its own
function GetVirtualScreenSize()
	return 1920, 1080
end

-- Parse arguments before HeadlessWrapper init (it consumes OnInit/OnFrame)
local mode = arg[1]
if mode ~= "xml" and mode ~= "json" then
	io.stderr:write("ERROR: First argument must be 'xml' or 'json'\n")
	os.exit(1)
end

local skillName = nil
local jsonItemsPath = nil
local jsonPassivesPath = nil

if mode == "xml" then
	-- Parse optional --skill "Name"
	local i = 2
	while i <= #arg do
		if arg[i] == "--skill" then
			i = i + 1
			skillName = arg[i]
			if not skillName then
				io.stderr:write("ERROR: --skill requires a skill name argument\n")
				os.exit(1)
			end
		end
		i = i + 1
	end
elseif mode == "json" then
	jsonItemsPath = arg[2]
	jsonPassivesPath = arg[3]
	if not jsonItemsPath or not jsonPassivesPath then
		io.stderr:write("ERROR: json mode requires: pob-runner.lua json <items.json> <passives.json>\n")
		os.exit(1)
	end
end

-- Initialize PoB headless environment
dofile("HeadlessWrapper.lua")

local dkjson = require("dkjson")

-- Helper: write JSON error to stdout and exit
local function exitWithError(msg)
	io.stdout:write(dkjson.encode({ error = msg }) .. "\n")
	os.exit(1)
end

-- Helper: read entire file contents
local function readFile(path)
	local fh, err = io.open(path, "r")
	if not fh then
		exitWithError("Cannot open file: " .. path .. " (" .. (err or "unknown error") .. ")")
	end
	local content = fh:read("*a")
	fh:close()
	return content
end

-- Helper: extract output stats from build.calcsTab.mainOutput
local function extractOutput()
	local output = build.calcsTab and build.calcsTab.mainOutput or {}
	local function n(key)
		local v = output[key]
		if type(v) == "number" then
			return v
		end
		return 0
	end

	return {
		build = {
			class = build.spec and build.spec.curClassName or "None",
			ascendancy = build.spec and build.spec.curAscendClassName or "None",
			level = build.characterLevel or 1,
		},
		offence = {
			combinedDPS = n("CombinedDPS"),
			totalDPS = n("TotalDPS"),
			totalDotDPS = n("TotalDotDPS"),
			fullDPS = n("FullDPS"),
			speed = n("Speed"),
			hitChance = n("HitChance"),
			critChance = n("CritChance"),
			critMultiplier = n("CritMultiplier"),
			bleedDPS = n("BleedDPS"),
			igniteDPS = n("IgniteDPS"),
			poisonDPS = n("PoisonDPS"),
			impaleDPS = n("ImpaleDPS"),
		},
		defence = {
			life = n("Life"),
			energyShield = n("EnergyShield"),
			evasion = n("Evasion"),
			armour = n("Armour"),
			totalEHP = n("TotalEHP"),
			blockChance = n("EffectiveBlockChance"),
			spellBlockChance = n("EffectiveSpellBlockChance"),
			suppressionChance = n("EffectiveSpellSuppressionChance"),
			physDamageReduction = n("PhysicalDamageReduction"),
		},
		resistances = {
			fire = n("FireResist"),
			cold = n("ColdResist"),
			lightning = n("LightningResist"),
			chaos = n("ChaosResist"),
			fireOvercap = n("FireResistOverCap"),
			coldOvercap = n("ColdResistOverCap"),
			lightningOvercap = n("LightningResistOverCap"),
		},
		attributes = {
			str = n("Str"),
			dex = n("Dex"),
			int = n("Int"),
		},
		resources = {
			lifeRegen = n("LifeRegenRecovery"),
			manaRegen = n("ManaRegenRecovery"),
			esRegen = n("EnergyShieldRegenRecovery"),
			netLifeRegen = n("NetLifeRegen"),
			manaUnreserved = n("ManaUnreserved"),
		},
	}
end

-- Helper: select skill by name in socket groups
local function selectSkillByName(name)
	local groups = build.skillsTab and build.skillsTab.socketGroupList
	if not groups then
		return false, "No socket groups found"
	end
	local lowerName = name:lower()
	for i, group in ipairs(groups) do
		if group.gemList then
			for _, gem in ipairs(group.gemList) do
				local gemName = gem.nameSpec or (gem.gemData and gem.gemData.name) or ""
				if gemName:lower() == lowerName then
					build.mainSocketGroup = i
					runCallback("OnFrame")
					return true, nil
				end
			end
		end
	end
	return false, "Skill not found: " .. name
end

-- Helper: auto-select main skill (socket group with most support gems)
local function autoSelectMainSkill()
	local groups = build.skillsTab and build.skillsTab.socketGroupList
	if not groups or #groups == 0 then
		return
	end
	local bestIndex = 1
	local bestSupportCount = -1
	for i, group in ipairs(groups) do
		if group.enabled and group.gemList then
			local supportCount = 0
			local hasActive = false
			for _, gem in ipairs(group.gemList) do
				if gem.gemData and gem.gemData.grantedEffect then
					if gem.gemData.grantedEffect.support then
						supportCount = supportCount + 1
					else
						hasActive = true
					end
				end
			end
			if hasActive and supportCount > bestSupportCount then
				bestSupportCount = supportCount
				bestIndex = i
			end
		end
	end
	if bestIndex ~= build.mainSocketGroup then
		build.mainSocketGroup = bestIndex
		runCallback("OnFrame")
	end
end

-- XML mode: read build XML from stdin
if mode == "xml" then
	local xmlText = io.read("*a")
	if not xmlText or xmlText:match("^%s*$") then
		exitWithError("Empty XML input")
	end

	local ok, err = pcall(loadBuildFromXML, xmlText, "sim")
	if not ok then
		exitWithError("Failed to load build XML: " .. tostring(err))
	end

	if skillName then
		local found, skillErr = selectSkillByName(skillName)
		if not found then
			exitWithError(skillErr)
		end
	end

	io.stdout:write(dkjson.encode(extractOutput()) .. "\n")

-- JSON mode: read items and passives from files
elseif mode == "json" then
	local itemsJSON = readFile(jsonItemsPath)
	local passivesJSON = readFile(jsonPassivesPath)

	local ok, err = pcall(loadBuildFromJSON, itemsJSON, passivesJSON)
	if not ok then
		exitWithError("Failed to load build JSON: " .. tostring(err))
	end

	autoSelectMainSkill()

	local result = extractOutput()

	-- Export build as XML for downstream tools (optimizer, encode)
	local xmlOk, xmlText = pcall(function()
		return build:SaveDB("export")
	end)
	if xmlOk and xmlText then
		result.xml = xmlText
	end

	io.stdout:write(dkjson.encode(result) .. "\n")
end
