--[[
    ██╗  ██╗ ██████╗  █████╗ ██╗      █████╗     ██╗  ██╗██╗   ██╗██████╗
    ██║ ██╔╝██╔═══██╗██╔══██╗██║     ██╔══██╗    ██║  ██║██║   ██║██╔══██╗
    █████╔╝ ██║   ██║███████║██║     ███████║    ███████║██║   ██║██████╔╝
    ██╔═██╗ ██║   ██║██╔══██║██║     ██╔══██║    ██╔══██║██║   ██║██╔══██╗
    ██║  ██╗╚██████╔╝██║  ██║███████╗██║  ██║    ██║  ██║╚██████╔╝██████╔╝
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝

    AUTO FASE RECORDING SYSTEM v1.0.0
    Sistema de gravação de movimentos para Auto-Fase
    
    Funcionalidades:
    - Gravar movimentos e cliques do jogador
    - Salvar/carregar gravações
    - Renomear gravações
    - Apagar gravações
    - Reproduzir gravações em loop
    - Sistema Anti-Lag (Booster Koala)
]]

local AutoFaseSystem = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")

local LP = Players.LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")

-- ==================================================================
--  DADOS DE GRAVAÇÃO
-- ==================================================================
AutoFaseSystem.Recordings = {} -- tabela com todas as gravações
AutoFaseSystem.IsRecording = false
AutoFaseSystem.IsPlayingBack = false
AutoFaseSystem.CurrentRecording = nil
AutoFaseSystem.RecordingName = ""
AutoFaseSystem.PlaybackSpeed = 1.0
AutoFaseSystem.AntiLagEnabled = false
AutoFaseSystem.LagBoostLevel = 0 -- 0 = off, 1 = low, 2 = medium, 3 = high

-- ==================================================================
--  HELPERS
-- ==================================================================
local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- ==================================================================
--  ANTI-LAG SYSTEM (Booster Koala)
-- ==================================================================
local antiLagConnection = nil

