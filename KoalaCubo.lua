--[[
    KOALA HUB — LEVANTE UM CUBO (Lift a Cube) — PlaceId 109530157755211
    -------------------------------------------------------------------
    v2 — mais rapido, mais sistemas.

    Novidades v2:
      * AUTO LIFT TURBO: intervalo configuravel (ate 0.05s) + rajada
        (varios ciclos abrir/concluir por tick). Muito mais rapido que v1.
      * AUTO POPS 2.0: agora pega pelo HOOK da bridge — no instante em
        que o servidor spawna o pop, a coleta volta pelo remote. Nao
        depende mais de clicar em botao na tela. (varredura de UI fica
        como fallback.)
      * ATRAVESSAR BARREIRAS: desliga a colisao dos portoes de Strength
        (World.Client.Barries) — entra nas zonas sem ter forca.
      * PROMPTS INSTANTANEOS: HoldDuration = 0 em todos os
        ProximityPrompts (bau abre sem segurar).
      * LISTA DE CUBOS AUTO-ATUALIZADA: quando o jogo da refresh nos
        cubos, o dropdown se refaz sozinho. Modo "Auto" pega sempre o
        menor cubo disponivel.
      * STATUS AO VIVO: Strength e Cash atualizando a cada segundo.
      * WalkSpeed TRAVADO (o jogo nao reseta mais).

    Formato dos remotes (do dump, BridgeNet2):
      bridge = "<UserId>_<Controller>", pacote = { Function, Args }
      Cubes: abrir {Args={idx}} | concluir {Function="FinishLift", Args={idx}}
      Training: {Args={reps}} | Pops: claim {Args={id}}
      AFK: {Args={}} a cada 30s

    Uso:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaCubo.lua"))()
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

local LP = Players.LocalPlayer

--==================================================================--
--  BRIDGENET2
--==================================================================--
local BridgeNet = nil
pcall(function()
    BridgeNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("bridgenet2"))
end)

local uid = tostring(LP.UserId):gsub("-", "")
local bridges = {}

local function bridge(nome)
    if not BridgeNet then return nil end
    if not bridges[nome] then
        local ok, b = pcall(function()
            return BridgeNet.ReferenceBridge(uid .. "_" .. nome)
        end)
        if ok then
            bridges[nome] = b
        else
            warn("[KoalaCubo] falha ao criar bridge: " .. nome)
            return nil
        end
    end
    return bridges[nome]
end

local function fire(nome, fn, args)
    local b = bridge(nome)
    if not b then return false end
    return pcall(function()
        b:Fire({ ["Function"] = fn, ["Args"] = args or {} })
    end)
end

--==================================================================--
--  HELPERS
--==================================================================--
local function notify(titulo, msg, dur)
    print("[KoalaCubo] " .. tostring(msg))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",
            { Title = titulo or "Koala Cubo", Text = msg, Duration = dur or 3 })
    end)
end

local function char() return LP.Character end
local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function hum()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function forca()
    local ok, v = pcall(function() return LP:GetAttribute("Strength") end)
    return ok and v or 0
end

local function dinheiro()
    local ok, v = pcall(function() return LP:GetAttribute("Cash") end)
    return ok and v or 0
end

local function andarAte(pos, timeout)
    local h, r = hum(), hrp()
    if not h or not r then return false end
    h:MoveTo(pos)
    local t0 = os.clock()
    while os.clock() - t0 < (timeout or 20) do
        local p = hrp()
        if not p then return false end
        local d2d = Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(pos.X, 0, pos.Z)
        if d2d.Magnitude < 7 then return true end
        task.wait(0.2)
    end
    return false
end

--==================================================================--
--  CUBOS (workspace.World.Shared.Cubes, nome numerico = index)
--==================================================================--
local function pastaCubos()
    local ok, f = pcall(function()
        return Workspace:WaitForChild("World", 10):WaitForChild("Shared", 10):WaitForChild("Cubes", 10)
    end)
    return ok and f or nil
end

