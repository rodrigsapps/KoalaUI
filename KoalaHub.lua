--[[
    ██╗  ██╗ ██████╗  █████╗ ██╗      █████╗     ██╗  ██╗██╗   ██╗██████╗
    ██║ ██╔╝██╔═══██╗██╔══██╗██║     ██╔══██╗    ██║  ██║██║   ██║██╔══██╗
    █████╔╝ ██║   ██║███████║██║     ███████║    ███████║██║   ██║██████╔╝
    ██╔═██╗ ██║   ██║██╔══██║██║     ██╔══██║    ██╔══██║██║   ██║██╔══██╗
    ██║  ██╗╚██████╔╝██║  ██║███████╗██║  ██║    ██║  ██║╚██████╔╝██████╔╝
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝

    KOALA HUB v1.1.0 — [👑] +1 Clique Por Ego
    UI: WindUI (clone Koala UI v3)
    Discord: https://discord.gg/ZRFffEgQQM

    Loadstring:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaHub.lua"))()
]]

--==================================================================--
--  SETUP
--==================================================================--
local Koala = loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaUI_v3.lua"))()

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VIM        = game:GetService("VirtualInputManager")

local LP = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")

local Flags = {
    AutoClick = false,
    AutoEsteira = false,
    AutoUpgrade = false,
    AutoRebirth = false,
    AutoSpin = false,
    AutoGift = false,
    AntiAFK = true,
}

--==================================================================--
--  HELPERS
--==================================================================--
local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function tpTo(cf)
    local root = hrp()
    if root then root.CFrame = cf end
end

-- anti-kick AFK (simula atividade leve, sem mexer o personagem)
do
    local lastPing = 0
    RunService.Heartbeat:Connect(function()
        if not Flags.AntiAFK then return end
        if tick() - lastPing > 45 then
            lastPing = tick()
            pcall(function()
                VIM:SendKeyEvent(true, Enum.KeyCode.Unknown, false, game)
                VIM:SendKeyEvent(false, Enum.KeyCode.Unknown, false, game)
            end)
        end
    end)
end

--==================================================================--
--  JANELA
--==================================================================--
local Window = Koala:CreateWindow({
    Title = "Koala Hub",
    Icon = "paw-print",
    Author = "discord.gg/ZRFffEgQQM",
    Folder = "KoalaHub",
    Size = UDim2.fromOffset(580, 460),
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightControl,
})

--==================================================================--
--  TAB: FARM
--==================================================================--
local FarmTab = Window:Tab({ Title = "Farm", Icon = "zap" })

FarmTab:Section({ Title = "Auto Click" })

FarmTab:Toggle({
    Title = "Auto Click (Ego)",
    Desc = "Clica sozinho usando o remote do jogo — sem kick do mapa",
    Value = false,
    Callback = function(v)
        Flags.AutoClick = v
        if v then
            task.spawn(function()
                while Flags.AutoClick do
                    pcall(function()
                        Remotes.ClicouParaGanharEgo:FireServer()
                    end)
                    task.wait(0.05)
                end
            end)
        end
    end,
})

FarmTab:Toggle({
    Title = "Auto Click Oficial (botão do jogo)",
    Desc = "Liga o auto-click nativo do jogo (remote Alternar)",
    Value = false,
    Callback = function(v)
        pcall(function()
            Remotes.AutoClickRemotes.Alternar:FireServer()
        end)
    end,
})

FarmTab:Section({ Title = "Esteiras (Conveyors)" })

local esteiraNames = {}
local esteiraMap = {}
pcall(function()
    local machines = Workspace:WaitForChild("Conveyors"):WaitForChild("Machines")
    for _, m in ipairs(machines:GetChildren()) do
        local mult = m.Name:match("Conveyor_(%d+)x")
        if mult then
            local label = "Esteira " .. mult .. "x"
            -- evita duplicata (tem 2x Conveyor_1x no mapa)
            if not esteiraMap[label] then
                table.insert(esteiraNames, label)
                esteiraMap[label] = m
            end
        end
    end
    table.sort(esteiraNames, function(a, b)
        return tonumber(a:match("(%d+)x")) < tonumber(b:match("(%d+)x"))
    end)
end)

