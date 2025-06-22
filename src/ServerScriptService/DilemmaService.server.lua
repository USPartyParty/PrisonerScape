-- ServerScriptService/DilemmaService.server.lua
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChoiceRE  = ReplicatedStorage:WaitForChild("DilemmaChoice")
local ResultRE  = ReplicatedStorage:WaitForChild("DilemmaResult")

-------------------------------------------------------------------
-- public API
-------------------------------------------------------------------
local Dilemma = {}

-------------------------------------------------------------------
-- internal state
-------------------------------------------------------------------
local waiting   = {}                -- queue of players awaiting an opponent
local active    = {}                -- pairId → { players = {p1,p2}, choice = {} }

-------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------
local function ensureLeaderstats(plr)
    if plr:FindFirstChild("leaderstats") then return end
    local ls = Instance.new("Folder")
    ls.Name  = "leaderstats"
    ls.Parent= plr
    local pts= Instance.new("IntValue")
    pts.Name = "Points"
    pts.Parent = ls
end

local payoff = {                    -- row = your choice, col = partner
    cooperate = { cooperate = 3, betray = 0 },
    betray    = { cooperate = 5, betray = 1 },
}

local function resolvePair(pairId)
    local info = active[pairId]
    if not info then return end
    local p1, p2     = info.players[1], info.players[2]
    local c1         = info.choice[p1] or "cooperate"
    local c2         = info.choice[p2] or "cooperate"

    -- award points
    p1.leaderstats.Points.Value += payoff[c1][c2]
    p2.leaderstats.Points.Value += payoff[c2][c1]

    -- tell clients what happened
    ResultRE:FireClient(p1, "result", c1, c2, payoff[c1][c2])
    ResultRE:FireClient(p2, "result", c2, c1, payoff[c2][c1])

    active[pairId] = nil

    -- nudge to next stage after 2 s
    task.delay(2, function()
        if _G.AdvancePlayer then
            _G.AdvancePlayer(p1)
            _G.AdvancePlayer(p2)
        end
    end)
end

-------------------------------------------------------------------
-- public entry: called by GameManager when a player enters the room
-------------------------------------------------------------------
function Dilemma.AddPlayer(plr)
    ensureLeaderstats(plr)
    table.insert(waiting, plr)

    if #waiting >= 2 then
        -- pop two, create a pair
        local p1 = table.remove(waiting, 1)
        local p2 = table.remove(waiting, 1)
        local id = tostring(math.random(1, 2^31))

        active[id] = { players = {p1, p2}, choice = {} }

        -- notify clients to pop up the UI (15 s timer)
        for _,p in ipairs(active[id].players) do
            ResultRE:FireClient(p, "start", id, 15)
        end

        -- hard timer – auto-resolve after 15 s
        task.delay(15, function() resolvePair(id) end)
    end
end

-------------------------------------------------------------------
-- remote from clients
-------------------------------------------------------------------
ChoiceRE.OnServerEvent:Connect(function(plr, pairId, choice)
    if choice ~= "betray" and choice ~= "cooperate" then return end
    local info = active[pairId]
    if not info then return end
    info.choice[plr] = choice
    if info.choice[info.players[1]] and info.choice[info.players[2]] then
        resolvePair(pairId)
    end
end)

return Dilemma
