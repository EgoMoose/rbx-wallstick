--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedPackages = ReplicatedStorage.SharedPackages
local RaycastHelper = require(SharedPackages.RaycastHelper)

local WallstickClass = require(ReplicatedStorage.Wallstick)

local function onCharacterAdded(character: Model)
	local wallstick = WallstickClass.new({
		parent = workspace:WaitForChild("Wallstick"),
		origin = CFrame.new(2000, 0, 0),
		retainWorldVelocity = true,
		camera = {
			tilt = true,
			spin = true,
		},
	})

	local humanoid = character and character:WaitForChild("Humanoid") :: Humanoid
	local hrp = humanoid and humanoid.RootPart :: BasePart

	local simulationConnection = RunService.PreSimulation:Connect(function(_dt)
		if wallstick:getFallDistance() < -50 then
			wallstick:set(workspace.Terrain, Vector3.yAxis)
			return
		end

		local rayParams = RaycastHelper.params({
			filterType = Enum.RaycastFilterType.Exclude,
			instances = { character :: Instance },
		})

		local hipHeight = humanoid.HipHeight
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			hipHeight = 2
		end

		local hrpCF = hrp.CFrame
		local result = RaycastHelper.raycast({
			origin = hrpCF.Position,
			direction = -(hipHeight + hrp.Size.Y / 2 + 0.1) * hrpCF.YVector,
			rayParams = rayParams,
		})

		if result then
			local stickPart = (result.Instance :: BasePart).AssemblyRootPart
			local stickNormal = stickPart.CFrame:VectorToObjectSpace(result.Normal)

			wallstick:setAndPivot(stickPart, stickNormal, result.Position)
		end
	end)

	humanoid.Died:Wait()
	simulationConnection:Disconnect()
	wallstick:Destroy()
end

if Players.LocalPlayer.Character then
	onCharacterAdded(Players.LocalPlayer.Character)
end

Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
