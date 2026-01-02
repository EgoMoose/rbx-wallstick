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

local function createReplicationFocus(player: Player, originCF: CFrame, parent: Instance)
	local part = Instance.new("Part")
	part.Name = `StreamingFocus_{player.UserId}`
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = originCF
	part.Parent = parent

	local attach = Instance.new("Attachment")
	attach.Parent = part

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Enabled = true
	alignPosition.MaxVelocity = 10_000_000
	alignPosition.Responsiveness = 200
	alignPosition.Position = originCF.Position
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attach
	alignPosition.Parent = part

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Enabled = true
	alignOrientation.MaxTorque = 10_000_000
	alignOrientation.Responsiveness = 200
	alignOrientation.CFrame = originCF
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attach
	alignOrientation.Parent = part

	if workspace.StreamingEnabled then
		player:AddReplicationFocus(part)
	end

	part:SetNetworkOwner(player)

	local connection
	connection = Players.PlayerRemoving:Connect(function(leavingPlayer)
		if leavingPlayer == player then
			connection:Disconnect()
			part:Destroy()
		end
	end)
end

local function setupWallstickModel()
	local wallstickModel = Instance.new("Model")
	wallstickModel.Name = "Wallstick"
	wallstickModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	wallstickModel.Parent = workspace

	local origin = Instance.new("Part")
	origin.Name = "Origin"
	origin.CFrame = CFrame.new(2000, 0, 0)
	origin.Size = Vector3.new(1, 1, 1)
	origin.Transparency = 1
	origin.Anchored = true
	origin.CanCollide = false
	origin.CanTouch = false
	origin.CanQuery = false
	origin.Parent = wallstickModel

	local streamingFoci = Instance.new("Folder")
	streamingFoci.Name = "StreamingFoci"
	streamingFoci.Parent = wallstickModel

	Players.PlayerAdded:Connect(function(player)
		createReplicationFocus(player, origin.CFrame, streamingFoci)
	end)
end

--

PlayerScripts.setup()
setupCollisions()
setupWallstickModel()

Replication.listenServer()
