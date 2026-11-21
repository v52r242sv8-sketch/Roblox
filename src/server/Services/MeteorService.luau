-- MeteorService: meteors falling from the sky, grabbing, carrying them over your head,
-- dropping them, delivering them home, speed gates and zone hazards.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Visuals = require(Shared.Visuals)

local MeteorService = {}
local Services

local meteorFolder
local carriedFolder
local active = {} -- [zoneIndex] = meteors currently waiting in that zone
local ground = {} -- [model] = entry
local carries = {} -- [player] = carry
local hazardCooldown = {} -- [player] = os.clock() time
local messageCooldown = {} -- [player] = { [key] = os.clock() time }

local function notifyThrottled(player, key, text, color, gap)
	messageCooldown[player] = messageCooldown[player] or {}
	local now = os.clock()
	local last = messageCooldown[player][key] or 0
	if now - last >= (gap or 3) then
		messageCooldown[player][key] = now
		Services.Notify(player, text, color)
	end
end

local function groundHeightAt(position)
	local ignore = { meteorFolder, carriedFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local result = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -300, 0), params)
	if result then
		return result.Position.Y
	end
	return 0
end

local function rarityOf(item)
	return Util.GetRarity(Config.MeteorlingById[item.id].Rarity)
end

function MeteorService.Init(services)
	Services = services
	meteorFolder = Services.Map.MeteorFolder
	carriedFolder = Instance.new("Folder")
	carriedFolder.Name = "Carried"
	carriedFolder.Parent = workspace
	for i in Config.Zones do
		active[i] = 0
	end
end

function MeteorService.GetCarry(player)
	return carries[player]
end

-- Ground meteors -------------------------------------------------------------

local function removeGround(entry)
	ground[entry.Model] = nil
	if entry.Zone then
		active[entry.Zone] = math.max(0, active[entry.Zone] - 1)
	end
	if entry.Beacon then
		entry.Beacon:Destroy()
		entry.Beacon = nil
	end
end

function MeteorService.MakeGround(model, item, opts)
	local root = model.PrimaryPart
	local rarity = rarityOf(item)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrabPrompt"
	prompt.ActionText = "Grab"
	local objectText = rarity.Name .. " Meteor"
	if item.mut then
		objectText = item.mut .. " " .. objectText
	end
	prompt.ObjectText = objectText
	prompt.HoldDuration = rarity.GrabTime
	prompt.MaxActivationDistance = 7 + rarity.Size / 2
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	local entry = {
		Model = model,
		Item = item,
		Zone = opts.Zone,
		ExpireAt = os.clock() + (opts.Lifetime or Config.Meteor.GroundLifetime),
		Beacon = opts.Beacon,
		Announce = opts.Announce,
	}
	ground[model] = entry

	prompt.Triggered:Connect(function(player)
		MeteorService.TryGrab(player, model)
	end)
	return entry
end

function MeteorService.TryGrab(player, model)
	local entry = ground[model]
	if not entry then
		return
	end
	if carries[player] then
		notifyThrottled(player, "full", "Your hands are full! Bring it home first.", Color3.fromRGB(255, 180, 80))
		return
	end
	if not Services.Plot.GetPlot(player) then
		return
	end
	local root = Services.Player.GetAliveParts(player)
	if not root or not model.PrimaryPart then
		return
	end
	if (root.Position - model.PrimaryPart.Position).Magnitude > 25 then
		return
	end

	local grabPosition = model.PrimaryPart.Position
	removeGround(entry)
	if entry.Announce then
		Services.NotifyAll(
			player.DisplayName .. " grabbed the " .. (entry.Item.mut or "Golden") .. " Comet! Bonk them!",
			Color3.fromRGB(255, 215, 60)
		)
	end
	if MeteorService.Carry(player, entry.Item, nil, model) then
		-- The zone Guardian wakes up and chases the thief
		Services.Guardian.Alert(player, grabPosition)
	else
		MeteorService.MakeGround(model, entry.Item, { Lifetime = Config.Meteor.DropLifetime })
	end
end

