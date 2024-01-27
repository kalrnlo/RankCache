--!strict

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RankCache = require(game:GetService("ServerStorage").RankCache)

RankCache.Config.DefualtGroupId = 23930122
RankCache.Init()

local CustomerTeam = Instance.new("Team")
CustomerTeam.Name = "Customers"
CustomerTeam.Parent = Teams

local ManagerTeam = Instance.new("Team")
ManagerTeam.Name = "Managers"
ManagerTeam.Parent = Teams

local StaffTeam = Instance.new("Team")
StaffTeam.Name = "Staff"
StaffTeam.Parent = Teams

local function AssignTeam(Player: Player, Rank: number)
    if Rank >= 20 then
        Player.Team = ManagerTeam
    elseif Rank >= 3 then
        Player.Team = StaffTeam
    else
        Player.Team = CustomerTeam
    end
end

Players.PlayerAdded:Connect(function(Player)
    AssignTeam(Player, RankCache.GetRank(Player))
end)

RankCache.OnRankChanged(AssignTeam)
