-- DeebPlus threat percent on the stock nameplates.
-- Uses UnitDetailedThreatSituation("player", unit): isTanking, status, scaledPercent, rawPercent.
-- Shows scaledPercent (100 = you pull aggro). Colours, DPS view: green safe, orange close,
-- red you have it. Tank view (DP.db.threatTank) flips: green you have it, red you lost it.
-- Toggle: DP.db.threatPlates
local DP = DeebPlus

local WARN = 80          -- orange from here up (DPS view)
local texts = {}         -- unit -> FontString

local function plateFor(unit)
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if ok then return plate end
end

local function textFor(unit)
	local plate = plateFor(unit)
	if not plate then return nil end
	local host = plate.UnitFrame or plate
	local t = texts[unit]
	if t and t:GetParent() ~= host then t:Hide(); t = nil end
	if not t then
		t = host:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
		local health = host.healthBar or host.HealthBar or (host.HealthBarsContainer and host.HealthBarsContainer.healthBar)
		if health then
			t:SetPoint("LEFT", health, "RIGHT", 4, 0)
		else
			t:SetPoint("BOTTOM", host, "TOP", 0, 2)
		end
		texts[unit] = t
	end
	return t
end

local function colour(isTanking, pct)
	local tank = DP.db and DP.db.threatTank
	if tank then
		if isTanking then return 0.2, 0.9, 0.2 end
		if pct and pct >= WARN then return 1, 0.6, 0.1 end
		return 0.9, 0.2, 0.2
	end
	if isTanking then return 0.9, 0.2, 0.2 end
	if pct and pct >= WARN then return 1, 0.6, 0.1 end
	return 0.2, 0.9, 0.2
end

local function update(unit)
	if not DP.db or not DP.db.threatPlates then return end
	if not unit or not UnitExists(unit) then return end
	local t = textFor(unit)
	if not t then return end
	if not UnitCanAttack("player", unit) or not UnitAffectingCombat(unit) or UnitIsDeadOrGhost(unit) then
		t:Hide(); return
	end
	local ok, isTanking, status, scaled, raw = pcall(UnitDetailedThreatSituation, "player", unit)
	if not ok or status == nil then t:Hide(); return end
	local pct = scaled or raw or 0
	t:SetText(string.format("%d%%", pct))
	t:SetTextColor(colour(isTanking, pct))
	t:Show()
end

local function updateAll()
	if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then update(unit) end
	end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE",
	"UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED" }) do
	pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_REMOVED" then
		local t = texts[unit]; if t then t:Hide() end
		texts[unit] = nil
	elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_THREAT_LIST_UPDATE" then
		if unit and string.find(unit, "nameplate", 1, true) then update(unit) else updateAll() end
	else
		updateAll()
	end
end)
-- threat list events can lag a beat; a slow ticker keeps the numbers honest
C_Timer.NewTicker(0.5, function() if DP.db and DP.db.threatPlates and InCombatLockdown() then updateAll() end end)

DP.register("threat", { apply = function()
	if DP.db and not DP.db.threatPlates then for _, t in pairs(texts) do t:Hide() end else updateAll() end
end })
