-- ServerScriptService/GameManager.server.lua
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ⬇️  NEW — bring the service in
local DilemmaService    = require(script.Parent.DilemmaService)

-- Remote signals for client UI
local StageChanged      = Instance.new("RemoteEvent")
StageChanged.Name       = "StageChanged"
StageChanged.Parent     = ReplicatedStorage

-- enum-like table for readability
local STAGE = {
    LOBBY      = 1,
    DILEMMA    = 2,
    MAZE       = 3,
    PROGRESSION= 4
}

-- keep state per player
local playerState = {}

local function teleportTo(tag, player)
    local target = workspace:FindFirstChild(tag)
    if target then
        -- put player at the tagged part’s CFrame
        local char = player.Character or player.CharacterAdded:Wait()
        char:PivotTo(target.CFrame + Vector3.new(0,3,0))
    end
end

local function advance(player)
    local state = playerState[player] or STAGE.LOBBY
    local nextState = state + 1
    if nextState > STAGE.PROGRESSION then nextState = STAGE.LOBBY end
    playerState[player] = nextState

    -- move avatar
    if nextState == STAGE.LOBBY then          teleportTo("Spawn_Lobby", player)
    elseif nextState == STAGE.DILEMMA then
        teleportTo("Spawn_Dilemma", player)
        DilemmaService.AddPlayer(player)    
    elseif nextState == STAGE.MAZE then       teleportTo("Spawn_Maze", player)
    elseif nextState == STAGE.PROGRESSION then teleportTo("Spawn_Progression", player)
    end

    -- notify clients so UI can update label or show rules
    StageChanged:FireClient(player, nextState)
end

-- ⬇️  EXPORT so DilemmaService can push players forward after it resolves
_G.AdvancePlayer = advance

Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        playerState[plr] = STAGE.LOBBY
        teleportTo("Spawn_Lobby", plr)
        StageChanged:FireClient(plr, STAGE.LOBBY)
    end)
end)

-- temporary: advance everyone every 45 s
while task.wait(10) do
    for _,p in ipairs(Players:GetPlayers()) do
        advance(p)
    end
end
