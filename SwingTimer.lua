-- DeebPlus swing timer reskin. Blizzard's timer (SwingTimerRangedFrame / SwingTimerMainHandFrame /
-- SwingTimerOffHandFrame) stays the engine; this only changes how it looks:
--   no border, no background, no "Ranged"/"Main Hand" text, your size, your colour,
--   and a red "stop moving" slice at the end of the bar.
-- The red slice is baked into the fill image (swingbar.tga: left half white, right half red)
-- and revealed as the bar fills, so nothing here reads or compares the timer's value.
-- Settings: DP.db.swing = { enabled, w, h, zone (% of bar that is red), r,g,b, hideText, hideBorder }
local DP = DeebPlus

local NAMES = { "SwingTimerRangedFrame", "SwingTimerMainHandFrame", "SwingTimerOffHandFrame" }
local TEX = "Interface\\AddOns\\DeebPlus\\swingbar"
local done = {}

local function cfg()
	DP.db.swing = DP.db.swing or {}
	local c = DP.db.swing
	if c.w == nil then c.w = 220 end
	if c.h == nil then c.h = 14 end
	if c.zone == nil then c.zone = 10 end            -- percent of the bar
	if c.r == nil then c.r, c.g, c.b = 0.9, 0.75, 0.2 end
	if c.hideText == nil then c.hideText = true end
	if c.hideBorder == nil then c.hideBorder = true end
	return c
end

-- texture is half colour, half red. Show [0, x] of it so that red = zone% of what is shown:
-- red fraction = (x - 0.5) / x  =>  x = 0.5 / (1 - zone)
local function texRight(zonePct)
	local z = math.max(0, math.min(0.6, (zonePct or 10) / 100))
	return 0.5 / (1 - z)
end

local function skin(frame)
	local c = cfg()
	local bar = frame.StatusBar
	if not bar then return end
	if c.hideBorder then
		if frame.Border then frame.Border:Hide() end
		if frame.Background then frame.Background:Hide() end
	else
		if frame.Border then frame.Border:Show() end
		if frame.Background then frame.Background:Show() end
	end
	-- any text on the frame or the bar
	for _, holder in ipairs({ frame, bar }) do
		for _, region in ipairs({ holder:GetRegions() }) do
			if region:GetObjectType() == "FontString" then
				if c.hideText then region:Hide() else region:Show() end
			end
		end
		for _, child in ipairs({ holder:GetChildren() }) do
			for _, region in ipairs({ child:GetRegions() }) do
				if region:GetObjectType() == "FontString" then
					if c.hideText then region:Hide() else region:Show() end
				end
			end
		end
	end
	-- size: the bar is anchored to the frame's corners, so resizing the frame resizes the bar
	pcall(frame.SetSize, frame, c.w, c.h)
	-- fill: our image with the red end
	if not done[frame] then
		pcall(bar.SetStatusBarTexture, bar, TEX)
		done[frame] = true
	end
	local tex = bar:GetStatusBarTexture()
	if tex then
		pcall(tex.SetTexCoord, tex, 0, texRight(c.zone), 0, 1)
		pcall(tex.SetVertexColor, tex, 1, 1, 1)     -- keep the image's own colours
	end
	pcall(bar.SetStatusBarColor, bar, c.r, c.g, c.b)   -- tints the white half only... if the client multiplies
	-- a plain dark backdrop so the bar reads without the border
	if not frame.dpBack then
		frame.dpBack = frame:CreateTexture(nil, "BACKGROUND")
		frame.dpBack:SetAllPoints(bar)
	end
	frame.dpBack:SetColorTexture(0, 0, 0, c.hideBorder and 0.55 or 0)
end

local hooked = {}
local function apply()
	if not DP.db then return end
	local c = cfg()
	if c.enabled == false then return end
	for _, name in ipairs(NAMES) do
		local frame = _G[name]
		if frame and frame.StatusBar then
			pcall(skin, frame)
			if not hooked[frame] and frame.HookScript then
				hooked[frame] = true
				frame:HookScript("OnShow", function(f) if DP.db.swing.enabled ~= false then pcall(skin, f) end end)
			end
		end
	end
end

-- the Blizzard addon may load after us
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= "Blizzard_SwingTimer" then return end
	C_Timer.After(1, apply)
end)