local function listarCubos()
    local out = {}
    local f = pastaCubos()
    if f then
        for _, c in ipairs(f:GetChildren()) do
            local idx = tonumber(c.Name)
            if idx and c:IsA("BasePart") then
                table.insert(out, idx)
            end
        end
    end
    table.sort(out)
    return out
end

--==================================================================--
--  ESTADO
--==================================================================--
local State = {
    autoLift = false,
    autoTrain = false,
    autoPops = false,
    autoBau = false,
    antiAfk = true,
    promptsInstant = false,
    atravessar = false,
    travarSpeed = false,
}

local cuboAlvo = 1          -- 0 = Auto (menor disponivel)
local liftIntervalo = 0.1   -- s entre ciclos
local liftRajada = 1        -- ciclos abrir+concluir por tick
local trainReps = 1
local trainIntervalo = 0.15
local speedAlvo = 16

--==================================================================--
--  AUTO LIFT (turbo: intervalo + rajada configuraveis)
--==================================================================--
task.spawn(function()
    while true do
        if State.autoLift then
            local idx = cuboAlvo
            if idx == 0 then
                local lista = listarCubos()
                idx = #lista > 0 and lista[1] or 1
            end
            for _ = 1, liftRajada do
                fire("Cubes", nil, { idx })
                fire("Cubes", "FinishLift", { idx })
            end
            task.wait(liftIntervalo)
        else
            task.wait(0.25)
        end
    end
end)

--==================================================================--
--  AUTO TRAIN
--==================================================================--
task.spawn(function()
    while true do
        if State.autoTrain then
            fire("Training", nil, { trainReps })
            task.wait(trainIntervalo)
        else
            task.wait(0.25)
        end
    end
end)

--==================================================================--
--  AUTO POPS v2 — hook da bridge (claim instantaneo via remote)
--==================================================================--
task.spawn(function()
    task.wait(3) -- deixa o jogo criar as bridges primeiro
    local b = bridge("Pops")
    if not b then return end
    pcall(function()
        b:Connect(function(pacote)
            if not State.autoPops then return end
            if type(pacote) == "table" and pacote.Function == "Spawn" then
                local id = pacote.Args and pacote.Args[1]
                if type(id) == "number" then
                    fire("Pops", nil, { id })
                end
            end
        end)
    end)
end)

-- fallback: varredura de botoes na Overlay (caso o hook nao pegue)
task.spawn(function()
    local overlay
    while true do
        if State.autoPops then
            if not (overlay and overlay.Parent) then
                overlay = nil
                pcall(function()
                    local pg = LP:FindFirstChildOfClass("PlayerGui")
                    for _, g in ipairs(pg:GetChildren()) do
                        local o = g:FindFirstChild("Overlay", true)
                        if o then overlay = o break end
                    end
                end)
            end
            if overlay then
                for _, d in ipairs(overlay:GetDescendants()) do
                    if d:IsA("GuiButton") and d.Visible then
                        pcall(function()
                            for _, c in ipairs(getconnections(d.Activated)) do
                                c:Fire()
                            end
                        end)
                    end
                end
            end
            task.wait(0.4)
        else
            task.wait(0.5)
        end
    end
end)

--==================================================================--
--  AUTO BAU
--==================================================================--
task.spawn(function()
    while true do
        if State.autoBau then
            pcall(function()
                local chests = Workspace.World.Shared:FindFirstChild("Chests")
                if chests then
                    for _, m in ipairs(chests:GetChildren()) do
                        if not State.autoBau then break end
                        local part = m:FindFirstChildWhichIsA("BasePart", true)
                        local prompt = m:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if part and prompt and prompt.Enabled then
                            andarAte(part.Position, 25)
                            task.wait(0.3)
                            pcall(function() fireproximityprompt(prompt) end)
                            task.wait(2.5)
                        end
                    end
                end
            end)
            task.wait(2)
        else
            task.wait(0.5)
        end
    end
end)

