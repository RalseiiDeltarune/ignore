-- ==========================================
-- AUTO-CLEANUP (Removes old script instance)
-- ==========================================
local _env = (type(getgenv) == "function" and getgenv()) or _G
if _env and type(_env.ActiveScriptCleanup) == "function" then
	pcall(_env.ActiveScriptCleanup)
end

local activeConnections = {}
local lightParts = {}
local espData = {}  -- per-model ESP Drawing data

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ==========================================
-- THEME (matches SpentHub palette)
-- ==========================================
local Theme = {
	ACCENT         = Color3.fromRGB(255, 182, 193),
	HP_HIGH        = Color3.fromRGB(80, 255, 100),
	HP_LOW         = Color3.fromRGB(255, 60, 60),
	NAME_COLOR     = Color3.fromRGB(255, 255, 255),
	TRACE_COLOR    = Color3.fromRGB(255, 255, 255),
	TARGET_LOCK    = Color3.fromRGB(255, 200, 220),
	RING_IDLE      = Color3.fromRGB(255, 255, 255),
	HP_BG          = Color3.fromRGB(20, 20, 20),
}

-- ==========================================
-- ESP SETTINGS
-- ==========================================
local ESPSettings = {
	Enabled      = true,
	ShowName     = true,
	ShowHealth   = true,
	ShowTrace    = false,
	ShowHighlight = true,
	MaxDistance  = 1500,
	FOVVisible   = true,
	FOVRadius    = 350,
}

-- ==========================================
-- FOV CIRCLE
-- ==========================================
local fov_circle = Drawing.new("Circle")
fov_circle.Thickness  = 1.5
fov_circle.NumSides   = 100
fov_circle.Radius     = ESPSettings.FOVRadius
fov_circle.Filled     = false
fov_circle.Visible    = false
fov_circle.ZIndex     = 999
fov_circle.Transparency = 0.9
fov_circle.Color      = Theme.RING_IDLE

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

	-- destroy all ESP entries
	for model, _ in pairs(espData) do
		removeESPEntry(model)
	end

	-- remove any leftover legacy ESP objects
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj.Name == "CustomESP_Highlight" or obj.Name == "CustomESP_Billboard" then
			obj:Destroy()
		end
	end

	pcall(function() fov_circle:Remove() end)

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
local fileName    = "Xeno_GameDefaultSpeed.txt"
local defaultSpeed = 16

local function fetchAndSaveDefault()
	local char = player.Character or player.CharacterAdded:Wait()
	local humanoid = char:WaitForChild("Humanoid", 5)
	if humanoid then
		local currentDefault = humanoid.WalkSpeed
		if not pcall(function() return isfile and isfile(fileName) end) or not isfile(fileName) then
			pcall(function() writefile(fileName, tostring(currentDefault)) end)
			defaultSpeed = currentDefault
			print("[SpeedLogger] Logged new default speed to file: " .. tostring(currentDefault))
		else
			local success, content = pcall(readfile, fileName)
			if success and content then
				local val = tonumber(content)
				defaultSpeed = val and val or currentDefault
				print("[SpeedLogger] Loaded default speed from file: " .. tostring(defaultSpeed))
			else
				defaultSpeed = currentDefault
			end
		end
	end
end

task.spawn(fetchAndSaveDefault)

-- ==========================================
-- MAIN SCRIPT SETUP
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
	table.insert(lightOffsets, Vector3.new( dist,  6,    0))
	table.insert(lightOffsets, Vector3.new(-dist,  6,    0))
	table.insert(lightOffsets, Vector3.new(   0,  6,  dist))
	table.insert(lightOffsets, Vector3.new(   0,  6, -dist))
	table.insert(lightOffsets, Vector3.new( dist,  6,  dist))
	table.insert(lightOffsets, Vector3.new(-dist,  6,  dist))
	table.insert(lightOffsets, Vector3.new( dist,  6, -dist))
	table.insert(lightOffsets, Vector3.new(-dist,  6, -dist))
end

local function clearFogAndAtmosphere()
	Lighting.FogEnd   = 9e9
	Lighting.FogStart = 0
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then atmosphere:Destroy() end
	table.insert(activeConnections, Lighting.ChildAdded:Connect(function(child)
		if child:IsA("Atmosphere") then child:Destroy() end
	end))
end

local function enableLight()
	if #lightParts == 0 then
		clearFogAndAtmosphere()
		for _, offset in ipairs(lightOffsets) do
			local lightPart = Instance.new("Part")
			lightPart.Size        = Vector3.new(1, 1, 1)
			lightPart.Transparency = 1
			lightPart.Anchored    = true
			lightPart.CanCollide  = false
			local pointLight = Instance.new("PointLight")
			pointLight.Brightness = 1.5
			pointLight.Range      = 120
			pointLight.Color      = Color3.fromRGB(255, 255, 255)
			pointLight.Parent     = lightPart
			lightPart.Parent = Workspace
			table.insert(lightParts, {Part = lightPart, Offset = offset})
		end
	end
