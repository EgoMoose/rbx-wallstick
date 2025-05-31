--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedPackages = ReplicatedStorage.SharedPackages
local Trove = require(SharedPackages.Trove)

local Replication = require(script.Replication)
local GravityCamera = require(script.GravityCamera)
local RotationSpring = require(script.RotationSpring)
local CharacterHelper = require(script.CharacterHelper)

local globalRenderTicket = 0

local CLASS_NAMES_TO_CONVERT = {
	["Seat"] = { ClassName = "Part" },
	["VehicleSeat"] = { ClassName = "Part" },
	["SpawnLocation"] = { ClassName = "Part" },

	["Terrain"] = {
		ClassName = "Part",
		Size = Vector3.new(1, 1, 1),
		CanCollide = false,
	},
}

-- Class

local WallstickClass = {}
WallstickClass.__index = WallstickClass
WallstickClass.ClassName = "Wallstick"

-- Types

export type Options = {
	parent: Instance,
	origin: CFrame,

	retainWorldVelocity: boolean,

	camera: {
		tilt: boolean,
		spin: boolean,
	},
}

export type Wallstick = typeof(setmetatable(
	{} :: {
		trove: Trove.Trove,

		options: Options,
		fallStartHeight: number,
		replicateTick: number,

		part: BasePart,
		normal: Vector3,

		cameraUpSpring: RotationSpring.RotationSpring,

		geometry: Folder,
		cachedCollisionGeometry: { [BasePart]: BasePart },

		real: CharacterHelper.RealCharacter,
		fake: CharacterHelper.FakeCharacter,
	},
	WallstickClass
))

-- Constructors

function WallstickClass.new(options: Options): Wallstick
	local self = setmetatable({}, WallstickClass) :: Wallstick

	self.trove = Trove.new()

	self.options = table.clone(options)
	self.fallStartHeight = -1
	self.replicateTick = -1

	self.part = workspace.Terrain
	self.normal = Vector3.yAxis

	self.cameraUpSpring = RotationSpring.new(1, 3, CFrame.identity, CFrame.identity)

	self.geometry = Instance.new("Folder")
	self.geometry.Name = "Geometry"
	self.geometry.Parent = self.options.parent
	self.trove:Add(self.geometry)

	self.cachedCollisionGeometry = {}

	self.real = CharacterHelper.real(Players.LocalPlayer)
	self.fake = CharacterHelper.fake(Players.LocalPlayer)

	self.trove:Add(CharacterHelper.applyCollisionGroup(self.real.character, "WallstickNoCollision"))

	self.real.humanoid.EvaluateStateMachine = false
	self.real.rootPart.Anchored = false

	self.fake.character.Parent = self.options.parent
	self.trove:Add(self.fake.character)

	CharacterHelper.setMyPerformer(self.real.character, self.fake.character)

	self:set(workspace.Terrain, Vector3.yAxis)

	self.trove:Add(self.fake.humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Freefall then
			self.fallStartHeight = self.fake.rootPart.Position.Y
		end
	end))

	self.trove:Add(RunService.PostSimulation:Connect(function(dt)
		self:_stepPhysics(dt)
	end))

	globalRenderTicket = globalRenderTicket + 1

	local renderBeforeCameraBindKey = "WallstickBeforeCamera" .. tostring(globalRenderTicket)
	local renderCharacterBindKey = "WallstickCharacter" .. tostring(globalRenderTicket)

	RunService:BindToRenderStep(renderBeforeCameraBindKey, Enum.RenderPriority.Camera.Value - 1, function(dt)
		self:_stepRenderBeforeCamera(dt)
	end)

	RunService:BindToRenderStep(renderCharacterBindKey, Enum.RenderPriority.Character.Value, function(dt)
		self:_stepRenderCharacter(dt)
	end)

	self.trove:Add(function()
		RunService:UnbindFromRenderStep(renderBeforeCameraBindKey)
		RunService:UnbindFromRenderStep(renderCharacterBindKey)

		GravityCamera.setSpinPart(workspace.Terrain)
		GravityCamera.setUpVector(Vector3.yAxis)

		CharacterHelper.setMyPerformer(self.real.character, nil)

		self.real.humanoid.EvaluateStateMachine = true
		self.real.rootPart.Anchored = false
	end)

	return self
end

-- Private

local function fromToRotation(from: Vector3, to: Vector3, backupUnitAxis: Vector3?)
	local dot = from:Dot(to)
	if dot < -0.99999 then
		return if backupUnitAxis
			then CFrame.fromAxisAngle(backupUnitAxis, math.pi)
			else CFrame.fromRotationBetweenVectors(from, to)
	end
	local qv = from:Cross(to)
	local qw = math.sqrt(from:Dot(from) * to:Dot(to)) + dot
	return CFrame.new(0, 0, 0, qv.X, qv.Y, qv.Z, qw)
