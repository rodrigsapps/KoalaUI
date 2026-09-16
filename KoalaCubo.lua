--[[
    KOALA HUB — LEVANTE UM CUBO — PlaceId 109530157755211
    -----------------------------------------------------
    v3 — feito pra FUNCIONAR e ser facil de entender.

    O que mudou:
      * TESTE AUTOMATICO ao abrir: o script dispara 1 levantamento de
        teste e ve se sua forca subiu. Se os remotes nao funcionarem no
        seu executor, ele te avisa e liga o MODO SEGURO.
      * MODO SEGURO: usa os botoes do proprio jogo (prompt + clique
        automatico). E mais lento, mas o servidor nao tem como ignorar.
      * Textos da UI curtos e diretos, em portugues.

    Abas:
      Farm      = levantar cubos e treinar sem parar
      Coletar   = baloes e baus automaticos
      Movimento = velocidade, atravessar portoes
      Status    = numeros ao vivo + o que esta funcionando

    Uso:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaCubo.lua"))()
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local VIM               = game:GetService("VirtualInputManager")

local LP = Players.LocalPlayer

--==================================================================--
--  AVISOS
--==================================================================--
local function aviso(msg, dur)
    print("[KoalaCubo] " .. tostring(msg))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",
            { Title = "Koala Cubo", Text = tostring(msg), Duration = dur or 3 })
    end)
end

--==================================================================--
--  REMOTES (BridgeNet2 — mesmo formato que o jogo usa)
--==================================================================--
local BridgeNet = nil
local REMOTES_OK = false

pcall(function()
    BridgeNet = require(ReplicatedStorage:WaitForChild("Packages", 10):WaitForChild("bridgenet2", 10))
end)

local uid = tostring(LP.UserId):gsub("-", "")
local bridges = {}
local falhaLog = {}

local function bridge(nome)
    if not BridgeNet then return nil end
    if not bridges[nome] then
        local ok, b = pcall(function()
            return BridgeNet.ReferenceBridge(uid .. "_" .. nome)
        end)
        if ok and b then
            bridges[nome] = b
        else
            if not falhaLog[nome] then
                falhaLog[nome] = true
                warn("[KoalaCubo] nao consegui abrir o canal: " .. nome)
            end
            return nil
        end
    end
    return bridges[nome]
end

local function fire(nome, fn, args)
    local b = bridge(nome)
    if not b then return false end
    local ok = pcall(function()
        b:Fire({ ["Function"] = fn, ["Args"] = args or {} })
    end)
    if not ok and not falhaLog[nome .. "_fire"] then
        falhaLog[nome .. "_fire"] = true
        warn("[KoalaCubo] falha ao enviar pacote: " .. nome)
    end
    return ok
end

--==================================================================--
--  ATALHOS
--==================================================================--
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
    return (ok and tonumber(v)) or 0
end

local function dinheiro()
    local ok, v = pcall(function() return LP:GetAttribute("Cash") end)
    return (ok and tonumber(v)) or 0
end

local function andarAte(pos, limite)
    local h, r = hum(), hrp()
    if not h or not r then return false end
    h:MoveTo(pos)
    local t0 = os.clock()
    while os.clock() - t0 < (limite or 20) do
        local p = hrp()
        if not p then return false end
        local d = Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(pos.X, 0, pos.Z)
        if d.Magnitude < 7 then return true end
        task.wait(0.2)
    end
    return false
end

local function clicarTela()
    pcall(function()
        local cam = Workspace.CurrentCamera
        local x = cam.ViewportSize.X / 2
        local y = cam.ViewportSize.Y / 2
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.03)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
end

--==================================================================--
--  CUBOS DO MAPA
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
                table.insert(out, { idx = idx, part = c })
            end
        end
    end
    table.sort(out, function(a, b) return a.idx < b.idx end)
    return out
end

local function menorCubo()
    local lista = listarCubos()
    return #lista > 0 and lista[1] or nil
