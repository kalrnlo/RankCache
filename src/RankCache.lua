--[[
    Whitehill Rank Cache Module
    Author: TheCakeChicken

    This module can be required from both the client and the server.

    This module is designed to provide the developer with greater control over how group ranks/roles are handled in their game.
    Games which rely on these usually use Player:GetRankInGroup, which caches even after a player rejoins.

    You may wish to consider implementing a server script to fetch/clear this data when a player joins/leaves
    to ensure that when a player rejoins the game, the latest ranking information is fetched and used.

    TO SETUP:
        - Place this ModuleScript into ReplicatedStorage
        - Set relevant settings in the config table

    USAGE:
        -- Load the library
        local rankCache = require(game.ReplicatedStorage.RankCache)

        -- Fetches Player1's rank for group 1234
        local player1Rank = rankCache:GetPlayerRank(game.Players.Player1, 1234)

        -- Fetches Player1's role for group 1234
        local player1Role = rankCache:GetPlayerRole(game.Players.Player1, 1234)

        -- Fetches Player2's rank for the configured default group
        local player2Rank = rankCache:GetPlayerRank(game.Players.Player2)

        -- Fetches Player2's role for the configured default group
        local player2Role = rankCache:GetPlayerRole(game.Players.Player2)


    More advanced usage can be found within the GitHub repository.

    Need help?
    Check out the example scripts available in the GitHub repository
]]
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
type PlayerCacheData = {
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

local PlayerCache = table.create(Players.MaxPlayers) :: {PlayerCacheData}
local PlayerCachePositions = table.create(Players.MaxPlayers) :: {Player}
local RankChangedCallbacks = {} :: {CallbackData}
local Config = {
	--// Specifies the group ID to use when no groupId is provided
	GroupRefreshRate = 120,
	DefualtGroupId = 0,
}

local module = {}

local function RefreshPlayerGroups(UserId: number, )

end

local OnRankChanged: OnRankChanged = function(CallbackOrGroupId, Callback)
	local Callback = if typeof(CallbackOrGroupId) == "function" then CallbackOrGroupId else Callback
	local GroupId = if not Callback then Config.DefualtGroupId else CallbackOrGroupId
	local IsGroupIdNotDefualt = GroupId ~= Config.DefualtGroupId
			
	local CallbackData = table.create(if IsGroupIdNotDefualt then 3 else 2) :: CallbackData
	CallbackData[1] = Callback
	CallbackData[2] = 1

	if IsGroupIdNotDefualt then
		CallbackData[2] = GroupId
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
