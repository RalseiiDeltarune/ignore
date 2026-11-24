local env = getgenv and getgenv() or _G
if env.CleanupOldScript then
	pcall(env.CleanupOldScript)
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"))()

local lp = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local char, hrp, hum

local baseSpeed = 10
local speedMult = 1.4
local speedOn = false
local lightOn = false
local aimbotOn = false
local aiming = false
local wallCheck = false
local espOn = true
local aimSmoothness = 0.5
local aimFOV = 450

local conns = {}
local espData = {}
local lights = {}
local fogCleared = false
local lastLightPos = Vector3.new(0, -9e9, 0)

local moveMouseRel = mousemoverel or (Input and Input.MouseMove)
local moveMouseAbs = mousemoveabs

local targets = {
	ai_arsonist = true,
	ai_bombardier = true,
	ai_friendlytank = true,
	ai_officer = true,
	ai_rifleman = true,
	ai_sniper = true,
	ai_stormtrooper = true,
	ai_tank = true,
	ai_zombie = true
}

local enemyTargets = {
	ai_arsonist = true,
	ai_bombardier = true,
	ai_officer = true,
	ai_rifleman = true,
	ai_sniper = true,
	ai_stormtrooper = true,
	ai_tank = true,
	ai_zombie = true
}

local function cacheCharacter(newChar)
	char = newChar
	if char then
		hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 10)
		hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	else
		hrp, hum = nil, nil
	end
end

cacheCharacter(lp.Character or lp.CharacterAdded:Wait())
table.insert(conns, lp.CharacterAdded:Connect(cacheCharacter))

table.insert(conns, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		camera = Workspace.CurrentCamera
	end
end))

local function removeESP(obj)
	local data = espData[obj]
	if not data then return end
	if data.conn then data.conn:Disconnect() end
	if data.destroyingConn then data.destroyingConn:Disconnect() end
	if data.hl then data.hl:Destroy() end
	if data.bb then data.bb:Destroy() end
	espData[obj] = nil
end

local function clearAllESP()
	for obj in pairs(espData) do
		removeESP(obj)
	end
	table.clear(espData)
end

local function toggleLights(state)
	if state then
		if not fogCleared then
			fogCleared = true
			Lighting.FogEnd = 9e9
			Lighting.FogStart = 0
			local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
			if atmo then atmo:Destroy() end

			table.insert(conns, Lighting.ChildAdded:Connect(function(c)
				if c:IsA("Atmosphere") and lightOn then
					c:Destroy()
				end
			end))
		end

		if #lights == 0 then
			local folder = Instance.new("Folder")
			folder.Name = "Fullbright_Grid"
			folder.Parent = Workspace

			local offsets = { Vector3.new(0, 6, 0) }
			for d = 110, 800, 110 do
				table.insert(offsets, Vector3.new(d, 6, 0))
				table.insert(offsets, Vector3.new(-d, 6, 0))
				table.insert(offsets, Vector3.new(0, 6, d))
				table.insert(offsets, Vector3.new(0, 6, -d))
				table.insert(offsets, Vector3.new(d, 6, d))
				table.insert(offsets, Vector3.new(-d, 6, d))
				table.insert(offsets, Vector3.new(d, 6, -d))
				table.insert(offsets, Vector3.new(-d, 6, -d))
			end

			for _, off in ipairs(offsets) do
				local p = Instance.new("Part")
				p.Size = Vector3.new(1, 1, 1)
				p.Transparency = 1
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false

				local pl = Instance.new("PointLight")
				pl.Brightness = 1.5
				pl.Range = 120
				pl.Parent = p

				p.Parent = folder
				table.insert(lights, { part = p, offset = off, folder = folder })
			end
		end

		lastLightPos = Vector3.new(0, -9e9, 0)
		if hrp then
			lastLightPos = hrp.Position
			for _, v in ipairs(lights) do
				v.part.CFrame = CFrame.new(hrp.Position + v.offset)
			end
		end
	else
		if #lights > 0 and lights[1].folder then
			lights[1].folder:Destroy()
		end
		table.clear(lights)
		lastLightPos = Vector3.new(0, -9e9, 0)
	end
end

local function formatName(rawName)
	local clean = rawName:gsub("^ai_", "")
	return clean:sub(1, 1):upper() .. clean:sub(2)
end