end

local function disableLight()
	for _, data in ipairs(lightParts) do
		if data.Part then data.Part:Destroy() end
	end
	lightParts = {}
end

-- ==========================================
-- 2. NPC ESP — SpentHub style
-- ==========================================
local targetNames = {
	"ai_arsonist", "ai_bombardier", "ai_friendlytank",
	"ai_rifleman", "ai_sniper", "ai_stormtrooper", "ai_tank", "ai_zombie", "ai_officer"
}

local function isTargetModel(model)
	if not model:IsA("Model") then return false end
	for _, name in ipairs(targetNames) do
		if model.Name == name then return true end
	end
	return false
end

-- Creates the Drawing + Highlight bundle for one NPC model
local function createESPEntry(model)
	local d = {}

	-- name label
	d.name            = Drawing.new("Text")
	d.name.Visible    = false
	d.name.Font       = 2          -- monospace, matches SpentHub
	d.name.Center     = true
	d.name.Outline    = true
	d.name.ZIndex     = 10

	-- HP bar background
	d.hpbarbg         = Drawing.new("Square")
	d.hpbarbg.Visible = false
	d.hpbarbg.Filled  = true
	d.hpbarbg.Thickness = 0
	d.hpbarbg.ZIndex  = 10

	-- HP bar fill
	d.hpbar           = Drawing.new("Square")
	d.hpbar.Visible   = false
	d.hpbar.Filled    = true
	d.hpbar.Thickness = 0
	d.hpbar.ZIndex    = 11

	-- trace line
	d.trace           = Drawing.new("Line")
	d.trace.Visible   = false
	d.trace.ZIndex    = 9
	d.trace.Thickness = 1

	-- highlight (AlwaysOnTop — sees through walls, identical to SpentHub fix)
	d.hl              = Instance.new("Highlight")
	d.hl.FillColor    = Theme.ACCENT
	d.hl.OutlineColor = Theme.ACCENT
	d.hl.FillTransparency    = 0.55
	d.hl.OutlineTransparency = 0
	d.hl.DepthMode   = Enum.HighlightDepthMode.AlwaysOnTop
	d.hl.Adornee     = model
	d.hl.Enabled      = false
	d.hl.Parent       = model

	espData[model] = d
	return d
end

local function hideESPEntry(d)
	if not d then return end
	d.name.Visible    = false
	d.hpbar.Visible   = false
	d.hpbarbg.Visible = false
	d.trace.Visible   = false
	if d.hl then d.hl.Enabled = false end
end