function MeteorService.Impact(position, rarity)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = rarity.Size * 2
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace

	local d = rarity.Size * 3.2
	local scorch = Visuals.Make("Part", {
		Name = "Scorch",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, d, d),
		CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(25, 20, 20),
		Transparency = 0.2,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, meteorFolder)
	TweenService:Create(scorch, TweenInfo.new(8), { Transparency = 1 }):Play()
	Debris:AddItem(scorch, 8.5)

	Remotes.Effect:FireAllClients("Impact", position, rarity.Size, rarity.Color)
end

-- Spawns one meteor in a zone. opts: Rarity, Mutation, Special, Beacon, WarningTime, Lifetime, Announce
function MeteorService.SpawnMeteor(zoneIndex, opts)
	opts = opts or {}
	local zone = Config.Zones[zoneIndex]
	local rarityName = opts.Rarity or Util.WeightedPick(zone.Weights)
	local list = Config.MeteorlingsByRarity[rarityName]
	local info = list[math.random(1, #list)]
	local rarity = Util.GetRarity(rarityName)

	local item = { id = info.Id, mut = opts.Mutation }
	if not item.mut and Services.Event.IsShower() then
		item.mut = Services.Plot.RollMutation(Config.Events.ShowerMutationMult * 2)
	end

	-- Inside the corridor; floors are flat at y = 0
	local w = Config.LaneHalfWidth
	local target = Vector3.new(math.random(-w + 8, w - 8), 0, math.random(zone.ZMin + 8, zone.ZMax - 8))

	local countedZone = nil
	if not opts.Special then
		countedZone = zoneIndex
		active[zoneIndex] += 1
	end

	local warning, inner = Visuals.WarningCircle(rarity.Size * 2 + 6, rarity.Color)
	warning.CFrame = CFrame.new(target + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	inner.CFrame = warning.CFrame
	-- The client shrinks the inner disc and shows a countdown until this time
	local warningTime = opts.WarningTime or Config.Meteor.WarningTime
	warning:SetAttribute("ImpactAt", workspace:GetServerTimeNow() + warningTime + Config.Meteor.FallTime)
	CollectionService:AddTag(warning, "ImpactWarning")
	warning.Parent = meteorFolder
	local pulse = TweenService:Create(
		warning,
		TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.85 }
	)
	pulse:Play()

	local beacon = nil
	if opts.Beacon then
		beacon = Visuals.Beacon(target, opts.BeaconColor or Color3.fromRGB(255, 210, 60))
		beacon.Parent = meteorFolder
	end

	task.delay(warningTime, function()
		local model = Visuals.MeteorModel(item, false)
		local root = model.PrimaryPart
		local startPos = target + Vector3.new(math.random(-90, 90), 280, math.random(-90, 90))
		model:PivotTo(CFrame.lookAt(startPos, target))

		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(rarity.Size * 0.45, 0, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(-rarity.Size * 0.45, 0, 0)
		a1.Parent = root
		local trail = Visuals.Make("Trail", {
			Attachment0 = a0,
			Attachment1 = a1,
			Lifetime = 0.6,
			LightEmission = 1,
			FaceCamera = true,
			Color = ColorSequence.new(rarity.Color, Color3.fromRGB(255, 120, 30)),
			Transparency = NumberSequence.new(0, 1),
		}, root)
		local fire = Visuals.Make("Fire", {
			Size = math.min(30, rarity.Size * 2),
			Heat = 20,
			Color = Color3.fromRGB(255, 140, 40),
			SecondaryColor = rarity.Color,
		}, root)

		model.Parent = meteorFolder
		local fall = TweenService:Create(
			root,
			TweenInfo.new(Config.Meteor.FallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = CFrame.new(target + Vector3.new(0, rarity.Size * 0.35, 0)) }
		)
		fall:Play()
		fall.Completed:Wait()

		pulse:Cancel()
		warning:Destroy()
		fire.Enabled = false
		trail.Enabled = false
		Debris:AddItem(fire, 2)

		root:SetAttribute("BaseCF", root.CFrame)
		MeteorService.Impact(target, rarity)
		MeteorService.MakeGround(model, item, {
			Zone = countedZone,
			Lifetime = opts.Lifetime,
			Beacon = beacon,
			Announce = opts.Announce,
		})
	end)
end

-- Carrying -------------------------------------------------------------------

-- stolen = { StolenFrom = player, Pedestal = number, Plot = plot } or nil
function MeteorService.Carry(player, item, stolen, existingModel)
	if carries[player] then
		return false
	end
	local root, humanoid = Services.Player.GetAliveParts(player)
	if not root then
		return false
	end
	-- Hands are busy: put the hammer away
	humanoid:UnequipTools()

	local model = existingModel or Visuals.ItemModel(item, false)
	local primary = model.PrimaryPart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	CollectionService:RemoveTag(primary, "Bob")
	CollectionService:RemoveTag(primary, "Spin")

	local offset = CFrame.new(0, 2.8 + primary.Size.Y / 2, 0)
	model:PivotTo(root.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = primary
	weld.C0 = offset
	weld.Parent = primary
	model.Parent = carriedFolder

	local carry = {
		Item = item,
		Model = model,
		Weld = weld,
	}
	if stolen then
		carry.StolenFrom = stolen.StolenFrom
		carry.Pedestal = stolen.Pedestal
		carry.Plot = stolen.Plot
	end
	carries[player] = carry

	player:SetAttribute("Carrying", item.id)
	player:SetAttribute("CarryStolen", stolen ~= nil)
	Services.Player.SetCarryPose(player, true)
	Services.Player.ApplyWalkSpeed(player)
	Remotes.Effect:FireClient(player, "Grab")
	return true
end

local function clearCarry(player)
	carries[player] = nil
	player:SetAttribute("Carrying", nil)
	player:SetAttribute("CarryStolen", nil)
	if player.Parent then
		Services.Player.SetCarryPose(player, false)
	end
end

function MeteorService.Drop(player, _reason)
	local carry = carries[player]
	if not carry then
		return
	end
	clearCarry(player)
	if carry.Weld then
		carry.Weld:Destroy()
	end

	local model = carry.Model
	if carry.StolenFrom then
		if model then
			model:Destroy()
		end
		Services.Plot.ReturnStolen(carry)
	elseif model and model.PrimaryPart then
		local primary = model.PrimaryPart
		local position = primary.Position
		local y = groundHeightAt(position)
		local rarity = rarityOf(carry.Item)
		primary.Anchored = true
		primary.CanQuery = true
		model:PivotTo(CFrame.new(position.X, y + rarity.Size * 0.35, position.Z))
		primary:SetAttribute("BaseCF", primary.CFrame)
		CollectionService:AddTag(primary, "Spin")
		model.Parent = meteorFolder
		MeteorService.MakeGround(model, carry.Item, { Lifetime = Config.Meteor.DropLifetime })
	end

	if player.Parent then
		Services.Player.ApplyWalkSpeed(player)
	end
end

function MeteorService.OnPlayerRemoving(player)
	MeteorService.Drop(player, "left")
	-- Anyone running away with this player's items loses them (the owner keeps them)
	for thief, carry in carries do
		if carry.StolenFrom == player then
			clearCarry(thief)
			if carry.Model then
				carry.Model:Destroy()
			end
			Services.Player.ApplyWalkSpeed(thief)
			Services.Notify(thief, "The owner left, the item vanished!", Color3.fromRGB(255, 180, 80))
		end
	end
	hazardCooldown[player] = nil
	messageCooldown[player] = nil
end

-- Hazards & gates ------------------------------------------------------------

function MeteorService.Hazard(player, source, kind)
	local now = os.clock()
	if (hazardCooldown[player] or 0) > now then
		return
	end
	hazardCooldown[player] = now + 1.5
	local root, humanoid = Services.Player.GetAliveParts(player)
	if not root then
		return
	end
	if carries[player] then
		MeteorService.Drop(player, kind)
		Services.Notify(player, "Ouch! You dropped it!", Color3.fromRGB(255, 120, 80))
	end
	if kind == "lava" then
		humanoid:TakeDamage(35)
	end
	local away = root.Position - source
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, -1)
	end
	Remotes.Knockback:FireClient(player, away.Unit * 70 + Vector3.new(0, 45, 0), 0.8)
end

local function checkPlayer(player)
	local root = Services.Player.GetAliveParts(player)
	local data = Services.Data.Get(player)
	if not root or not data then
		return
	end
	local position = root.Position

	-- Speed gates: push back players that are too slow for a zone
	for zoneIndex = 2, #Config.Zones do
		local zone = Config.Zones[zoneIndex]
		local gateZ = zone.ZMin - 10
		if position.Z > gateZ and data.Speed < zone.Speed then
			root.CFrame = CFrame.new(position.X, position.Y + 0.5, gateZ - 6) * root.CFrame.Rotation
			notifyThrottled(
				player,
				"gate",
				"You need " .. zone.Speed .. " Speed for " .. zone.Name .. ". Stand on your Speed Pad!",
				Color3.fromRGB(120, 210, 255)
			)
			return
		end
	end

	-- Lava pools
	for _, pool in Services.Map.LavaPools do
		local dx = position.X - pool.Position.X
		local dz = position.Z - pool.Position.Z
		if dx * dx + dz * dz < pool.Radius * pool.Radius and position.Y < 6 then
			MeteorService.Hazard(player, pool.Position, "lava")
			return
		end
	end

	-- Spinning sweepers in the void
	for _, sweeper in Services.Map.Sweepers do
		local cf = sweeper.Part.CFrame
		local rel = position - cf.Position
		if math.abs(rel.Y) < 4.5 then
			local along = rel:Dot(cf.RightVector)
			if math.abs(along) <= sweeper.Part.Size.X / 2 then
				local perp = rel - cf.RightVector * along
				if Vector3.new(perp.X, 0, perp.Z).Magnitude < 2.8 then
					MeteorService.Hazard(player, cf.Position, "sweeper")
					return
				end
			end
		end
	end
end

local function checkDeposits()
	for player, carry in carries do
		local root = Services.Player.GetAliveParts(player)
		local plot = Services.Plot.GetPlot(player)
		if root and plot and Services.Plot.InsidePlot(plot, root.Position, -1) then
			if Services.Plot.Deposit(player, carry) then
				clearCarry(player)
				if carry.Model then
					carry.Model:Destroy()
				end
				Services.Player.ApplyWalkSpeed(player)
			else
				notifyThrottled(
					player,
					"noslot",
					"No free pedestal! Sell a Meteorling or buy pedestals in the Shop.",
					Color3.fromRGB(255, 120, 120)
				)
			end
		end
	end
end

function MeteorService.Start()
	-- Natural meteor spawning, one loop per zone
	for zoneIndex, zone in Config.Zones do
		task.spawn(function()
			task.wait(zoneIndex)
			while true do
				local mult = 1
				if Services.Event.IsShower() then
					mult = Config.Events.ShowerSpawnMult
				end
				task.wait(zone.Interval / mult)
				local maxActive = zone.MaxActive
				if mult > 1 then
					maxActive = math.floor(maxActive * 1.5)
				end
				if #Players:GetPlayers() > 0 and active[zoneIndex] < maxActive then
					MeteorService.SpawnMeteor(zoneIndex)
				end
			end
		end)
	end

	-- Expire meteors nobody grabbed
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for model, entry in ground do
				if now >= entry.ExpireAt then
					removeGround(entry)
					model:Destroy()
				end
			end
		end
	end)

	-- Sweepers spin every frame; player checks run 10x per second
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		for _, sweeper in Services.Map.Sweepers do
			sweeper.Angle += dt * sweeper.Speed
			sweeper.Part.CFrame = CFrame.new(sweeper.Center) * CFrame.Angles(0, sweeper.Angle, 0)
		end

		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		checkDeposits()
		for _, player in Players:GetPlayers() do
			checkPlayer(player)
		end
	end)
end

return MeteorService
