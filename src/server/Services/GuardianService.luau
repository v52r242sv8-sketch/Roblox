-- GuardianService: every zone has a Guardian. Grab a meteor in its zone and it chases you.
-- Further zones have faster Guardians, so you need speed (and carrying slows you down).
-- Catch = you drop the meteor and get knocked back. Run far enough toward your base to escape.
-- Bonk a Guardian with the Hammer to stun it for a moment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Visuals = require(Shared.Visuals)

local GuardianService = {}
local Services

local guardians = {}
local rng = Random.new()

local function zoneAt(z)
	for index, zone in Config.Zones do
		if z >= zone.ZMin - 12 and z <= zone.ZMax + 12 then
			return index
		end
	end
	return nil
end
GuardianService.ZoneAt = zoneAt

function GuardianService.Init(services)
	Services = services
end

local function setAlert(g, on)
	if g.AlertGui then
		g.AlertGui.Enabled = on
	end
end

local function stopChase(g, reason)
	local target = g.Target
	g.State = "Return"
	g.Target = nil
	setAlert(g, false)
	if target and target.Parent then
		Remotes.Effect:FireClient(target, "Chase", false, g.Zone.Guardian.Name)
		if reason == "escaped" then
			Services.Notify(target, "You escaped the " .. g.Zone.Guardian.Name .. "!", Color3.fromRGB(120, 255, 160))
		end
	end
end

local function catch(g, player, root)
	Services.Meteor.Drop(player, "guardian")
	Services.Notify(
		player,
		"😠 The " .. g.Zone.Guardian.Name .. " caught you! Get more Speed!",
		Color3.fromRGB(255, 110, 90)
	)
	local away = root.Position - g.Position
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, -1)
	end
	Remotes.Knockback:FireClient(player, away.Unit * 70 + Vector3.new(0, 40, 0), 1)
	Remotes.Effect:FireAllClients("Bonk", root.Position)
	stopChase(g, "caught")
end

-- Called when a player grabs a meteor lying at `position`
function GuardianService.Alert(player, position)
	local index = zoneAt(position.Z)
	local g = index and guardians[index]
	if not g then
		return
	end
	if g.State == "Chase" or g.State == "Alert" then
		return -- busy with another thief
	end
	local now = os.clock()
	g.State = "Alert"
	g.Target = player
	g.ReactAt = now + Config.Guardian.ReactTime
	g.GiveUpAt = now + Config.Guardian.ReactTime + Config.Guardian.MaxChaseTime
	setAlert(g, true)
	Remotes.Effect:FireClient(player, "Chase", true, g.Zone.Guardian.Name)
end

-- Hammer hit check. Returns true if a Guardian got bonked.
function GuardianService.TryBonk(attackerRoot, facing, range)
	local hit = false
	for _, g in guardians do
		local offset = g.Position - attackerRoot.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local reach = range + g.Radius
		if flat.Magnitude <= reach and (flat.Magnitude < g.Radius + 2 or flat.Unit:Dot(facing) > 0.1) then
			g.StunUntil = os.clock() + Config.Guardian.StunTime
			Remotes.Effect:FireAllClients("Bonk", g.Position + Vector3.new(0, g.Height, 0))
			hit = true
		end
	end
	return hit
end

local function place(g, now, dt)
	local hop
	if g.State == "Chase" then
		hop = math.abs(math.sin(now * 12)) * 1.4
	else
		hop = math.abs(math.sin(now * 4 + g.Index)) * 0.35
	end
	local position = g.Position + Vector3.new(0, g.Height + hop, 0)
	local cf = CFrame.lookAt(position, position + g.Facing)
	if now < g.StunUntil then
		g.Spin += dt * 12
		cf = CFrame.new(position) * CFrame.Angles(0, g.Spin, 0)
	end
	g.Root.CFrame = cf
end

