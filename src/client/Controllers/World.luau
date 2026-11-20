-- World: client-side life for the 3D world.
--   * "Sell" prompts only on your base, "Steal" prompts only on other bases
--   * hatch countdowns, impact countdowns (shrinking target + 3..2..1)
--   * Meteorlings hop and sway, meteors on the ground slowly spin
--   * camera FOV widens with speed, beam from you to your base while carrying

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)

local player = Players.LocalPlayer

local World = {}

local beam = nil
local beamAttachment = nil
local warnings = setmetatable({}, { __mode = "k" }) -- [part] = { Start, Gui, Label }
local currentFov = 70

local function findPlotModel(instance)
	local current = instance.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("PlotIndex") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function updatePrompt(prompt)
	local kind = prompt:GetAttribute("Kind")
	if not kind then
		return
	end
	local plotModel = findPlotModel(prompt)
	if not plotModel then
		return
	end
	local owner = plotModel:GetAttribute("Owner") or 0
	local mine = owner == player.UserId
	if kind == "Sell" then
		prompt.Enabled = mine
	else
		prompt.Enabled = (not mine) and owner ~= 0
	end
end

local function updatePlotPrompts(plotModel)
	for _, descendant in plotModel:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			updatePrompt(descendant)
		end
	end
end

local function myPlotModel()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plotModel in plots:GetChildren() do
		if plotModel:GetAttribute("Owner") == player.UserId then
			return plotModel
		end
	end
	return nil
end

local function clearBeam()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if beamAttachment then
		beamAttachment:Destroy()
		beamAttachment = nil
	end
end

local function updateBeam()
	clearBeam()
	if not player:GetAttribute("Carrying") then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local plotModel = myPlotModel()
	local floor = plotModel and plotModel:FindFirstChild("Floor")
	local target = floor and floor:FindFirstChild("DepositPoint")
	if not root or not target then
		return
	end
	beamAttachment = Instance.new("Attachment")
	beamAttachment.Name = "CarryBeamStart"
	beamAttachment.Parent = root

	beam = Instance.new("Beam")
	beam.Name = "CarryBeam"
	beam.Attachment0 = beamAttachment
	beam.Attachment1 = target
	beam.Color = ColorSequence.new(Color3.fromRGB(90, 255, 140), Color3.fromRGB(60, 200, 255))
	beam.Width0 = 0.8
	beam.Width1 = 3
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new(0.15, 0.55)
	beam.Segments = 1
	beam.Parent = root
end

local function textLoop()
	while true do
		task.wait(0.2)
		local now = workspace:GetServerTimeNow()
		for _, timer in CollectionService:GetTagged("HatchTimer") do
			local hatchAt = timer:GetAttribute("HatchAt")
			if hatchAt then
				local left = hatchAt - now
				if left > 0 then
					timer.Text = "🥚 " .. Util.FormatTime(left)
				else
					timer.Text = "🐣 Hatching..."
				end
			end
		end
	end
end

local function updateWarning(part, now)
	local impactAt = part:GetAttribute("ImpactAt")
	local inner = part:FindFirstChild("Inner")
	if not impactAt or not inner then
		return
	end
	local state = warnings[part]
	if not state then
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(6, 0, 3, 0)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 250
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(255, 80, 80)
		text.TextStrokeTransparency = 0
		text.Text = ""
		text.Parent = gui
		gui.Parent = part
		state = { Start = now, Total = math.max(0.5, impactAt - now), Label = text, Diameter = part.Size.Y }
		warnings[part] = state
	end
	local left = impactAt - now
	local fraction = math.clamp(left / state.Total, 0.02, 1)
	local d = state.Diameter * fraction
	inner.Size = Vector3.new(inner.Size.X, d, d)
	inner.CFrame = part.CFrame
	if left > 0 then
		state.Label.Text = tostring(math.ceil(left))
		state.Label.TextSize = 40
	else
		state.Label.Text = "!"
	end
end

function World.Init()
	-- Prompt filtering
	workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			task.defer(updatePrompt, descendant)
		end
	end)
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots")
		local function hookPlot(plotModel)
			plotModel:GetAttributeChangedSignal("Owner"):Connect(function()
				updatePlotPrompts(plotModel)
				updateBeam()
			end)
			updatePlotPrompts(plotModel)
		end
		for _, plotModel in plots:GetChildren() do
			hookPlot(plotModel)
		end
		plots.ChildAdded:Connect(hookPlot)
	end)

	-- Carry beam
	player:GetAttributeChangedSignal("Carrying"):Connect(updateBeam)
	player.CharacterAdded:Connect(function()
		beam = nil
		beamAttachment = nil
		task.wait(0.5)
		updateBeam()
	end)

	task.spawn(textLoop)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local now = workspace:GetServerTimeNow()

		-- Meteorlings: happy hop + sway
		for _, part in CollectionService:GetTagged("Bob") do
			if part.Anchored then
				local base = part:GetAttribute("BaseCF")
				if typeof(base) == "CFrame" then
					local phase = (base.Position.X + base.Position.Z) * 0.13
					local hop = math.abs(math.sin(t * 2.6 + phase)) * 0.55
					part.CFrame = base
						* CFrame.new(0, hop + 0.15, 0)
						* CFrame.Angles(0, math.sin(t * 1.1 + phase) * 0.45, math.sin(t * 2.6 + phase) * 0.06)
				end
			end
		end

		-- Meteors: slow spin and float
		for _, part in CollectionService:GetTagged("Spin") do
			if part.Anchored then
				local base = part:GetAttribute("BaseCF")
				if typeof(base) == "CFrame" then
					local phase = (base.Position.X - base.Position.Z) * 0.1
					part.CFrame = base
						* CFrame.new(0, math.sin(t * 1.8 + phase) * 0.25 + 0.25, 0)
						* CFrame.Angles(0, t * 0.8 + phase, math.sin(t + phase) * 0.15)
				end
			end
		end

		-- Impact countdowns
		for _, part in CollectionService:GetTagged("ImpactWarning") do
			updateWarning(part, now)
		end

		-- Speed FOV
		local camera = workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if camera and root then
			local velocity = root.AssemblyLinearVelocity
			local flat = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local target = 70 + math.clamp((flat - 20) * 0.12, 0, 22)
			currentFov += (target - currentFov) * math.clamp(dt * 4, 0, 1)
			camera.FieldOfView = currentFov
		end
	end)
end

function World.SetState(_state) end

return World
