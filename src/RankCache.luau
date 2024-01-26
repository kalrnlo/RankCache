--!optimize 2
--!native
--!strict

-- RankCache
-- A rewritten version of Whitehill Groups RankCache designed to overtime refresh the cache automatically, 
-- so players arent forced to rejoin to get their rank refreshed. This version also has the ability to register
-- callbacks for whenever a players rank changes in a group or in litterally any group with GlobalOnRankChanged.
-- @Kalrnlo, @TheCakeChicken
-- 25/1/2024

local GroupService = game:GetService("GroupService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

type OnRankChanged = ((Callback: RankChangedCallback) -> () -> ()) & ((GroupId: number, Callback: RankChangedCallback) -> () -> ())

export type GlobalRankChangedCallback = (GroupId: number, Player: Player, NewRank: number, OldRank: number) -> ()

export type RankChangedCallback = (Player: Player, NewRank: number, OldRank: number) -> ()

type RankCacheConfig = {
	GroupRefreshRate: number,
	DefualtGroupId: number,
	[string] = nil
}

-- GroupBufferFormat 
-- 1 byte for rank, rest is role string
-- {[1] = LastTimeChecked, [2] = {[GroupId] = {GroupBuffer}}}
type PlayerData = {
	["1"]: number,
	["2"]: {buffer}
}

-- [1] = Callback
-- [2] == 1 = Specific, 2 = Global
-- [3] == OptionalGroupIdSpeciferParam
type CallbackData = {
	["1"]: RankChangedCallback | GlobalRankChangedCallback,
	["2"]: number,
	["3"]: number?,
}

-- {[PlayerPosition] = PlayerData}
local PlayerCache = table.create(Players.MaxPlayers) :: {[number]: PlayerData}
local PlayerPositions = table.create(Players.MaxPlayers) :: {Player}
-- {[UserId] = {Thread}}
local PlayerWaitingThreads = {} :: {[number]: {thread}}
local RankChangedCallbacks = {} :: {CallbackData}
local FreeThreads = {} :: {thread}
local HasInitiated = false
local Config = {
	GroupRefreshRate = 120,
	DefualtGroupId = 0,
} :: RankCacheConfig

-- Fast Spawner taken from: https://github.com/red-blox/Util/blob/main/libs/Spawn/Spawn.luau
local function RunCallback(Callback, Thread, ...)
	Callback(...)
	table.insert(FreeThreads, Thread)
end

local function Yielder()
	while true do
		RunCallback(coroutine.yield())
	end
end

local function Spawn<T...>(Callback: (T...) -> (), ...: T...)
	local Thread
	if #FreeThreads > 0 then
		Thread = FreeThreads[#FreeThreads]
		FreeThreads[#FreeThreads] = nil
	else
		Thread = coroutine.create(Yielder)
		coroutine.resume(Thread)
	end

	task.spawn(Thread, Callback, Thread, ...)
end

local function GetCurrentGroups(Player: Player): {buffer}
	local Sucess, Groups = pcall(function(UserId: number)
		return GroupService:GetGroupsAsync(UserId)
	end, Player.UserId)
	
	if Sucess then
		local NewGroupData = {} :: PlayerData
		
		for _, Group in Groups do
			local GroupBuffer = buffer.create(1 + #Group.Role)
			buffer.writestring(GroupBuffer, 1, Group.Role)
			buffer.writeu8(GroupBuffer, 0, Group.Rank)

			NewGroupData[Group.Id] = GroupBuffer
		end
		return NewGroupData
	else
		warn(`[RankCache] GetCurrentGroups couldn't get groups for Player {Player.UserId}\n\tGetGroupsAsyncError: {Groups}`)
		return nil
	end
end

local function RunCallbacks(Player: Player, NewGroupData: {buffer}, OldGroupData: {buffer})
	local Diffrence = math.abs(#NewGroupData - #OldGroupData) 
	-- 8 bytes for groupid, 1 byte for new rank, 1 byte for old rank
	local DataBuffer = buffer.create((Diffrence + #OldGroupData) * 10)
	local GroupIdsChecked = table.create(#NewGroupData)
	local Offset = 0
	local Index = 1

	for GroupId, GroupBuffer in NewGroupData do 
		local OldGroupBuffer = OldGroupData[GroupId]
		local OldRank = if OldGroupBuffer then buffer.readu8(OldGroupBuffer, 0) else 0
		local NewRank = buffer.readu8(GroupBuffer, 0)

		GroupIdsChecked[Index] = GroupId
		Index += 1

		if NewRank ~= OldRank then
			buffer.writef64(DataBuffer, Offset, GroupId)
			Offset += 9
			buffer.writeu8(DataBuffer, Offset, NewRank)
			Offset += 1
			buffer.writeu8(DataBuffer, Offset, OldRank)
			Offset += 1
		else
			buffer.writef64(DataBuffer, Offset, 0)
			Offset += 1	
		end
	end

	for GroupId, GroupBuffer in OldGroupData do
		if table.find(GroupIdsChecked, GroupId) then continue end

		buffer.writef64(DataBuffer, Offset, GroupId)
		Offset += 9
		buffer.writeu8(DataBuffer, Offset, 0)
		Offset += 1
		buffer.writeu8(DataBuffer, Offset, buffer.readu8(GroupBuffer, 0))
		Offset += 1
	end

	local ReadOffset = 0

	for Index = 1, GroupIdCount do
		local GroupId = buffer.readf64(DataBuffer, ReadOffset)
		ReadOffset += 9 

		if GroupId == 0 then continue end
		local NewRank = buffer.readu8(DataBuffer, ReadOffset)
		ReadOffset += 1
		local OldRank = buffer.readu8(DataBuffer, ReadOffset)
		ReadOffset += 1

		for _, CallbackData in RankChangedCallbacks do
			if CallbackData[3] == GroupId then
				Spawn(Callback[1], Player, NewRank, OldRank)
			elseif CallbackData[2] == 2 then
				Spawn(Callback[1], GroupId, Player, NewRank, OldRank)
			end
		end
	end
end

local function RefreshPlayerGroups(Player: Player, PlayerPosition: number, GroupData: {buffer})
	local NewGroupData = GetCurrentGroups(Player)
	
	if Groups then
		Spawn(RunCallbacks, Player, NewGroupData, GroupData)
		PlayerCache[PlayerPosition][2] = NewGroupData
		return true
	else
		return false
	end
end

local function OnPostSimulation(DeltaTime: number)
	for Position, PlayerData in PlayerCache do
		local Diffrence = (os.clock() - DeltaTime) - PlayerData[1]		

		if Diffrence >= Config.GroupRefreshRate then
			PlayerData[1] = os.clock()
			Spawn(
				RefreshPlayerGroups,
				PlayerPositions[Position],
				Position,
				PlayerData[2]
			)
		end
	end
end

local function OnPlayerRemoving(Player: Player)
	for Position, PlayerAtPosition in PlayerPositions do
		if PlayerAtPosition == Player then
			PlayerPositions[Position] = nil
			break
		end
	end
end

local function OnPlayerAdded(Player: Player)
	local ThreadsWaitingForPlayer = ThreadsWaitingForPlayers[Player.UserId]
	local PlayerData = table.create(2)
	local PlayerPosition

	for Position, PlayerAtPosition in PlayerPositions do
		if not PlayerAtPosition then
			PlayerPositions[Position] = Player
			PlayerPosition = Position
			break
		end
	end

	PlayerData[2] = GetCurrentGroups(Player)
	PlayerData[1] = os.clock()
	PlayerCache[PlayerPosition] = PlayerData

	if ThreadsWaitingForPlayer then
		for _, Thread in ThreadsWaitingForPlayer do
			task.spawn(Thread, PlayerData, PlayerPosition)
		end
		ThreadsWaitingForPlayers[Player.UserId] = nil
	end
	-- this is here just incase if the player doesnt get removed by the player removing callback
	-- never had an issue with that, but it might happen so this is here
	if not Player:IsDescendantOf(Players) then
		PlayerPositions[PlayerPosition] = nil
	end
end

-- Returns PlayerData, PlayerPosition
local function GetPlayerData(Player: Player): (PlayerData?, number)
	local PlayerPosition = table.find(PlayerPositions, Player)

	if PlayerPosition then
		return PlayerCache[PlayerPosition], PlayerPosition 
	elseif Player:IsDescendantOf(Players) then
		local PlayerThreads = PlayerWaitingThreads[Player.UserId]

		if PlayerThreads then
			table.insert(PlayerThreads, coroutine.running())
		else
			PlayerWaitingThreads[Player.UserId] = table.create(1, coroutine.running())
		end
		return coroutine.yield()
	else
		return nil, -1
	end
end

local function GetRoleAndRank(Player: Player, GroupId: number?): (string, number)
	local GroupId = if GroupId then GroupId else Config.DefualtGroupId
	local PlayerData = GetPlayerData(Player)
	
	if PlayerData then
		local GroupBuffer = PlayerData[2][GroupId]

		if GroupBuffer then
			local Role = buffer.readstring(GroupBuffer, 1, buffer.len(GroupBuffer) - 1)
			local Rank = buffer.readu8(GroupBuffer, 0)

			return Role, Rank
		end
	end

	return "Guest", 0
end

local OnRankChanged: OnRankChanged = function(CallbackOrGroupId, Callback)
	local GroupId = if typeof(CallbackOrGroupId) == "function" then Config.DefualtGroupId else CallbackOrGroupId
	local Callback = if typeof(CallbackOrGroupId) == "function" then CallbackOrGroupId else Callback
	local IsGroupIdNotDefualt = GroupId ~= Config.DefualtGroupId
			
	local CallbackData = table.create(if IsGroupIdNotDefualt then 3 else 2) :: CallbackData
	CallbackData[1] = Callback
	CallbackData[2] = 1

	if IsGroupIdNotDefualt then
		CallbackData[3] = GroupId
	end
	table.insert(RankChangedCallbacks, CallbackData)

	return function()
		local Index = table.find(RankChangedCallbacks, CallbackData)
		table.remove(RankChangedCallbacks, Index)
	end
end

local function GlobalOnRankChanged(Callback: GlobalRankChangedCallback)
	local CallbackData = table.create(2) :: CallbackData
	CallbackData[1] = Callback
	CallbackData[2] = 2

	return function()
		local Index = table.find(RankChangedCallbacks, CallbackData)
		table.remove(RankChangedCallbacks, Index)
	end
end

local function IsInGroup(Player: Player, GroupId: number?): boolean
	local GroupId = if GroupId then GroupId else Config.DefualtGroupId
	local PlayerData = GetPlayerData(Player)
		
	if PlayerData then
		local GroupBuffer = PlayerData[2][GroupId]
	
		if GroupBuffer then
			return buffer.readu8(GroupBuffer, 0) > 0
		end
	end

	return false
end

local function GetRole(Player: Player, GroupId: number?): string
	local GroupId = if GroupId then GroupId else Config.DefualtGroupId
	local PlayerData = GetPlayerData(Player)
		
	if PlayerData then
		local GroupBuffer = PlayerData[2][GroupId]
	
		if GroupBuffer then
			return buffer.readstring(GroupBuffer, 1, buffer.len(GroupBuffer) - 1)
		end
	end

	return "Guest"
end

local function GetRank(Player: Player, GroupId: number?): number
	local GroupId = if GroupId then GroupId else Config.DefualtGroupId
	local PlayerData = GetPlayerData(Player)
		
	if PlayerData then
		local GroupBuffer = PlayerData[2][GroupId]
	
		if GroupBuffer then
			return buffer.readu8(GroupBuffer, 0)
		end
	end

	return 0
end

local function ForceRefresh(Player: Player): boolean
	local PlayerData, PlayerPosition = GetPlayerData(Player)

	if PlayerData then
		PlayerData[1] = os.clock()
		return RefreshPlayerGroups(Player, PlayerPosition, PlayerData[2])
	else
		return false
	end
end

local function Init()
	if HasInitiated then
		error("[RankCache] Cannot initalize twice without disconnecting first")
	else
		HasInitiated = true
	end

	local RefreshConnection = RunService.PostSimulation:Connect(OnPostSimulation)
	local RemovingConnection = Players.PlayerRemoving:Connect(OnPlayerRemoving)
	local AddedConnection = Players.PlayerAdded:Connect(OnPlayerAdded)

	for _, Player in Players:GetPlayers() do
		if table.find(PlayerPositions, Player) then continue end
		Spawn(OnPlayerAdded, Player)
	end

	return function()
		RemovingConnection:Disconnect()
		RefreshConnection:Disconnect()
		AddedConnection:Disconnect()
		table.clear(PlayerPositions)
		HasInitiated = false
	end
end

local RankCache = {
	GlobalOnRankChanged = GlobalOnRankChanged,
	GetRoleAndRank = GetRoleAndRank,
	OnRankChanged = OnRankChanged,
	ForceRefresh = ForceRefresh,
	IsInGroup = IsInGroup,
	GetRole = GetRole,
	GetRank = GetRank,
	Config = Config,
	Init = Init,
}

return RankCache
