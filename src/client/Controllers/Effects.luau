-- Effects: knockback from bonks, camera shake from impacts, sounds and popups.

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

local function bonkPopup(position)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position + Vector3.new(0, 3, 0)
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(6, 0, 2, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.Text = "💥 BONK!"
	text.TextColor3 = Color3.fromRGB(255, 230, 80)
	text.TextStrokeTransparency = 0
	text.Parent = gui

	TweenService:Create(anchor, TweenInfo.new(0.9), { Position = anchor.Position + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(text, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1, function()
		anchor:Destroy()
	end)
end

local HANDLERS = {}

function HANDLERS.Impact(position, size)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local distance = (root.Position - position).Magnitude
	local reach = 60 + size * 12
	if distance < reach then
		shake((1 - distance / reach) * (1.5 + size * 0.4), 0.5)
	end
end

function HANDLERS.Collect(amount)
	UI.FloatText("+" .. Util.FormatMoney(amount), Color3.fromRGB(120, 255, 120), false)
	play("Collect", 0.4)
end

function HANDLERS.Speed(gain)
	UI.FloatText("+" .. gain .. " ⚡", Color3.fromRGB(120, 220, 255), true)
end

function HANDLERS.Grab()
	play("Grab", 0.6)
end

function HANDLERS.Deposit()
	play("Deposit", 0.35)
	UI.Popup("Delivered! ☄️", Color3.fromRGB(120, 255, 160))
end

function HANDLERS.Hatch(id, rarityName, mutation)
	local rarity = Util.GetRarity(rarityName)
	local rarityIndex = Config.RarityIndex[rarityName] or 1
	if rarityIndex >= 4 or mutation then
		local text = "🐣 " .. id .. "!"
		if mutation then
			text = "🐣 " .. string.upper(mutation) .. " " .. id .. "!"
		end
		UI.Popup(text, rarity.Color)
		play("Hatch", 0.5)
		if rarityIndex >= 6 then
			shake(2, 0.6)
		end
	end
end

function HANDLERS.Discovered(id, rarityName)
	-- Wait for the hatch popup to finish first
	task.delay(1.8, function()
		UI.Popup("📖 NEW: " .. id, Util.GetRarity(rarityName).Color)
	end)
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
	play("Ouch", 0.6)
	shake(2.5, 0.35)
	task.delay(stunTime or 0.8, function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

function Effects.Init(ui)
	UI = ui
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
