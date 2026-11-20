-- PlayerService: characters, walk speed, game pass ownership and all player multipliers.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local PlayerService = {}
local Services

local ownedPasses = {} -- [player] = { [passKey] = true }

function PlayerService.Init(services)
	Services = services
end

function PlayerService.Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, pass in Config.GamePasses do
			if pass.Id ~= 0 and pass.Id == passId then
				ownedPasses[player] = ownedPasses[player] or {}
				ownedPasses[player][key] = true
				PlayerService.OnPassGranted(player, key)
			end
		end
	end)
end

function PlayerService.LoadPasses(player)
	local owned = {}
	for key, pass in Config.GamePasses do
		if pass.Id ~= 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and result then
				owned[key] = true
			end
		end
	end
	ownedPasses[player] = owned
end

function PlayerService.HasPass(player, key)
	local owned = ownedPasses[player]
	return owned ~= nil and owned[key] == true
end

function PlayerService.OnPassGranted(player, key)
	Services.Notify(player, "Thanks for buying " .. Config.GamePasses[key].Name .. "!", Color3.fromRGB(255, 220, 90))
	if key == "VIP" then
		Services.Plot.RefreshPedestals(player)
		PlayerService.ApplyTag(player)
	elseif key == "BigHammer" then
		Services.Combat.GiveHammer(player, true)
	end
	PlayerService.ApplyWalkSpeed(player)
	Services.Data.MarkDirty(player)
end

function PlayerService.Cleanup(player)
	ownedPasses[player] = nil
end

-- Multipliers -------------------------------------------------------------

function PlayerService.GetIncomeMultiplier(player)
	local data = Services.Data.Get(player)
	if not data then
		return 1
	end
	local mult = Util.RebirthMultiplier(data.Rebirths)
	mult *= 1 + Config.IndexBonusPerEntry * Util.CountKeys(data.Index)
	if PlayerService.HasPass(player, "DoubleMoney") then
		mult *= 2
	end
	return mult
end

function PlayerService.GetLuck(player)
	local data = Services.Data.Get(player)
	local luck = 1
	if PlayerService.HasPass(player, "VIP") then
		luck *= Config.VipLuck
	end
	if data and data.LuckUntil > os.time() then
		luck *= 2
	end
	if Services.Event.IsShower() then
		luck *= Config.Events.ShowerMutationMult
	end
	return luck
end

function PlayerService.GetPadRate(player)
	local data = Services.Data.Get(player)
	if not data then
		return Config.PadBaseRate
	end
	local rate = Config.PadBaseRate + data.Boots
	if PlayerService.HasPass(player, "DoubleSpeed") then
		rate *= 2
	end
	return rate
end

function PlayerService.GetPedestalCount(player)
	local data = Services.Data.Get(player)
	if not data then
		return Config.StartPedestals
	end
	local count = data.Pedestals
	if PlayerService.HasPass(player, "VIP") then
		count += Config.VipBonusPedestals
	end
	return math.min(count, Config.PhysicalPedestals)
end

-- Characters ---------------------------------------------------------------

function PlayerService.GetAliveParts(player)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

function PlayerService.ApplyWalkSpeed(player)
	local data = Services.Data.Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = math.min(Config.MaxSpeed, math.floor(data.Speed))
	local carry = Services.Meteor.GetCarry(player)
	if carry then
		local rarity = Util.GetRarity(Config.MeteorlingById[carry.Item.id].Rarity)
		local penalty = rarity.Weight
		if carry.StolenFrom then
			penalty += Config.Meteor.StolenPenalty
		end
		speed = math.max(12, speed * (1 - penalty))
	end
	humanoid.WalkSpeed = speed
	-- Fast players need a stronger jump to feel right
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 50 + math.min(30, speed / 10)
	PlayerService.UpdateTrail(player, data.Speed)
end

-- Speed trail: everyone sees how fast you are -------------------------------------

local TRAIL_TIERS = {
	{ Speed = 40, Color = Color3.fromRGB(90, 220, 255) },
	{ Speed = 90, Color = Color3.fromRGB(190, 110, 255) },
	{ Speed = 160, Color = Color3.fromRGB(255, 200, 60) },
	{ Speed = 230, Color = Color3.fromRGB(255, 80, 180) },
}

