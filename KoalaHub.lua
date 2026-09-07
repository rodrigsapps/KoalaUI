--[[
    ██╗  ██╗ ██████╗  █████╗ ██╗      █████╗     ██╗  ██╗██╗   ██╗██████╗
    ██║ ██╔╝██╔═══██╗██╔══██╗██║     ██╔══██╗    ██║  ██║██║   ██║██╔══██╗
    █████╔╝ ██║   ██║███████║██║     ███████║    ███████║██║   ██║██████╔╝
    ██╔═██╗ ██║   ██║██╔══██║██║     ██╔══██║    ██╔══██║██║   ██║██╔══██╗
    ██║  ██╗╚██████╔╝██║  ██║███████╗██║  ██║    ██║  ██║╚██████╔╝██████╔╝
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝

    KOALA HUB v1.3.0 — [👑] +1 Clique Por Ego
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
    AutoTrofeu = false,
    Noclip = false,
    AntiAFK = true,
}

--==================================================================--
--  HELPERS
--==================================================================--
local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- anda ate uma posicao (MoveTo = andar de verdade, sem kick por teleporte)
-- com anti-travamento: se ficar parado, pula e tenta de novo
-- retorna true quando chega ou false se cancelado
local function andarAte(pos, flagName, timeout)
    local h = hum()
    local root = hrp()
    if not h or not root then return false end

    timeout = timeout or 30
    local inicio = tick()
    local ultimaPos = root.Position
    local ultimoProgresso = tick()

    while flagName == nil or Flags[flagName] do
        root = hrp()
        h = hum()
        if not root or not h or h.Health <= 0 then return false end

        local dist = (root.Position - pos).Magnitude
        if dist < 6 then return true end
        if tick() - inicio > timeout then return false end

        -- anti-travamento: se nao saiu do lugar em 3s, pula
        if (root.Position - ultimaPos).Magnitude > 1 then
            ultimaPos = root.Position
            ultimoProgresso = tick()
        elseif tick() - ultimoProgresso > 3 then
            h.Jump = true
            ultimoProgresso = tick()
        end

        h:MoveTo(pos)
        task.wait(0.5)
    end
    return false
end

-- noclip: atravessa paredes/obstaculos enquanto ligado
RunService.Stepped:Connect(function()
    if not Flags.Noclip then return end
    local c = LP.Character
    if c then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                p.CanCollide = false
            end
        end
    end
end)

-- acha a primeira BasePart dentro de um modelo/folder
local function acharPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart", true)
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

local esteiraSelecionada = esteiraNames[#esteiraNames]

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
    Title = "Auto Esteira (andando)",
    Desc = "ANDA ate a esteira escolhida e fica farmando — sem teleporte, sem kick",
    Value = false,
    Callback = function(v)
        Flags.AutoEsteira = v
        if v then
            task.spawn(function()
                while Flags.AutoEsteira do
                    local model = esteiraMap[esteiraSelecionada]
                    local part = acharPart(model)
                    if part then
                        -- anda ate a esteira
                        local chegou = andarAte(part.Position + Vector3.new(0, 0, 0), "AutoEsteira", 60)
                        if chegou then
                            -- chegou: fica parado farmando
                            local h = hum()
                            if h then h:MoveTo(hrp().Position) end
                            while Flags.AutoEsteira do
                                pcall(function()
                                    Remotes.ClicouParaGanharEgo:FireServer()
                                end)
                                task.wait(0.05)
                                -- se caiu/morreu, volta a andar
                                local root = hrp()
                                if not root or (root.Position - part.Position).Magnitude > 12 then
                                    break
                                end
                            end
                        else
                            task.wait(1)
                        end
                    else
                        task.wait(1)
                    end
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
--  TAB: TROFEU
--==================================================================--
local TrofeuTab = Window:Tab({ Title = "Troféu", Icon = "trophy" })

TrofeuTab:Section({ Title = "Fases" })

-- posicao exata do trofeu da ultima fase (confirmada in-game)
local TROFEU_CF = CFrame.new(-16.921936, -3.63867998, 3353.7356, -1, 0, 0, 0, 1, 0, 0, 0, -1)

-- nomes que o trofeu/win pode ter no mapa
local TROFEU_NOMES = { "trofeu", "trophy", "win", "goal", "finish", "recompensa", "prize", "podio", "podium" }

local function acharTrofeu()
    -- procura nas fases primeiro (da ultima pra primeira)
    local phases = Workspace:FindFirstChild("Gameplay") and Workspace.Gameplay:FindFirstChild("Phases")
    if phases then
        local nums = {}
        for _, f in ipairs(phases:GetChildren()) do
            local n = tonumber(f.Name)
            if n then table.insert(nums, n) end
        end
        table.sort(nums, function(a, b) return a > b end)
        for _, n in ipairs(nums) do
            local pasta = phases:FindFirstChild(tostring(n))
            if pasta then
                for _, d in ipairs(pasta:GetDescendants()) do
                    if d:IsA("BasePart") then
                        local nm = d.Name:lower()
                        for _, padrao in ipairs(TROFEU_NOMES) do
                            if nm:find(padrao) then return d end
                        end
                    end
                end
            end
        end
        -- fallback: ultima fase, qualquer parte
        if #nums > 0 then
            local ultima = phases:FindFirstChild(tostring(nums[1]))
            return acharPart(ultima)
        end
    end
    -- procura no workspace inteiro
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("BasePart") then
            local nm = d.Name:lower()
            for _, padrao in ipairs(TROFEU_NOMES) do
                if nm:find(padrao) then return d end
            end
        end
    end
    return nil
end

-- anda ate o trofeu: usa a posicao fixa da ultima fase; se nao chegar, tenta achar por nome
-- liga noclip durante o percurso pra nao travar em parede/porta
local function irAoTrofeu(flagName)
    local noclipAntes = Flags.Noclip
    Flags.Noclip = true
    -- caminho principal: posicao fixa confirmada
    local chegou = andarAte(TROFEU_CF.Position, flagName, 180)
    if not chegou then
        -- fallback: busca por nome no mapa
        local trofeu = acharTrofeu()
        if trofeu then
            chegou = andarAte(trofeu.Position, flagName, 120)
        end
    end
    Flags.Noclip = noclipAntes
    return chegou
end

-- encosta no trofeu e avisa o servidor
local function coletarTrofeu()
    local root = hrp()
    if root then
        root.CFrame = TROFEU_CF + Vector3.new(0, 2, 0)
    end
    pcall(function()
        Remotes.MostrarWin:FireServer()
    end)
end

TrofeuTab:Toggle({
    Title = "Auto Troféu (andando)",
    Desc = "Anda ate o trofeu da ultima fase e coleta — sem teleporte, sem kick",
    Value = false,
    Callback = function(v)
        Flags.AutoTrofeu = v
        if v then
            task.spawn(function()
                while Flags.AutoTrofeu do
                    local chegou = irAoTrofeu("AutoTrofeu")
                    if chegou then
                        coletarTrofeu()
                        task.wait(3)
                    else
                        task.wait(2)
                    end
                end
            end)
        end
    end,
})

TrofeuTab:Button({
    Title = "Andar até o Troféu (1x)",
    Desc = "Anda ate o trofeu uma unica vez",
    Callback = function()
        task.spawn(function()
            local chegou = irAoTrofeu(nil)
            if chegou then
                coletarTrofeu()
            else
                Koala:Notify({
                    Title = "Koala Hub",
                    Content = "Nao consegui chegar no trofeu.",
                    Duration = 4,
                })
            end
        end)
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

ConfigTab:Section({ Title = "Movimento" })

ConfigTab:Toggle({
    Title = "Noclip",
    Desc = "Atravessa paredes e obstaculos — fica ligado ate voce desligar",
    Value = false,
    Callback = function(v)
        Flags.Noclip = v
        if not v then
            -- ao desligar, restaura colisao do personagem
            local c = LP.Character
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") then
                        pcall(function() p.CanCollide = true end)
                    end
                end
            end
        end
    end,
})

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
        for k in pairs(Flags) do Flags[k] = false end
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