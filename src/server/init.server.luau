--!strict

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

--

local wallstickFolder = Instance.new("Folder")
wallstickFolder.Name = "Wallstick"
wallstickFolder.Parent = workspace

PlayerScripts.setup()
setupCollisions()

Replication.listenServer()