end

--==================================================================--
--  ESTADO
--==================================================================--
local S = {
    lift = false,        -- levantar cubos
    liftSeguro = false,  -- modo seguro (prompt + clique)
    treino = false,      -- treinar (flexao)
    baloes = false,      -- pegar baloes
    baus = false,        -- abrir baus
    portoes = false,     -- atravessar portoes
    botoesRapidos = false, -- HoldDuration = 0
    manterVel = false,
    antiAfk = true,
}

local cuboAlvo = 0       -- 0 = automatico (mais fraco)
local velLift = 0.15     -- s entre levantamentos
local repsTreino = 1
local velTreino = 0.2
local velAndar = 16

--==================================================================--
--  LEVANTAR CUBOS — MODO RAPIDO (remote direto)
--==================================================================--
task.spawn(function()
    while true do
        if S.lift and not S.liftSeguro and REMOTES_OK then
            local idx = cuboAlvo
            if idx == 0 then
                local m = menorCubo()
                idx = m and m.idx or 1
            end
            fire("Cubes", nil, { idx })            -- comeca
            fire("Cubes", "FinishLift", { idx })   -- conclui
            task.wait(velLift)
        else
            task.wait(0.25)
        end
    end
end)

--==================================================================--
--  LEVANTAR CUBOS — MODO SEGURO (prompt + clique de verdade)
--==================================================================--
task.spawn(function()
    while true do
        if S.liftSeguro then
            local alvo = nil
            if cuboAlvo == 0 then
                alvo = menorCubo()
            else
                local f = pastaCubos()
                local p = f and f:FindFirstChild(tostring(cuboAlvo))
                if p then alvo = { idx = cuboAlvo, part = p } end
            end
            if alvo then
                local r = hrp()
                if r then
                    -- encosta no cubo
                    r.CFrame = alvo.part.CFrame * CFrame.new(0, 0, 4)
                    task.wait(0.3)
                    -- aperta o botao do cubo
                    local prompt = alvo.part:FindFirstChildOfClass("ProximityPrompt")
                    if prompt then
                        pcall(function() prompt.HoldDuration = 0 end)
                        pcall(function() fireproximityprompt(prompt) end)
                    end
                    -- clica ate concluir (o proprio jogo conta o progresso)
                    local t0 = os.clock()
                    while S.liftSeguro and os.clock() - t0 < 8 do
                        clicarTela()
                        task.wait(0.08)
                    end
                end
            else
                task.wait(1)
            end
            task.wait(0.2)
        else
            task.wait(0.25)
        end
    end
end)

--==================================================================--
--  TREINO (flexao)
--==================================================================--
task.spawn(function()
    while true do
        if S.treino and REMOTES_OK then
            fire("Training", nil, { repsTreino })
            task.wait(velTreino)
        else
            task.wait(0.25)
        end
    end
end)

