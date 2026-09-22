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