--==================================================================--
--  ANTI-AFK
--==================================================================--
task.spawn(function()
    while true do
        if State.antiAfk then fire("AFK", nil, {}) end
        task.wait(25)
    end
end)

--==================================================================--
--  PROMPTS INSTANTANEOS (HoldDuration = 0)
--==================================================================--
task.spawn(function()
    while true do
        if State.promptsInstant then
            pcall(function()
                for _, d in ipairs(Workspace:GetDescendants()) do
                    if d:IsA("ProximityPrompt") and d.HoldDuration > 0 then
                        d.HoldDuration = 0
                    end
                end
            end)
        end
        task.wait(2)
    end
end)

--==================================================================--
--  ATRAVESSAR BARREIRAS (portoes de Strength — typo "Barries" e do jogo)
--==================================================================--
local barreirasSalvas = {}

local function aplicarBarreiras(semColisao)
    pcall(function()
        local pasta = Workspace.World.Client:FindFirstChild("Barries")
        if not pasta then return end
        for _, d in ipairs(pasta:GetDescendants()) do
            if d:IsA("BasePart") then
                if semColisao then
                    if barreirasSalvas[d] == nil then
                        barreirasSalvas[d] = d.CanCollide
                    end
                    d.CanCollide = false
                else
                    if barreirasSalvas[d] ~= nil then
                        d.CanCollide = barreirasSalvas[d]
                    end
                end
            end
        end
    end)
end

task.spawn(function()
    while true do
        if State.atravessar then aplicarBarreiras(true) end
        task.wait(1)
    end
end)

--==================================================================--
--  WALKSPEED TRAVADO
--==================================================================--
RunService.Heartbeat:Connect(function()
    if State.travarSpeed then
        local h = hum()
        if h and h.WalkSpeed ~= speedAlvo then
            h.WalkSpeed = speedAlvo
        end
    end
end)

--==================================================================--
--  UI — WindUI (Koala UI v3)
--==================================================================--
local Koala = loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaUI_v3.lua"))()

local Window = Koala:CreateWindow({
    Title = "Koala Hub — Levante um Cubo",
    Icon = "box",
    Author = "discord.gg/ZRFffEgQQM",
    Folder = "KoalaCubo",
    Size = UDim2.fromOffset(580, 460),
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightControl,
})

--==================================================================--
--  TAB: FARM
--==================================================================--
local FarmTab = Window:Tab({ Title = "Farm", Icon = "zap" })

FarmTab:Section({ Title = "Auto Lift" })

local cuboNomes = { "Auto (menor cubo)" }
for _, idx in ipairs(listarCubos()) do
    table.insert(cuboNomes, "Cubo " .. idx)
end

local ddCubos
ddCubos = FarmTab:Dropdown({
    Title = "Cubo alvo",
    Desc = "'Auto' pega sempre o menor cubo disponivel (mais facil, refresh-proof)",
    Values = cuboNomes,
    Value = "Auto (menor cubo)",
    Callback = function(v)
        cuboAlvo = tonumber(v:match("%d+")) or 0
    end,
})

-- auto-atualiza a lista quando os cubos dao refresh
task.spawn(function()
    while true do
        task.wait(10)
        local novos = { "Auto (menor cubo)" }
        for _, idx in ipairs(listarCubos()) do
            table.insert(novos, "Cubo " .. idx)
        end
        if #novos ~= #cuboNomes then
            cuboNomes = novos
            pcall(function() ddCubos:Refresh(novos) end)
        end
    end
end)

FarmTab:Slider({
    Title = "Intervalo do lift",
    Desc = "Tempo entre ciclos (menor = mais rapido; 0.05 = maximo)",
    Value = { Min = 0.05, Max = 1, Default = 0.1, Step = 0.05 },
    Callback = function(v)
        liftIntervalo = tonumber(v) or 0.1
    end,
})

FarmTab:Slider({
    Title = "Rajada (ciclos por tick)",
    Desc = "Quantos abrir+concluir por ciclo. Sobe o ganho, mas o servidor pode ignorar excesso",
    Value = { Min = 1, Max = 10, Default = 1, Step = 1 },
    Callback = function(v)
        liftRajada = math.floor(tonumber(v) or 1)
    end,
})

