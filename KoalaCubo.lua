--[[
    KOALA HUB — LEVANTE UM CUBO (Lift a Cube) — PlaceId 109530157755211
    -------------------------------------------------------------------
    v1 — feito em cima do dump do KoalaSpy (fontes do client).

    Como o jogo funciona (do dump):
      * Toda comunicacao passa pelo BridgeNet2 (ReplicatedStorage.Packages.bridgenet2).
      * Cada "controller" tem uma bridge: "<UserId>_<NomeDoController>"
        ex: "9267263202_Cubes", "9267263202_Training", "9267263202_Pops".
      * Formato: replicator:Fire({ Function = "...", Args = { ... } })

    Funcoes deste script:
      * AUTO LIFT: abre o cubo escolhido (Args={index}) e conclui
        (Function="FinishLift", Args={index}) em loop. SE o servidor
        nao medir o tempo, o ganho e instantaneo. Se medir, ele paga
        so o proporcional — liga e ve se a forca sobe rapido.
      * AUTO TRAIN: repete o pacote de treino (Training, Args={reps})
        que o proprio jogo manda quando voce faz flexao. Funciona SEM
        precisar estar na zona de treino? Depende da validacao do
        servidor — testa dentro e fora da zona e me fala.
      * AUTO POPS: clica sozinho nos baloes/botoes que aparecem na tela
        (server manda spawnar, o claim e confirmado pelo servidor).
      * AUTO BAU: teleporta ate os baus (World.Shared.Chests) e ativa
        o ProximityPrompt — abre de graca se tiver no raio.
      * ANTI-AFK: manda o ping do controller AFK a cada 25s.
      * SPEED: WalkSpeed direto + sem o lock de treino.

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
        if ok then bridges[nome] = b else
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
--  CUBOS DISPONIVEIS (workspace.World.Shared.Cubes, nome = index)
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
--  AUTO LIFT
--==================================================================--
local State = { autoLift = false, autoTrain = false, autoPops = false, autoBau = false, antiAfk = true }
local cuboAlvo = 1

task.spawn(function()
    while true do
        if State.autoLift then
            local f = pastaCubos()
            local idx = cuboAlvo
            if f and not f:FindFirstChild(tostring(idx)) then
                -- cubo sumiu (refresh) — pega o menor disponivel
                local lista = listarCubos()
                if #lista > 0 then idx = lista[1] end
            end
            fire("Cubes", nil, { idx })            -- abre o lift
            task.wait(0.25)
            fire("Cubes", "FinishLift", { idx })   -- conclui
            task.wait(0.25)
        else
            task.wait(0.3)
        end
    end
end)

--==================================================================--
--  AUTO TRAIN (repete o pacote de flexao do jogo)
--==================================================================--
local trainReps = 1

task.spawn(function()
    while true do
        if State.autoTrain then
            fire("Training", nil, { trainReps })
            task.wait(0.25)
        else
            task.wait(0.3)
        end
    end
end)

--==================================================================--
--  AUTO POPS (baloes/botoes da UI do jogo)
--==================================================================--
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
            task.wait(0.3)
        else
            task.wait(0.5)
        end
    end
end)

--==================================================================--
--  AUTO BAU (chests)
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
                            task.wait(3) -- animacao do roll
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
--  ANTI-AFK (ping nativo do jogo, a cada 25s)
--==================================================================--
task.spawn(function()
    while true do
        if State.antiAfk then fire("AFK", nil, {}) end
        task.wait(25)
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

-- TAB: Farm
local FarmTab = Window:Tab({ Title = "Farm", Icon = "zap" })

FarmTab:Section({ Title = "Levantar cubos" })

local cuboNomes = {}
do
    for _, idx in ipairs(listarCubos()) do
        table.insert(cuboNomes, "Cubo " .. idx)
    end
    if #cuboNomes == 0 then cuboNomes = { "Cubo 1" } end
end

FarmTab:Dropdown({
    Title = "Cubo alvo",
    Desc = "Qual cubo levantar (indice da pasta World.Shared.Cubes)",
    Values = cuboNomes,
    Value = cuboNomes[1],
    Callback = function(v)
        cuboAlvo = tonumber(v:match("%d+")) or 1
    end,
})

FarmTab:Toggle({
    Title = "Auto Lift (instantaneo?)",
    Desc = "Abre e conclui o cubo em loop. Se o server nao medir tempo, a forca sobe MUITO rapido. Olha o contador de Strength.",
    Value = false,
    Callback = function(v)
        State.autoLift = v
        notify("Auto Lift", v and "Ligado no cubo " .. cuboAlvo or "Desligado", 2)
    end,
})

FarmTab:Section({ Title = "Treino (forca passiva)" })

FarmTab:Slider({
    Title = "Reps por pacote",
    Desc = "Quantas flexoes o pacote reporta (o jogo manda 1 por vez naturalmente)",
    Value = { Min = 1, Max = 50, Default = 1 },
    Callback = function(v)
        trainReps = math.floor(tonumber(v) or 1)
    end,
})

FarmTab:Toggle({
    Title = "Auto Train",
    Desc = "Manda o pacote de treino do jogo em loop, sem precisar ficar fazendo flexao",
    Value = false,
    Callback = function(v)
        State.autoTrain = v
        notify("Auto Train", v and "Ligado" or "Desligado", 2)
    end,
})

-- TAB: Extras
local ExtrasTab = Window:Tab({ Title = "Extras", Icon = "gift" })

ExtrasTab:Section({ Title = "Coletaveis" })

ExtrasTab:Toggle({
    Title = "Auto Pops",
    Desc = "Clica sozinho nos baloes/bonus que aparecem na tela",
    Value = false,
    Callback = function(v) State.autoPops = v end,
})

ExtrasTab:Toggle({
    Title = "Auto Bau",
    Desc = "Anda ate os baus do mapa e abre (prompt do jogo)",
    Value = false,
    Callback = function(v) State.autoBau = v end,
})

ExtrasTab:Section({ Title = "Utilidades" })

ExtrasTab:Toggle({
    Title = "Anti-AFK",
    Desc = "Ping nativo do jogo a cada 25s — fica online sem chutar",
    Value = true,
    Callback = function(v) State.antiAfk = v end,
})

ExtrasTab:Slider({
    Title = "WalkSpeed",
    Desc = "Velocidade do personagem",
    Value = { Min = 16, Max = 150, Default = 16 },
    Callback = function(v)
        local h = hum()
        if h then h.WalkSpeed = tonumber(v) or 16 end
    end,
})

-- TAB: Status
local StatusTab = Window:Tab({ Title = "Status", Icon = "info" })

StatusTab:Section({ Title = "Contadores" })

local lblForca = nil
pcall(function()
    lblForca = StatusTab:Paragraph({ Title = "Strength", Desc = "..." })
end)

task.spawn(function()
    while true do
        pcall(function()
            if lblForca and lblForca.SetDesc then
                lblForca:SetDesc("Strength: " .. tostring(forca()))
            end
        end)
        task.wait(1)
    end
end)

StatusTab:Button({
    Title = "Teste: concluir cubo 1 agora",
    Desc = "Dispara abrir+FinishLift uma vez e olha se a Strength subiu",
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

notify("Koala Cubo", "Carregado! Abre a aba Farm e testa o Auto Lift. Me fala se a Strength dispara.", 5)

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
        tab:Toggle({ Title = "Anti-AFK", Value = State.antiAfk, Callback = function(v) State.antiAfk = v end })
    end)
end
