--[[
    KOALA HUB — CORTAR E VENDER (Chop & Sell) — PlaceId 122642804419736
    -------------------------------------------------------------------
    Script especifico pro jogo "[BETA] Cortar e Vender", montado a partir
    do dump (remotes + fontes decompiladas) extraido pelo KoalaSpy.

    Features:
      * PEGAR QUALQUER MACHADO — clona do ReplicatedStorage.MachadosCorta
        pro seu Backpack (machado, angelical, gelo, fogo, demon) sem pagar.
      * SPAWNAR TRONCOS — TRONCO / TRONCO DE OURO / TRONCO DE DIAMANTE
        direto no Backpack (eles sao Tools em ReplicatedStorage).
      * VENDER TUDO — chama Remotes.SellAll (RemoteFunction).
      * AUTO FARM — loop: equipa machado -> anda ate a arvore mais
        proxima -> ativa a Tool -> pega troncos do chao -> vende quando
        a mochila encher (ou a cada N cortes).
      * AUTO VENDER — vende tudo a cada X segundos.
      * TELEPORTE — usa o remote do jogo (Teleport:FireServer(Vector3))
        + botoes pras zonas FARM1/2/3 e SELL, e teleporte direto via
        CFrame (instantaneo, mais arriscado).
      * SPEED — via remote UpdateWalkspeed do jogo + WalkSpeed direto.
      * COLETAR BAUS — anda ate cada Bau (Comum/Raro/Mitico) do mapa.

    ATENCAO (risco de ban): BuyAxe/BuyFireAxe/SellAll sao validados no
    servidor (a UI mostra "SEM_DINHEIRO"), entao dinheiro NAO da pra
    forjar — mas CLONAR TOOLS do ReplicatedStorage pula a loja
    inteira. Teleport remote aparentemente nao valida posicao.

    Uso:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaCortarVender.lua"))()

    Standalone: cria uma mini GUI propria. Dentro do hub (futuro):
    retorna funcao(Koala, Window, Flags) que cria a aba.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

local LP = Players.LocalPlayer

--==================================================================--
--  REMOTES / REFS DO JOGO (do dump)
--==================================================================--
local R = {
    Teleport    = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Teleport"),
    SellAll     = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellAll"),
    SellTool    = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellTool"),
    BuyAxe      = ReplicatedStorage:WaitForChild("BuyAxe"),
    BuyFireAxe  = ReplicatedStorage:WaitForChild("BuyFireAxe"),
    UpdateWS    = ReplicatedStorage:WaitForChild("UpdateWalkspeed"),
    DropTool    = ReplicatedStorage:WaitForChild("DropTool"),
}
local PASTA_MACHADOS = ReplicatedStorage:WaitForChild("MachadosCorta")

local NOMES_MACHADOS = { "machado", "machado de gelo", "machado de fogo", "machado angelical", "machado demon" }
local NOMES_TRONCOS  = { "TRONCO", "TRONCO DE OURO", "TRONCO DE DIAMANTE" }

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

local function andarAte(pos, timeout)
    local h, r = hum(), hrp()
    if not h or not r then return false end
    h:MoveTo(pos)
    local t0 = os.clock()
    local alvo = Vector3.new(pos.X, r.Position.Y, pos.Z)
    while os.clock() - t0 < (timeout or 20) do
        local p = hrp()
        if not p then return false end
        local atual = Vector3.new(p.Position.X, 0, p.Position.Z)
        local dest  = Vector3.new(pos.X, 0, pos.Z)
        if (atual - dest).Magnitude < 6 then return true end
        task.wait(0.2)
    end
    return false
end

local function tpRemote(pos)
    pcall(function() R.Teleport:FireServer(pos) end)
end

local function tpDireto(pos)
    local r = hrp()
    if r then r.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
end

--==================================================================--
--  MACHADOS / TRONCOS (clone do ReplicatedStorage -> Backpack)
--==================================================================--
local function darItem(nome, origem)
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if not backpack then return false, "sem Backpack" end
    local jaTem = backpack:FindFirstChild(nome) or (char() and char():FindFirstChild(nome))
    if jaTem then return false, "voce ja tem " .. nome end

    local fonte = (origem and origem:FindFirstChild(nome))
        or PASTA_MACHADOS:FindFirstChild(nome)
        or ReplicatedStorage:FindFirstChild(nome)
    if not fonte then return false, nome .. " nao existe no ReplicatedStorage" end

    local clone = fonte:Clone()
    clone.Parent = backpack
    return true
end

local function equipar(nome)
    local h = hum()
    local backpack = LP:FindFirstChildOfClass("Backpack")
    local tool = (char() and char():FindFirstChild(nome)) or (backpack and backpack:FindFirstChild(nome))
    if h and tool and tool:IsA("Tool") and tool.Parent ~= char() then
        h:EquipTool(tool)
    end
    return tool ~= nil
end

--==================================================================--
--  ARVORES / BAUS — varredura dinamica
--==================================================================--
local function acharArvores()
    -- o jogo tem ~3 mil instancias chamadas "Tree" espalhadas no Workspace
    local out = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "Tree" then
            local p = d:IsA("BasePart") and d
                or d:FindFirstChildWhichIsA("BasePart", true)
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
--  VENDER
--==================================================================--
local function venderTudo()
    local ok, res = pcall(function() return R.SellAll:InvokeServer() end)
    return ok, res
end

--==================================================================--
--  ESTADO / LOOPS
--==================================================================--
local State = {
    autoFarm   = false,
    autoVender = false,
    autoBau    = false,
    venderACada = 15,   -- segundos (auto vender)
    speed      = 16,
}

task.spawn(function() -- AUTO VENDER
    while true do
        task.wait(State.venderACada)
        if State.autoVender then
            venderTudo()
        end
    end
end)

task.spawn(function() -- AUTO FARM
    while true do
        task.wait(0.3)
        if State.autoFarm then
            pcall(function()
                -- 1) garante um machado equipado
                local backpack = LP:FindFirstChildOfClass("Backpack")
                local temMachado = false
                for _, nome in ipairs(NOMES_MACHADOS) do
                    if (char() and char():FindFirstChild(nome)) or (backpack and backpack:FindFirstChild(nome)) then
                        temMachado = equipar(nome)
                        break
                    end
                end
                if not temMachado then
                    darItem("machado")
                    equipar("machado")
                end

                -- 2) vai ate a arvore mais proxima e corta
                local alvo = arvoreMaisProxima()
                if alvo then
                    andarAte(alvo.Position, 25)
                    local tool = char() and char():FindFirstChildWhichIsA("Tool")
                    local t0 = os.clock()
                    while State.autoFarm and os.clock() - t0 < 6 do
                        if tool and tool.Parent == char() then
                            tool:Activate()
                        end
                        task.wait(0.4)
                        -- se apareceu tronco no chao perto, coleta
                        for _, d in ipairs(Workspace:GetChildren()) do
                            if d:IsA("Tool") and d.Name:match("^TRONCO") then
                                local handle = d:FindFirstChild("Handle")
                                local r = hrp()
                                if handle and r and (handle.Position - r.Position).Magnitude < 60 then
                                    andarAte(handle.Position, 8)
                                end
                            end
                        end
                    end
                end

                -- 3) mochila cheia? vende
                local backpack2 = LP:FindFirstChildOfClass("Backpack")
                if backpack2 then
                    local troncos = 0
                    for _, t in ipairs(backpack2:GetChildren()) do
                        if t.Name:match("^TRONCO") then troncos = troncos + 1 end
                    end
                    if char() then
                        for _, t in ipairs(char():GetChildren()) do
                            if t:IsA("Tool") and t.Name:match("^TRONCO") then troncos = troncos + 1 end
                        end
                    end
                    if troncos >= 8 then
                        local sell = Workspace:FindFirstChild("SELL")
                        if sell then tpRemote(sell.Position) task.wait(1.5) end
                        venderTudo()
                        task.wait(1)
                    end
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
                        task.wait(1.5) -- deixa o prompt do bau disparar
                    end
                end
            end)
        end
    end
