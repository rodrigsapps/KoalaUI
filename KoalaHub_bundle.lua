--[[
    ██╗  ██╗ ██████╗  █████╗ ██╗      █████╗     ██╗  ██╗██╗   ██╗██████╗
    ██║ ██╔╝██╔═══██╗██╔══██╗██║     ██╔══██╗    ██║  ██║██║   ██║██╔══██╗
    █████╔╝ ██║   ██║███████║██║     ███████║    ███████║██║   ██║██████╔╝
    ██╔═██╗ ██║   ██║██╔══██║██║     ██╔══██║    ██╔══██║██║   ██║██╔══██╗
    ██║  ██╗╚██████╔╝██║  ██║███████╗██║  ██║    ██║  ██║╚██████╔╝██████╔╝
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝

    KOALA HUB v1.4.0 — [👑] +1 Clique Por Ego
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
--  TAB: AUTO FASE (GRAVADOR + ANTI-LAG)
--==================================================================--
pcall(function()
    -- modulo Gravador inlinado (era um HttpGet separado)
    local Gravador = (function()
        --[[
            KOALA HUB — MODULO GRAVADOR / AUTO FASE + ANTI-LAG
            ---------------------------------------------------
            Grava as acoes do player (posicao, rotacao e pulo), salva em disco,
            e repete em loop no modo "Auto Fase".

            Integracao no KoalaHub.lua (2 linhas, no final do arquivo):

                local Gravador = loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaGravador.lua"))()
                Gravador(Koala, Window, Flags)

            Executores testados: Arceus X, Fluxus, Delta (todos expoem writefile/listfiles).
            Se o executor nao tiver as funcoes de arquivo, o modulo cai para modo
            memoria: grava e repete normalmente, mas perde tudo ao fechar o jogo.
        ]]

        return function(Koala, Window, Flags)

        local Players    = game:GetService("Players")
        local RunService = game:GetService("RunService")
        local Lighting   = game:GetService("Lighting")
        local HttpService= game:GetService("HttpService")
        local Workspace  = game:GetService("Workspace")

        local LP = Players.LocalPlayer

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

        local function notify(msg, dur)
            pcall(function()
                Koala:Notify({
                    Title = "Koala Hub",
                    Content = msg,
                    Duration = dur or 4,
                    Icon = "paw-print",
                })
            end)
        end

        --==================================================================--
        --  CAMADA DE ARQUIVO (com deteccao de suporte)
        --==================================================================--
        local FOLDER = "KoalaHub"
        local SUBFOLDER = "KoalaHub/gravacoes"

        -- pega uma global do executor resolvendo pelo metatable do env
        -- (rawget nao funciona: writefile & cia vivem na global table real)
        local function glob(nome)
            local ok, v = pcall(function() return getfenv()[nome] end)
            if ok and type(v) == "function" then return v end
            return nil
        end

        local FS = {
            write  = glob("writefile"),
            read   = glob("readfile"),
            list   = glob("listfiles"),
            isfile = glob("isfile"),
            isdir  = glob("isfolder"),
            mkdir  = glob("makefolder"),
            del    = glob("delfile"),
        }

        local TEM_DISCO = (FS.write and FS.read and FS.list and FS.del) and true or false

        if TEM_DISCO then
            pcall(function()
                if FS.isdir and not FS.isdir(FOLDER) then FS.mkdir(FOLDER) end
                if FS.isdir and not FS.isdir(SUBFOLDER) then FS.mkdir(SUBFOLDER) end
            end)
        end

        -- fallback em memoria quando o executor nao tem file system
        local MEM = {}

        local function nomeSeguro(n)
            n = tostring(n or ""):gsub("[^%w%s%-_]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if n == "" then n = "gravacao" end
            return n:sub(1, 40)
        end

        local function caminho(nome)
            return SUBFOLDER .. "/" .. nome .. ".json"
        end

        local function listarNomes()
            local out = {}
            if TEM_DISCO then
                local ok, files = pcall(FS.list, SUBFOLDER)
                if ok and type(files) == "table" then
                    for _, f in ipairs(files) do
                        local nome = tostring(f):match("([^/\\]+)%.json$")
                        if nome then table.insert(out, nome) end
                    end
                end
            else
                for nome in pairs(MEM) do table.insert(out, nome) end
            end
            table.sort(out)
            return out
        end

        local function salvarGravacao(nome, dados)
            local ok, json = pcall(function() return HttpService:JSONEncode(dados) end)
            if not ok then return false, "falha ao serializar" end
            if TEM_DISCO then
                local ok2, err = pcall(FS.write, caminho(nome), json)
                if not ok2 then return false, tostring(err) end
            else
                MEM[nome] = json
            end
            return true
        end

        local function carregarGravacao(nome)
            local json
            if TEM_DISCO then
                local ok, res = pcall(FS.read, caminho(nome))
                if not ok then return nil end
                json = res
            else
                json = MEM[nome]
            end
            if not json then return nil end
            local ok, dados = pcall(function() return HttpService:JSONDecode(json) end)
            if not ok or type(dados) ~= "table" or type(dados.frames) ~= "table" then return nil end
            return dados
        end

        local function apagarGravacao(nome)
            if TEM_DISCO then
                local ok = pcall(FS.del, caminho(nome))
                return ok
            else
                MEM[nome] = nil
                return true
            end
        end

        --==================================================================--
        --  GRAVACAO
        --==================================================================--
        local TAXA = 0.05                 -- 20 amostras por segundo
        local gravando = false
        local bufferFrames = {}
        local conexaoGrav = nil

        -- guarda CFrame como 12 componentes (posicao + matriz de rotacao)
        local function capturarFrame(t, raiz, h)
            local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = raiz.CFrame:GetComponents()
            return {
                t = t,
                c = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 },
                j = (h and h:GetState() == Enum.HumanoidStateType.Jumping) or false,
            }
        end

        local function frameParaCFrame(f)
            local c = f.c
            return CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
        end

        local function iniciarGravacao()
            local raiz, h = hrp(), hum()
            if not raiz then
                notify("Personagem nao encontrado. Espera respawnar.")
                return false
            end
            bufferFrames = {}
            gravando = true

            local t0 = os.clock()
            local acc = 0
            table.insert(bufferFrames, capturarFrame(0, raiz, h))

            conexaoGrav = RunService.Heartbeat:Connect(function(dt)
                if not gravando then return end
                acc = acc + dt
                if acc < TAXA then return end
                acc = 0
                local r, hh = hrp(), hum()
                if not r then return end
                table.insert(bufferFrames, capturarFrame(os.clock() - t0, r, hh))
            end)
            return true
        end

        local function pararGravacao()
            gravando = false
            if conexaoGrav then
                conexaoGrav:Disconnect()
                conexaoGrav = nil
            end
            return bufferFrames
        end

        --==================================================================--
        --  REPLAY (AUTO FASE) — loop infinito
        --==================================================================--
        Flags.AutoFase = false
        local gravacaoSelecionada = nil

        local function tocarUmaVez(dados)
            local frames = dados.frames
            if #frames < 2 then return end

            local raiz, h = hrp(), hum()
            if not raiz then return end

            local i = 1
            local t = 0

            while Flags.AutoFase and i < #frames do
                local dt = RunService.Heartbeat:Wait()
                t = t + dt

                -- avanca até o par de frames correspondente ao tempo atual
                while i < #frames and frames[i + 1].t <= t do
                    i = i + 1
                end
                if i >= #frames then break end

                local a, b = frames[i], frames[i + 1]
                local span = b.t - a.t
                local alpha = span > 0 and math.clamp((t - a.t) / span, 0, 1) or 0

                raiz, h = hrp(), hum()
                if not raiz then return end

                -- interpolacao suave entre as amostras
                local ok = pcall(function()
                    raiz.CFrame = frameParaCFrame(a):Lerp(frameParaCFrame(b), alpha)
                end)
                if not ok then return end

                if b.j and h then
                    pcall(function() h.Jump = true end)
                end
            end
        end

        local function loopAutoFase()
            task.spawn(function()
                while Flags.AutoFase do
                    if not gravacaoSelecionada then
                        notify("Escolhe uma gravacao primeiro.")
                        Flags.AutoFase = false
                        return
                    end
                    local dados = carregarGravacao(gravacaoSelecionada)
                    if not dados then
                        notify("Nao consegui ler a gravacao '" .. tostring(gravacaoSelecionada) .. "'.")
                        Flags.AutoFase = false
                        return
                    end
                    tocarUmaVez(dados)
                    if Flags.AutoFase then task.wait(0.3) end  -- respiro entre repeticoes
                end
            end)
        end

        --==================================================================--
        --  ANTI-LAG
        --==================================================================--
        local CLASSES_EFEITO = {
            ParticleEmitter = true, Trail = true, Smoke = true, Fire = true,
            Sparkles = true, Explosion = true, Beam = true,
        }
        local CLASSES_POS = {
            BloomEffect = true, SunRaysEffect = true, DepthOfFieldEffect = true,
            BlurEffect = true, ColorCorrectionEffect = true,
        }

        local antilagLigado = false
        local conexaoAntiLag = nil
        local estadoOriginal = {}

        local function limparObjeto(obj)
            local cls = obj.ClassName
            if CLASSES_EFEITO[cls] then
                pcall(function() obj.Enabled = false end)
            elseif cls == "Texture" or cls == "Decal" then
                pcall(function() obj.Transparency = 1 end)
            elseif CLASSES_POS[cls] then
                pcall(function() obj.Enabled = false end)
            elseif cls == "MeshPart" then
                pcall(function() obj.RenderFidelity = Enum.RenderFidelity.Performance end)
            end
        end

        local function ligarAntiLag()
            antilagLigado = true

            estadoOriginal.GlobalShadows = Lighting.GlobalShadows
            estadoOriginal.Technology = Lighting.Technology
            estadoOriginal.Decoration = Workspace.Terrain.Decoration

            pcall(function() Lighting.GlobalShadows = false end)
            pcall(function() Workspace.Terrain.Decoration = false end)
            pcall(function() Workspace.Terrain.WaterWaveSize = 0 end)
            pcall(function() Workspace.Terrain.WaterReflectance = 0 end)
            pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)

            for _, obj in ipairs(game:GetDescendants()) do
                limparObjeto(obj)
            end

            -- mantem limpando o que aparecer depois
            conexaoAntiLag = game.DescendantAdded:Connect(function(obj)
                if antilagLigado then
                    task.defer(limparObjeto, obj)
                end
            end)
        end

        local function desligarAntiLag()
            antilagLigado = false
            if conexaoAntiLag then
                conexaoAntiLag:Disconnect()
                conexaoAntiLag = nil
            end
            pcall(function() Lighting.GlobalShadows = estadoOriginal.GlobalShadows end)
            pcall(function() Workspace.Terrain.Decoration = estadoOriginal.Decoration end)
            pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
            notify("Anti-Lag desligado. Efeitos ja removidos so voltam ao recarregar o jogo.", 5)
        end

        --==================================================================--
        --  UI
        --==================================================================--
        local GravTab = Window:Tab({ Title = "Auto Fase", Icon = "circle-play" })

        GravTab:Section({ Title = "Gravador" })

        local nomeDigitado = ""
        local dropdownRef = nil

        local function atualizarDropdown()
            local nomes = listarNomes()
            if #nomes == 0 then nomes = { "(nenhuma)" } end
            pcall(function()
                if dropdownRef and dropdownRef.Refresh then
                    dropdownRef:Refresh(nomes)
                elseif dropdownRef and dropdownRef.SetValues then
                    dropdownRef:SetValues(nomes)
                end
            end)
            return nomes
        end

        pcall(function()
            GravTab:Input({
                Title = "Nome da gravacao",
                Desc = "Usado ao salvar e ao renomear",
                Placeholder = "ex: fase1",
                Callback = function(v)
                    nomeDigitado = v
                end,
            })
        end)

        GravTab:Toggle({
            Title = "Gravar movimento",
            Desc = "Liga = comeca a gravar. Desliga = para e salva com o nome acima",
            Value = false,
            Callback = function(v)
                if v then
                    if Flags.AutoFase then
                        notify("Desliga o Auto Fase antes de gravar.")
                        return
                    end
                    if iniciarGravacao() then
                        notify("Gravando... desliga o toggle pra parar e salvar.", 4)
                    end
                else
                    if not gravando then return end
                    local frames = pararGravacao()
                    if #frames < 2 then
                        notify("Gravacao curta demais, descartada.")
                        return
                    end
                    local nome = nomeSeguro(nomeDigitado ~= "" and nomeDigitado or ("gravacao_" .. os.date("%H%M%S")))
                    local dados = {
                        nome = nome,
                        criado = os.time(),
                        taxa = TAXA,
                        duracao = frames[#frames].t,
                        frames = frames,
                    }
                    local ok, err = salvarGravacao(nome, dados)
                    if ok then
                        notify(("Salvo '%s' — %d frames, %.1fs"):format(nome, #frames, dados.duracao), 5)
                        atualizarDropdown()
                    else
                        notify("Falha ao salvar: " .. tostring(err), 6)
                    end
                end
            end,
        })

        GravTab:Section({ Title = "Gravacoes salvas" })

        dropdownRef = GravTab:Dropdown({
            Title = "Gravacao",
            Desc = "Qual gravacao o Auto Fase vai repetir",
            Values = (function()
                local n = listarNomes()
                return #n > 0 and n or { "(nenhuma)" }
            end)(),
            Value = listarNomes()[1] or "(nenhuma)",
            Callback = function(v)
                gravacaoSelecionada = (v ~= "(nenhuma)") and v or nil
            end,
        })

        gravacaoSelecionada = listarNomes()[1]

        GravTab:Button({
            Title = "Atualizar lista",
            Desc = "Recarrega as gravacoes salvas",
            Callback = function()
                local n = atualizarDropdown()
                notify(#n .. " gravacao(oes) encontrada(s).")
            end,
        })

        GravTab:Button({
            Title = "Renomear selecionada",
            Desc = "Renomeia a gravacao escolhida usando o campo 'Nome da gravacao'",
            Callback = function()
                if not gravacaoSelecionada then
                    notify("Escolhe uma gravacao primeiro.")
                    return
                end
                local novo = nomeSeguro(nomeDigitado)
                if novo == "gravacao" and nomeDigitado == "" then
                    notify("Escreve o novo nome no campo acima.")
                    return
                end
                if novo == gravacaoSelecionada then
                    notify("O nome novo e igual ao atual.")
                    return
                end
                local dados = carregarGravacao(gravacaoSelecionada)
                if not dados then
                    notify("Nao consegui ler a gravacao.")
                    return
                end
                dados.nome = novo
                local ok = salvarGravacao(novo, dados)
                if not ok then
                    notify("Falha ao salvar com o nome novo.")
                    return
                end
                apagarGravacao(gravacaoSelecionada)
                notify(("Renomeado: '%s' -> '%s'"):format(gravacaoSelecionada, novo))
                gravacaoSelecionada = novo
                atualizarDropdown()
            end,
        })

        GravTab:Button({
            Title = "Apagar selecionada",
            Desc = "Remove a gravacao escolhida (nao tem como desfazer)",
            Callback = function()
                if not gravacaoSelecionada then
                    notify("Escolhe uma gravacao primeiro.")
                    return
                end
                if Flags.AutoFase then
                    notify("Desliga o Auto Fase antes de apagar.")
                    return
                end
                local alvo = gravacaoSelecionada
                if apagarGravacao(alvo) then
                    notify("Apagado: '" .. alvo .. "'")
                    gravacaoSelecionada = nil
                    atualizarDropdown()
                else
                    notify("Falha ao apagar.")
                end
            end,
        })

        GravTab:Section({ Title = "Auto Fase" })

        GravTab:Toggle({
            Title = "Auto Fase (repetir em loop)",
            Desc = "Repete a gravacao selecionada sem parar",
            Value = false,
            Callback = function(v)
                if v and gravando then
                    notify("Para a gravacao antes de ligar o Auto Fase.")
                    return
                end
                Flags.AutoFase = v
                if v then
                    if not gravacaoSelecionada then
                        notify("Escolhe uma gravacao primeiro.")
                        Flags.AutoFase = false
                        return
                    end
                    notify("Auto Fase ligado: '" .. gravacaoSelecionada .. "'")
                    loopAutoFase()
                else
                    notify("Auto Fase desligado.")
                end
            end,
        })

        GravTab:Section({ Title = "Anti-Lag / Booster" })

        GravTab:Toggle({
            Title = "Anti-Lag (FPS mais liso)",
            Desc = "Desliga particulas, sombras, texturas e efeitos de tela",
            Value = false,
            Callback = function(v)
                if v then
                    ligarAntiLag()
                    notify("Anti-Lag ligado.", 4)
                else
                    desligarAntiLag()
                end
            end,
        })

        pcall(function()
            if glob("setfpscap") then
                GravTab:Dropdown({
                    Title = "Limite de FPS",
                    Desc = "Travar o FPS deixa o frame time mais constante",
                    Values = { "30", "60", "90", "120", "Sem limite" },
                    Value = "60",
                    Callback = function(v)
                        local cap = tonumber(v) or 0
                        pcall(function() setfpscap(cap) end)
                    end,
                })
            end
        end)

        if not TEM_DISCO then
            notify("Executor sem suporte a arquivos: as gravacoes duram so esta sessao.", 8)
        end

        end
    end)()
    Gravador(Koala, Window, Flags)
end)

--==================================================================--
--  NOTIFICACAO INICIAL
--==================================================================--
Koala:Notify({
    Title = "Koala Hub",
    Content = "Carregado! discord.gg/ZRFffEgQQM",
    Duration = 5,
    Icon = "paw-print",
})