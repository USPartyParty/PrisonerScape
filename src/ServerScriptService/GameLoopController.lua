--!strict

--[[
Module: GameLoopController
Role: Drives the finite-state machine (FSM) for each round: Lobby → Dilemma → Maze → Progression → Lobby.
Inputs: Player joins, Ready status, Dilemma choices, timeouts.
Outputs: RemoteEvents.RoundStateChanged, RemoteEvents.ShowPayoff
Constraints: Must be server-only. Must broadcast state changes every second to all clients.
Style: Luau strict, camelCase for locals, PascalCase for modules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local roundStateChanged = remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
local showPayoff = remotes:WaitForChild("ShowPayoff") :: RemoteEvent
local readyEvent = remotes:WaitForChild("ReadyEvent") :: RemoteEvent
local choiceFunction = remotes:WaitForChild("ChoiceFunction") :: RemoteFunction

local MatchmakerService = require(script.Parent:WaitForChild("MatchmakerService"))
local MazeService = require(script.Parent:WaitForChild("MazeService"))
local DilemmaService = require(script.Parent:WaitForChild("DilemmaService"))

local GameLoopController = {}

-- State definition ------------------------------------------------------------
export type RoundStateName = "Lobby" | "Dilemma" | "Maze" | "Progression"

local RoundState = {
    Lobby = "Lobby",
    Dilemma = "Dilemma",
    Maze = "Maze",
    Progression = "Progression",
}

local stateDurations = {
    [RoundState.Lobby] = 20,
    [RoundState.Dilemma] = 15,
    [RoundState.Maze] = 120,
    [RoundState.Progression] = 10,
}

local currentState: RoundStateName = RoundState.Lobby
local remaining = stateDurations[currentState]

-- Player bookkeeping ---------------------------------------------------------
local playersReady: {[Player]: boolean} = {}
local playerChoices: {[Player]: string} = {}

local function onPlayerAdded(player: Player)
    playersReady[player] = false
end

local function onPlayerRemoving(player: Player)
    playersReady[player] = nil
    playerChoices[player] = nil

    -- Replace leaving player with a bot during active rounds
    if currentState ~= RoundState.Lobby then
        MatchmakerService:SpawnBotFor(player)
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Readiness & choice plumbing ------------------------------------------------
readyEvent.OnServerEvent:Connect(function(player: Player, isReady: boolean)
    playersReady[player] = isReady == true
end)

choiceFunction.OnServerInvoke = function(player: Player, choice: string)
    if typeof(choice) == "string" then
        playerChoices[player] = choice
        return true
    end
    return false
end

-- Utility --------------------------------------------------------------------
local function broadcastState()
    roundStateChanged:FireAllClients(currentState, remaining)
end

local function allPlayersReady(): boolean
    for _, plr in ipairs(Players:GetPlayers()) do
        if not playersReady[plr] then
            return false
        end
    end
    return #Players:GetPlayers() > 0
end

local function choicesSubmitted(): boolean
    for _, plr in ipairs(Players:GetPlayers()) do
        if playerChoices[plr] == nil then
            return false
        end
    end
    return #Players:GetPlayers() > 0
end

-- Lobby ----------------------------------------------------------------------
local function runLobby()
    currentState = RoundState.Lobby
    remaining = stateDurations[currentState]
    for _, plr in ipairs(Players:GetPlayers()) do
        playersReady[plr] = false
    end
    broadcastState()

    while remaining > 0 do
        if allPlayersReady() then
            break
        end
        task.wait(1)
        remaining -= 1
        broadcastState()
    end
end

-- Dilemma --------------------------------------------------------------------
local function runDilemma()
    currentState = RoundState.Dilemma
    remaining = stateDurations[currentState]
    playerChoices = {}
    broadcastState()

    while remaining > 0 do
        if choicesSubmitted() then
            break
        end
        task.wait(1)
        remaining -= 1
        broadcastState()
    end

    local results = DilemmaService:Resolve(playerChoices, playersReady)
    showPayoff:FireAllClients(results)
end

-- Maze -----------------------------------------------------------------------
local function mazeCompleted(): boolean
    return MazeService:IsRoundComplete()
end

local function runMaze()
    currentState = RoundState.Maze
    remaining = stateDurations[currentState]
    broadcastState()

    while remaining > 0 do
        if mazeCompleted() then
            break
        end
        task.wait(1)
        remaining -= 1
        broadcastState()
    end

    -- TODO: Finalize results, award minimum loot if timed out
end

-- Progression ----------------------------------------------------------------
local function runProgression()
    currentState = RoundState.Progression
    remaining = stateDurations[currentState]
    broadcastState()

    while remaining > 0 do
        task.wait(1)
        remaining -= 1
        broadcastState()
    end
end

-- FSM loop -------------------------------------------------------------------
local function fsmLoop()
    while true do
        runLobby()
        runDilemma()
        runMaze()
        runProgression()
    end
end

function GameLoopController.start()
    task.spawn(fsmLoop)
end

return GameLoopController