local function update(dt)
	local now = os.clock()
	local lane = Config.LaneHalfWidth
	for _, g in guardians do
		local zone = g.Zone
		local speed = zone.Guardian.Speed
		local goal = nil
		local moveSpeed = speed

		if now < g.StunUntil then
			place(g, now, dt)
			continue
		end

		if g.State == "Alert" then
			local root = g.Target and Services.Player.GetAliveParts(g.Target)
			if root then
				local look = Vector3.new(root.Position.X - g.Position.X, 0, root.Position.Z - g.Position.Z)
				if look.Magnitude > 0.1 then
					g.Facing = look.Unit
				end
			end
			if now >= g.ReactAt then
				g.State = "Chase"
			end
		elseif g.State == "Chase" then
			local target = g.Target
			local root = target and target.Parent and Services.Player.GetAliveParts(target)
			local carry = target and Services.Meteor.GetCarry(target)
			if not root or not carry or carry.StolenFrom then
				stopChase(g, "lost")
			elseif now > g.GiveUpAt then
				stopChase(g, "escaped")
			elseif root.Position.Z < zone.ZMin - Config.Guardian.EscapeDistance then
				stopChase(g, "escaped")
			else
				goal = root.Position
				local flat = Vector3.new(goal.X - g.Position.X, 0, goal.Z - g.Position.Z)
				if flat.Magnitude <= Config.Guardian.CatchDistance + g.Radius * 0.5 then
					catch(g, target, root)
					goal = nil
				end
			end
		elseif g.State == "Return" then
			goal = g.Home
			moveSpeed = math.max(10, speed * 0.6)
			if (Vector3.new(g.Position.X, 0, g.Position.Z) - g.Home).Magnitude < 2 then
				g.State = "Idle"
			end
		else
			-- Idle: wander around its zone
			if not g.WanderTo or (Vector3.new(g.Position.X, 0, g.Position.Z) - g.WanderTo).Magnitude < 2 then
				g.WanderTo = Vector3.new(rng:NextNumber(-lane + 10, lane - 10), 0, rng:NextNumber(zone.ZMin + 15, zone.ZMax - 15))
			end
			goal = g.WanderTo
			moveSpeed = math.min(8, speed * 0.4)
		end

		if goal then
			local delta = Vector3.new(goal.X - g.Position.X, 0, goal.Z - g.Position.Z)
			local distance = delta.Magnitude
			if distance > 0.1 then
				local step = math.min(distance, moveSpeed * dt)
				g.Position += delta.Unit * step
				g.Facing = delta.Unit
			end
		end
		g.Position = Vector3.new(
			math.clamp(g.Position.X, -lane + 5, lane - 5),
			0,
			math.clamp(g.Position.Z, zone.ZMin - Config.Guardian.EscapeDistance - 10, zone.ZMax + 15)
		)
		place(g, now, dt)
	end
end

function GuardianService.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Guardians"
	folder.Parent = workspace

	for index, zone in Config.Zones do
		local model = Visuals.GuardianModel(zone)
		local root = model.PrimaryPart
		local home = Vector3.new(0, 0, (zone.ZMin + zone.ZMax) / 2)
		local height = root.Size.Y / 2 + 1.2
		model:PivotTo(CFrame.lookAt(home + Vector3.new(0, height, 0), home + Vector3.new(0, height, -1)))
		model.Parent = folder
		local alertGui = root:FindFirstChild("AlertGui")
		guardians[index] = {
			Index = index,
			Zone = zone,
			Model = model,
			Root = root,
			Home = home,
			Position = home,
			Height = height,
			Radius = root.Size.X / 2,
			Facing = Vector3.new(0, 0, -1),
			State = "Idle",
			Target = nil,
			StunUntil = 0,
			Spin = 0,
			AlertGui = alertGui,
		}
	end

	RunService.Heartbeat:Connect(update)

	Players.PlayerRemoving:Connect(function(player)
		for _, g in guardians do
			if g.Target == player then
				stopChase(g, "left")
			end
		end
	end)
end

return GuardianService
