-- Steal a Meteor: client entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = require(Controllers:WaitForChild("UI"))
local World = require(Controllers:WaitForChild("World"))
local Effects = require(Controllers:WaitForChild("Effects"))

UI.Init()
World.Init()
Effects.Init(UI)

Remotes.Sync.OnClientEvent:Connect(function(state)
	UI.Update(state)
	World.SetState(state)
	Effects.SetState(state)
end)

Remotes.Notify.OnClientEvent:Connect(function(text, color)
	UI.Toast(text, color)
end)

Remotes.Banner.OnClientEvent:Connect(function(data)
	UI.Banner(data)
end)
