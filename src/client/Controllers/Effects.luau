-- Effects: knockback, camera shake, impact shockwaves with debris, hatch bursts, sounds.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local Effects = {}
local UI

local sounds = {}
local shakeUntil = 0
local shakePower = 0
local shaking = false
local fxFolder

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local SOUND_IDS = {
	Collect = "rbxasset://sounds/electronicpingshort.wav",
	Grab = "rbxasset://sounds/swoosh.wav",
	Deposit = "rbxasset://sounds/victory.wav",
	Ouch = "rbxasset://sounds/uuhhh.mp3",
	Alarm = "rbxasset://sounds/Rocket shot.wav",
	Hatch = "rbxasset://sounds/victory.wav",
}

local function play(name, volume)
	local sound = sounds[name]
	if sound then
		sound.Volume = volume or 0.5
		sound:Play()
	end
end

local function shake(power, duration)
	shakePower = math.max(shakePower, power)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
	if shaking then
		return
	end
	shaking = true
	RunService:BindToRenderStep("MeteorShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		local camera = workspace.CurrentCamera
		if now >= shakeUntil or not camera then
			RunService:UnbindFromRenderStep("MeteorShake")
			shaking = false
			shakePower = 0
			return
		end
		local p = shakePower * math.clamp((shakeUntil - now) * 2, 0, 1)
		camera.CFrame = camera.CFrame
			* CFrame.Angles(math.rad((math.random() - 0.5) * p), math.rad((math.random() - 0.5) * p), 0)
	end)
end

local function localPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = fxFolder
	return p
end

local function distanceTo(position)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return math.huge
	end
	return (root.Position - position).Magnitude
end

local function ring(position, color, fromSize, toSize, duration)
	local r = localPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, fromSize, fromSize),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.1,
	})
	TweenService:Create(r, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, toSize, toSize),
		Transparency = 1,
	}):Play()
	Debris:AddItem(r, duration + 0.1)
end

local function burst(position, color, count, size, speed, texture)
	local anchor = localPart({ Size = Vector3.new(1, 1, 1), Position = position, Transparency = 1 })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.4)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Texture = texture or SPARKLE
	emitter.Parent = anchor
	emitter:Emit(count)
	Debris:AddItem(anchor, 2)
	return anchor
end

local function flash(position, color, range, brightness, duration)
	local anchor = localPart({ Size = Vector3.new(1, 1, 1), Position = position, Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(duration), { Brightness = 0 }):Play()
	Debris:AddItem(anchor, duration + 0.1)
end

local function bonkPopup(position)
	local anchor = localPart({ Size = Vector3.new(1, 1, 1), Position = position + Vector3.new(0, 3, 0), Transparency = 1 })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(7, 0, 2.4, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.Text = "💥 BONK!"
	text.TextColor3 = Color3.fromRGB(255, 230, 80)
	text.TextStrokeTransparency = 0
	text.Rotation = math.random(-15, 15)
	text.Parent = gui
	TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Position = anchor.Position + Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(text, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 240, 120), 18, 0.8, 18)
	Debris:AddItem(anchor, 1)
end

local HANDLERS = {}

function HANDLERS.Impact(position, size, color)
	color = color or Color3.fromRGB(255, 150, 60)
	local distance = distanceTo(position)
	local reach = 60 + size * 12
	if distance < reach then
		shake((1 - distance / reach) * (1.5 + size * 0.45), 0.5)
	end
	if distance > 400 then
		return
	end

	ring(position + Vector3.new(0, 0.3, 0), color, 2, size * 9, 0.7)
	ring(position + Vector3.new(0, 0.4, 0), Color3.fromRGB(255, 200, 120), 1, size * 5, 0.45)
	flash(position + Vector3.new(0, 4, 0), color, size * 10, 6, 0.8)
	burst(position + Vector3.new(0, 1, 0), color, 25 + size * 4, 0.9, 30)

	-- Dust cloud
	local dust = burst(position + Vector3.new(0, 1, 0), Color3.fromRGB(150, 130, 150), 14, size * 1.6, 12, SMOKE)
	local emitter = dust:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter.LightEmission = 0
		emitter.Transparency = NumberSequence.new(0.4, 1)
		emitter.Lifetime = NumberRange.new(1.2, 2)
	end

	-- Flying rocks
	for _ = 1, math.floor(5 + size) do
		local s = math.random() * 1.2 + 0.5
		local rock = localPart({
			Size = Vector3.new(s, s * 0.8, s),
			Position = position + Vector3.new(math.random(-2, 2), 2, math.random(-2, 2)),
			Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(60, 50, 50),
			Anchored = false,
			CanCollide = true,
		})
		local direction = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		if direction.Magnitude < 0.05 then
			direction = Vector3.new(1, 0, 0)
		end
		rock.AssemblyLinearVelocity = direction.Unit * math.random(20, 45) + Vector3.new(0, math.random(35, 60), 0)
		rock.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
		TweenService:Create(rock, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.6), {
			Transparency = 1,
		}):Play()
		Debris:AddItem(rock, 2.8)
	end
