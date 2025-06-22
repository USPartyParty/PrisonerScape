-- StarterGui/DilemmaGui/Client.lua
local RS           = game:GetService("ReplicatedStorage")
local StageChanged = RS:WaitForChild("StageChanged")
local ChoiceRE     = RS:WaitForChild("DilemmaChoice")
local ResultRE     = RS:WaitForChild("DilemmaResult")

local gui    = script.Parent.Frame
gui.Visible  = false
local pairId = nil

local function hide() gui.Visible = false end

-- button hooks
gui.Betray.MouseButton1Click:Connect(function()
    if pairId then ChoiceRE:FireServer(pairId, "betray"); hide() end
end)
gui.Cooperate.MouseButton1Click:Connect(function()
    if pairId then ChoiceRE:FireServer(pairId, "cooperate"); hide() end
end)

-- server tells us when round starts / ends
ResultRE.OnClientEvent:Connect(function(mode, ...)
    if mode == "start" then
        pairId = select(1, ...)
        gui.Visible = true
    elseif mode == "result" then
        -- optional: show result to player here
        pairId = nil
        hide()
    end
end)

-- hide the GUI whenever we leave the Dilemma stage
StageChanged.OnClientEvent:Connect(function(stage)
    if stage ~= 2 then hide() end   -- STAGE.DILEMMA = 2
end)