function PlayerService.CreateTrail(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or root:FindFirstChild("SpeedTrail") then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, 1.1, 0.3)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -1.8, 0.3)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SpeedTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.MinLength = 0.2
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = root
end

function PlayerService.UpdateTrail(player, speed)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local trail = root and root:FindFirstChild("SpeedTrail")
	if not trail then
		return
	end
	local color = nil
	for _, tier in TRAIL_TIERS do
		if speed >= tier.Speed then
			color = tier.Color
		end
	end
	trail.Enabled = color ~= nil
	if color then
		trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	end
end

-- Arm poses (no animation assets needed: we rotate the shoulder joints) ---------

local originalC0 = setmetatable({}, { __mode = "k" })

local function getShoulders(character)
	local rightArm = character:FindFirstChild("RightUpperArm")
	local leftArm = character:FindFirstChild("LeftUpperArm")
	if rightArm and leftArm then
		return rightArm:FindFirstChild("RightShoulder"), leftArm:FindFirstChild("LeftShoulder"), "R15"
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		return torso:FindFirstChild("Right Shoulder"), torso:FindFirstChild("Left Shoulder"), "R6"
	end
	return nil, nil, nil
end

local function baseC0(motor)
	if not originalC0[motor] then
		originalC0[motor] = motor.C0
	end
	return originalC0[motor]
end

local function rotated(motor, rig, degrees)
	local angle = math.rad(degrees)
	if rig == "R15" then
		return baseC0(motor) * CFrame.Angles(angle, 0, 0)
	end
	return baseC0(motor) * CFrame.Angles(0, 0, angle)
end

local function tweenC0(motor, goal, duration, style)
	local tween = TweenService:Create(
		motor,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ C0 = goal }
	)
	tween:Play()
	return tween
end

-- Both arms straight up while carrying something over your head
function PlayerService.SetCarryPose(player, on)
	local character = player.Character
	if not character then
		return
	end
	local right, left, rig = getShoulders(character)
	for _, motor in { right or false, left or false } do
		if motor and motor:IsA("Motor6D") then
			if on then
				tweenC0(motor, rotated(motor, rig, 180), 0.25, Enum.EasingStyle.Back)
			else
				tweenC0(motor, baseC0(motor), 0.2)
			end
		end
	end
end

-- Hammer swing: wind up over the head, smash down, return
function PlayerService.PlaySwing(player)
	local character = player.Character
	if not character then
		return
	end
	local right, _, rig = getShoulders(character)
	if not right or not right:IsA("Motor6D") then
		return
	end
	task.spawn(function()
		tweenC0(right, rotated(right, rig, 115), 0.1).Completed:Wait()
		tweenC0(right, rotated(right, rig, -35), 0.08, Enum.EasingStyle.Quart).Completed:Wait()
		task.wait(0.05)
		if right.Parent then
			tweenC0(right, baseC0(right), 0.22)
		end
	end)
end

function PlayerService.ApplyTag(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("VipTag")
	if old then
		old:Destroy()
	end
	if not PlayerService.HasPass(player, "VIP") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VipTag"
	gui.Size = UDim2.new(4, 0, 1, 0)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "⭐ VIP"
	label.TextColor3 = Color3.fromRGB(255, 215, 60)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = head
end

function PlayerService.OnCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end

	-- Move the player to their own base
	local plot = Services.Plot.GetPlot(player)
	if plot then
		-- Small delay so the default spawn positioning does not override the teleport
		task.delay(0.1, function()
			if root.Parent then
				character:PivotTo(plot.SpawnCFrame)
			end
		end)
	end

	PlayerService.CreateTrail(character)
	PlayerService.ApplyWalkSpeed(player)
	PlayerService.ApplyTag(player)
	Services.Combat.GiveHammer(player, false)

	humanoid.Died:Connect(function()
		Services.Meteor.Drop(player, "died")
	end)
end

function PlayerService.Setup(player)
	Services.Data.SetupLeaderstats(player)
	PlayerService.LoadPasses(player)

	player.CharacterAdded:Connect(function(character)
		PlayerService.OnCharacter(player, character)
	end)
	if player.Character then
		task.spawn(PlayerService.OnCharacter, player, player.Character)
	end
end

return PlayerService
