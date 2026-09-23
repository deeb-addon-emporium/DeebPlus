-- DeebPlus settings window + minimap button.
local DP = DeebPlus

local ROWS = {
	{ key = "questAccept",   label = "Auto accept and turn in quests (never picks rewards)" },
	{ key = "questWalk",     label = "Walk the NPC's quest list for me" },
	{ key = "questTrivial",  label = "Accept trivial (gray) quests too" },
	{ key = "vendorJunk",    label = "Sell gray junk at merchants" },
	{ key = "autoRepair",    label = "Auto repair at any repair vendor" },
	{ key = "autoAmmo",      label = "Auto buy ammo at vendors, above level 4 (/dp ammo <amount>)" },
	{ key = "gossipSkip",    label = "Auto-open vendor / trainer from NPC menus (hold Shift to see the menu)" },
	{ key = "lowVendor",     label = "Outline the bag item worth the least to a vendor" },
	{ key = "fsr",           label = "Five second rule bar on the mana bar" },
	{ key = "fogOff",        label = "Fog off (volumeFog 0)" },
	{ key = "tooltipCursor", label = "Tooltip follows the mouse" },
	{ key = "targetXP",      label = "Kill XP next to the target's level (below the cap)" },
	{ key = "classColorHP",  label = "Class-coloured health bars on the default frames" },
	{ key = "threatPlates",  label = "Threat % on nameplates, left of the health bar" },
	{ key = "questXP",       label = "Remember quest XP seen on alts, show it when the game says 0" },
	{ key = "errorCatcher",  label = "Catch Lua errors quietly (/dp errors to view and copy)" },
	{ key = "hideIssueReporter", label = "Hide the beta issue reporter" },
	{ key = "chatFilter",    label = "Hide chat containing banned phrases (friends exempt)" },
	{ key = "minimap",       label = "Show the minimap button" },
}
local PHRASE_BOX_H = 110

local cfg = CreateFrame("Frame", "DeebPlusConfig", UIParent, "BasicFrameTemplateWithInset")
cfg:SetSize(420, 40 + #ROWS * 30 + 40 + PHRASE_BOX_H + 60)
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
-- banned phrases: one per line
local phraseLbl = cfg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
phraseLbl:SetPoint("TOPLEFT", 16, y - 4); phraseLbl:SetText("Banned phrases, one per line (Enter saves):")
local phraseBg = CreateFrame("Frame", nil, cfg, "BackdropTemplate")
phraseBg:SetPoint("TOPLEFT", 16, y - 22); phraseBg:SetSize(388, PHRASE_BOX_H)
if phraseBg.SetBackdrop then
	phraseBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	phraseBg:SetBackdropColor(0, 0, 0, 0.6)
end
local phraseScroll = CreateFrame("ScrollFrame", "DeebPlusPhraseScroll", phraseBg, "UIPanelScrollFrameTemplate")
phraseScroll:SetPoint("TOPLEFT", 6, -6); phraseScroll:SetPoint("BOTTOMRIGHT", -26, 6)
local phraseBox = CreateFrame("EditBox", "DeebPlusPhraseBox", phraseScroll)
phraseBox:SetMultiLine(true); phraseBox:SetAutoFocus(false); phraseBox:SetFontObject(ChatFontNormal)
phraseBox:SetWidth(350); phraseBox:SetMaxLetters(4000)
phraseScroll:SetScrollChild(phraseBox)
local function savePhrases()
	DP.db.banPhrases = phraseBox:GetText() or ""
	DP.rebuildPhrases()
	DP.msg("banned phrases saved")
end
-- Enter inserts a newline (multi-line box); Ctrl+Enter or losing focus saves
phraseBox:SetScript("OnEnterPressed", function(self)
	if IsControlKeyDown() then self:ClearFocus() else self:Insert("\n") end
end)
phraseBox:SetScript("OnEditFocusLost", savePhrases)
phraseBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
phraseLbl:SetText("Banned phrases, one per line (click away or Ctrl+Enter to save):")

local swingBtn = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
swingBtn:SetSize(160, 22); swingBtn:SetPoint("BOTTOMRIGHT", -16, 30); swingBtn:SetText("Swing timer settings...")
swingBtn:SetScript("OnClick", function() DP.showSwingPanel() end)

local hint = cfg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("BOTTOMLEFT", 14, 12); hint:SetWidth(390); hint:SetJustifyH("LEFT")
hint:SetText("/dp opens this. /dpd dumps quest state. /fsr previews the mana bar.")

function DP.refreshConfig()
	if not DP.db then return end
	for _, cb in ipairs(boxes) do cb:SetChecked(DP.db[cb.key] and true or false) end
	if not phraseBox:HasFocus() then phraseBox:SetText(DP.db.banPhrases or "") end
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
SlashCmdList.DEEBPLUS = function(input)
	local cmd, rest = string.match(strtrim(input or ""), "^(%S+)%s*(.*)$")
	if cmd == "frames" then DP.listFrames(rest); return end
	if cmd == "errors" then DP.showErrors(); return end
	if cmd == "xp" then DP.questXPLookup(rest); return end
	if cmd == "swing" then DP.swingCmd(rest); return end
	if cmd == "ammo" then DP.ammoCmd(rest); return end
	if cmd == "hide" and rest ~= "" then
		DP.db.hideFrames = (DP.db.hideFrames or "") .. "\n" .. rest
		DP.msg("will hide frames named like '" .. rest .. "'"); DP.apply("hideFrames"); return
	end
	cfg:SetShown(not cfg:IsShown())
end
