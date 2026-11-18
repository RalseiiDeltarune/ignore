-- ==========================================
-- AUTO-CLEANUP (Removes old script instance)
-- ==========================================
local _env = (type(getgenv) == "function" and getgenv()) or _G
if _env and type(_env.ActiveScriptCleanup) == "function" then
	pcall(_env.ActiveScriptCleanup)
end

local activeConnections = {}
local lightParts = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local function cleanup()
	for _, conn in ipairs(activeConnections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	activeConnections = {}

	for _, data in ipairs(lightParts) do
		if data.Part then
			data.Part:Destroy()
		end
	end
	lightParts = {}

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

if _env then
	_env.ActiveScriptCleanup = cleanup
end

-- ==========================================
-- FILE-BASED DEFAULT WALKSPEED LOGGING
-- ==========================================
local fileName = "Xeno_GameDefaultSpeed.txt"
local defaultSpeed = 16 -- fallback

local function fetchAndSaveDefault()
	local char = player.Character or player.CharacterAdded:Wait()
	local humanoid = char:WaitForChild("Humanoid", 5)
	if humanoid then
		local currentDefault = humanoid.WalkSpeed
		if not pcall(function() return isfile and isfile(fileName) end) or not isfile(fileName) then
			pcall(function()
				writefile(fileName, tostring(currentDefault))
			end)
			defaultSpeed = currentDefault
			print("[SpeedLogger] Logged new default speed to file: " .. tostring(currentDefault))
		else
			local success, content = pcall(readfile, fileName)
			if success and content then
				local val = tonumber(content)
				if val then
					defaultSpeed = val
					print("[SpeedLogger] Loaded default speed from file: " .. tostring(defaultSpeed))
				else
					defaultSpeed = currentDefault
				end
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

-- 1. Light Grid & Fog Remover
local lightToggled = false
local lightOffsets = { Vector3.new(0, 6, 0) }
local maxDistance = 800
local spacing = 110

for dist = spacing, maxDistance, spacing do
	table.insert(lightOffsets, Vector3.new(dist, 6, 0))
	table.insert(lightOffsets, Vector3.new(-dist, 6, 0))
	table.insert(lightOffsets, Vector3.new(0, 6, dist))
	table.insert(lightOffsets, Vector3.new(0, 6, -dist))
	table.insert(lightOffsets, Vector3.new(dist, 6, dist))
	table.insert(lightOffsets, Vector3.new(-dist, 6, dist))
	table.insert(lightOffsets, Vector3.new(dist, 6, -dist))
	table.insert(lightOffsets, Vector3.new(-dist, 6, -dist))
end

local function clearFogAndAtmosphere()
	Lighting.FogEnd = 9e9
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
			lightPart.Size = Vector3.new(1, 1, 1)
			lightPart.Transparency = 1
			lightPart.Anchored = true
			lightPart.CanCollide = false
			
			local pointLight = Instance.new("PointLight")
			pointLight.Brightness = 1.5
			pointLight.Range = 120
			pointLight.Color = Color3.fromRGB(255, 255, 255)
			pointLight.Parent = lightPart
			
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

-- 2. NPC ESP
local targetNames = {
	"ai_arsonist", "ai_bombardier", "ai_friendlytank",
	"ai_rifleman", "ai_sniper", "ai_stormtrooper", "ai_tank", "ai_zombie"
}

local function setupESP(model)
	if not model:IsA("Model") then return end
	local isTarget = false
	for _, name in ipairs(targetNames) do
		if model.Name == name then
			isTarget = true
			break
		end
	end
	
	if isTarget and not model:FindFirstChild("CustomESP_Highlight") then
		local highlight = Instance.new("Highlight")
		highlight.Name = "CustomESP_Highlight"
		highlight.Adornee = model
		highlight.FillColor = Color3.fromRGB(255, 0, 0)
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.5
		highlight.Parent = model
		
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "CustomESP_Billboard"
		billboard.Size = UDim2.new(0, 100, 0, 50)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.AlwaysOnTop = true
		
		local textLabel = Instance.new("TextLabel")
		textLabel.Size = UDim2.new(1, 0, 1, 0)
		textLabel.BackgroundTransparency = 1
		textLabel.Text = model.Name
		textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		textLabel.TextScaled = true
		textLabel.Font = Enum.Font.SourceSansBold
		
		local stroke = Instance.new("UIStroke")
		stroke.Parent = textLabel
		textLabel.Parent = billboard
		
		local targetPart = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if targetPart then
			billboard.Adornee = targetPart
			billboard.Parent = model
		end
	end
end

for _, child in ipairs(Workspace:GetChildren()) do
	setupESP(child)
end

-- ==========================================
-- INPUT & EVENT LISTENERS
-- ==========================================
local speedToggled = false
local speedMultiplier = 1.4 -- 40% speed boost

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

table.insert(activeConnections, Workspace.ChildAdded:Connect(function(child)
	task.wait(0.05)
	setupESP(child)
end))

-- Handle Light Grid & Clean CFrame-based Speed Offset
table.insert(activeConnections, RunService.RenderStepped:Connect(function(dt)
	if lightToggled and #lightParts > 0 and character and character:FindFirstChild("HumanoidRootPart") then
		local hrp = character.HumanoidRootPart
		for _, data in ipairs(lightParts) do
			if data.Part and hrp then
				data.Part.CFrame = CFrame.new(hrp.Position + data.Offset)
			end
		end
	end
	
	-- CFrame Movement Translation Bypass (Guarantees immediate stop & working speed increase)
	if speedToggled and character then
		local humanoid = character:FindFirstChild("Humanoid")
		local hrp = character:FindFirstChild("HumanoidRootPart")
		
		if humanoid and hrp then
			humanoid.WalkSpeed = defaultSpeed -- Keep server property normal
			
			local moveDir = humanoid.MoveDirection
			if moveDir.Magnitude > 0 then
				local extraSpeed = (defaultSpeed * (speedMultiplier - 1)) * dt
				hrp.CFrame = hrp.CFrame + (moveDir * extraSpeed)
			end
		end
	end
end))

print("Loaded have fun bro :)")
