--[[
================================================================================
                           ROBLOX BLOCK BOT
================================================================================
                              by 2y | discord: goc2v
================================================================================
]]

-- Configuration Section
local Config = {
    FollowDistance = 5,
    MovementSpeed = 16,
    JumpWhenBlocked = true,
    FollowPosition = "Front", -- "Front" or "Back"
    SmoothMovement = true,
    SmoothnessFactor = 0.5,
    TeleportIfTooFar = false, -- Disabled teleport, we want natural walk only
    TooFarDistance = 200,
    RespawnIfStuck = true,
    StuckTimeout = 10,
    AutoRespawn = true,
    HeartbeatInterval = 0.1,
    AntiFlood = true,
    AntiDetection = true,
    MaxAttempts = 3,
    ShowDebugInfo = false,
    DebugKeybind = Enum.KeyCode.F9,

    -- Target player username or displayname inside brackets []
    TargetName = "[username or displayname]"
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

local TargetPlayer, TargetCharacter = nil, nil
local IsFollowing = false
local LastPosition = HumanoidRootPart.Position
local LastPositionTime = os.time()
local DebugUI, DebugActive = nil, false
local ConnectionTable = {}

local function DebugPrint(message)
    if Config.ShowDebugInfo then
        print("[DEBUG] " .. message)
    end
end

local function CreateDebugUI()
    if DebugUI then DebugUI:Destroy() end
    DebugUI = Instance.new("ScreenGui")
    DebugUI.Name = "BlockBotDebugUI_" .. HttpService:GenerateGUID(false)
    DebugUI.Parent = game:GetService("CoreGui")
    DebugUI.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0.3, 0, 0.2, 0)
    frame.Position = UDim2.new(0.05, 0, 0.75, 0)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BackgroundTransparency = 0.5
    frame.BorderSizePixel = 0
    frame.Parent = DebugUI

    local title = Instance.new("TextLabel")
    title.Text = "ROBLOX BLOCK BOT DEBUG"
    title.Size = UDim2.new(1, 0, 0.15, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.SourceSansBold
    title.Parent = frame

    local content = Instance.new("TextLabel")
    content.Name = "Content"
    content.Text = "Debug information will appear here"
    content.Size = UDim2.new(1, 0, 0.85, 0)
    content.Position = UDim2.new(0, 0, 0.15, 0)
    content.BackgroundTransparency = 1
    content.TextColor3 = Color3.fromRGB(255, 255, 255)
    content.TextXAlignment = Enum.TextXAlignment.Left
    content.TextYAlignment = Enum.TextYAlignment.Top
    content.TextWrapped = true
    content.Font = Enum.Font.SourceSans
    content.Parent = frame
end

local function UpdateDebugUI(info)
    if DebugUI and DebugUI:FindFirstChild("Frame") then
        local content = DebugUI.Frame:FindFirstChild("Content")
        if content then
            content.Text = info
        end
    end
end

local function ToggleDebug()
    DebugActive = not DebugActive
    if DebugActive then
        if not DebugUI then
            CreateDebugUI()
        else
            DebugUI.Enabled = true
        end
        Config.ShowDebugInfo = true
    else
        if DebugUI then
            DebugUI.Enabled = false
        end
        Config.ShowDebugInfo = false
    end
end

local function Notify(message)
    DebugPrint(message)
    if DebugUI and DebugActive then
        UpdateDebugUI(os.date("%X") .. ": " .. message .. "\n" .. (DebugUI.Frame.Content.Text or ""))
    end
end

local function CleanupConnections()
    for _, c in pairs(ConnectionTable) do
        if c then c:Disconnect() end
    end
    ConnectionTable = {}
end

-- Find player by username or display name, input inside brackets like [playername]
local function GetPlayerByName(name)
    local input = name:lower()
    if input:sub(1,1) == "[" and input:sub(-1,-1) == "]" then
        input = input:sub(2, -2)
    end
    for _, player in ipairs(Players:GetPlayers()) do
        local uname = player.Name:lower()
        local dname = player.DisplayName:lower()
        if uname:find(input) == 1 or dname:find(input) == 1 then
            return player
        end
    end
    return nil
end

local function IsAlive(character)
    local h = character and character:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function Respawn()
    Character:BreakJoints()
    repeat task.wait() until Character:FindFirstChild("Humanoid") and Character.Humanoid.Health <= 0
    repeat task.wait() until Character:FindFirstChild("Humanoid") and Character.Humanoid.Health > 0
    Notify("Respawned character")
    return true
end

-- Calculate a position to follow: in front or behind the target, offset by FollowDistance
local function CalculatePositionInFront(cf, dist)
    return cf.Position + (cf.LookVector * dist)
end

local function CalculatePositionBehind(cf, dist)
    return cf.Position - (cf.LookVector * dist)
end

local function GetFollowPosition(cf, dist)
    if Config.FollowPosition:lower() == "back" then
        return CalculatePositionBehind(cf, dist)
    else
        return CalculatePositionInFront(cf, dist)
    end
end

local function CheckIfStuck()
    local currentPosition = HumanoidRootPart.Position
    if (currentPosition - LastPosition).Magnitude < 1 then
        if os.time() - LastPositionTime > Config.StuckTimeout then
            Notify("Character is stuck! Trying to resolve...")
            if Config.JumpWhenBlocked then
                Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
            if Config.RespawnIfStuck then
                Respawn()
            end
            LastPositionTime = os.time()
        end
    else
        LastPosition = currentPosition
        LastPositionTime = os.time()
    end
end

local function FollowTarget()
    if not IsFollowing or not TargetCharacter or not TargetCharacter:FindFirstChild("HumanoidRootPart") then return false end
    if not IsAlive(Character) then
        if Config.AutoRespawn then Respawn() return false end
        IsFollowing = false
        return false
    end

    local targetHRP = TargetCharacter.HumanoidRootPart
    local botPos = HumanoidRootPart.Position
    local targetPos = GetFollowPosition(targetHRP.CFrame, Config.FollowDistance)

    -- Just make humanoid walk to the follow position (Vector3)
    Humanoid:MoveTo(targetPos)

    if Config.RespawnIfStuck then
        CheckIfStuck()
    end

    return true
end

local function RenderSteppedFollow()
    if IsFollowing then
        FollowTarget()
    end
end

local function StartFollowing(name)
    local attempts = 0
    while attempts < Config.MaxAttempts do
        TargetPlayer = GetPlayerByName(name)
        if TargetPlayer then
            TargetCharacter = TargetPlayer.Character or TargetPlayer.CharacterAdded:Wait()
            if TargetCharacter:FindFirstChild("HumanoidRootPart") then
                IsFollowing = true
                Humanoid.WalkSpeed = Config.MovementSpeed
                CleanupConnections()
                table.insert(ConnectionTable, TargetPlayer.CharacterAdded:Connect(function(char)
                    TargetCharacter = char
                    Notify("Target character changed")
                end))
                table.insert(ConnectionTable, RunService.RenderStepped:Connect(RenderSteppedFollow))
                Notify("Now following " .. TargetPlayer.Name)
                return true
            end
        end
        attempts = attempts + 1
        Notify("Retrying to find player... (" .. attempts .. "/" .. Config.MaxAttempts .. ")")
        task.wait(1)
    end
    Notify("Failed to find player")
    return false
end

local function StopFollowing()
    IsFollowing = false
    CleanupConnections()
    Humanoid:MoveTo(HumanoidRootPart.Position) -- Stop movement
    Notify("Stopped following")
    return true
end

local function Initialize()
    LocalPlayer.CharacterAdded:Connect(function(char)
        Character = char
        Humanoid = char:WaitForChild("Humanoid")
        HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
        LastPosition = HumanoidRootPart.Position
        LastPositionTime = os.time()
        if IsFollowing then
            Notify("Respawned. Continuing to follow.")
            Humanoid.WalkSpeed = Config.MovementSpeed
        end
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Config.DebugKeybind then
            ToggleDebug()
        end
    end)

    -- Auto start following the TargetName from config, if it's set and not default placeholder
    if Config.TargetName ~= "" and Config.TargetName ~= "[username or displayname]" then
        StartFollowing(Config.TargetName)
    end

    Notify("Block Bot initialized")
end

Initialize()

return {
    StartFollowing = StartFollowing,
    StopFollowing = StopFollowing,
    GetConfig = function() return Config end,
    SetConfig = function(new)
        for k,v in pairs(new) do
            if Config[k] ~= nil then
                if k == "FollowPosition" and (v:lower() == "front" or v:lower() == "back") then
                    Config[k] = v
                elseif k ~= "FollowPosition" then
                    Config[k] = v
                end
            end
        end
        Notify("Config updated")
        if Humanoid then Humanoid.WalkSpeed = Config.MovementSpeed end
    end,
    GetTarget = function() return TargetPlayer end,
    IsFollowing = function() return IsFollowing end,
    ToggleDebug = ToggleDebug
}
