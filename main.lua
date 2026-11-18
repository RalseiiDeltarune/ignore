-- ==========================================
-- AUTO-CLEANUP (Removes old script instance)
-- ==========================================
local _env = (type(getgenv) == "function" and getgenv()) or _G
if _env and type(_env.ActiveScriptCleanup) == "function" then
	pcall(_env.ActiveScriptCleanup)
end

local activeConnections = {}
local lightParts = {}
local espData = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ==========================================
-- THEME
-- ==========================================
local Theme = {
	ACCENT      = Color3.fromRGB(255, 182, 193),
	NAME_COLOR  = Color3.fromRGB(255, 255, 255),
	TRACE_COLOR = Color3.fromRGB(255, 255, 255),
	HP_BG       = Color3.fromRGB(20, 20, 20),
}

-- ==========================================
-- ESP SETTINGS
-- ==========================================
local ESPSettings = {
	Enabled       = true,
	ShowName      = true,
	ShowHealth    = true,
	ShowTrace     = false,
	ShowHighlight = true,
	MaxDistance   = 1500,
}

-- ==========================================
-- CLEANUP
-- ==========================================
local function removeESPEntry(model)
	local d = espData[model]
	if not d then return end
	pcall(function() d.name:Remove() end)
	pcall(function() d.hpbar:Remove() end)
	pcall(function() d.hpbarbg:Remove() end)
	pcall(function() d.trace:Remove() end)
	pcall(function() d.hl:Destroy() end)
	espData[model] = nil
end

local function cleanup()
	for _, conn in ipairs(activeConnections) do
		if conn and conn.Connected then conn:Disconnect() end
	end
	activeConnections = {}

	for _, data in ipairs(lightParts) do
		if data.Part then data.Part:Destroy() end
	end
	lightParts = {}

	for model in pairs(espData) do
		removeESPEntry(model)
	end

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj.Name == "CustomESP_Highlight" or obj.Name == "CustomESP_Billboard" then
			obj:Destroy()
		end
	end

	camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		camera.CameraSubject = player.Character.Humanoid
	end

	print("Previous script instance cleaned up!")
end

if _env then _env.ActiveScriptCleanup = cleanup end

-- ==========================================
-- FILE-BASED DEFAULT WALKSPEED LOGGING
-- ==========================================
local fileName     = "Xeno_GameDefaultSpeed.txt"
local defaultSpeed = 16

local function fetchAndSaveDefault()
	local char = player.Character or player.CharacterAdded:Wait()
	local humanoid = char:WaitForChild("Humanoid", 5)
	if humanoid then
		local currentDefault = humanoid.WalkSpeed
		if not pcall(function() return isfile and isfile(fileName) end) or not isfile(fileName) then
			pcall(function() writefile(fileName, tostring(currentDefault)) end)
			defaultSpeed = currentDefault
		else
			local ok, content = pcall(readfile, fileName)
			defaultSpeed = (ok and tonumber(content)) or currentDefault
		end
	end
end

task.spawn(fetchAndSaveDefault)

-- ==========================================
-- CHARACTER TRACKING
-- ==========================================
local character = player.Character or player.CharacterAdded:Wait()
table.insert(activeConnections, player.CharacterAdded:Connect(function(char)
	character = char
	task.spawn(fetchAndSaveDefault)
end))

-- ==========================================
-- 1. LIGHT GRID & FOG REMOVER
-- ==========================================
local lightToggled = false
local lightOffsets = { Vector3.new(0, 6, 0) }
local maxDistance  = 800
local spacing      = 110

for dist = spacing, maxDistance, spacing do
	table.insert(lightOffsets, Vector3.new( dist, 6,    0))
	table.insert(lightOffsets, Vector3.new(-dist, 6,    0))
	table.insert(lightOffsets, Vector3.new(    0, 6,  dist))
	table.insert(lightOffsets, Vector3.new(    0, 6, -dist))
	table.insert(lightOffsets, Vector3.new( dist, 6,  dist))
	table.insert(lightOffsets, Vector3.new(-dist, 6,  dist))
	table.insert(lightOffsets, Vector3.new( dist, 6, -dist))
	table.insert(lightOffsets, Vector3.new(-dist, 6, -dist))
end

local function clearFogAndAtmosphere()
	Lighting.FogEnd   = 9e9
	Lighting.FogStart = 0
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then atm:Destroy() end
	table.insert(activeConnections, Lighting.ChildAdded:Connect(function(child)
		if child:IsA("Atmosphere") then child:Destroy() end
	end))
end

local function enableLight()
	if #lightParts > 0 then return end
	clearFogAndAtmosphere()
	for _, offset in ipairs(lightOffsets) do
		local part = Instance.new("Part")
		part.Size        = Vector3.new(1, 1, 1)
		part.Transparency = 1
		part.Anchored    = true
		part.CanCollide  = false
		local pl = Instance.new("PointLight")
		pl.Brightness = 1.5
		pl.Range      = 120
		pl.Color      = Color3.fromRGB(255, 255, 255)
		pl.Parent     = part
		part.Parent = Workspace
		table.insert(lightParts, {Part = part, Offset = offset})
	end