-- /dp swing ...
DP.swingCmd = function(rest)
	local c = cfg()
	local k, v = string.match(rest or "", "^(%S+)%s*(.*)$")
	if k == nil or k == "ui" then DP.showSwingPanel(); return end
	if k == "size" then
		local w, h = string.match(v, "(%d+)%s+(%d+)")
		if w then c.w, c.h = tonumber(w), tonumber(h); DP.msg("swing bar " .. w .. "x" .. h) else DP.msg("/dp swing size <width> <height>") end
	elseif k == "zone" then
		c.zone = tonumber(v) or 10; DP.msg("stop zone " .. c.zone .. "% of the bar")
	elseif k == "color" then
		local r, g, b = string.match(v, "([%d.]+)%s+([%d.]+)%s+([%d.]+)")
		if r then c.r, c.g, c.b = tonumber(r), tonumber(g), tonumber(b); DP.msg("swing colour set") else DP.msg("/dp swing color <r> <g> <b>  (0-1 each)") end
	elseif k == "text" then c.hideText = not c.hideText; DP.msg("swing text " .. (c.hideText and "hidden" or "shown"))
	elseif k == "border" then c.hideBorder = not c.hideBorder; DP.msg("swing border " .. (c.hideBorder and "hidden" or "shown"))
	elseif k == "off" then c.enabled = false; DP.msg("swing reskin off - /reload to get Blizzard's look back")
	elseif k == "on" then c.enabled = true; DP.msg("swing reskin on")
	else
		DP.msg("/dp swing size W H | zone PCT | color R G B | text | border | on | off")
		DP.msg(string.format("now: %dx%d, zone %d%%, colour %.2f %.2f %.2f, text %s, border %s", c.w, c.h, c.zone, c.r, c.g, c.b, c.hideText and "hidden" or "shown", c.hideBorder and "hidden" or "shown"))
		return
	end
	apply()
end

DP.register("swing", { apply = apply })

-- ---------------------------------------------------------------------------
-- Settings panel: sliders, colour picker, toggles. Opened from /dp (button) or /dp swing ui
-- ---------------------------------------------------------------------------
local panel
local function buildPanel()
	if panel then return panel end
	local c = cfg()
	panel = CreateFrame("Frame", "DeebPlusSwingPanel", UIParent, "BasicFrameTemplateWithInset")
	panel:SetSize(340, 300); panel:SetPoint("CENTER", 120, 40); panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving); panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	if panel.TitleText then panel.TitleText:SetText("Swing timer") end
	tinsert(UISpecialFrames, "DeebPlusSwingPanel")
	panel:Hide()

	local y = -36
	local function slider(label, key, lo, hi, step, fmt)
		local s = CreateFrame("Slider", "DeebPlusSwing_" .. key, panel, "OptionsSliderTemplate")
		s:SetPoint("TOPLEFT", 24, y); s:SetWidth(280); s:SetMinMaxValues(lo, hi); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
		_G[s:GetName() .. "Low"]:SetText(tostring(lo)); _G[s:GetName() .. "High"]:SetText(tostring(hi))
		local text = _G[s:GetName() .. "Text"]
		local function show(v) text:SetText(string.format("%s: " .. fmt, label, v)) end
		s:SetValue(c[key]); show(c[key])
		s:SetScript("OnValueChanged", function(self, v)
			v = math.floor(v / step + 0.5) * step
			c[key] = v; show(v); apply()
		end)
		y = y - 44
		return s
	end
	slider("Width", "w", 80, 500, 2, "%d")
	slider("Height", "h", 4, 40, 1, "%d")
	slider("Stop zone", "zone", 0, 50, 1, "%d%% of the bar")

	-- colour
	local colBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	colBtn:SetSize(120, 22); colBtn:SetPoint("TOPLEFT", 24, y); colBtn:SetText("Bar colour")
	local swatch = panel:CreateTexture(nil, "ARTWORK"); swatch:SetSize(22, 22); swatch:SetPoint("LEFT", colBtn, "RIGHT", 8, 0)
	local function paintSwatch() swatch:SetColorTexture(c.r, c.g, c.b, 1) end
	paintSwatch()
	colBtn:SetScript("OnClick", function()
		local function onChange()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			c.r, c.g, c.b = r, g, b; paintSwatch(); apply()
		end
		local info = { r = c.r, g = c.g, b = c.b, hasOpacity = false, swatchFunc = onChange, cancelFunc = function(prev) if prev then c.r, c.g, c.b = prev.r, prev.g, prev.b; paintSwatch(); apply() end end }
		if ColorPickerFrame.SetupColorPickerAndShow then ColorPickerFrame:SetupColorPickerAndShow(info)
		else ColorPickerFrame.func = onChange; ColorPickerFrame.cancelFunc = info.cancelFunc; ColorPickerFrame:SetColorRGB(c.r, c.g, c.b); ColorPickerFrame:Show() end
	end)
	y = y - 32

	local function check(label, key, invert)
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 20, y); cb:SetSize(26, 26)
		local t = cb.Text or cb:GetFontString(); if t then t:SetText(label) end
		local function val() local v = c[key]; if invert then return not v end; return v ~= false end
		cb:SetChecked(val())
		cb:SetScript("OnClick", function(self)
			local on = self:GetChecked() and true or false
			c[key] = invert and (not on) or on
			apply()
			if key == "enabled" and not on then DP.msg("swing reskin off - /reload to get Blizzard's look back") end
		end)
		y = y - 28
	end
	check("Reskin the swing timer", "enabled")
	check("Show the Ranged / Main Hand text", "hideText", true)
	check("Show Blizzard's border", "hideBorder", true)

	local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", 16, 12); hint:SetWidth(300); hint:SetJustifyH("LEFT")
	hint:SetText("Stop zone: the red end of the bar. 3 s Auto Shot: 7% is about 0.2 s.")
	return panel
end
DP.showSwingPanel = function() buildPanel(); panel:SetShown(not panel:IsShown()) end