end

function HANDLERS.HatchFX(position, color, rarityIndex)
	if distanceTo(position) > 300 then
		return
	end
	rarityIndex = rarityIndex or 1
	burst(position, color, 20 + rarityIndex * 8, 1 + rarityIndex * 0.15, 20)
	ring(position - Vector3.new(0, 1.5, 0), color, 2, 10 + rarityIndex * 2, 0.6)
	flash(position, color, 18 + rarityIndex * 4, 5, 1)
	if rarityIndex >= 5 then
		local pillar = localPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(120, 3, 3),
			CFrame = CFrame.new(position + Vector3.new(0, 58, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Neon,
			Color = color,
			Transparency = 0.2,
		})
		TweenService:Create(pillar, TweenInfo.new(1.6, Enum.EasingStyle.Quad), {
			Size = Vector3.new(120, 10, 10),
			Transparency = 1,
		}):Play()
		Debris:AddItem(pillar, 1.7)
	end
end

function HANDLERS.Collect(amount)
	UI.FloatText("+" .. Util.FormatMoney(amount), Color3.fromRGB(130, 255, 130), false)
	UI.CoinBurst()
	play("Collect", 0.4)
end

function HANDLERS.Speed(gain)
	UI.FloatText("+" .. gain .. " ⚡", Color3.fromRGB(130, 225, 255), true)
end

function HANDLERS.Grab()
	play("Grab", 0.6)
end

function HANDLERS.Deposit()
	play("Deposit", 0.35)
	UI.Popup("Delivered! ☄️", Color3.fromRGB(120, 255, 160))
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		burst(root.Position + Vector3.new(0, 3, 0), Color3.fromRGB(120, 255, 160), 25, 1, 16)
	end
end

function HANDLERS.Hatch(id, rarityName, mutation)
	local rarityIndex = Config.RarityIndex[rarityName] or 1
	if rarityIndex >= 3 or mutation then
		UI.HatchCard(id, rarityName, mutation)
		play("Hatch", 0.5)
		if rarityIndex >= 6 then
			shake(2, 0.6)
		end
	end
end

function HANDLERS.Discovered(id, rarityName)
	if not UI.MarkNew(id) then
		task.delay(0.3, function()
			UI.Popup("📖 NEW: " .. id, Util.GetRarity(rarityName).Color)
		end)
	end
end

function HANDLERS.Alarm()
	UI.Flash(Color3.fromRGB(255, 40, 40))
	play("Alarm", 0.5)
end

function HANDLERS.Bonk(position)
	bonkPopup(position)
end

function HANDLERS.Rebirth()
	UI.Flash(Color3.fromRGB(200, 140, 255))
	UI.Popup("🌟 REBIRTH! 🌟", Color3.fromRGB(220, 170, 255))
	play("Hatch", 0.6)
end

local function onKnockback(velocity, stunTime)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
	play("Ouch", 0.6)
	shake(3, 0.4)
	UI.Flash(Color3.fromRGB(255, 255, 255))
	task.delay(stunTime or 0.8, function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

function Effects.Init(ui)
	UI = ui
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalFX"
	fxFolder.Parent = workspace

	for name, id in SOUND_IDS do
		local sound = Instance.new("Sound")
		sound.Name = "Fx_" .. name
		sound.SoundId = id
		sound.Parent = SoundService
		sounds[name] = sound
	end

	Remotes.Knockback.OnClientEvent:Connect(onKnockback)
	Remotes.Effect.OnClientEvent:Connect(function(kind, ...)
		local handler = HANDLERS[kind]
		if handler then
			handler(...)
		end
	end)
end

function Effects.SetState(_state) end

return Effects
