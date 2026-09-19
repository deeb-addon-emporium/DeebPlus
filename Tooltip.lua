-- Tooltip follows the mouse. Done from our OWN OnUpdate, never from inside Blizzard's tooltip
-- code: hooking GameTooltip_SetDefaultAnchor taints whatever button opened the tooltip, and on
-- this client that blocked right-clicking items in bags. Only tooltips using the default anchor
-- (ANCHOR_NONE, parked bottom-right) are moved; unit-frame / cursor-anchored ones are left alone.
local DP = DeebPlus

local OFF_X, OFF_Y = 16, 8
local driver = CreateFrame("Frame")
local missFrames = 0
local wasShown = false

local function follow()
	if not DP.db or not DP.db.tooltipCursor then return end
	local tt = GameTooltip
	if not tt or not tt:IsShown() then wasShown = false; return end
	if not wasShown then wasShown = true; missFrames = 0 end   -- fresh tooltip
	-- no slow fade, but no flicker either: hide only once the mouse has clearly left
	local owner = tt:GetOwner()
	local _, unit = tt:GetUnit()
	local gone
	if unit then
		gone = not UnitExists("mouseover")
	elseif owner and owner ~= UIParent and owner.IsMouseOver then
		gone = not owner:IsMouseOver()
	end
	if gone then
		missFrames = missFrames + 1
		if missFrames >= 4 then tt:Hide(); missFrames = 0; return end
	else
		missFrames = 0
	end
	if tt:GetAnchorType() ~= "ANCHOR_NONE" then return end
	-- world units (mouseover mobs) have UIParent as the owner; they count too
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	x, y = x / s + OFF_X, y / s + OFF_Y
	local w, h = tt:GetWidth() or 0, tt:GetHeight() or 0
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if x + w > sw then x = sw - w end
	if y + h > sh then y = sh - h end
	-- Blizzard's default anchor is a BOTTOMRIGHT point on UIParent and it re-applies it on
	-- every unit-tooltip refresh. Setting the SAME point replaces it; a different point would
	-- be added to it and the tooltip would stretch between the two.
	tt:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", x + w, y)
end

local function apply()
	if DP.db and DP.db.tooltipCursor then
		driver:SetScript("OnUpdate", follow)
	else
		driver:SetScript("OnUpdate", nil)
	end
end

DP.register("tooltip", { apply = apply })
