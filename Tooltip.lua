-- Tooltip follows the mouse. Done from our OWN OnUpdate, never from inside Blizzard's tooltip
-- code: hooking GameTooltip_SetDefaultAnchor taints whatever button opened the tooltip, and on
-- this client that blocked right-clicking items in bags. Only tooltips using the default anchor
-- (ANCHOR_NONE, parked bottom-right) are moved; unit-frame / cursor-anchored ones are left alone.
local DP = DeebPlus

local OFF_X, OFF_Y = 16, 8
local driver = CreateFrame("Frame")

local function follow()
	if not DP.db or not DP.db.tooltipCursor then return end
	local tt = GameTooltip
	if not tt or not tt:IsShown() then return end
	-- no slow fade: the moment it starts fading, or the mob under the mouse is gone, drop it
	if tt:GetAlpha() < 1 then tt:Hide(); return end
	local _, unit = tt:GetUnit()
	if unit and not UnitExists("mouseover") and not (tt:GetOwner() and tt:GetOwner() ~= UIParent and tt:GetOwner():IsMouseOver()) then
		tt:Hide(); return
	end
	if tt:GetAnchorType() ~= "ANCHOR_NONE" then return end
	-- world units (mouseover mobs) have UIParent as the owner; they count too
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	x, y = x / s + OFF_X, y / s + OFF_Y
	-- keep it on screen
	local w, h = tt:GetWidth() or 0, tt:GetHeight() or 0
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if x + w > sw then x = sw - w end
	if y + h > sh then y = sh - h end
	tt:ClearAllPoints()
	tt:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function apply()
	if DP.db and DP.db.tooltipCursor then
		driver:SetScript("OnUpdate", follow)
	else
		driver:SetScript("OnUpdate", nil)
	end
end

DP.register("tooltip", { apply = apply })