end)

--==================================================================--
--  GUI PROPRIA (standalone) — simples, sobrevive a respawn
--==================================================================--
local function criarGui()
    local pg = LP:WaitForChild("PlayerGui")
    if pg:FindFirstChild("KoalaCV") then pg.KoalaCV:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "KoalaCV"
    gui.ResetOnSpawn = false
    gui.Parent = pg

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 240, 0, 380)
    main.Position = UDim2.new(0, 20, 0.5, -190)
    main.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

    local titulo = Instance.new("TextLabel")
    titulo.Size = UDim2.new(1, 0, 0, 32)
    titulo.BackgroundTransparency = 1
    titulo.Text = "Koala — Cortar e Vender"
    titulo.TextColor3 = Color3.fromRGB(255, 255, 255)
    titulo.Font = Enum.Font.GothamBlack
    titulo.TextSize = 14
    titulo.Parent = main

    local lista = Instance.new("UIListLayout")
    lista.Padding = UDim.new(0, 5)
    lista.HorizontalAlignment = Enum.HorizontalAlignment.Center
    lista.Parent = main
    lista.SortOrder = Enum.SortOrder.LayoutOrder

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
        b.AutoButtonColor = true
        b.Parent = main
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        b.MouseButton1Click:Connect(function() callback(b) end)
        y = y + 1
        return b
    end

    local function toggle(texto, chave)
        return botao(texto .. ": OFF", function(b)
            State[chave] = not State[chave]
            b.Text = texto .. (State[chave] and ": ON" or ": OFF")
            b.BackgroundColor3 = State[chave] and Color3.fromRGB(35, 120, 70) or Color3.fromRGB(45, 48, 55)
        end)
    end

    toggle("Auto Farm", "autoFarm")
    toggle("Auto Vender", "autoVender")
    toggle("Auto Bau", "autoBau")

    botao("Vender tudo agora", function()
        local ok = venderTudo()
        notify("Vender", ok and "Inventario vendido!" or "Falha ao vender.", 2)
    end)

    botao("TP: zona FARM (remote)", function()
        local f = Workspace:FindFirstChild("FARM1")
        if f then tpRemote(f.Position) end
    end)

    botao("TP: vendedor SELL (remote)", function()
        local s = Workspace:FindFirstChild("SELL")
        if s then tpRemote(s.Position) task.wait(1) venderTudo() end
    end)

    -- machados
    for _, nome in ipairs(NOMES_MACHADOS) do
        botao("Pegar: " .. nome, function()
            local ok, err = darItem(nome)
            notify("Machado", ok and (nome .. " no Backpack!") or tostring(err), 3)
        end)
    end

    -- troncos
    for _, nome in ipairs(NOMES_TRONCOS) do
        botao("Spawnar: " .. nome, function()
            local ok, err = darItem(nome, ReplicatedStorage)
            notify("Tronco", ok and (nome .. " no Backpack!") or tostring(err), 2)
        end)
    end

    botao("Speed 50 (remote do jogo)", function()
        pcall(function() R.UpdateWS:FireServer(50) end)
        local h = hum()
        if h then h.WalkSpeed = 50 end
    end)

    main.Size = UDim2.new(0, 240, 0, 44 + (y * 35))
    return gui
