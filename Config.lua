-- DeebPlus settings window + minimap button.
local DP = DeebPlus

local ROWS = {
	{ key = "questAccept",   label = "Auto accept and turn in quests (never picks rewards)" },
	{ key = "questWalk",     label = "Walk the NPC's quest list for me" },
	{ key = "questTrivial",  label = "Accept trivial (gray) quests too" },
	{ key = "vendorJunk",    label = "Sell gray junk at merchants" },
	{ key = "lowVendor",     label = "Outline the bag item worth the least to a vendor" },
	{ key = "fsr",           label = "Five second rule bar on the mana bar" },
	{ key = "fogOff",        label = "Fog off (volumeFog 0)" },
	{ key = "tooltipCursor", label = "Tooltip follows the mouse" },
	{ key = "minimap",       label = "Show the minimap button" },
}

local cfg = CreateFrame("Frame", "DeebPlusConfig", UIParent, "BasicFrameTemplateWithInset")
cfg:SetSize(420, 40 + #ROWS * 30 + 40)
cfg:SetPoint("CENTER")
cfg:SetMovable(true); cfg:EnableMouse(true); cfg:RegisterForDrag("LeftButton")
cfg:SetScript("OnDragStart", cfg.StartMoving)
cfg:SetScript("OnDragStop", cfg.StopMovingOrSizing)
cfg:SetFrameStrata("DIALOG")
cfg:Hide()
if cfg.TitleText then cfg.TitleText:SetText("DeebPlus") end
tinsert(UISpecialFrames, "DeebPlusConfig")

local boxes = {}
local y = -34
for i, row in ipairs(ROWS) do
	local cb = CreateFrame("CheckButton", "DeebPlusConfigCheck" .. i, cfg, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", 14, y); cb:SetSize(26, 26)
	local t = cb.Text or _G[cb:GetName() .. "Text"]
	if t then t:SetText(row.label) end
	cb:SetScript("OnClick", function(self) DP.set(row.key, self:GetChecked() and true or false) end)
	cb.key = row.key
	boxes[#boxes + 1] = cb
	y = y - 30
end
local hint = cfg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("BOTTOMLEFT", 14, 12); hint:SetWidth(390); hint:SetJustifyH("LEFT")
hint:SetText("/dp opens this. /dpd dumps quest state. /fsr previews the mana bar.")

function DP.refreshConfig()
	if not DP.db then return end
	for _, cb in ipairs(boxes) do cb:SetChecked(DP.db[cb.key] and true or false) end
	if DeebPlusMinimapButton then DeebPlusMinimapButton:SetShown(DP.db.minimap ~= false) end
end
cfg:SetScript("OnShow", DP.refreshConfig)

local function buildMinimapButton()
	local btn = CreateFrame("Button", "DeebPlusMinimapButton", Minimap)
	btn:SetSize(32, 32); btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp"); btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local overlay = btn:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53); overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); overlay:SetPoint("TOPLEFT")
	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); bg:SetPoint("TOPLEFT", 7, -5)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18); icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01"); icon:SetPoint("TOPLEFT", 8, -6)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local function place()
		local angle = math.rad(DP.db.minimapAngle or 210)
		local r = (Minimap:GetWidth() / 2) + 5
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
	end
	local function dragUpdate()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local sc = Minimap:GetEffectiveScale()
		DP.db.minimapAngle = math.deg(math.atan2(cy / sc - my, cx / sc - mx))
		place()
	end
	btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
	btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	btn:SetScript("OnClick", function() cfg:SetShown(not cfg:IsShown()) end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("DeebPlus")
		GameTooltip:AddLine("Click: settings", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Drag: move", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	place()
	btn:SetShown(DP.db.minimap ~= false)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	C_Timer.After(0, function()
		local ok, err = pcall(buildMinimapButton)
		if not ok then DP.msg("minimap button failed: " .. tostring(err)) end
	end)
end)

SLASH_DEEBPLUS1 = "/dp"
SlashCmdList.DEEBPLUS = function() cfg:SetShown(not cfg:IsShown()) end
