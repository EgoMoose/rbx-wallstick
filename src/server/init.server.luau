--!strict

local Players = game:GetService("Players") :: Players
local PhysicsService = game:GetService("PhysicsService") :: PhysicsService

local PlayerScripts = require(script.PlayerScripts)
local Replication = require(game.ReplicatedStorage.Wallstick.Replication)

-- Private

local function setupCollisions()
	PhysicsService:RegisterCollisionGroup("WallstickCollision")
	PhysicsService:RegisterCollisionGroup("WallstickNoCollision")

	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		PhysicsService:CollisionGroupSetCollidable(group.name, "WallstickCollision", false)
		PhysicsService:CollisionGroupSetCollidable(group.name, "WallstickNoCollision", false)
	end

	PhysicsService:CollisionGroupSetCollidable("WallstickCollision", "WallstickCollision", true)
end

local function setupWallstickModel()
	local wallstickModel = Instance.new("Model")
	wallstickModel.Name = "Wallstick"
	wallstickModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	wallstickModel.Parent = workspace

	local wallstickOrigin = Instance.new("Part")
	wallstickOrigin.Name = "Origin"
	wallstickOrigin.CFrame = CFrame.new(2000, 0, 0)
	wallstickOrigin.Size = Vector3.new(1, 1, 1)
	wallstickOrigin.Transparency = 1
	wallstickOrigin.Anchored = true
	wallstickOrigin.CanCollide = false
	wallstickOrigin.CanTouch = false
	wallstickOrigin.CanQuery = false
	wallstickOrigin.Parent = wallstickModel

	if workspace.StreamingEnabled then
		Players.PlayerAdded:Connect(function(player)
			player:AddReplicationFocus(wallstickOrigin)
		end)
	end
end

--

PlayerScripts.setup()
setupCollisions()
setupWallstickModel()

Replication.listenServer()
