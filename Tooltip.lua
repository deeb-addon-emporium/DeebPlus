-- Anchor the game tooltip to the mouse instead of the bottom right corner.
local DP = DeebPlus
local hooked = false
local function onSetDefaultAnchor(tt, parent)
	if not DP.db or not DP.db.tooltipCursor then return end
	if tt ~= GameTooltip then return end
	tt:SetOwner(parent or UIParent, "ANCHOR_CURSOR_RIGHT", 16, 8)
end
local function apply()
	if hooked or not hooksecurefunc then return end
	hooksecurefunc("GameTooltip_SetDefaultAnchor", onSetDefaultAnchor)
	hooked = true
end
DP.register("tooltip", { apply = apply })