FarmTab:Toggle({
    Title = "Auto Lift",
    Desc = "Abre e conclui o cubo em loop. Olha a aba Status — se a Strength dispara, o server nao mede tempo",
    Value = false,
    Callback = function(v)
        State.autoLift = v
        notify("Auto Lift", v and "Ligado" or "Desligado", 2)
    end,
})

FarmTab:Section({ Title = "Auto Train (flexao)" })

FarmTab:Slider({
    Title = "Reps por pacote",
    Desc = "O jogo manda 1 naturalmente; mais = mais forca por pacote (se o server aceitar)",
    Value = { Min = 1, Max = 500, Default = 1, Step = 1 },
    Callback = function(v)
        trainReps = math.max(1, math.floor(tonumber(v) or 1))
    end,
})

FarmTab:Slider({
    Title = "Intervalo do treino",
    Desc = "Tempo entre pacotes (0.05 = maximo)",
    Value = { Min = 0.05, Max = 1, Default = 0.15, Step = 0.05 },
    Callback = function(v)
        trainIntervalo = tonumber(v) or 0.15
    end,
})

FarmTab:Toggle({
    Title = "Auto Train",
    Desc = "Manda pacotes de treino em loop, sem fazer flexao",
    Value = false,
    Callback = function(v)
        State.autoTrain = v
        notify("Auto Train", v and "Ligado" or "Desligado", 2)
    end,
})

--==================================================================--
--  TAB: EXTRAS
--==================================================================--
local ExtrasTab = Window:Tab({ Title = "Extras", Icon = "gift" })

ExtrasTab:Section({ Title = "Coletaveis" })

ExtrasTab:Toggle({
    Title = "Auto Pops (instantaneo)",
    Desc = "Hook na bridge: coleta o pop no instante em que o servidor spawna — sem clicar",
    Value = false,
    Callback = function(v) State.autoPops = v end,
})

ExtrasTab:Toggle({
    Title = "Auto Bau",
    Desc = "Anda ate os baus e abre (combine com Prompts Instantaneos)",
    Value = false,
    Callback = function(v) State.autoBau = v end,
})

ExtrasTab:Section({ Title = "Movimento / mundo" })

ExtrasTab:Toggle({
    Title = "Atravessar barreiras",
    Desc = "Remove a colisao dos portoes de Strength — entra em qualquer zona",
    Value = false,
    Callback = function(v)
        State.atravessar = v
        aplicarBarreiras(v)
    end,
})

ExtrasTab:Toggle({
    Title = "Prompts instantaneos",
    Desc = "HoldDuration = 0 em todos os ProximityPrompts (bau/cubo abrem sem segurar)",
    Value = false,
    Callback = function(v) State.promptsInstant = v end,
})

ExtrasTab:Slider({
    Title = "WalkSpeed",
    Desc = "Velocidade alvo",
    Value = { Min = 16, Max = 250, Default = 16, Step = 1 },
    Callback = function(v)
        speedAlvo = tonumber(v) or 16
        local h = hum()
        if h then h.WalkSpeed = speedAlvo end
    end,
})

ExtrasTab:Toggle({
    Title = "Travar WalkSpeed",
    Desc = "Reaplica a velocidade todo frame — o jogo nao reseta mais",
    Value = false,
    Callback = function(v) State.travarSpeed = v end,
})

ExtrasTab:Section({ Title = "Utilidades" })

ExtrasTab:Toggle({
    Title = "Anti-AFK",
    Desc = "Ping nativo do jogo a cada 25s",
    Value = true,
    Callback = function(v) State.antiAfk = v end,
})

ExtrasTab:Button({
    Title = "Resgatar recompensa do grupo",
    Desc = "Tenta o claim do GroupReward (precisa estar no grupo + 3 convites — o servidor valida)",
    Callback = function()
        fire("GroupReward", nil, {})
        notify("GroupReward", "Pacote enviado — se faltar requisito o servidor ignora", 3)
    end,
})