-- Called every ESP tick for one NPC model
local function updateESPEntry(model, d)
	local humanoid  = model:FindFirstChildOfClass("Humanoid")
	local hrp       = model:FindFirstChild("HumanoidRootPart")
	local head      = model:FindFirstChild("Head")

	if not humanoid or not hrp or humanoid.Health <= 0 then
		hideESPEntry(d)
		return
	end

	local camPos   = camera.CFrame.Position
	local dist     = (hrp.Position - camPos).Magnitude

	if dist > ESPSettings.MaxDistance then
		hideESPEntry(d)
		return
	end

	-- world-to-viewport for head and feet
	local headPos  = head and head.Position or (hrp.Position + Vector3.new(0, 2.5, 0))
	local feetPos  = hrp.Position - Vector3.new(0, 2.8, 0)
	local hVec3    = camera:WorldToViewportPoint(headPos)
	local fVec3    = camera:WorldToViewportPoint(feetPos)

	if hVec3.Z <= 0 and fVec3.Z <= 0 then
		hideESPEntry(d)
		return
	end

	local vp   = camera.ViewportSize
	local hs   = Vector2.new(hVec3.X, hVec3.Y)
	local fs   = Vector2.new(fVec3.X, fVec3.Y)
	local refX = hVec3.Z > 0 and hs.X or fs.X
	local refY = hVec3.Z > 0 and hs.Y or fs.Y

	-- cull if totally off screen
	if refX < -200 or refX > vp.X + 200 or refY < -200 or refY > vp.Y + 200 then
		hideESPEntry(d)
		return
	end

	local bh   = math.clamp(math.abs(hs.Y - fs.Y), 12, 400)
	local topY = math.min(hs.Y, fs.Y)
	local botY = topY + bh
	local midX = hs.X

	-- ── HIGHLIGHT ──────────────────────────────────────────
	if ESPSettings.ShowHighlight then
		d.hl.Enabled = true
	else
		d.hl.Enabled = false
	end

	-- ── NAME ───────────────────────────────────────────────
	if ESPSettings.ShowName then
		d.name.Visible   = true
		d.name.Text      = string.format("%s [%d]", model.Name, math.floor(dist))
		d.name.Color     = Theme.NAME_COLOR
		d.name.Size      = math.clamp(13 - dist / 120, 8, 14)
		d.name.Position  = Vector2.new(midX, topY - 16)
	else
		d.name.Visible = false
	end

	-- ── HEALTH BAR ─────────────────────────────────────────
	if ESPSettings.ShowHealth then
		local pct  = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		local bwd  = math.max(3, math.min(6, bh * 0.06))
		-- sit bar to the left of the bounding box
		local bx   = midX - (bh * 0.275) - bwd - 4

		d.hpbarbg.Visible   = true
		d.hpbarbg.Position  = Vector2.new(bx, topY)
		d.hpbarbg.Size      = Vector2.new(bwd, bh)
		d.hpbarbg.Color     = Theme.HP_BG

		local fillH         = bh * pct
		local r2            = math.floor(255 * (1 - pct))
		local g2            = math.floor(255 * pct)
		d.hpbar.Visible     = true
		d.hpbar.Position    = Vector2.new(bx, botY - fillH)
		d.hpbar.Size        = Vector2.new(bwd, fillH)
		d.hpbar.Color       = Color3.fromRGB(r2, g2, 40)
	else
		d.hpbar.Visible   = false
		d.hpbarbg.Visible = false
	end

	-- ── TRACE ──────────────────────────────────────────────
	if ESPSettings.ShowTrace then
		d.trace.Visible = true
		d.trace.From    = Vector2.new(vp.X / 2, vp.Y)
		d.trace.To      = Vector2.new(midX, botY)
		d.trace.Color   = Theme.TRACE_COLOR
	else
		d.trace.Visible = false
	end
end

-- Bootstrap ESP on models already in Workspace
local function initESP(model)
	if not isTargetModel(model) then return end
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
-- INPUT & EVENT LISTENERS
-- ==========================================
local speedToggled   = false
local speedMultiplier = 1.4

table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Quote then
		lightToggled = not lightToggled
		if lightToggled then
			print("Personal Light 8-Way Grid + Fog Remover: ON")
			enableLight()
		else
			print("Personal Light Grid: OFF")
			disableLight()
		end
	elseif input.KeyCode == Enum.KeyCode.Comma then
		speedToggled = not speedToggled
		print(string.format("CFrame Speed Boost Toggled: %s", tostring(speedToggled)))
	end
end))

-- ==========================================
-- RENDERSTEPPED — lights + speed + ESP
-- ==========================================
local espLastTick = 0
local ESP_INTERVAL = 0.05  -- 20hz, same as SpentHub

table.insert(activeConnections, RunService.RenderStepped:Connect(function(dt)

	-- light grid follow player
	if lightToggled and #lightParts > 0 and character and character:FindFirstChild("HumanoidRootPart") then
		local hrp = character.HumanoidRootPart
		for _, data in ipairs(lightParts) do
			if data.Part then
				data.Part.CFrame = CFrame.new(hrp.Position + data.Offset)
			end
		end
	end

	-- CFrame speed bypass
	if speedToggled and character then
		local humanoid = character:FindFirstChild("Humanoid")
		local hrp      = character:FindFirstChild("HumanoidRootPart")
		if humanoid and hrp then
			humanoid.WalkSpeed = defaultSpeed
			local moveDir = humanoid.MoveDirection
			if moveDir.Magnitude > 0 then
				local extraSpeed = (defaultSpeed * (speedMultiplier - 1)) * dt
				hrp.CFrame = hrp.CFrame + (moveDir * extraSpeed)
			end
		end
	end

	-- FOV circle (screen center)
	if ESPSettings.FOVVisible then
		fov_circle.Visible  = true
		fov_circle.Radius   = ESPSettings.FOVRadius
		fov_circle.Position = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
		fov_circle.Color    = Theme.RING_IDLE
	else
		fov_circle.Visible = false
	end

	-- ESP tick (throttled)
	local now = tick()
	if now - espLastTick >= ESP_INTERVAL then
		espLastTick = now
		if ESPSettings.Enabled then
			for model, d in pairs(espData) do
				if model.Parent then
					pcall(updateESPEntry, model, d)
				else
					removeESPEntry(model)
				end
			end
		else
			for _, d in pairs(espData) do
				hideESPEntry(d)
			end
		end
	end
end))

print("Loaded have fun bro :)")