local function startAntiLag(level)
    if antiLagConnection then
        antiLagConnection:Disconnect()
    end
    
    AutoFaseSystem.LagBoostLevel = level
    
    if level == 0 then
        return
    end
    
    antiLagConnection = RunService.Heartbeat:Connect(function()
        if AutoFaseSystem.LagBoostLevel == 0 then return end
        
        -- Level 1: Desativar TextureStreaming
        if AutoFaseSystem.LagBoostLevel >= 1 then
            pcall(function()
                local terrain = workspace.Terrain
                if terrain then
                    terrain.UseHeightMap = false
                end
            end)
        end
        
        -- Level 2: Reduzir qualidade de renderização
        if AutoFaseSystem.LagBoostLevel >= 2 then
            pcall(function()
                for _, part in ipairs(workspace:FindPartBoundsInRadius(hrp().Position, 100)) do
                    if part ~= hrp() and part.Parent ~= LP.Character then
                        part.TopSurface = Enum.SurfaceType.Smooth
                        part.BottomSurface = Enum.SurfaceType.Smooth
                    end
                end
            end)
        end
        
        -- Level 3: Garbage collection agressivo + reduzir objetos
        if AutoFaseSystem.LagBoostLevel >= 3 then
            pcall(function()
                collectgarbage("step", 10)
                -- Desativar visibilidade de objetos distantes
                local hrpPos = hrp().Position
                for _, part in ipairs(workspace:FindPartBoundsInRadius(hrpPos, 200)) do
                    if part ~= hrp() and part.Parent ~= LP.Character then
                        local dist = (part.Position - hrpPos).Magnitude
                        if dist > 150 then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        end
    end)
end

local function stopAntiLag()
    if antiLagConnection then
        antiLagConnection:Disconnect()
        antiLagConnection = nil
    end
    AutoFaseSystem.LagBoostLevel = 0
end

AutoFaseSystem.StartAntiLag = startAntiLag
AutoFaseSystem.StopAntiLag = stopAntiLag

-- ==================================================================
--  RECORD SYSTEM
-- ==================================================================
local recordingData = {}
local recordStartTime = 0
local lastRecordedPos = Vector3.new(0, 0, 0)

local function startRecording(name)
    if AutoFaseSystem.IsRecording then
        return false
    end
    
    AutoFaseSystem.IsRecording = true
    AutoFaseSystem.RecordingName = name or "Recording_" .. os.time()
    recordingData = {
        name = AutoFaseSystem.RecordingName,
        duration = 0,
        movements = {},
        clicks = {},
        startTime = tick(),
        createdAt = os.date("%Y-%m-%d %H:%M:%S"),
    }
    recordStartTime = tick()
    lastRecordedPos = hrp().Position
    
    -- Conectar para gravar movimentos
    local movementConnection = RunService.Heartbeat:Connect(function()
        if not AutoFaseSystem.IsRecording then
            return
        end
        
        local root = hrp()
        if not root then return end
        
        local currentPos = root.Position
        local distance = (currentPos - lastRecordedPos).Magnitude
        
        -- Gravar movimento apenas se deslocou
        if distance > 0.1 then
            table.insert(recordingData.movements, {
                time = tick() - recordStartTime,
                position = currentPos,
                cframe = root.CFrame,
                distance = distance,
            })
            lastRecordedPos = currentPos
        end
    end)
    
    -- Armazenar conexão para cleanup
    recordingData.connection = movementConnection
    
    return true
end

local function stopRecording()
    if not AutoFaseSystem.IsRecording then
        return false
    end
    
    AutoFaseSystem.IsRecording = false
    recordingData.duration = tick() - recordStartTime
    
    if recordingData.connection then
        recordingData.connection:Disconnect()
    end
    
    -- Salvar a gravação
    if #recordingData.movements > 0 then
        AutoFaseSystem.Recordings[recordingData.name] = recordingData
        return true
    end
    
    return false
end

local function recordClick()
    if AutoFaseSystem.IsRecording then
        table.insert(recordingData.clicks, {
            time = tick() - recordStartTime,
        })
    end
end

AutoFaseSystem.StartRecording = startRecording
AutoFaseSystem.StopRecording = stopRecording
AutoFaseSystem.RecordClick = recordClick

-- ==================================================================
--  PLAYBACK SYSTEM
-- ==================================================================
local playbackConnection = nil

local function playRecording(recordingName, loop, speed)
    if not AutoFaseSystem.Recordings[recordingName] then
        return false
    end
    
    local recording = AutoFaseSystem.Recordings[recordingName]
    speed = speed or 1.0
    loop = loop ~= false -- default true
    
    AutoFaseSystem.IsPlayingBack = true
    AutoFaseSystem.PlaybackSpeed = speed
    
    if playbackConnection then
        playbackConnection:Disconnect()
    end
    
    playbackConnection = RunService.Heartbeat:Connect(function()
        if not AutoFaseSystem.IsPlayingBack then return end
        
        local root = hrp()
        if not root then return end
        
        local elapsed = (tick() - recordStartTime) * speed
        
        -- Verificar se precisa fazer loop
        if elapsed > recording.duration then
            if loop then
                recordStartTime = tick()
            else
                AutoFaseSystem.IsPlayingBack = false
                playbackConnection:Disconnect()
                return
            end
        end
        
        -- Encontrar o movimento mais próximo do tempo atual
        local targetMove = nil
        for _, move in ipairs(recording.movements) do
            if move.time <= elapsed then
                targetMove = move
            else
                break
            end
        end
        
        if targetMove then
            -- Mover o personagem para a posição da gravação
            local h = hum()
            if h then
                h:MoveTo(targetMove.position)
            end
        end
        
        -- Reproduzir clicks
        for _, click in ipairs(recording.clicks) do
            if click.time <= elapsed and click.time > (elapsed - 0.1) then
                pcall(function()
                    Remotes.ClicouParaGanharEgo:FireServer()
                end)
            end
        end
    end)
    
    recordStartTime = tick()
    return true
end

local function stopPlayback()
    if playbackConnection then
        playbackConnection:Disconnect()
        playbackConnection = nil
    end
    AutoFaseSystem.IsPlayingBack = false
end

AutoFaseSystem.PlayRecording = playRecording
AutoFaseSystem.StopPlayback = stopPlayback

-- ==================================================================
--  FILE MANAGEMENT (renomear, deletar, listar)
-- ==================================================================
local function renameRecording(oldName, newName)
    if not AutoFaseSystem.Recordings[oldName] then
        return false
    end
    
    if AutoFaseSystem.Recordings[newName] then
        return false -- Nova nome já existe
    end
    
    local recording = AutoFaseSystem.Recordings[oldName]
    recording.name = newName
    AutoFaseSystem.Recordings[newName] = recording
    AutoFaseSystem.Recordings[oldName] = nil
    
    return true
end

local function deleteRecording(name)
    if not AutoFaseSystem.Recordings[name] then
        return false
    end
    
    AutoFaseSystem.Recordings[name] = nil
    return true
end

local function getRecordingsList()
    local list = {}
    for name, data in pairs(AutoFaseSystem.Recordings) do
        table.insert(list, {
            name = name,
            duration = data.duration,
            movements = #data.movements,
            createdAt = data.createdAt,
        })
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

AutoFaseSystem.RenameRecording = renameRecording
AutoFaseSystem.DeleteRecording = deleteRecording
AutoFaseSystem.GetRecordingsList = getRecordingsList

-- ==================================================================
--  EXPORT/IMPORT JSON
-- ==================================================================
local function exportRecordingJSON(name)
    if not AutoFaseSystem.Recordings[name] then
        return nil
    end
    
    local recording = AutoFaseSystem.Recordings[name]
    local json = game:GetService("HttpService"):JSONEncode(recording)
    return json
end

local function importRecordingJSON(jsonData)
    pcall(function()
        local recording = game:GetService("HttpService"):JSONDecode(jsonData)
        if recording.name then
            AutoFaseSystem.Recordings[recording.name] = recording
            return true
        end
    end)
    return false
end

AutoFaseSystem.ExportRecordingJSON = exportRecordingJSON
AutoFaseSystem.ImportRecordingJSON = importRecordingJSON

-- ==================================================================
--  USER INPUT (detectar cliques durante gravação)
-- ==================================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        recordClick()
    end
end)

return AutoFaseSystem