end

function WallstickClass._getOriginCFrame(self: Wallstick)
	return self.options.origin * fromToRotation(self.normal, Vector3.yAxis, Vector3.xAxis)
end

function WallstickClass._getCalculatedRealRootCFrame(self: Wallstick)
	local originCF = self:_getOriginCFrame()
	local offset = originCF:ToObjectSpace(self.fake.rootPart.CFrame)
	return self.part.CFrame * offset
end

function WallstickClass._updateCollisionGeometry(self: Wallstick)
	local newCachedCollisionGeometry = {}

	local originCF = self:_getOriginCFrame()
	local realRootCF = self.real.rootPart.CFrame
	local stickCFInv = self.part.CFrame:Inverse()

	local colliderBoxSizeHalf = Vector3.new(10, 10, 10)

	-- stylua: ignore
	-- selene: allow (deprecated)
	local parts = workspace:FindPartsInRegion3WithIgnoreList(Region3.new(
		realRootCF.Position - colliderBoxSizeHalf,
		realRootCF.Position + colliderBoxSizeHalf
	), {self.real.character, self.options.parent} :: {Instance}, 1000) :: {BasePart}

	for _, realPart in parts do
		local collisionPart: BasePart
		local foundPart = self.cachedCollisionGeometry[realPart]

		if not foundPart then
			local properties = CLASS_NAMES_TO_CONVERT[realPart.ClassName] :: { [string]: any }

			if properties then
				local convertedPart = Instance.new(properties.ClassName) :: any
				for key, value in properties do
					if key ~= "ClassName" then
						(convertedPart :: any)[key] = value
					end
				end

				collisionPart = convertedPart :: BasePart
			else
				collisionPart = realPart:Clone()
				collisionPart.Name = "Part"
				collisionPart:ClearAllChildren()
			end

			collisionPart.CollisionGroup = "WallstickCollision"
			collisionPart.Parent = self.geometry
		else
			collisionPart = foundPart
		end

		collisionPart.Anchored = true
		collisionPart.CastShadow = false
		collisionPart.AssemblyLinearVelocity = Vector3.zero
		collisionPart.AssemblyAngularVelocity = Vector3.zero
		collisionPart.CFrame = originCF * (stickCFInv * realPart.CFrame)
		collisionPart.Size = realPart.Size
		collisionPart.CanCollide = realPart.CanCollide
		collisionPart.Transparency = 1

		self.cachedCollisionGeometry[realPart] = collisionPart
		newCachedCollisionGeometry[realPart] = collisionPart
	end

	for realPart, collisionPart in self.cachedCollisionGeometry do
		if not newCachedCollisionGeometry[realPart] then
			self.cachedCollisionGeometry[realPart] = nil
			collisionPart:Destroy()
		end
	end
end

function WallstickClass._trySendReplication(self: Wallstick, force: boolean)
	local t = os.clock()
	if force or t - self.replicateTick >= Replication.REPLICATE_DEBOUNCE_TIME then
		self.replicateTick = t

		local realRootCFrame = self:_getCalculatedRealRootCFrame()
		local offset = self.part.CFrame:ToObjectSpace(realRootCFrame)

		Replication.send(self.part, offset)
	end
end

function WallstickClass._stepRenderBeforeCamera(self: Wallstick, dt: number)
	if self.options.camera.tilt then
		self.cameraUpSpring:step(dt)

		local upVector = self.cameraUpSpring:getPosition().YVector
		local worldUpVector = self.part.CFrame:VectorToWorldSpace(upVector)

		GravityCamera.setUpVector(worldUpVector)
	end
end

function WallstickClass._stepRenderCharacter(self: Wallstick, _dt: number)
	local realRootCF = self:_getCalculatedRealRootCFrame()
	local rootCameraOffset = realRootCF:ToObjectSpace(workspace.CurrentCamera.CFrame)
	local geometryCameraCF = self.fake.rootPart.CFrame * rootCameraOffset

	self.fake.humanoid.Jump = self.real.humanoid.Jump
	self.fake.humanoid:Move(GravityCamera.getMoveVector(geometryCameraCF), false)

	if GravityCamera.getRotationType() == Enum.RotationType.CameraRelative then
		local right = GravityCamera.getMoveVector(geometryCameraCF, Vector3.xAxis)
		local rotation = CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis)
		self.fake.alignOrientation.CFrame = rotation
		self.fake.alignOrientation.Enabled = true
	else
		self.fake.alignOrientation.Enabled = false
	end
end

function WallstickClass._stepPhysics(self: Wallstick, _dt: number)
	if self.fake.rootPart.Position.Y <= workspace.FallenPartsDestroyHeight then
		self:Destroy()
		return
	end

	local realRootCFrame = self:_getCalculatedRealRootCFrame()

	self.real.rootPart.CFrame = realRootCFrame
	self.real.alignPosition.Position = realRootCFrame.Position
	self.real.alignOrientation.CFrame = realRootCFrame

	self:_updateCollisionGeometry()
	self:_trySendReplication(false)
