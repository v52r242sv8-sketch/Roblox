-- World: client-side touches on the 3D world.
--   * shows "Sell" prompts only on your base and "Steal" prompts only on other bases
--   * hatch countdowns above meteors
--   * Meteorlings bob and sway on their pedestals
--   * a beam that points from you to your base while you carry something

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
	beam.Color = ColorSequence.new(Color3.fromRGB(90, 255, 120), Color3.fromRGB(60, 200, 255))
	beam.Width0 = 0.9
	beam.Width1 = 2.5
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new(0.2, 0.5)
	beam.Segments = 1
	beam.Parent = root
end

local function hatchTimerLoop()
	while true do
		task.wait(0.25)
		local now = workspace:GetServerTimeNow()
		for _, timer in CollectionService:GetTagged("HatchTimer") do
			local hatchAt = timer:GetAttribute("HatchAt")
			if hatchAt then
				local left = hatchAt - now
				if left > 0 then
					timer.Text = "Hatching in " .. Util.FormatTime(left)
				else
					timer.Text = "Hatching..."
				end
			end
		end
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

	task.spawn(hatchTimerLoop)

	-- Bobbing Meteorlings
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, part in CollectionService:GetTagged("Bob") do
			if part.Anchored then
				local base = part:GetAttribute("BaseCF")
				if typeof(base) == "CFrame" then
					local phase = (base.Position.X + base.Position.Z) * 0.1
					part.CFrame = base
						* CFrame.new(0, math.sin(t * 2 + phase) * 0.35 + 0.35, 0)
						* CFrame.Angles(0, math.sin(t * 0.9 + phase) * 0.4, 0)
				end
			end
		end
	end)
end

function World.SetState(_state) end

return World
