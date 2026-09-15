--[[
    KOALA HUB — CORTAR E VENDER (Chop & Sell) — PlaceId 122642804419736
    -------------------------------------------------------------------
    v3 — CORRIGIDO: nada mais de clone visual.

    O que o dump mostrou (e por que a v2 falhou):
      * Clonar Tools do ReplicatedStorage NAO funciona — o servidor
        mantem o registro do que voce comprou/tem; clones client-side
        sao ignorados no corte e na venda.
      * O caminho real e usar os REMOTES DE COMPRA do jogo:
        BuyAxe (machado de gelo, 450$) e BuyFireAxe (fogo, 850$).
        Eles registram a Tool no servidor -> corta e vende de verdade.
      * Machado "demon" e "angelical" nao tem remote de compra publico
        no dump — so via gamepass/loja Robux. Sem exploit.

    O que ESTE script faz:
      * COMPRAR machados de verdade via BuyAxe / BuyFireAxe (precisa do
        Cash; se faltar, o jogo avisa "SEM_DINHEIRO").
      * AUTO FARM completo: teleporta (remote do jogo) ate FARM1/2/3,
        equipa machado REAL, anda ate a arvore mais proxima, corta ate
        cair, coleta os troncos do chao (touch), teleporta pro SELL e
        vende (SellAll). Loop infinito.
      * HITKILL: cola o Handle do machado na arvore antes de cada golpe.
        Funciona SE o Script do machado medir distancia Handle<->arvore
        (testa e me fala). Se medir do personagem, o farm ja anda junto.
      * AUTO VENDER a cada N segundos.
      * AUTO BAU: anda por todos os baus do mapa.
      * TELEPORTE via remote (FARM1/2/3, SELL) — aparentemente sem
        validacao server-side.
      * SPEED via remote UpdateWalkspeed + WalkSpeed direto.

    Uso:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaCortarVender.lua"))()
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

local LP = Players.LocalPlayer

--==================================================================--
--  REMOTES / REFS (do dump do KoalaSpy)
--==================================================================--
local R = {
    Teleport    = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Teleport"),
    SellAll     = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellAll"),
    SellTool    = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellTool"),
    BuyAxe      = ReplicatedStorage:WaitForChild("BuyAxe"),      -- machado de gelo (450$)
    BuyFireAxe  = ReplicatedStorage:WaitForChild("BuyFireAxe"),  -- machado de fogo (850$)
    UpdateWS    = ReplicatedStorage:WaitForChild("UpdateWalkspeed"),
    DropTool    = ReplicatedStorage:WaitForChild("DropTool"),
}

-- nomes REAIS das Tools que o jogo da ao comprar (descobertos no dump)
local MACHADO_BASE  = "machado"          -- StarterPack
local MACHADO_GELO  = "machado de gelo"  -- via BuyAxe
local MACHADO_FOGO  = "machado de fogo"  -- via BuyFireAxe
local ORDEM_MACHADOS = { MACHADO_FOGO, MACHADO_GELO, MACHADO_BASE } -- prioridade

--==================================================================--
--  HELPERS
--==================================================================--
local function notify(titulo, msg, dur)
    print("[KoalaC&V] " .. tostring(msg))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",
            { Title = titulo or "Koala C&V", Text = msg, Duration = dur or 3 })
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

local function cash()
    local ok, v = pcall(function()
        return LP:WaitForChild("leaderstats"):WaitForChild("Cash").Value
    end)
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
        if d2d.Magnitude < 6 then return true end
        task.wait(0.2)
    end
    return false
end

local function tpRemote(pos)
    pcall(function() R.Teleport:FireServer(pos) end)
end

local function posDe(nomePart)
    local p = Workspace:FindFirstChild(nomePart)
    return p and p.Position or nil
end

--==================================================================--
--  MACHADOS — compra REAL via remote do jogo
--==================================================================--
local function temMachado(nome)
    local backpack = LP:FindFirstChildOfClass("Backpack")
    return (backpack and backpack:FindFirstChild(nome))
        or (char() and char():FindFirstChild(nome))
end

local function melhorMachado()
    for _, nome in ipairs(ORDEM_MACHADOS) do
        if temMachado(nome) then return nome end
    end
    return nil
end

local function equipar(nome)
    local h = hum()
    local backpack = LP:FindFirstChildOfClass("Backpack")
    local tool = (char() and char():FindFirstChild(nome)) or (backpack and backpack:FindFirstChild(nome))
    if h and tool and tool:IsA("Tool") and tool.Parent ~= char() then
        h:EquipTool(tool)
        task.wait(0.2)
    end
    return tool ~= nil
end

local function comprarGelo()
    if temMachado(MACHADO_GELO) then return true, "voce ja tem" end
    if cash() < 450 then return false, "precisa de 450$ (voce tem " .. cash() .. "$)" end
    R.BuyAxe:FireServer()
    task.wait(1)
    return temMachado(MACHADO_GELO), temMachado(MACHADO_GELO) and "comprado!" or "servidor nao deu (sem cash?)"
end

local function comprarFogo()
    if temMachado(MACHADO_FOGO) then return true, "voce ja tem" end
    if cash() < 850 then return false, "precisa de 850$ (voce tem " .. cash() .. "$)" end
    R.BuyFireAxe:FireServer()
    task.wait(1)
    return temMachado(MACHADO_FOGO), temMachado(MACHADO_FOGO) and "comprado!" or "servidor nao deu (sem cash?)"
end

--==================================================================--
--  ARVORES / BAUS
--==================================================================--
local function acharArvores()
    local out = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "Tree" then
            local p = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
            if p then table.insert(out, p) end
        end
    end
    return out
end

local function arvoreMaisProxima()
    local r = hrp()
    if not r then return nil end
    local melhor, menor = nil, math.huge
    for _, p in ipairs(acharArvores()) do
        local dist = (p.Position - r.Position).Magnitude
        if dist < menor then menor, melhor = dist, p end
    end
    return melhor
end

local function acharBaus()
    local out = {}
    local pasta = Workspace:FindFirstChild("Baús") or Workspace:FindFirstChild("Baus")
    if pasta then
        for _, m in ipairs(pasta:GetChildren()) do
            if m:IsA("Model") then table.insert(out, m) end
        end
    end
    return out
end

--==================================================================--
--  HITKILL — cola o Handle na arvore antes de cada golpe
--  Funciona SE o Script do machado medir distancia Handle<->arvore.
--==================================================================--
local Hitkill = { ativo = false, alvoAtual = nil }

RunService.Heartbeat:Connect(function()
    if not Hitkill.ativo then return end
    local c = char()
    local tool = c and c:FindFirstChildWhichIsA("Tool")
    if not tool or not tool.Name:lower():match("machado") then return end
    local handle = tool:FindFirstChild("Handle")
    local alvo = Hitkill.alvoAtual
    if handle and alvo and alvo.Parent then
        handle.CFrame = CFrame.new(alvo.Position + Vector3.new(
            math.random(-5,5)/10, math.random(0,10)/10, math.random(-5,5)/10))
    end
end)

--==================================================================--
--  COLETAR TRONCOS — Tools no Workspace entram no Backpack por touch
--==================================================================--
local Coletar = { ativo = true, raio = 300 }

local function coletarTroncos()
    local r = hrp()
    if not r then return 0 end
    local n = 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Tool") and d.Name:match("^TRONCO") then
            local handle = d:FindFirstChild("Handle") or d:FindFirstChildWhichIsA("BasePart", true)
            if handle and (handle.Position - r.Position).Magnitude <= Coletar.raio then
                local cf0 = r.CFrame
                r.CFrame = CFrame.new(handle.Position + Vector3.new(0, 1, 0))
                task.wait(0.12)
                local r2 = hrp()
                if r2 then r2.CFrame = cf0 end
                n = n + 1
            end
        end
    end
    return n
end

--==================================================================--
--  VENDER
--==================================================================--
local function venderTudo()
    local ok = pcall(function() R.SellAll:InvokeServer() end)
    return ok
end

local function contarTroncos()
    local n = 0
    local backpack = LP:FindFirstChildOfClass("Backpack")
    local containers = { backpack, char() }
    for _, cont in ipairs(containers) do
        if cont then
            for _, t in ipairs(cont:GetChildren()) do
                if t:IsA("Tool") and t.Name:match("^TRONCO") then n = n + 1 end
            end
        end
    end
    return n
end

--==================================================================--
--  ESTADO / LOOPS
--==================================================================--
local State = {
    autoFarm   = false,
    autoVender = false,
    autoBau    = false,
    venderACada = 20,
}

task.spawn(function() -- AUTO VENDER
    while true do
        task.wait(State.venderACada)
        if State.autoVender and not State.autoFarm then
            venderTudo()
        end
    end
end)

task.spawn(function() -- AUTO FARM (loop principal)
    while true do
        task.wait(0.5)
        if State.autoFarm then
            pcall(function()
                -- 1) garante machado real (compra gelo se nao tiver nenhum)
                local machado = melhorMachado()
                if not machado then
                    local ok, msg = comprarGelo()
                    if not ok then
                        notify("Auto Farm", "Sem machado! " .. tostring(msg), 4)
                        State.autoFarm = false
                        return
                    end
                    machado = melhorMachado()
                end
                equipar(machado)

                -- 2) teleporta pro FARM se estiver longe das arvores
                local alvo = arvoreMaisProxima()
                local r = hrp()
                if alvo and r and (alvo.Position - r.Position).Magnitude > 400 then
                    local f = posDe("FARM1")
                    if f then tpRemote(f) task.wait(1.5) end
                    alvo = arvoreMaisProxima()
                end

                -- 3) corta a arvore mais proxima ate cair
                if alvo then
                    andarAte(alvo.Position, 25)
                    Hitkill.alvoAtual = alvo
                    local t0 = os.clock()
                    while State.autoFarm and alvo.Parent and os.clock() - t0 < 10 do
                        local tool = char() and char():FindFirstChildWhichIsA("Tool")
                        if tool and tool.Name:lower():match("machado") then
                            tool:Activate()
                        end
                        task.wait(0.2)
                        if Coletar.ativo then coletarTroncos() end
                    end
                    Hitkill.alvoAtual = nil
                end

                -- 4) vende quando juntar troncos suficientes
                if contarTroncos() >= 6 then
                    local s = posDe("SELL")
                    if s then
                        tpRemote(s)
                        task.wait(1.5)
                    end
                    venderTudo()
                    task.wait(1)
                end
            end)
        end
    end
