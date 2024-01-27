# RankCache

RankCache is a fully typed library designed to make it easier to obtain up-to-date group ranking information across all of your in-game scripts.

**Why use this over :GetRankInGroup/:GetRoleInGroup?**
- This library ensures that you get up-to-date rank information whilst keeping API requests to a minimum.
- It provides almost full control over when rank data is refreshed, through the use of being able
- to change the refresh time to whatever you'd like.
- Its this way so that there should be minimal yielding when ever any of the methods are called,
- as its not doing the api requests within any of the methods except for ForceRefresh.

## Installation methods

### Method 1: Rojo
1. Download the GitHub repository to your computer.
2. Install [Rojo](https://rojo.space/) and all associated Studio/VSC plugins.
3. Use Rojo to sync the RankCache library into your Studio project. (Or build the library using `rojo build -o RankCache.rbxm`)

## Basic Usage
```lua
local RankCache = require(game:GetService("ServerStorage").RankCache)

RankCache.Config.DefualtGroupId = 23930122
RankCache.Init()

-- Fetches Player1's role and rank for group 1234
local Role, Rank = RankCache.GetRoleAndRank(game.Players.Player1, 1234)

-- Fetches Player1's rank for group 1234
local Rank = RankCache.GetRank(game.Players.Player1, 1234)

-- Fetches Player1's role for group 1234
local Role = RankCache.GetRole(game.Players.Player1, 1234)

-- Checks if Player1 is in group 1234
local IsPlayerInGroup = RankCache.IsInGroup(game.Players.Player1, 1234)

-- Forces a refesh in the cache for Player1
local Sucess = RankCache.ForceRefresh(game.Players.Player1)

-- Creates a callback thats called whenever any players rank changes in any group
local Disconnect = RankCache.GlobalOnRankChanged(function(GroupId, Player, NewRank, OldRank)
    print(`{Player.Name}'s new rank is {NewRank} in group {GroupId}`)
end)

-- Creates a callback to be called whenever a players rank changes in the defualt group
-- that then immediatly disconnects
local Disconnect = RankCache.OnRankChanged(functiion(Player, NewRank, OldRank)
    print(`{Player.Name}'s new rank is {NewRank} in group {RankCache.Config.DefualtGroupId})`)
    Disconnect()
end)

-- Creates a callback to be called whenever a players rank changes in the group 1234
local Disconnect = RankCache.OnRankChanged(1234, functiion(Player, NewRank, OldRank)
    print(`{Player.Name}'s new rank is {NewRank} in group 1234`)
end)
```

More examples are available in the [examples](https://github.com/kalrnlo/RankCache/tree/main/examples) folder.
