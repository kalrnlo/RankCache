--[[
    This script outlines basic uses of the RankCache library.
]]

local rankCache = require(game:GetService("ServerStorage").RankCache)

rankCache.Config.DefualtGroupId = 23930122
rankCache.Init()

-- Fetches Player1's role and rank for group 1234
local Role, Rank = rankCache.GetRoleAndRank(game.Players.Player1, 1234)

-- Fetches Player1's rank for group 1234
local player1Rank = rankCache.GetRank(game.Players.Player1, 1234)

-- Fetches Player1's role for group 1234
local player1Role = rankCache.GetRole(game.Players.Player1, 1234)

-- Forces a refesh in the cache for Player1
local Sucess = rankCache.ForceRefresh(game.Players.Player1)

-- Fetches Player1's role and rank the configured default group
local Role, Rank = rankCache.GetRoleAndRank(game.Players.Player1)

-- Fetches Player2's rank for the configured default group
local player2Rank = rankCache.GetRank(game.Players.Player2)

-- Fetches Player2's role for the configured default group
local player2Role = rankCache.GetRole(game.Players.Player2)

-- 
