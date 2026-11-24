local env = getgenv and getgenv() or _G
if env.CleanupOldScript then
	pcall(env.CleanupOldScript)
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local lp = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local char, hrp, hum

local baseSpeed = 10
local speedMult = 1.4
local speedOn = false
local lightOn = false
local aimbotOn = false
local aiming = false
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
}))

local function removeESP(obj)
	local data = espData[obj]
	if not data then return end
	if data.conn then data.conn:Disconnect() end
	if data.destroyingConn then data.destroyingConn:Disconnect() end
	if data.hl then data.hl:Destroy() end
	if data.bb then data.bb:Destroy() end
	espData[obj] = nil
end

local function formatName(rawName)
	local clean = rawName:gsub("^ai_", "")
	return clean:sub(1, 1):upper() .. clean:sub(2)
end

local function addESP(obj)
	if not obj or not obj:IsA("Model") or espData[obj] then return end
	local lowerName = string.lower(obj.Name)
	if not targets[obj.Name] and not targets[lowerName] then return end

	local root = obj:FindFirstChild("Head") or obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
	local targetHum = obj:FindFirstChildOfClass("Humanoid")
	if not root or not targetHum or targetHum.Health <= 0 then return end

	local isFriendly = (obj.Name == "ai_friendlytank" or lowerName == "ai_friendlytank")
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

	for obj in pairs(espData) do
		if obj and obj.Parent and (enemyTargets[obj.Name] or enemyTargets[string.lower(obj.Name)]) then
			local targetHum = obj:FindFirstChildOfClass("Humanoid")
			local aimPart = getAimPoint(obj)
			if targetHum and targetHum.Health > 0 and aimPart then
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

	for obj in pairs(espData) do
		removeESP(obj)
	end
	table.clear(espData)
	toggleLights(false)
end

for _, v in ipairs(Workspace:GetDescendants()) do
	if v:IsA("Model") then
		addESP(v)
	end
end

table.insert(conns, Workspace.DescendantAdded:Connect(function(v)
	if v:IsA("Model") then
		task.wait(0.1)
		addESP(v)
	end
end))

table.insert(conns, UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end

	if input.KeyCode == Enum.KeyCode.Quote then
		lightOn = not lightOn
		toggleLights(lightOn)
		print("Lights:", lightOn)
	elseif input.KeyCode == Enum.KeyCode.Comma then
		speedOn = not speedOn
		print("Speed:", speedOn)
	elseif input.KeyCode == Enum.KeyCode.Z then
		aimbotOn = not aimbotOn
		print("Aimbot:", aimbotOn, "mousemoverel:", moveMouseRel ~= nil)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		aiming = true
	end
end))

table.insert(conns, UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		aiming = false
	end
end))

table.insert(conns, RunService.RenderStepped:Connect(function(dt)
	if not hrp and char then
		hrp = char:FindFirstChild("HumanoidRootPart")
	end
	if not hum and char then
		hum = char:FindFirstChildOfClass("Humanoid")
	end

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

print("Loaded standalone script :)")