ExtrasTab:Button({
    Title = "Respawn",
    Desc = "Mata o personagem e renasce no spawn",
    Callback = function()
        local h = hum()
        if h then h.Health = 0 end
    end,
})

--==================================================================--
--  TAB: STATUS
--==================================================================--
local StatusTab = Window:Tab({ Title = "Status", Icon = "info" })

StatusTab:Section({ Title = "Contadores ao vivo" })

local lblForca, lblCash
pcall(function()
    lblForca = StatusTab:Paragraph({ Title = "Strength", Desc = "..." })
    lblCash  = StatusTab:Paragraph({ Title = "Cash", Desc = "..." })
end)

task.spawn(function()
    while true do
        pcall(function()
            if lblForca then lblForca:SetDesc(tostring(forca())) end
            if lblCash then lblCash:SetDesc(tostring(dinheiro())) end
        end)
        task.wait(1)
    end
end)

StatusTab:Section({ Title = "Testes (antes/depois)" })

StatusTab:Button({
    Title = "Teste: concluir cubo 1 agora",
    Desc = "Dispara abrir+FinishLift uma vez e compara a Strength",
    Callback = function()
        local antes = forca()
        fire("Cubes", nil, { 1 })
        task.wait(0.3)
        fire("Cubes", "FinishLift", { 1 })
        task.wait(0.5)
        local depois = forca()
        notify("Teste Lift", ("Antes: %s | Depois: %s"):format(tostring(antes), tostring(depois)), 5)
    end,
})

StatusTab:Button({
    Title = "Teste: pacote de treino",
    Desc = "Manda 1 pacote Training e compara a Strength",
    Callback = function()
        local antes = forca()
        fire("Training", nil, { trainReps })
        task.wait(0.5)
        local depois = forca()
        notify("Teste Train", ("Antes: %s | Depois: %s"):format(tostring(antes), tostring(depois)), 5)
    end,
})

StatusTab:Button({
    Title = "Teste: rajada (10x cubo 1)",
    Desc = "Dispara 10 ciclos de uma vez — mostra se o servidor aceita rajada",
    Callback = function()
        local antes = forca()
        for _ = 1, 10 do
            fire("Cubes", nil, { 1 })
            fire("Cubes", "FinishLift", { 1 })
        end
        task.wait(1)
        local depois = forca()
        notify("Teste Rajada", ("Antes: %s | Depois: %s"):format(tostring(antes), tostring(depois)), 5)
    end,
})

notify("Koala Cubo v2", "Carregado! Aba Farm = lift/treino turbo. Aba Status = testes e contadores.", 5)

--==================================================================--
--  RETORNO: integracao futura com o hub
--==================================================================--
return function(KoalaRef, WindowRef, Flags)
    if not WindowRef then return end
    pcall(function()
        local tab = WindowRef:Tab({ Title = "Cubo", Icon = "box" })
        tab:Toggle({ Title = "Auto Lift", Value = State.autoLift, Callback = function(v) State.autoLift = v end })
        tab:Toggle({ Title = "Auto Train", Value = State.autoTrain, Callback = function(v) State.autoTrain = v end })
        tab:Toggle({ Title = "Auto Pops", Value = State.autoPops, Callback = function(v) State.autoPops = v end })
        tab:Toggle({ Title = "Auto Bau", Value = State.autoBau, Callback = function(v) State.autoBau = v end })
        tab:Toggle({ Title = "Atravessar barreiras", Value = State.atravessar, Callback = function(v) State.atravessar = v aplicarBarreiras(v) end })
        tab:Toggle({ Title = "Prompts instantaneos", Value = State.promptsInstant, Callback = function(v) State.promptsInstant = v end })
        tab:Toggle({ Title = "Anti-AFK", Value = State.antiAfk, Callback = function(v) State.antiAfk = v end })
    end)
end