end)

task.spawn(function() -- AUTO BAU
    while true do
        task.wait(5)
        if State.autoBau then
            pcall(function()
                for _, bau in ipairs(acharBaus()) do
                    if not State.autoBau then break end
                    local p = bau:FindFirstChildWhichIsA("BasePart", true)
                    if p then
                        andarAte(p.Position, 30)
                        task.wait(1.5)
                    end
                end
            end)
        end
    end
end)

--==================================================================--
--  GUI (standalone)
--==================================================================--
local function criarGui()
    local pg = LP:WaitForChild("PlayerGui")
    if pg:FindFirstChild("KoalaCV") then pg.KoalaCV:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "KoalaCV"
    gui.ResetOnSpawn = false
    gui.Parent = pg

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 250, 0, 100)
    main.Position = UDim2.new(0, 20, 0.5, -200)
    main.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

    local titulo = Instance.new("TextLabel")
    titulo.Size = UDim2.new(1, 0, 0, 30)
    titulo.BackgroundTransparency = 1
    titulo.Text = "Koala — Cortar e Vender  |  Cash: 0"
    titulo.TextColor3 = Color3.fromRGB(255, 255, 255)
    titulo.Font = Enum.Font.GothamBlack
    titulo.TextSize = 13
    titulo.Parent = main

    task.spawn(function() -- atualiza o cash no titulo
        while gui.Parent do
            pcall(function()
                titulo.Text = string.format("Koala — Cortar e Vender  |  Cash: %d", cash())
            end)
            task.wait(2)
        end
    end)

    local lista = Instance.new("UIListLayout")
    lista.Padding = UDim.new(0, 5)
    lista.HorizontalAlignment = Enum.HorizontalAlignment.Center
    lista.SortOrder = Enum.SortOrder.LayoutOrder
    lista.Parent = main

    local pad = Instance.new("UIPadding", main)
    pad.PaddingTop = UDim.new(0, 34)

    local y = 0
    local function botao(texto, callback)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -16, 0, 30)
        b.BackgroundColor3 = Color3.fromRGB(45, 48, 55)
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.Text = texto
        b.Parent = main
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        b.MouseButton1Click:Connect(function() callback(b) end)
        y = y + 1
        main.Size = UDim2.new(0, 250, 0, 44 + (y * 35))
        return b
    end

    local function toggleBtn(texto, get, set)
        return botao(texto .. ": OFF", function(b)
            local novo = not get()
            set(novo)
            b.Text = texto .. (novo and ": ON" or ": OFF")
            b.BackgroundColor3 = novo and Color3.fromRGB(35, 120, 70) or Color3.fromRGB(45, 48, 55)
        end)
    end

    -- toggles principais
    toggleBtn("Auto Farm", function() return State.autoFarm end, function(v) State.autoFarm = v end)
    toggleBtn("Hitkill arvore", function() return Hitkill.ativo end, function(v) Hitkill.ativo = v end)
    toggleBtn("Auto coletar", function() return Coletar.ativo end, function(v) Coletar.ativo = v end)
    toggleBtn("Auto Vender", function() return State.autoVender end, function(v) State.autoVender = v end)
    toggleBtn("Auto Bau", function() return State.autoBau end, function(v) State.autoBau = v end)

    -- compras reais
    botao("Comprar machado de gelo (450$)", function()
        local ok, msg = comprarGelo()
        notify("Loja", tostring(msg), 3)
    end)
    botao("Comprar machado de fogo (850$)", function()
        local ok, msg = comprarFogo()
        notify("Loja", tostring(msg), 3)
    end)

    -- acoes
    botao("Vender tudo agora", function()
        local ok = venderTudo()
        notify("Vender", ok and "Vendido!" or "Falha (sem troncos?)", 2)
    end)
    botao("TP: FARM1", function() local p = posDe("FARM1") if p then tpRemote(p) end end)
    botao("TP: FARM2", function() local p = posDe("FARM2") if p then tpRemote(p) end end)
    botao("TP: FARM3", function() local p = posDe("FARM3") if p then tpRemote(p) end end)
    botao("TP: SELL + vender", function()
        local p = posDe("SELL")
        if p then tpRemote(p) task.wait(1.5) venderTudo() end
    end)
    botao("Speed 50", function()
        pcall(function() R.UpdateWS:FireServer(50) end)
        local h = hum()
        if h then h.WalkSpeed = 50 end
    end)

    return gui