end

--==================================================================--
--  BOOT standalone
--==================================================================--
if not _G.KoalaCVBooted then
    _G.KoalaCVBooted = true
    task.spawn(function()
        task.wait(1.5)
        criarGui()
        notify("Koala C&V", "Carregado! GUI na lateral esquerda.", 4)
    end)
end

--==================================================================--
--  RETORNO: integracao com o hub (futuro)
--==================================================================--
return function(Koala, Window, Flags)
    -- quando integrado ao KoalaHub, expoe as mesmas acoes numa aba
    if not Window then return end
    pcall(function()
        local tab = Window:Tab({ Title = "Cortar&Vender", Icon = "axe" })
        tab:Toggle({ Title = "Auto Farm", Value = State.autoFarm, Callback = function(v) State.autoFarm = v end })
        tab:Toggle({ Title = "Auto Vender (a cada " .. State.venderACada .. "s)", Value = State.autoVender, Callback = function(v) State.autoVender = v end })
        tab:Toggle({ Title = "Auto Bau", Value = State.autoBau, Callback = function(v) State.autoBau = v end })
        tab:Button({ Title = "Vender tudo agora", Callback = venderTudo })
        for _, nome in ipairs(NOMES_MACHADOS) do
            tab:Button({ Title = "Pegar: " .. nome, Callback = function() darItem(nome) end })
        end
        for _, nome in ipairs(NOMES_TRONCOS) do
            tab:Button({ Title = "Spawnar: " .. nome, Callback = function() darItem(nome, ReplicatedStorage) end })
        end
        tab:Button({
            Title = "TP: vendedor (remote) + vender",
            Callback = function()
                local s = Workspace:FindFirstChild("SELL")
                if s then tpRemote(s.Position) task.wait(1) venderTudo() end
            end,
        })
    end)
end
