-- DeebPlus five second rule module (ported from FiveSecondRule). Toggle: DP.db.fsr
local DP = DeebPlus
-- After you spend mana on a spell, mana regen stops for 5 seconds. This draws a bar over your
-- mana bar that drains over those 5 seconds. Gone = regenerating again.
--   /fsr        fake a cast so you can see the bar
--   /fsr reset  forget a dragged position and snap back onto the mana bar

local DURATION = 5
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local function msg(t) DP.msg("5SR " .. t) end

-- ---- find the player's mana bar, old or new frame layout ----
local function findManaBar()
	local pf = _G.PlayerFrame
	if pf and pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentMain then
		local area = pf.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
		if area and area.ManaBar then return area.ManaBar end
	end
	if pf and pf.manabar then return pf.manabar end
	return _G.PlayerFrameManaBar
end

-- ---- bar ----
local bar = CreateFrame("Frame", "FiveSecondRuleBar", UIParent)
bar:SetFrameStrata("HIGH")
bar:SetSize(120, 12)
bar:Hide()

local fill = bar:CreateTexture(nil, "ARTWORK")
fill:SetColorTexture(0.2, 0.6, 1.0, 0.55)
fill:SetPoint("TOPLEFT")
fill:SetPoint("BOTTOMLEFT")

local edge = bar:CreateTexture(nil, "OVERLAY")
edge:SetColorTexture(1, 1, 1, 0.9)
edge:SetWidth(2)
edge:SetPoint("TOP", fill, "TOPRIGHT")
edge:SetPoint("BOTTOM", fill, "BOTTOMRIGHT")

local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetPoint("CENTER")

local endTime = 0

local function anchor()
	bar:ClearAllPoints()
	local db = DP.db and DP.db.fsrPos
	if type(db) == "table" and db.x and db.y then
		bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
		bar:SetSize(db.w or 120, db.h or 12)
		return
	end
	local mb = findManaBar()
	if mb then
		bar:SetAllPoints(mb)
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
	end
end

bar:SetScript("OnUpdate", function(self)
	local left = endTime - GetTime()
	if left <= 0 then
		self:Hide()
		return
	end
	local frac = 1 - (left / DURATION)   -- grows left to right
	fill:SetWidth(math.max(1, self:GetWidth() * frac))
	text:SetFormattedText("%.1f", left)
end)

local function start()
	if not DP.db or not DP.db.fsr then return end
	endTime = GetTime() + DURATION
	anchor()
	bar:Show()
end

-- drag to move (hold Shift), position saved
bar:SetMovable(true)
bar:EnableMouse(false)
local mover = CreateFrame("Frame", nil, bar)
mover:SetAllPoints()
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:SetScript("OnDragStart", function()
	if IsShiftKeyDown() then bar:StartMoving() end
end)
mover:SetScript("OnDragStop", function()
	bar:StopMovingOrSizing()
	local x, y = bar:GetCenter()
	DP.db.fsrPos = DP.db.fsrPos or {}
	DP.db.fsrPos.x, DP.db.fsrPos.y = x, y
	DP.db.fsrPos.w, DP.db.fsrPos.h = bar:GetWidth(), bar:GetHeight()
end)
mover:SetPropagateMouseClicks(true)
mover:SetPropagateMouseMotion(true)

-- ---- did that spell cost mana? ----
local function costsMana(spellID)
	if not spellID then return false end
	local costs
	if C_Spell and C_Spell.GetSpellPowerCost then
		local ok, r = pcall(C_Spell.GetSpellPowerCost, spellID)
		if ok then costs = r end
	elseif GetSpellPowerCost then
		local ok, r = pcall(GetSpellPowerCost, spellID)
		if ok then costs = r end
	end
	if type(costs) ~= "table" then return false end
	for _, c in ipairs(costs) do
		if type(c) == "table" and c.type == MANA and type(c.cost) == "number" and c.cost > 0 then
			return true
		end
	end
	return false
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", function(_, event, unit, _, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit ~= "player" then return end
		if UnitPowerType("player") ~= MANA then return end
		if costsMana(spellID) then start() end
		return
	end
	if event == "PLAYER_LOGIN" then
		DP.db.fsrPos = DP.db.fsrPos or {}
	end
	anchor()
end)

SLASH_FIVESECONDRULE1 = "/fsr"
SlashCmdList.FIVESECONDRULE = function(input)
	local w = string.lower(strtrim and strtrim(input or "") or (input or ""))
	if w == "reset" then
		DP.db.fsrPos = {}
		anchor()
		msg("snapped back onto the mana bar")
		return
	end
	start()
end

DP.register("fsr", { apply = function() if DP.db and not DP.db.fsr then bar:Hide() end end })