end

-- Public

function WallstickClass.getPart(self: Wallstick)
	return self.part
end

function WallstickClass.getNormal(self: Wallstick, worldSpace: boolean)
	if worldSpace then
		return self.part.CFrame:VectorToWorldSpace(self.normal)
	end
	return self.normal
end

function WallstickClass.getFallDistance(self: Wallstick)
	if self.fake.humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		return self.fake.rootPart.Position.Y - self.fallStartHeight
	end
	return 0
end

function WallstickClass.set(self: Wallstick, part: BasePart, normal: Vector3, teleportCF: CFrame?)
	local prevPart = self.part
	local prevPartCF = prevPart.CFrame
	local worldUpCFrame = prevPartCF:ToWorldSpace(self.cameraUpSpring:getPosition())
	local worldUpVelocity = prevPartCF:VectorToWorldSpace(self.cameraUpSpring:getVelocity())

	local partCF = part.CFrame
	local newWorldNormal = partCF:VectorToWorldSpace(normal)
	local worldGoalUpCFrame = fromToRotation(worldUpCFrame.YVector, newWorldNormal, worldUpCFrame.XVector)
		* worldUpCFrame

	self.cameraUpSpring:setGoal(partCF:ToObjectSpace(worldGoalUpCFrame))
	self.cameraUpSpring:setPosition(partCF:ToObjectSpace(worldUpCFrame))
	self.cameraUpSpring:setVelocity(partCF:VectorToObjectSpace(worldUpVelocity))

	self.part = part
	self.normal = normal

	if self.options.camera.spin then
		GravityCamera.setSpinPart(self.part)
	end

	local originCF = self:_getOriginCFrame()
	local targetCF = originCF * self.part.CFrame:ToObjectSpace(teleportCF or self.real.rootPart.CFrame)
	local sphericalArc = fromToRotation(targetCF.YVector, Vector3.yAxis, targetCF.XVector)
	local resultCF = (sphericalArc * targetCF.Rotation) + targetCF.Position

	local fakeRoot = self.fake.rootPart
	local localRootVelocity = fakeRoot.CFrame:VectorToObjectSpace(fakeRoot.AssemblyLinearVelocity)
	local localRootAngularVelocity = fakeRoot.CFrame:VectorToObjectSpace(fakeRoot.AssemblyAngularVelocity)

	fakeRoot.CFrame = resultCF

	if self.options.retainWorldVelocity then
		fakeRoot.AssemblyLinearVelocity = targetCF:VectorToWorldSpace(localRootVelocity)
		fakeRoot.AssemblyAngularVelocity = targetCF:VectorToWorldSpace(localRootAngularVelocity)
	else
		fakeRoot.AssemblyLinearVelocity = resultCF:VectorToWorldSpace(localRootVelocity)
		fakeRoot.AssemblyAngularVelocity = resultCF:VectorToWorldSpace(localRootAngularVelocity)
	end

	self.fallStartHeight = fakeRoot.Position.Y

	self:_updateCollisionGeometry()

	if self.part ~= prevPart then
		self:_trySendReplication(true)
	end
end

function WallstickClass.setAndPivot(self: Wallstick, part: BasePart, normal: Vector3, position: Vector3)
	local worldNormal = part.CFrame:VectorToWorldSpace(normal)
	local realRootCF = self:_getCalculatedRealRootCFrame()
	local heightAdjust = (realRootCF.Position - position):Dot(worldNormal)

	local floorRootCF = realRootCF * CFrame.new(0, -heightAdjust, 0)
	local newRotation = fromToRotation(floorRootCF.YVector, worldNormal, floorRootCF.XVector) * floorRootCF.Rotation
	local teleportCF = CFrame.new(position) * newRotation * CFrame.new(0, heightAdjust, 0)

	return self:set(part, normal, teleportCF)
end

function WallstickClass.setAndTeleport(self: Wallstick, part: BasePart, normal: Vector3, position: Vector3)
	local worldNormal = part.CFrame:VectorToWorldSpace(normal)
	local realRootCF = self:_getCalculatedRealRootCFrame()
	local heightAdjust = self.real.rootPart.Size.Y / 2 + self.real.humanoid.HipHeight

	local floorRootCF = realRootCF * CFrame.new(0, -heightAdjust, 0)
	local newRotation = fromToRotation(floorRootCF.YVector, worldNormal, floorRootCF.XVector) * floorRootCF.Rotation
	local teleportCF = CFrame.new(position) * newRotation * CFrame.new(0, heightAdjust, 0)

	return self:set(part, normal, teleportCF)
end

function WallstickClass.Destroy(self: Wallstick)
	self.trove:Destroy()
end

--

return WallstickClass
