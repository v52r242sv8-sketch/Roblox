-- CombatService: the Hammer. Bonk a player to knock them back and make them drop
-- whatever they carry. Stolen items fly back to their owner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Visuals = require(Shared.Visuals)

local CombatService = {}
local Services

local lastSwing = {} -- [player] = os.clock()

function CombatService.Init(services)
	Services = services
end

function CombatService.Start()
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

local function findHammer(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local tool = (backpack and backpack:FindFirstChild("Hammer")) or (character and character:FindFirstChild("Hammer"))
	return tool
end

function CombatService.GiveHammer(player, replace)
	local existing = findHammer(player)
	if existing then
		if not replace then
			return
		end
		existing:Destroy()
	end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end
	local big = Services.Player.HasPass(player, "BigHammer")
	local tool = Visuals.HammerTool(big)
	tool.Activated:Connect(function()
		CombatService.Swing(player, tool, big)
	end)
	tool.Parent = backpack
end

function CombatService.Hit(attacker, victim, direction)
	local carry = Services.Meteor.GetCarry(victim)
	if carry then
		if carry.StolenFrom == attacker then
			Services.Notify(attacker, "You got your " .. carry.Item.id .. " back!", Color3.fromRGB(120, 255, 160))
		else
			Services.Notify(attacker, "Bonk! " .. victim.DisplayName .. " dropped it!", Color3.fromRGB(255, 220, 120))
		end
		Services.Meteor.Drop(victim, "bonk")
		Services.Notify(victim, attacker.DisplayName .. " bonked you!", Color3.fromRGB(255, 120, 80))
	end

	local push = direction
	if push.Magnitude < 0.1 then
		push = Vector3.new(0, 0, 1)
	end
	push = push.Unit * Config.Bonk.Knockback + Vector3.new(0, 35, 0)
	Remotes.Knockback:FireClient(victim, push, Config.Bonk.StunTime)

	local victimRoot = Services.Player.GetAliveParts(victim)
	if victimRoot then
		Remotes.Effect:FireAllClients("Bonk", victimRoot.Position)
	end
end

function CombatService.HitDummy(dummy, direction)
	dummy.Hits += 1
	dummy.Label.Text = "🎯 BONK DUMMY\nbonks: " .. dummy.Hits
	Remotes.Effect:FireAllClients("Bonk", dummy.Torso.Position)
	-- Wobble away from the hit and spring back
	local away = direction
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, 1)
	end
	local axis = Vector3.new(0, 1, 0):Cross(away.Unit)
	local tilt = CFrame.fromAxisAngle(axis, math.rad(35))
	local tiltBack = CFrame.fromAxisAngle(axis, math.rad(-12))
	local base = dummy.Base
	local position = base.Position
	local rotation = base - position
	task.spawn(function()
		local out = TweenService:Create(dummy.Pivot, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
			CFrame = CFrame.new(position) * tilt * rotation,
		})
		out:Play()
		out.Completed:Wait()
		local back = TweenService:Create(dummy.Pivot, TweenInfo.new(0.25, Enum.EasingStyle.Sine), {
			CFrame = CFrame.new(position) * tiltBack * rotation,
		})
		back:Play()
		back.Completed:Wait()
		TweenService:Create(dummy.Pivot, TweenInfo.new(0.5, Enum.EasingStyle.Elastic), { CFrame = base }):Play()
	end)
end

function CombatService.Swing(player, tool, big)
	local cooldown = Config.Bonk.Cooldown
	local range = Config.Bonk.Range
	if big then
		cooldown = Config.Bonk.BigCooldown
		range = Config.Bonk.BigRange
	end
	local now = os.clock()
	if now - (lastSwing[player] or 0) < cooldown then
		return
	end
	lastSwing[player] = now

	local root = Services.Player.GetAliveParts(player)
	if not root then
		return
	end
	if Services.Meteor.GetCarry(player) then
		return -- hands are full
	end

	-- Swing animation (rotates the shoulder joint), trail + sound
	Services.Player.PlaySwing(player)
	local head = tool:FindFirstChild("Head")
	local trail = head and head:FindFirstChild("SwingTrail")
	if trail then
		trail.Enabled = true
		task.delay(0.4, function()
			trail.Enabled = false
		end)
	end
	local handle = tool:FindFirstChild("Handle")
	if handle then
		local swing = handle:FindFirstChild("Swing")
		if swing then
			swing:Play()
		end
	end

	-- Hit lands when the hammer comes down
	task.wait(0.15)
	if not root.Parent then
		return
	end

	local facing = root.CFrame.LookVector
	facing = Vector3.new(facing.X, 0, facing.Z).Unit
	local hitSomeone = false
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = Services.Player.GetAliveParts(other)
			if otherRoot then
				local offset = otherRoot.Position - root.Position
				if offset.Magnitude <= range then
					local flat = Vector3.new(offset.X, 0, offset.Z)
					if flat.Magnitude < 3 or flat.Unit:Dot(facing) > 0.15 then
						CombatService.Hit(player, other, flat)
						hitSomeone = true
					end
				end
			end
		end
	end

	-- Guardians get stunned
	if Services.Guardian.TryBonk(root, facing, range) then
		hitSomeone = true
	end

	-- Training dummies
	for _, dummy in Services.Map.Dummies or {} do
		local offset = dummy.Torso.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= range + 1.5 and (flat.Magnitude < 3 or flat.Unit:Dot(facing) > 0.15) then
			hitSomeone = true
			CombatService.HitDummy(dummy, flat)
		end
	end

	if hitSomeone and handle then
		local hit = handle:FindFirstChild("Hit")
		if hit then
			hit:Play()
		end
	end
end

return CombatService