end

--==================================================================--
--  BOOT
--==================================================================--
if not _G.KoalaCVBooted then
    _G.KoalaCVBooted = true
    task.spawn(function()
        task.wait(1.5)
        criarGui()
        notify("Koala C&V", "Carregado! Compre um machado real (botao na GUI) e ligue o Auto Farm.", 5)
    end)
end

--==================================================================--
--  RETORNO: integracao futura com o hub
--==================================================================--
return function(Koala, Window, Flags)
    if not Window then return end
    pcall(function()
        local tab = Window:Tab({ Title = "Cortar&Vender", Icon = "axe" })
        tab:Toggle({ Title = "Auto Farm", Value = State.autoFarm, Callback = function(v) State.autoFarm = v end })
        tab:Toggle({ Title = "Hitkill arvore", Value = Hitkill.ativo, Callback = function(v) Hitkill.ativo = v end })
        tab:Toggle({ Title = "Auto coletar", Value = Coletar.ativo, Callback = function(v) Coletar.ativo = v end })
        tab:Toggle({ Title = "Auto Vender", Value = State.autoVender, Callback = function(v) State.autoVender = v end })
        tab:Toggle({ Title = "Auto Bau", Value = State.autoBau, Callback = function(v) State.autoBau = v end })
        tab:Button({ Title = "Comprar machado de gelo (450$)", Callback = comprarGelo })
        tab:Button({ Title = "Comprar machado de fogo (850$)", Callback = comprarFogo })
        tab:Button({ Title = "Vender tudo agora", Callback = venderTudo })
        tab:Button({ Title = "TP: SELL + vender", Callback = function()
            local p = posDe("SELL")
            if p then tpRemote(p) task.wait(1.5) venderTudo() end
        end })
    end)
end