local function addESP(obj)
	if not espOn then return end
	if not obj:IsA("Model") or not targets[obj.Name] or espData[obj] then return end

	local root = obj:FindFirstChild("Head") or obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
	local targetHum = obj:FindFirstChildOfClass("Humanoid")
	if not root or not targetHum or targetHum.Health <= 0 then return end

	local isFriendly = (obj.Name == "ai_friendlytank")
	local mainColor = isFriendly and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(255, 50, 50)

	local hl = Instance.new("Highlight")
	hl.Name = "AI_Highlight"
	hl.Adornee = obj
	hl.FillColor = mainColor
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.65
	hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = obj

	local bb = Instance.new("BillboardGui")
	bb.Name = "AI_Billboard"
	bb.Size = UDim2.fromOffset(130, 42)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 1500
	bb.Adornee = root
	bb.Parent = obj

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.fromOffset(6, 36)
	barBg.Position = UDim2.new(0, 4, 0.5, -18)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	barBg.BorderSizePixel = 0
	barBg.Parent = bb

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = Color3.new(0, 0, 0)
	bgStroke.Thickness = 1
	bgStroke.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.AnchorPoint = Vector2.new(0, 1)
	barFill.Position = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, 0)
	lbl.Position = UDim2.fromOffset(14, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = formatName(obj.Name)
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextSize = 14
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = bb

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.new(0, 0, 0)
	textStroke.Thickness = 1.2
	textStroke.Parent = lbl

	local function updateHealth()
		local pct = math.clamp(targetHum.Health / math.max(targetHum.MaxHealth, 1), 0, 1)
		barFill.Size = UDim2.fromScale(1, pct)
		barFill.BackgroundColor3 = Color3.fromHSV(pct * 0.33, 0.9, 1)
		if pct <= 0 then
			removeESP(obj)
		end
	end

	updateHealth()

	local healthConn = targetHum.HealthChanged:Connect(updateHealth)
	local destroyingConn = obj.Destroying:Connect(function()
		removeESP(obj)
	end)

	espData[obj] = {
		hl = hl,
		bb = bb,
		conn = healthConn,
		destroyingConn = destroyingConn
	}
end

local function refreshESP()
	clearAllESP()
	if not espOn then return end
	for _, v in ipairs(Workspace:GetDescendants()) do
		if targets[v.Name] then
			addESP(v)
		end
	end
end

local function isVisible(part)
	if not wallCheck then return true end
	if not camera or not part then return false end
	local origin = camera.CFrame.Position
	local direction = part.Position - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if char then table.insert(ignore, char) end
	if part.Parent then table.insert(ignore, part.Parent) end
	if #lights > 0 and lights[1].folder then table.insert(ignore, lights[1].folder) end
	params.FilterDescendantsInstances = ignore

	local result = Workspace:Raycast(origin, direction, params)
	return result == nil
end

local function getAimPoint(obj)
	return obj:FindFirstChild("Head") or obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
end

local function getAnchorPos()
	if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter and camera then
		local vp = camera.ViewportSize
		return Vector2.new(vp.X * 0.5, vp.Y * 0.5)
	end
	return UIS:GetMouseLocation()
end

local function getClosestTargetPart()
	if not camera then return nil end
	local anchor = getAnchorPos()
	local bestPart = nil
	local bestDist = aimFOV

	for _, v in ipairs(Workspace:GetDescendants()) do
		if v:IsA("Model") and enemyTargets[v.Name] then
			local targetHum = v:FindFirstChildOfClass("Humanoid")
			local aimPart = getAimPoint(v)
			if targetHum and targetHum.Health > 0 and aimPart and isVisible(aimPart) then
				local screenPos, onScreen = camera:WorldToViewportPoint(aimPart.Position)
				if onScreen and screenPos.Z > 0 then
					local dist = (Vector2.new(screenPos.X, screenPos.Y) - anchor).Magnitude
					if dist < bestDist then
						bestDist = dist
						bestPart = aimPart
					end
				end
			end
		end
	end

	return bestPart
end

env.CleanupOldScript = function()
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	clearAllESP()
	toggleLights(false)
	pcall(function()
		Library:Unload()
	end)
end

local Window = Library:CreateWindow({
	Title = "Combat & Visuals",
	Center = true,
	AutoShow = true,
	TabPadding = 8,
	MenuFadeTime = 0.2
})

local Tabs = {
	Main = Window:AddTab("Main"),
	Visuals = Window:AddTab("Visuals"),
	UISettings = Window:AddTab("UI Settings")
}

local AimGroup = Tabs.Main:AddLeftGroupbox("Aimbot")
AimGroup:AddToggle("AimbotToggle", {
	Text = "Aimbot (Hold RMB)",
	Default = false
}):AddKeyPicker("AimbotKeybind", {
	Default = "Z",
	SyncToggleState = true,
	Mode = "Toggle",
	Text = "Aimbot Toggle",
	NoUI = false,
	Callback = function(Value)
		aimbotOn = Value
	end
})

Toggles.AimbotToggle:OnChanged(function(val)
	aimbotOn = val
end)

AimGroup:AddToggle("WallCheckToggle", {
	Text = "Wall Check",
	Default = false,
	Callback = function(val)
		wallCheck = val
	end
})

AimGroup:AddSlider("AimSmoothSlider", {
	Text = "Smoothness",
	Default = 0.5,
	Min = 0.05,
	Max = 1,
	Rounding = 2,
	Compact = false,
	Callback = function(val)
		aimSmoothness = val
	end
})

AimGroup:AddSlider("AimFOVSlider", {
	Text = "FOV Radius",
	Default = 450,
	Min = 50,
	Max = 1000,
	Rounding = 0,
	Compact = false,
	Callback = function(val)
		aimFOV = val
	end
})

local MoveGroup = Tabs.Main:AddRightGroupbox("Movement")
MoveGroup:AddToggle("SpeedToggle", {
	Text = "Speed Boost",
	Default = false
}):AddKeyPicker("SpeedKeybind", {
	Default = "Comma",
	SyncToggleState = true,
	Mode = "Toggle",
	Text = "Speed Toggle",
	NoUI = false,
	Callback = function(val)
		speedOn = val
	end
})

Toggles.SpeedToggle:OnChanged(function(val)
	speedOn = val
end)

MoveGroup:AddSlider("SpeedMultSlider", {
	Text = "Speed Multiplier",
	Default = 1.4,
	Min = 1,
	Max = 3,
	Rounding = 1,
	Compact = false,
	Callback = function(val)
		speedMult = val
	end
})

local EspGroup = Tabs.Visuals:AddLeftGroupbox("ESP")
EspGroup:AddToggle("ESPToggle", {
	Text = "AI ESP & Health Bar",
	Default = true,
	Callback = function(val)
		espOn = val
		refreshESP()
	end
})

local LightGroup = Tabs.Visuals:AddRightGroupbox("Lighting")
LightGroup:AddToggle("LightsToggle", {
	Text = "Fullbright & No Fog",
	Default = false
}):AddKeyPicker("LightsKeybind", {
	Default = "Quote",
	SyncToggleState = true,
	Mode = "Toggle",
	Text = "Lights Toggle",
	NoUI = false,
	Callback = function(val)
		lightOn = val
		toggleLights(lightOn)
	end
})

Toggles.LightsToggle:OnChanged(function(val)
	lightOn = val
	toggleLights(lightOn)
end)

local MenuGroup = Tabs.UISettings:AddLeftGroupbox("Menu")
MenuGroup:AddButton("Unload Script", function()
	env.CleanupOldScript()
end)
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
	Default = "RightShift",
	NoUI = true,
	Text = "Menu keybind"
})

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("CombatVisualsLib")
SaveManager:SetFolder("CombatVisualsLib/main")
SaveManager:ApplyToTab(Tabs.UISettings)