local esteiraSelecionada = esteiraNames[#esteiraNames] -- melhor por padrao

FarmTab:Dropdown({
    Title = "Esteira",
    Desc = "Escolhe qual esteira farmar",
    Values = esteiraNames,
    Value = esteiraSelecionada,
    Callback = function(v)
        esteiraSelecionada = v
    end,
})

FarmTab:Toggle({
    Title = "Auto Esteira",
    Desc = "Teleporta UMA vez pra esteira e fica farmando parado (sem ficar voltando)",
    Value = false,
    Callback = function(v)
        Flags.AutoEsteira = v
        if v then
            task.spawn(function()
                -- teleporta uma unica vez pra nao dar kick por teleporte excessivo
                pcall(function()
                    local model = esteiraMap[esteiraSelecionada]
                    if model then
                        local part = model:FindFirstChildWhichIsA("BasePart", true)
                        if part then
                            tpTo(part.CFrame + Vector3.new(0, 3, 0))
                        end
                    end
                end)
                -- depois so mantem o auto click ligado enquanto estiver na esteira
                while Flags.AutoEsteira do
                    pcall(function()
                        Remotes.ClicouParaGanharEgo:FireServer()
                    end)
                    task.wait(0.05)
                end
            end)
        end
    end,
})

FarmTab:Section({ Title = "Upgrades" })

FarmTab:Toggle({
    Title = "Auto Comprar Upgrades",
    Desc = "Compra todos os upgrades do 1 ao 20 em loop",
    Value = false,
    Callback = function(v)
        Flags.AutoUpgrade = v
        if v then
            task.spawn(function()
                while Flags.AutoUpgrade do
                    for i = 1, 20 do
                        if not Flags.AutoUpgrade then break end
                        pcall(function()
                            Remotes.ComprarUpgrade:FireServer(i)
                        end)
                        task.wait(0.3)
                    end
                    task.wait(2)
                end
            end)
        end
    end,
})

--==================================================================--
--  TAB: RECOMPENSAS
--==================================================================--
local RewardTab = Window:Tab({ Title = "Recompensas", Icon = "gift" })

RewardTab:Section({ Title = "Roleta" })

RewardTab:Toggle({
    Title = "Auto Spin (Roda da Fortuna)",
    Desc = "Gira a roda automaticamente",
    Value = false,
    Callback = function(v)
        Flags.AutoSpin = v
        if v then
            task.spawn(function()
                while Flags.AutoSpin do
                    pcall(function()
                        Remotes.SpinWheelEvent:FireServer()
                    end)
                    task.wait(5)
                end
            end)
        end
    end,
})

RewardTab:Section({ Title = "Presentes (por tempo de jogo)" })

RewardTab:Toggle({
    Title = "Auto Coletar Presentes",
    Desc = "Resgata os gifts por tempo — tenta todos os ids",
    Value = false,
    Callback = function(v)
        Flags.AutoGift = v
        if v then
            task.spawn(function()
                while Flags.AutoGift do
                    -- tenta ids numericos de 1 a 12 (padrao de gifts por tempo)
                    for id = 1, 12 do
                        if not Flags.AutoGift then break end
                        pcall(function()
                            Remotes.GiftRemotes.Claim:InvokeServer(id)
                        end)
                        task.wait(0.2)
                    end
                    task.wait(10)
                end
            end)
        end
    end,
})

RewardTab:Button({
    Title = "Coletar Recompensa do Grupo",
    Desc = "Resgata o bau do grupo (GroupChest)",
    Callback = function()
        pcall(function()
            Remotes.GroupRewardRemotes.Claim:InvokeServer()
        end)
    end,
})

RewardTab:Button({
    Title = "Coletar Ego Offline",
    Desc = "Resgata o ego acumulado offline",
    Callback = function()
        pcall(function()
            Remotes.OfflineEgoRemotes.ClaimFree:InvokeServer()
        end)
    end,
})

--==================================================================--
--  TAB: REBIRTH
--==================================================================--
local RebirthTab = Window:Tab({ Title = "Rebirth", Icon = "repeat" })

RebirthTab:Button({
    Title = "Fazer Rebirth",
    Desc = "Solicita rebirth agora",
    Callback = function()
        pcall(function()
            Remotes.SolicitarRebirth:InvokeServer()
        end)
    end,
})

RebirthTab:Toggle({
    Title = "Auto Rebirth",
    Desc = "Faz rebirth automaticamente quando possivel",
    Value = false,
    Callback = function(v)
        Flags.AutoRebirth = v
        if v then
            task.spawn(function()
                while Flags.AutoRebirth do
                    pcall(function()
                        Remotes.SolicitarRebirth:InvokeServer()
                    end)
                    task.wait(15)
                end
            end)
        end
    end,
})

--==================================================================--
--  TAB: CONFIG
--==================================================================--
local ConfigTab = Window:Tab({ Title = "Config", Icon = "settings" })

ConfigTab:Section({ Title = "Protecao" })

ConfigTab:Toggle({
    Title = "Anti-AFK",
    Desc = "Evita kick por inatividade (padrao: ligado)",
    Value = true,
    Callback = function(v)
        Flags.AntiAFK = v
    end,
})

ConfigTab:Section({ Title = "Interface" })

ConfigTab:Dropdown({
    Title = "Tema",
    Values = { "Dark", "Light", "Rose", "Midnight", "Plant", "Red", "Indigo", "Sky", "Violet", "Amber", "Emerald", "Crimson" },
    Value = "Dark",
    Callback = function(v)
        Koala:SetTheme(v)
    end,
})

ConfigTab:Button({
    Title = "Fechar Hub",
    Desc = "Destroi a interface",
    Callback = function()
        Flags.AutoClick = false
        Flags.AutoEsteira = false
        Flags.AutoUpgrade = false
        Flags.AutoRebirth = false
        Flags.AutoSpin = false
        Flags.AutoGift = false
        pcall(function() Koala.ScreenGui:Destroy() end)
    end,
})

--==================================================================--
--  NOTIFICACAO INICIAL
--==================================================================--
Koala:Notify({
    Title = "Koala Hub",
    Content = "Carregado! discord.gg/ZRFffEgQQM",
    Duration = 5,
    Icon = "paw-print",
})
