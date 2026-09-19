-- DeebPlus threat percent on the stock nameplates.
-- UnitDetailedThreatSituation returns SECRET values on this client: they can be shown and fed
-- to widgets, never compared in addon code. So: the number is printed as-is, and the colour
-- comes from a small StatusBar whose texture is a green-orange-red gradient. Filled to the
-- percent, the bar's right edge lands on the colour that matches. No comparisons anywhere.
-- Toggle: DP.db.threatPlates. DP.db.threatTank flips the gradient (red = losing it).
local DP = DeebPlus

local BAR_W, BAR_H = 44, 6
local widgets = {}         -- unit -> { text=, bar= }

local function plateFor(unit)
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if ok then return plate end
end

local function gradient(tex, tank)
	if tank then
		tex:SetGradient("HORIZONTAL", CreateColor(0.9, 0.2, 0.2, 1), CreateColor(0.2, 0.9, 0.2, 1))
	else
		tex:SetGradient("HORIZONTAL", CreateColor(0.2, 0.9, 0.2, 1), CreateColor(0.9, 0.2, 0.2, 1))
	end
end

local function widgetFor(unit)
	local plate = plateFor(unit)
	if not plate then return nil end
	local host = plate.UnitFrame or plate
	local w = widgets[unit]
	if w and w.bar:GetParent() ~= host then w.bar:Hide(); w.text:Hide(); w = nil end
	if not w then
		local health = host.healthBar or host.HealthBar or (host.HealthBarsContainer and host.HealthBarsContainer.healthBar)
		local bar = CreateFrame("StatusBar", nil, host)
		bar:SetSize(BAR_W, BAR_H)
		bar:SetMinMaxValues(0, 100)
		bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
		bar:SetFrameLevel((host:GetFrameLevel() or 0) + 2)
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
		local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
		text:SetPoint("BOTTOM", bar, "TOP", 0, 1)
		if health then
			bar:SetPoint("RIGHT", health, "LEFT", -6, 0)     -- left of the health bar
		else
			bar:SetPoint("BOTTOMRIGHT", host, "TOPLEFT", -6, 2)
		end
		w = { bar = bar, text = text, tex = bar:GetStatusBarTexture() }
		widgets[unit] = w
	end
	gradient(w.tex, DP.db and DP.db.threatTank)
	return w
end

local function hide(w) if w then w.bar:Hide(); w.text:Hide() end end

local function update(unit)
	if not DP.db or not DP.db.threatPlates then return end
	if not unit or not UnitExists(unit) then return end
	local w = widgetFor(unit)
	if not w then return end
	if not UnitCanAttack("player", unit) or not UnitAffectingCombat(unit) or UnitIsDeadOrGhost(unit) then
		hide(w); return
	end
	local ok, _isTanking, status, scaled, raw = pcall(UnitDetailedThreatSituation, "player", unit)
	if not ok or status == nil then hide(w); return end
	local pct = scaled
	if pct == nil then pct = raw end
	if pct == nil then hide(w); return end
	-- secret-safe: format and SetValue accept secrets; nothing here compares them
	local okv = pcall(w.bar.SetValue, w.bar, pct)
	local okt = pcall(w.text.SetFormattedText, w.text, "%d%%", pct)
	if not okv or not okt then hide(w); return end
	w.bar:Show(); w.text:Show()
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
		hide(widgets[unit]); widgets[unit] = nil
	elseif (event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_THREAT_LIST_UPDATE") and unit and string.find(unit, "nameplate", 1, true) then
		pcall(update, unit)
	else
		pcall(updateAll)
	end
end)
C_Timer.NewTicker(0.5, function() if DP.db and DP.db.threatPlates and InCombatLockdown() then pcall(updateAll) end end)

DP.register("threat", { apply = function()
	if DP.db and not DP.db.threatPlates then for _, w in pairs(widgets) do hide(w) end else pcall(updateAll) end
end })