end

local function disableLight()
	for _, data in ipairs(lightParts) do
		if data.Part then data.Part:Destroy() end
	end
	lightParts = {}
end

-- ==========================================
-- 2. NPC ESP
-- ==========================================
local targetNames = {
	ai_arsonist=true, ai_bombardier=true, ai_friendlytank=true,
	ai_rifleman=true, ai_sniper=true, ai_stormtrooper=true,
	ai_tank=true, ai_zombie=true, ai_officer=true
}

-- Pre-computed HP color table: index 0–100 → Color3
-- Avoids per-frame fromRGB math for 40 NPCs
local hpColors = {}
for i = 0, 100 do
	local t  = i / 100
	local r  = math.floor(255 * (1 - t))
	local g  = math.floor(255 * t)
	hpColors[i] = Color3.fromRGB(r, g, 40)
end

local function createESPEntry(model)
	local d = {}

	d.name            = Drawing.new("Text")
	d.name.Visible    = false
	d.name.Font       = 2
	d.name.Center     = true
	d.name.Outline    = true
	d.name.ZIndex     = 10
	d.name.Color      = Theme.NAME_COLOR  -- set once, never changes

	d.hpbarbg         = Drawing.new("Square")
	d.hpbarbg.Visible = false
	d.hpbarbg.Filled  = true
	d.hpbarbg.Thickness = 0
	d.hpbarbg.ZIndex  = 10
	d.hpbarbg.Color   = Theme.HP_BG       -- set once, never changes

	d.hpbar           = Drawing.new("Square")
	d.hpbar.Visible   = false
	d.hpbar.Filled    = true
	d.hpbar.Thickness = 0
	d.hpbar.ZIndex    = 11

	d.trace           = Drawing.new("Line")
	d.trace.Visible   = false
	d.trace.ZIndex    = 9
	d.trace.Thickness = 1
	d.trace.Color     = Theme.TRACE_COLOR  -- set once, never changes

	d.hl              = Instance.new("Highlight")
	d.hl.FillColor    = Theme.ACCENT
	d.hl.OutlineColor = Theme.ACCENT
	d.hl.FillTransparency    = 0.55
	d.hl.OutlineTransparency = 0
	d.hl.DepthMode   = Enum.HighlightDepthMode.AlwaysOnTop
	d.hl.Adornee     = model
	d.hl.Enabled     = false
	d.hl.Parent      = model

	-- cache the parts we need every tick — avoids FindFirstChild every frame
	d.hrp      = model:FindFirstChild("HumanoidRootPart")
	d.head     = model:FindFirstChild("Head")
	d.humanoid = model:FindFirstChildOfClass("Humanoid")

	espData[model] = d
end

local function hideESPEntry(d)
	d.name.Visible    = false
	d.hpbar.Visible   = false
	d.hpbarbg.Visible = false
	d.trace.Visible   = false
	d.hl.Enabled      = false
end

-- Viewport size cached — read once per frame outside the loop
local vpX, vpY = 0, 0

local function updateESPEntry(d)
	local hrp      = d.hrp
	local humanoid = d.humanoid

	-- dead or missing
	if not hrp or not hrp.Parent or not humanoid or humanoid.Health <= 0 then
		hideESPEntry(d)
		return
	end

	local camPos = camera.CFrame.Position
	local hrpPos = hrp.Position

	-- distance cull — cheapest check first
	local dx = hrpPos.X - camPos.X
	local dy = hrpPos.Y - camPos.Y
	local dz = hrpPos.Z - camPos.Z
	local distSq = dx*dx + dy*dy + dz*dz
	local maxSq  = ESPSettings.MaxDistance * ESPSettings.MaxDistance
	if distSq > maxSq then
		hideESPEntry(d)
		return
	end
	local dist = math.sqrt(distSq)

	-- world-to-viewport (two calls, unavoidable)
	local headPos = d.head and d.head.Position or (hrpPos + Vector3.new(0, 2.5, 0))
	local hVec3   = camera:WorldToViewportPoint(headPos)
	local fVec3   = camera:WorldToViewportPoint(hrpPos - Vector3.new(0, 2.8, 0))

	if hVec3.Z <= 0 and fVec3.Z <= 0 then
		hideESPEntry(d)
		return
	end

	local hx = hVec3.X
	local hy = hVec3.Y
	local fx = fVec3.X
	local fy = fVec3.Y

	-- screen cull
	local refX = hVec3.Z > 0 and hx or fx
	local refY = hVec3.Z > 0 and hy or fy
	if refX < -200 or refX > vpX + 200 or refY < -200 or refY > vpY + 200 then
		hideESPEntry(d)
		return
	end

	-- box geometry
	local bh   = math.clamp(math.abs(hy - fy), 12, 400)
	local topY = math.min(hy, fy)
	local botY = topY + bh
	local midX = hx

	-- ── HIGHLIGHT ──────────────────────────────────────────
	d.hl.Enabled = ESPSettings.ShowHighlight

	-- ── NAME ───────────────────────────────────────────────
	if ESPSettings.ShowName then
		d.name.Visible   = true
		d.name.Text      = string.format("%s [%d]", d.hrp.Parent.Name, math.floor(dist))
		d.name.Size      = math.clamp(13 - dist * 0.00833, 8, 14)  -- /120 precomputed
		d.name.Position  = Vector2.new(midX, topY - 16)
	else
		d.name.Visible = false
	end

	-- ── HEALTH BAR ─────────────────────────────────────────
	if ESPSettings.ShowHealth then
		local pct  = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		local bwd  = math.max(3, math.min(6, bh * 0.06))
		local bx   = midX - bh * 0.275 - bwd - 4

		d.hpbarbg.Visible  = true
		d.hpbarbg.Position = Vector2.new(bx, topY)
		d.hpbarbg.Size     = Vector2.new(bwd, bh)

		local fillH = bh * pct
		d.hpbar.Visible   = true
		d.hpbar.Position  = Vector2.new(bx, botY - fillH)
		d.hpbar.Size      = Vector2.new(bwd, fillH)
		d.hpbar.Color     = hpColors[math.floor(pct * 100)]  -- LUT, zero alloc
	else
		d.hpbar.Visible   = false
		d.hpbarbg.Visible = false
	end

	-- ── TRACE ──────────────────────────────────────────────
	if ESPSettings.ShowTrace then
		d.trace.Visible = true
		d.trace.From    = Vector2.new(vpX * 0.5, vpY)
		d.trace.To      = Vector2.new(midX, botY)
	else
		d.trace.Visible = false
	end