--==================================================================--
--  BALOES (pops) — clica sozinho nos bonus que aparecem
--==================================================================--
task.spawn(function()
    local overlay
    while true do
        if S.baloes then
            if not (overlay and overlay.Parent) then
                overlay = nil
                pcall(function()
                    local pg = LP:FindFirstChildOfClass("PlayerGui")
                    if not pg then return end
                    -- o jogo guarda os pops dentro da tela "Screen" (Overlay)
                    local screen = pg:FindFirstChild("Screen")
                    if screen then
                        overlay = screen:FindFirstChild("Overlay", true)
                    end
                    if not overlay then
                        for _, g in ipairs(pg:GetChildren()) do
                            local o = g:FindFirstChild("Overlay", true)
                            if o then overlay = o break end
                        end
                    end
                end)
            end
            if overlay then
                for _, d in ipairs(overlay:GetDescendants()) do
                    if d:IsA("GuiButton") and d.Visible then
                        -- 1) dispara os eventos do botao
                        pcall(function()
                            for _, c in ipairs(getconnections(d.Activated)) do
                                c:Fire()
                            end
                        end)
                        -- 2) garantia: clique real na posicao do botao
                        pcall(function()
                            local p = d.AbsolutePosition + d.AbsoluteSize / 2
                            VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
                            task.wait(0.03)
                            VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
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
--  BAUS
--==================================================================--
task.spawn(function()
    while true do
        if S.baus then
            pcall(function()
                local chests = Workspace.World.Shared:FindFirstChild("Chests")
                if chests then
                    for _, m in ipairs(chests:GetChildren()) do
                        if not S.baus then break end
                        local part = m:FindFirstChildWhichIsA("BasePart", true)
                        local prompt = m:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if part and prompt and prompt.Enabled then
                            andarAte(part.Position, 25)
                            task.wait(0.3)
                            pcall(function() prompt.HoldDuration = 0 end)
                            pcall(function() fireproximityprompt(prompt) end)
                            task.wait(2.5) -- animacao do giro
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
        if S.antiAfk then fire("AFK", nil, {}) end
        task.wait(25)
    end
end)

--==================================================================--
--  BOTOES INSTANTANEOS (sem segurar)
--==================================================================--
task.spawn(function()
    while true do
        if S.botoesRapidos then
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
--  ATRAVESSAR PORTOES (colisao client-side — pasta "Barries", typo do jogo)
--==================================================================--
local portoesSalvos = {}

local function aplicarPortoes(semColisao)
    pcall(function()
        local pasta = Workspace.World.Client:FindFirstChild("Barries")
        if not pasta then return end
        for _, d in ipairs(pasta:GetDescendants()) do
            if d:IsA("BasePart") then
                if semColisao then
                    if portoesSalvos[d] == nil then
                        portoesSalvos[d] = d.CanCollide
                    end
                    d.CanCollide = false
                elseif portoesSalvos[d] ~= nil then
                    d.CanCollide = portoesSalvos[d]
                end
            end
        end
    end)
end

task.spawn(function()
    while true do
        if S.portoes then aplicarPortoes(true) end
        task.wait(1)
    end
end)

--==================================================================--
--  MANTER VELOCIDADE
--==================================================================--
RunService.Heartbeat:Connect(function()
    if S.manterVel then
        local h = hum()
        if h and h.WalkSpeed ~= velAndar then
            h.WalkSpeed = velAndar
        end
    end
end)

--==================================================================--
--  TESTE AUTOMATICO DOS REMOTES (roda ao abrir)
--==================================================================--
task.spawn(function()
    task.wait(4) -- espera o jogo carregar
    if not BridgeNet then
        warn("[KoalaCubo] BridgeNet2 nao encontrado — modo rapido desligado. Use o MODO SEGURO.")
        aviso("Remotes indisponiveis. Liga o 'Modo seguro' na aba Farm — ele funciona sempre.", 8)
        return
    end
    local antes = forca()
    fire("Cubes", nil, { 1 })
    task.wait(0.3)
    fire("Cubes", "FinishLift", { 1 })
    task.wait(1.2)
    local depois = forca()
    if depois > antes then
        REMOTES_OK = true
        print(("[KoalaCubo] TESTE OK — remotes funcionam (forca %s -> %s). Pode ligar tudo."):format(antes, depois))
        aviso("Tudo funcionando! Liga o 'Levantar cubos sozinho' na aba Farm.", 6)
    else
        warn(("[KoalaCubo] TESTE FALHOU — servidor ignorou o remote (forca %s -> %s). Use o MODO SEGURO."):format(antes, depois))
        aviso("Modo rapido bloqueado pelo jogo. Liga o 'Modo seguro' na aba Farm.", 8)
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
--  ABA: FARM
--==================================================================--
local Farm = Window:Tab({ Title = "Farm", Icon = "zap" })

Farm:Section({ Title = "Levantar cubos (ganha forca)" })

Farm:Toggle({
    Title = "Levantar cubos sozinho",
    Desc = "Rapido. Liga e olha sua forca subir na aba Status.",
    Value = false,
    Callback = function(v)
        S.lift = v
        if v and not REMOTES_OK then
            aviso("Remote bloqueado — liga tambem o 'Modo seguro' aqui embaixo.", 5)
        end
    end,
})

Farm:Toggle({
    Title = "Modo seguro (usa os botoes do jogo)",
    Desc = "Mais lento, mas funciona sempre. Use se o rapido nao subir sua forca.",
    Value = false,
    Callback = function(v)
        S.liftSeguro = v
    end,
})

Farm:Dropdown({
    Title = "Qual cubo",
    Desc = "O automatico sempre pega o cubo mais fraco do mapa",
    Values = (function()
        local t = { "Automatico (mais fraco)" }
        for _, c in ipairs(listarCubos()) do
            table.insert(t, "Cubo " .. c.idx)
        end
        return t
    end)(),
    Value = "Automatico (mais fraco)",
    Callback = function(v)
        cuboAlvo = tonumber(v:match("%d+")) or 0
    end,
})

Farm:Slider({
    Title = "Velocidade",
    Desc = "Rapido demais pode ser ignorado pelo jogo. Se nao subir, aumente o tempo.",
    Value = { Min = 0.05, Max = 1, Default = 0.15, Step = 0.05 },
    Callback = function(v)
        velLift = tonumber(v) or 0.15
    end,
})

Farm:Section({ Title = "Treinar (flexao — forca em qualquer lugar)" })

Farm:Toggle({
    Title = "Treinar sozinho",
    Desc = "Faz flexao sem parar, sem precisar ir na zona de treino.",
    Value = false,
    Callback = function(v)
        S.treino = v
        if v and not REMOTES_OK then
            aviso("Treino precisa do remote, e ele esta bloqueado neste jogo.", 5)
        end
    end,
})

Farm:Slider({
    Title = "Forca por vez",
    Desc = "Quanto cada pacote vale. Se nao funcionar, deixe em 1.",
    Value = { Min = 1, Max = 100, Default = 1, Step = 1 },
    Callback = function(v)
        repsTreino = math.max(1, math.floor(tonumber(v) or 1))
    end,
})

--==================================================================--
--  ABA: COLETAR
--==================================================================--
local Coletar = Window:Tab({ Title = "Coletar", Icon = "gift" })

Coletar:Section({ Title = "Bonus" })

Coletar:Toggle({
    Title = "Pegar baloes sozinho",
    Desc = "Coleta os baloes de bonus que aparecem na tela.",
    Value = false,
    Callback = function(v) S.baloes = v end,
})

Coletar:Toggle({
    Title = "Abrir baus sozinho",
    Desc = "Vai ate cada bau do mapa e abre. Junto com 'Botoes rapidos' fica melhor.",
    Value = false,
    Callback = function(v) S.baus = v end,
})

Coletar:Toggle({
    Title = "Botoes rapidos",
    Desc = "Baus e cubos abrem na hora, sem segurar o botao.",
    Value = false,
    Callback = function(v) S.botoesRapidos = v end,
})

--==================================================================--
--  ABA: MOVIMENTO
--==================================================================--
local Mov = Window:Tab({ Title = "Movimento", Icon = "run" })

Mov:Section({ Title = "Mapa" })

Mov:Toggle({
    Title = "Atravessar portoes",
    Desc = "Passa pelos portoes de forca sem ter a forca necessaria.",
    Value = false,
    Callback = function(v)
        S.portoes = v
        aplicarPortoes(v)
    end,
})

Mov:Section({ Title = "Velocidade" })

Mov:Slider({
    Title = "Velocidade de andar",
    Desc = "O normal do jogo e 16.",
    Value = { Min = 16, Max = 250, Default = 16, Step = 1 },
    Callback = function(v)
        velAndar = tonumber(v) or 16
        local h = hum()
        if h then h.WalkSpeed = velAndar end
    end,
})

Mov:Toggle({
    Title = "Manter velocidade",
    Desc = "Impede o jogo de voltar sua velocidade ao normal.",
    Value = false,
    Callback = function(v) S.manterVel = v end,
})

Mov:Section({ Title = "Outros" })

Mov:Toggle({
    Title = "Anti-AFK",
    Desc = "O jogo nao te chuta por ficar parado.",
    Value = true,
    Callback = function(v) S.antiAfk = v end,
})

Mov:Button({
    Title = "Renascer",
    Desc = "Volta pro spawn (se travar em algum lugar).",
    Callback = function()
        local h = hum()
        if h then h.Health = 0 end
    end,
})

--==================================================================--
--  ABA: STATUS
--==================================================================--
local Status = Window:Tab({ Title = "Status", Icon = "info" })

Status:Section({ Title = "Seus numeros (ao vivo)" })

local lblForca, lblCash, lblSistema
pcall(function()
    lblForca   = Status:Paragraph({ Title = "Forca", Desc = "..." })
    lblCash    = Status:Paragraph({ Title = "Dinheiro", Desc = "..." })
    lblSistema = Status:Paragraph({ Title = "Modo rapido (remotes)", Desc = "testando..." })
end)

task.spawn(function()
    while true do
        pcall(function()
            if lblForca then lblForca:SetDesc(tostring(forca())) end
            if lblCash then lblCash:SetDesc(tostring(dinheiro())) end
            if lblSistema then
                lblSistema:SetDesc(REMOTES_OK and "FUNCIONANDO — pode usar tudo"
                    or "BLOQUEADO pelo jogo — use o Modo seguro na aba Farm")
            end
        end)
        task.wait(1)
    end
end)

Status:Section({ Title = "Testar de novo" })

Status:Button({
    Title = "Testar se o modo rapido funciona",
    Desc = "Levanta o cubo 1 uma vez e ve se sua forca sobe.",
    Callback = function()
        local antes = forca()
        fire("Cubes", nil, { 1 })
        task.wait(0.3)
        fire("Cubes", "FinishLift", { 1 })
        task.wait(1)
        local depois = forca()
        if depois > antes then
            REMOTES_OK = true
            aviso(("Funcionou! Forca %s -> %s"):format(antes, depois), 4)
        else
            aviso(("Nao subiu (%s -> %s). Use o Modo seguro."):format(antes, depois), 5)
        end
    end,
})

aviso("Koala Cubo carregado! Aba Farm > 'Levantar cubos sozinho'.", 5)

--==================================================================--
--  RETORNO: integracao com o hub
--==================================================================--
return function(KoalaRef, WindowRef, Flags)
    if not WindowRef then return end
    pcall(function()
        local tab = WindowRef:Tab({ Title = "Cubo", Icon = "box" })
        tab:Toggle({ Title = "Levantar cubos sozinho", Value = S.lift, Callback = function(v) S.lift = v end })
        tab:Toggle({ Title = "Modo seguro", Value = S.liftSeguro, Callback = function(v) S.liftSeguro = v end })
        tab:Toggle({ Title = "Treinar sozinho", Value = S.treino, Callback = function(v) S.treino = v end })
        tab:Toggle({ Title = "Pegar baloes sozinho", Value = S.baloes, Callback = function(v) S.baloes = v end })
        tab:Toggle({ Title = "Abrir baus sozinho", Value = S.baus, Callback = function(v) S.baus = v end })
        tab:Toggle({ Title = "Atravessar portoes", Value = S.portoes, Callback = function(v) S.portoes = v aplicarPortoes(v) end })
        tab:Toggle({ Title = "Anti-AFK", Value = S.antiAfk, Callback = function(v) S.antiAfk = v end })
    end)
end
