--!optimize 2
--!native
--!strict

local GroupService = game:GetService("GroupService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

type OnRankChanged = ((Callback: RankChangedCallback) -> () -> ()) & ((GroupId: number, Callback: RankChangedCallback) -> () -> ())

export type GlobalRankChangedCallback = (GroupId: number, Player: Player, NewRank: number, OldRank: number) -> ()

export type RankChangedCallback = (Player: Player, NewRank: number, OldRank: number) -> ()

type RankCacheConfig = {
	GroupRefreshRate: number,
	DefualtGroupId: number,
}

-- [1] = {[DataIndex] = GroupId}
-- GroupDataFormat 
-- 1 byte for rank, 1 byte for role string length, rest is role string
-- [2] {[DataIndex] = GroupData}
type PlayerData = {
	["1"]: {number},
	["2"]: {buffer}
}

-- [1] = Callback
-- [2] == 1 = Specific, 2 = Global
-- [3] == OptionalGroupIdSpeciferParam
type CallbackData = {
	["1"]: RankChangedCallback,
	["2"]: number,
	["3"]: number?,
}

local PlayerCachePositions = table.create(Players.MaxPlayers) :: {Player}
local PlayerCache = table.create(Players.MaxPlayers) :: {PlayerData}
-- {[UserId] = {Thread}}
local ThreadsWaitingForPlayers = {} :: {[number]: {thread}}
local RankChangedCallbacks = {} :: {CallbackData}
local Config = {
	GroupRefreshRate = 120,
	DefualtGroupId = 0,
}

-- TODO: implement callback runner
local function RunCallbacks(Player: Player, NewPlayerData: PlayerData, OldPlayerData: PlayerData)

	for _, Callback in RankChangedCallbacks do
		task.spawn(Callback[1], Player, NewRank, OldRank)
	end
end

local function RefreshPlayerGroups(Player: Player, CachePosition: number, PlayerData: PlayerData)
	local Sucess, Groups = pcall(function(UserId: number)
		return GroupService:GetGroupsAsync(UserId)
	end, Player.UserId)
	
	if Sucess then
		local GroupBuffers = table.create(#Groups)
		local GroupIds = table.create(#Groups)
		
		for Index, Group in Groups do
			local GroupBuffer = buffer.create(1 + #Group.Role)
			buffer.writestring(GroupBuffer, 1, Group.Role)
			buffer.writeu8(GroupBuffer, 0, Group.Rank)

			GroupBuffers[Index] = GroupBuffer
			GroupIds[Index] = Group.Id
		end
		local NewPlayerData = table.create(2) :: PlayerData
		NewPlayerData[2] = GroupBuffers
		NewPlayerData[1] = GroupIds

		task.spawn(RunCallbacks, Player, NewPlayerData, OldPlayerData)
		PlayerCache[CachePosition] = NewPlayerData
		return true
	else
		warn(`[RankCache] RefreshPlayerGroups couldn't get groups for Player {Player.UserId}\n\tGetGroupsAsyncError: {Groups}`)
		return false
	end
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

local function OnGlobalRankChanged(Callback: GlobalRankChangedCallback)
	local CallbackData = table.create(2) :: CallbackData
	CallbackData[1] = Callback
	CallbackData[2] = 2

	return function()
		local Index = table.find(RankChangedCallbacks, CallbackData)
		table.remove(RankChangedCallbacks, Index)
	end
end

module.dataCache = setmetatable({}, {
	__index = function(t,i)
		t[i] = setmetatable({}, {__index = function(t_,i_) t_[i_] = {} return t_[i_] end})
		return t[i]
	end
})

module.FetchPlayerInfo = function(self, player, groupId)
	if (not groupId and not config.DefaultGroupID) then
		return error("Attempt to fetch player rank without specifying group. Is a default group set?")
	elseif (not groupId and config.DefaultGroupID) then
		groupId = config.DefaultGroupID
	end

	local isSuccess, usrGroups = pcall(function() return GroupService:GetGroupsAsync(player.UserId) end)

    --// If the request failed, return a default value but do not store to the cache, so subsequent requests will attempt to fetch new data
    if (not isSuccess) then
        warn("[RankCache] Failed to fetch group (ID: " .. groupId .. ") data for " .. player.Name .. " (" .. player.UserId .. ")");

        return {
            Rank = 0;
            Role = "Guest";
        }
    end

	local playerRank = 0
	local playerRole = "Guest"

	for _, group in pairs(usrGroups) do
		if group.Id == groupId then
			playerRank = group.Rank;
			playerRole = group.Role;

			break;
		end
	end

	self.dataCache[player.UserId][groupId] = {
		Rank = playerRank;
		Role = playerRole;
	}

	return self.dataCache[player.UserId][groupId]
end

module.ClearPlayerInfo = function(self, player)
	self.dataCache[player.UserId] = nil
end

module.GetPlayerRank = function(self, player, groupId)
	if (not groupId and not config.DefaultGroupID) then
		return error("Attempt to fetch player rank without specifying group. Is a default group set?")
	elseif (not groupId and config.DefaultGroupID) then
		groupId = config.DefaultGroupID
	end

	if self.dataCache[player.UserId][groupId].Rank then
		return self.dataCache[player.UserId][groupId].Rank
	end

	local data = self:FetchPlayerInfo(player, groupId)
	return data.Rank
end

module.GetPlayerRole = function(self, player, groupId)
	if (not groupId and not config.DefaultGroupID) then
		return error("Attempt to fetch player rank without specifying group. Is a default group set?")
	elseif (not groupId and config.DefaultGroupID) then
		groupId = config.DefaultGroupID
	end

	if self.dataCache[player.UserId][groupId].Role then
		return self.dataCache[player.UserId][groupId].Role
	end

	local data = self:FetchPlayerInfo(player, groupId)
	return data.Role
end

return module