end

-- Bootstrap
local function initESP(model)
	if not targetNames[model.Name] then return end
	if not model:IsA("Model") then return end
	if not espData[model] then createESPEntry(model) end
end

for _, child in ipairs(Workspace:GetChildren()) do
	initESP(child)
end

table.insert(activeConnections, Workspace.ChildAdded:Connect(function(child)
	task.wait(0.05)
	initESP(child)
end))

table.insert(activeConnections, Workspace.ChildRemoved:Connect(function(child)
	removeESPEntry(child)
end))

-- ==========================================
-- INPUT
-- ==========================================
local speedToggled    = false
local speedMultiplier = 1.4

table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Quote then
		lightToggled = not lightToggled
		if lightToggled then enableLight() else disableLight() end
		print("Light Grid: " .. (lightToggled and "ON" or "OFF"))
	elseif input.KeyCode == Enum.KeyCode.Comma then
		speedToggled = not speedToggled
		print("CFrame Speed Boost: " .. tostring(speedToggled))
	end
end))

-- ==========================================
-- RENDERSTEPPED — lights + speed + ESP
-- Throttle ESP to 20hz, everything else runs every frame
-- ==========================================
local espAccum    = 0
local ESP_INTERVAL = 0.05  -- 20hz

-- Pre-build iteration list to avoid next() overhead on espData every frame
local espList = {}

local function rebuildEspList()
	table.clear(espList)
	for model, d in pairs(espData) do
		espList[#espList + 1] = d
	end
end

-- Rebuild the flat list whenever a model is added/removed
-- (ChildAdded/ChildRemoved already fires initESP/removeESPEntry;
--  we just hook into those moments)
local _origCreate = createESPEntry
createESPEntry = function(model)
	_origCreate(model)
	espList[#espList + 1] = espData[model]
end

local _origRemove = removeESPEntry
removeESPEntry = function(model)
	_origRemove(model)
	rebuildEspList()  -- cheap, only on remove events not every frame
end

table.insert(activeConnections, RunService.RenderStepped:Connect(function(dt)

	-- ── LIGHTS ─────────────────────────────────────────────
	if lightToggled and #lightParts > 0 and character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local pos = hrp.Position
			for i = 1, #lightParts do
				local ld = lightParts[i]
				if ld.Part then
					ld.Part.CFrame = CFrame.new(pos + ld.Offset)
				end
			end
		end
	end

	-- ── SPEED ──────────────────────────────────────────────
	if speedToggled and character then
		local humanoid = character:FindFirstChild("Humanoid")
		local hrp      = character:FindFirstChild("HumanoidRootPart")
		if humanoid and hrp then
			humanoid.WalkSpeed = defaultSpeed
			local moveDir = humanoid.MoveDirection
			if moveDir.Magnitude > 0 then
				hrp.CFrame = hrp.CFrame + moveDir * ((defaultSpeed * (speedMultiplier - 1)) * dt)
			end
		end
	end

	-- ── ESP (throttled) ────────────────────────────────────
	espAccum = espAccum + dt
	if espAccum < ESP_INTERVAL then return end
	espAccum = 0

	if not ESPSettings.Enabled then
		for i = 1, #espList do hideESPEntry(espList[i]) end
		return
	end

	-- cache viewport once per ESP tick, not per NPC
	local vp = camera.ViewportSize
	vpX = vp.X
	vpY = vp.Y

	for i = 1, #espList do
		updateESPEntry(espList[i])
	end
end))

print("Loaded have fun bro :)")