refreshESP()

table.insert(conns, Workspace.DescendantAdded:Connect(function(v)
	if espOn and targets[v.Name] then
		task.wait(0.1)
		addESP(v)
	end
end))

table.insert(conns, UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		aiming = true
	end
end))

table.insert(conns, UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		aiming = false
	end
end))

table.insert(conns, RunService.RenderStepped:Connect(function(dt)
	if speedOn and hrp and hum and hum.MoveDirection.Magnitude > 0 then
		hum.WalkSpeed = baseSpeed
		local boost = (baseSpeed * (speedMult - 1)) * dt
		hrp.CFrame += hum.MoveDirection * boost
	end

	if aimbotOn and aiming and camera then
		local targetPart = getClosestTargetPart()
		if targetPart then
			local screenPos, onScreen = camera:WorldToViewportPoint(targetPart.Position)
			if onScreen and screenPos.Z > 0 then
				local anchor = getAnchorPos()
				local deltaX = (screenPos.X - anchor.X) * aimSmoothness
				local deltaY = (screenPos.Y - anchor.Y) * aimSmoothness
				if math.abs(deltaX) > 0.1 or math.abs(deltaY) > 0.1 then
					if moveMouseRel then
						pcall(moveMouseRel, deltaX, deltaY)
					elseif moveMouseAbs then
						pcall(moveMouseAbs, anchor.X + deltaX, anchor.Y + deltaY)
					end
				end
			end
		end
	end
end))

table.insert(conns, RunService.Heartbeat:Connect(function()
	if lightOn and #lights > 0 and hrp then
		local pos = hrp.Position
		if (pos - lastLightPos).Magnitude > 15 then
			lastLightPos = pos
			for _, v in ipairs(lights) do
				v.part.CFrame = CFrame.new(pos + v.offset)
			end
		end
	end
end))

Library:Notify("Loaded LinoriaLib UI", 3)
