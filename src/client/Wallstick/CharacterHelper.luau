--!strict

local Players = game:GetService("Players")

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local RbxCharacterSounds = PlayerScripts:WaitForChild("RbxCharacterSounds")
local CharacterSoundsController = require(RbxCharacterSounds:WaitForChild("Controller")) :: any

local STRIP: { [string]: boolean } = {
	["Part"] = true,
	["MeshPart"] = true,
	["Motor6D"] = true,
	["Humanoid"] = true,
	["Attachment"] = true,
}

type BaseCharacter = {
	character: Model,
	rootPart: BasePart,
	humanoid: Humanoid,
}

export type RealCharacter = BaseCharacter & {
	alignPosition: AlignPosition,
	alignOrientation: AlignOrientation,
}

export type FakeCharacter = BaseCharacter & {
	alignOrientation: AlignOrientation,
}

local CharacterHelper = {}

-- Private

local function getCharacter(player: Player): Model?
	local character = player.Character
	local humanoid = character and character:WaitForChild("Humanoid")
	local root = humanoid and (humanoid :: Humanoid).RootPart

	if character and humanoid and root then
		return character
	end

	return nil
end

local function stripCopy(character: Model): Model
	local copy = nil
	local archivable = character.Archivable

	character.Archivable = true
	copy = character:Clone()
	character.Archivable = archivable

	for _, part in copy:GetDescendants() do
		if not STRIP[part.ClassName] then
			part:Destroy()
		elseif part:IsA("BasePart") then
			part.Transparency = 1
		end
	end

	local humanoid = copy:WaitForChild("Humanoid") :: Humanoid
	humanoid:ClearAllChildren()
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

	return copy
end

local function createFakeCharacter(player: Player): Model?
	local character = getCharacter(player)
	if character then
		local copy = stripCopy(character)
		CharacterHelper.applyCollisionGroup(copy, "WallstickCollision")
		return copy
	end
	return nil
end

local function packageCharacter(character: Model?)
	local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
	local rootPart = humanoid and humanoid.RootPart

	assert(character and humanoid and rootPart, "Failed to package character.")

	return {
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
	}
end

-- Public

function CharacterHelper.applyCollisionGroup(character: Model, collisionGroup: string)
	local prevGroup = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			prevGroup[part] = part.CollisionGroup
			part.CollisionGroup = collisionGroup
		end
	end

	return function()
		for part, group in prevGroup do
			part.CollisionGroup = group
		end
	end
end

function CharacterHelper.real(player: Player): RealCharacter
	local character = getCharacter(player)
	local packaged = packageCharacter(character) :: RealCharacter

	local rootAttach = packaged.rootPart:WaitForChild("RootAttachment") :: Attachment

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Enabled = true
	alignPosition.MaxVelocity = 10_000_000
	alignPosition.Responsiveness = 200
	alignPosition.Position = Vector3.zero
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = rootAttach
	alignPosition.Parent = packaged.rootPart

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Enabled = true
	alignOrientation.MaxTorque = 10_000_000
	alignOrientation.Responsiveness = 200
	alignOrientation.CFrame = CFrame.identity
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = rootAttach
	alignOrientation.Parent = packaged.rootPart

	packaged.alignPosition = alignPosition
	packaged.alignOrientation = alignOrientation

	return packaged
end

function CharacterHelper.fake(player: Player): FakeCharacter
	local character = createFakeCharacter(player)
	local packaged = packageCharacter(character) :: FakeCharacter

	local rootAttach = packaged.rootPart:WaitForChild("RootAttachment") :: Attachment

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Enabled = false
	alignOrientation.MaxTorque = 10_000_000
	alignOrientation.Responsiveness = 200
	alignOrientation.CFrame = CFrame.identity
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = rootAttach
	alignOrientation.Parent = packaged.rootPart

	packaged.alignOrientation = alignOrientation

	return packaged
end

function CharacterHelper.setMyPerformer(real: Model, fake: Model?)
	CharacterSoundsController.setPerformer(Players.LocalPlayer, fake)

	local animate = real:WaitForChild("Animate")
	local animateController = require(animate:WaitForChild("Controller")) :: any

	local humanoid = if fake then fake:WaitForChild("Humanoid") else real:WaitForChild("Humanoid")
	animateController.matchAnimate(humanoid)
end

--

return CharacterHelper
