--!strict

local Players = game:GetService("Players") :: Players
local RunService = game:GetService("RunService") :: RunService
local TweenService = game:GetService("TweenService") :: TweenService

local TypedRemote = require(game.ReplicatedStorage.SharedPackages.TypedRemote)

local Replication = {}

type ReplicationFrame = {
	part: BasePart,
	offset: CFrame,
}

type ClientReplicationFrame = ReplicationFrame & {
	fromOffset: CFrame,
	lerpOffset: CFrame,
	receivedAt: number,
}

-- stylua: ignore start
local syncRemote = TypedRemote.func("SyncRemote", script) :: TypedRemote.Function<(), ({ [Player]: ReplicationFrame })>
local replicatorRemote = TypedRemote.event("ReplicatorRemote", script) :: TypedRemote.Event<BasePart?, CFrame?, Player?>
-- stylua: ignore end

Replication.ENABLED = true
Replication.REPLICATE_DEBOUNCE_TIME = 0.2

function Replication.send(part: BasePart, offset: CFrame)
	assert(RunService:IsClient(), "This API can only be called from the client")
	if Replication.ENABLED then
		replicatorRemote:FireServer(part, offset)
	end
end

function Replication.listenServer()
	assert(RunService:IsServer(), "This API can only be called from the server")

	if not Replication.ENABLED then
		return
	end

	local framesByPlayer: { [Player]: ReplicationFrame } = {}

	Players.PlayerRemoving:Connect(function(player)
		framesByPlayer[player] = nil
		replicatorRemote:FireAllClients(nil, nil, player)
	end)

	replicatorRemote.OnServerEvent:Connect(function(player, part, offset)
		if part and offset then
			framesByPlayer[player] = {
				part = part,
				offset = offset,
			}
		else
			framesByPlayer[player] = nil
		end

		replicatorRemote:FireAllClients(part, offset, player)
	end)

	syncRemote.OnServerInvoke = function(_player)
		return framesByPlayer
	end
end

function Replication.listenClient()
	assert(RunService:IsClient(), "This API can only be called from the client")

	if not Replication.ENABLED then
		return
	end

	task.spawn(function()
		local clientFrameByPlayer: { [Player]: ClientReplicationFrame } = {}
		for player, frame in syncRemote:InvokeServer() do
			clientFrameByPlayer[player] = {
				part = frame.part,
				offset = frame.offset,
				fromOffset = frame.offset,
				lerpOffset = frame.offset,
				receivedAt = os.clock(),
			}
		end

		replicatorRemote.OnClientEvent:Connect(function(part, offset, sentPlayer)
			local player = sentPlayer :: Player

			if part and offset then
				local now = os.clock()
				local frame: ClientReplicationFrame = clientFrameByPlayer[player]
					or {
						part = part,
						offset = offset,
						fromOffset = offset,
						lerpOffset = offset,
						receivedAt = now,
					}

				local worldCF = frame.part.CFrame * frame.lerpOffset
				local fromOffset = part.CFrame:ToObjectSpace(worldCF)

				clientFrameByPlayer[player] = {
					part = part,
					offset = offset,
					fromOffset = fromOffset,
					lerpOffset = fromOffset,
					receivedAt = now,
				}
			else
				clientFrameByPlayer[player] = nil
			end
		end)

		RunService.PreRender:Connect(function(_dt)
			local now = os.clock()
			for player, frame in clientFrameByPlayer do
				if player == Players.LocalPlayer then
					continue
				end

				local character = player.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart

				if rootPart and frame.part then
					local dt = now - frame.receivedAt
					local alpha = TweenService:GetValue(
						math.min(1, dt / Replication.REPLICATE_DEBOUNCE_TIME),
						Enum.EasingStyle.Linear,
						Enum.EasingDirection.Out
					)

					frame.lerpOffset = frame.fromOffset:Lerp(frame.offset, alpha)

					rootPart.CFrame = frame.part.CFrame * frame.lerpOffset
					rootPart.Anchored = true
				end
			end
		end)
	end)
end

return Replication
