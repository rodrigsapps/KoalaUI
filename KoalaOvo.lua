--[[
    KOALA OVO — ROUBE UM OVO (Steal An Egg) — PlaceId 107778070777162
    ------------------------------------------------------------------
    v2 — GUI simples estilo Miranda Hub: lista de ovos + GO/STOP.

    Como funciona o roubo (do jeito que nao da erro):
      1. Toque num ovo da lista (ou aperte GO pra ir no melhor)
      2. O script VOA voce ate o ovo e tenta pegar pelo remote
      3. Se pegar: VOCE volta ANDANDO pra base (a volta automatica
         era o que dava erro — por isso a volta e manual)

    Anti-AFK da esteira:
      A cada 2 minutos o script abre a loja e fecha, pro jogo
      contar como atividade enquanto voce fica na esteira.

    Uso:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaOvo.lua"))()
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local VIM               = game:GetService("VirtualInputManager")

local LP = Players.LocalPlayer

--==================================================================--
--  ESTADO
--==================================================================--
local voando      = false
local noclipFarm  = false
local selecionado = nil   -- uid do ovo tocado na lista
local roubados    = 0
local statusTxt   = "Escolhe um ovo e aperta GO"
local esteiraAfk  = true
local espLigado   = false

--==================================================================--
--  RARIDADES / CORES
--==================================================================--
local RAR_COR = {
    Common    = Color3.fromRGB(170, 170, 175),
    Uncommon  = Color3.fromRGB(80, 220, 100),
    Rare      = Color3.fromRGB(60, 140, 255),
    Epic      = Color3.fromRGB(170, 85, 247),
    Legendary = Color3.fromRGB(251, 191, 36),
    Mythic    = Color3.fromRGB(230, 60, 90),
    Cosmic    = Color3.fromRGB(6, 182, 212),
    Secret    = Color3.fromRGB(249, 115, 22),
    Eternal   = Color3.fromRGB(217, 70, 239),
    Divine    = Color3.fromRGB(244, 63, 94),
    Unknown   = Color3.fromRGB(120, 120, 130),
}
local RAR_RANK = { Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, Cosmic=7, Secret=8, Eternal=9, Divine=10, Unknown=0 }

--==================================================================--
--  UTILS
--==================================================================--
local function aviso(msg, dur)
    print("[KoalaOvo] " .. tostring(msg))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",
            { Title = "Koala Ovo", Text = tostring(msg), Duration = dur or 3 })
    end)
end

local function fmtDinheiro(n)
    n = tonumber(n) or 0
    if n >= 1e9 then return string.format("%.2fb", n / 1e9) end
    if n >= 1e6 then return string.format("%.2fm", n / 1e6) end
    if n >= 1e3 then return string.format("%.2fk", n / 1e3) end
    if n > 0    then return tostring(math.floor(n)) end
    return ""
end

--==================================================================--
--  REMOTES (nomes reais do jogo)
--==================================================================--
local NET = nil
pcall(function()
    NET = ReplicatedStorage:WaitForChild("Packages", 10):WaitForChild("Networking", 10)
end)

local function net(nome)
    if NET then
        local r = NET:FindFirstChild(nome)
        if r then return r end
    end
    local curto = nome:match("([^/]+)$") or nome
    return ReplicatedStorage:FindFirstChild(curto, true)
end

local function rfCarry()    return net("RF/EggWorld/AskFieldEggCarry")    end
local function rfSnapshot() return net("RF/EggWorld/AskFieldEggSnapshot") end

local function chamarRF(remote, ...)
    if not remote then return false end
    local args = { ... }
    local ok = pcall(function()
        if remote:IsA("RemoteFunction") then
            remote:InvokeServer(table.unpack(args))
        else
            remote:FireServer(table.unpack(args))
        end
    end)
    return ok
end

-- modulo com dados dos ovos (raridade, ganho por segundo, nome)
local AssetItems = nil
pcall(function()
    AssetItems = require(ReplicatedStorage:WaitForChild("Shared", 5):WaitForChild("Util", 5):WaitForChild("AssetItems", 5))
end)

local function dadosDaCategoria(cat)
    -- retorna raridade, ganhoPorSegundo
    local rar, ganho = nil, 0
    if AssetItems then
        pcall(function()
            if AssetItems.Assets and AssetItems.Assets[cat] then
                local a = AssetItems.Assets[cat]
                rar = a.Rarity or (a.Egg and a.Egg.Rarity)
                ganho = a.EarningRate or (a.Egg and a.Egg.EarningRate) or 0
            end
            if (not ganho or ganho == 0) and AssetItems.ProfileIncomePerSecond then
                ganho = AssetItems.ProfileIncomePerSecond(cat) or 0
            end
        end)
    end
    return rar or "Unknown", tonumber(ganho) or 0
end

--==================================================================--
--  LISTA DE OVOS (snapshot do servidor, cache 4s)
--==================================================================--
local ovosCache = {}
local ovosTempo = 0

local ESTADOS_OK = { Slot = true, Dropped = true, GuardCarried = true, [1] = true }

local function atualizarOvos(forcar)
    if not forcar and (os.clock() - ovosTempo) < 4 and #ovosCache > 0 then
        return ovosCache
    end
    local r = rfSnapshot()
    local ok, ret = pcall(function() return r and r:InvokeServer() end)
    if not (ok and type(ret) == "table") then return ovosCache end

    local lista = {}
    local recs = type(ret.Records) == "table" and ret.Records or ret
    for chave, rec in pairs(recs) do
        if type(rec) == "table" then
            local uid = rec.Uid or (type(chave) == "string" and chave)
            local cf = rec.BoundsCFrame
            local pos = nil
            pcall(function() pos = cf and cf.Position end)
            if not pos then
                local m = rec.PhysicalModel
                pcall(function()
                    local p = m and (m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart"))
                    if p then pos = p.Position end
                end)
            end
            local roubavel = ESTADOS_OK[rec.State] == true
            -- ovos da area inicial / da propria base nao entram
            if pos and pos.X < 530 then roubavel = false end
            if uid and tostring(uid):find("FirstArea") then roubavel = false end

            if uid and pos and roubavel then
                local cat = rec.AssetCategory or rec.Name or "Ovo"
                local rar, ganho = dadosDaCategoria(cat)
                if rar == "Unknown" and type(rec.Rarity) == "string" then rar = rec.Rarity end
                table.insert(lista, {
                    Uid = uid, Cat = cat, Rar = rar, Ganho = ganho, Pos = pos,
                    Area = tostring(rec.AreaId or ""),
                })
            end
        end
    end
    table.sort(lista, function(a, b)
        if a.Ganho ~= b.Ganho then return a.Ganho > b.Ganho end
        return (RAR_RANK[a.Rar] or 0) > (RAR_RANK[b.Rar] or 0)
    end)
    if #lista > 0 then
        ovosCache = lista
        ovosTempo = os.clock()
    end
    return ovosCache
end

local function melhorOvo()
    local lista = atualizarOvos(false)
    return lista[1]
end

local function ovoPorUid(uid)
    for _, o in ipairs(atualizarOvos(false)) do
        if o.Uid == uid then return o end
    end
    return nil
end

--==================================================================--
--  VOO (tween cancelavel) + NOCLIP durante o voo
--==================================================================--
local tweenAtivo = nil

local function cancelarTween()
    if tweenAtivo then
        pcall(function() tweenAtivo:Cancel() end)
        tweenAtivo = nil
    end
end

local function pegarHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function irPara(pos, velocidade)
    local hrp = pegarHRP()
    if not hrp then return false end
    cancelarTween()
    local dist = (hrp.Position - pos).Magnitude
    if dist < 3 then return true end
    local tempo = math.clamp(dist / (velocidade or 100), 0.1, 30)
    local ok, tw = pcall(function()
        return TweenService:Create(hrp, TweenInfo.new(tempo, Enum.EasingStyle.Linear),
            { CFrame = CFrame.new(pos) })
    end)
    if not ok or not tw then return false end
    tweenAtivo = tw
    tw:Play()
    local fim = os.clock() + tempo + 3
    while tweenAtivo == tw and os.clock() < fim do
        if tw.PlaybackState ~= Enum.PlaybackState.Playing then break end
        task.wait(0.1)
    end
    if tweenAtivo == tw then tweenAtivo = nil end
    local h2 = pegarHRP()
    return h2 and (h2.Position - pos).Magnitude < 14
end

RunService.Stepped:Connect(function()
    if not noclipFarm then return end
    pcall(function()
        local c = LP.Character
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end)
end)

--==================================================================--
--  PEGAR OVO
--==================================================================--
local function ferramentaOvo(inst)
    if not inst:IsA("Tool") then return false end
    if inst:GetAttribute("UID") or inst:GetAttribute("EggUid") then return true end
    return inst.Name:lower():find("egg", 1, true) ~= nil
end

local function ovoNaMao()
    local c = LP.Character
    if not c then return nil end
    for _, filho in ipairs(c:GetChildren()) do
        if ferramentaOvo(filho) then
            return filho:GetAttribute("UID") or filho:GetAttribute("EggUid") or filho.Name
        end
    end
    return nil
end

local function tentarPegar(uid)
    local r = rfCarry()
    if r then
        chamarRF(r, { Uid = uid })
        chamarRF(r, uid)
    end
    -- plano B: aperta o prompt de pegar que estiver perto
    pcall(function()
        local hrp = pegarHRP()
        if not hrp then return end
        local pasta = Workspace:FindFirstChild("AreaEggSlotsClient")
        local modelo = pasta and pasta:FindFirstChild(tostring(uid))
        local alvos = modelo and modelo:GetDescendants() or {}
        for _, d in ipairs(alvos) do
            if d:IsA("ProximityPrompt") then
                fireproximityprompt(d)
            end
        end
    end)
end

--==================================================================--
--  ROUBO (voo de ida, volta manual)
--==================================================================--
local function goRoubo()
    if voando then return end
    local alvo = selecionado and ovoPorUid(selecionado) or melhorOvo()
    if not alvo then
        statusTxt = "Nenhum ovo no mapa agora"
        atualizarOvos(true)
        return
    end
    voando = true
    noclipFarm = true
    local okVoo, err = pcall(function()
        statusTxt = "Voando ate: " .. tostring(alvo.Cat)
        -- sobe, cruza por cima, desce
        irPara(alvo.Pos + Vector3.new(0, 28, 0), 130)
        if not voando then return end
        irPara(alvo.Pos + Vector3.new(0, 2, 0), 70)
        if not voando then return end

        statusTxt = "Pegando " .. tostring(alvo.Cat) .. "..."
        local t0 = os.clock()
        local pegou = false
        while os.clock() - t0 < 8 and voando do
            tentarPegar(alvo.Uid)
            task.wait(0.3)
            if ovoNaMao() then pegou = true break end
        end
        if pegou then
            roubados = roubados + 1
            statusTxt = "Pegou! Volta ANDANDO pra base"
            aviso("Pegou! Agora volta ANDANDO (a volta automatica da erro)", 5)
        else
            statusTxt = "Nao peguei sozinho — aperta o botao de pegar"
            aviso("Nao consegui pegar. Toca no ovo ai do lado!", 5)
        end
    end)
    voando = false
    noclipFarm = false
    cancelarTween()
    if not okVoo then
        statusTxt = "Erro: " .. tostring(err):sub(1, 40)
    end
end

--==================================================================--
--  ANTI-AFK ESTEIRA: abre e fecha a loja a cada 2 min
--==================================================================--
local function clicarEm(botao)
    pcall(function()
        local pos = botao.AbsolutePosition + botao.AbsoluteSize / 2
        VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
        task.wait(0.06)
        VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
    end)
end

local function acharBotaoLoja()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local melhor = nil
    for _, d in ipairs(pg:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible then
            local nome = d.Name:lower()
            local texto = ""
            pcall(function() texto = (d.Text or ""):lower() end)
            if nome:find("shop") or nome:find("loja") or nome:find("store")
                or texto:find("shop") or texto:find("loja") or texto:find("store") then
                melhor = d
                break
            end
        end
    end
    return melhor
end

local function fecharLoja()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _, d in ipairs(pg:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible then
            local nome = d.Name:lower()
            local texto = ""
            pcall(function() texto = (d.Text or ""):lower() end)
            if nome:find("close") or nome:find("fechar") or nome == "x"
                or texto == "x" or texto:find("close") or texto:find("fechar") then
                clicarEm(d)
                return true
            end
        end
    end
    return false
end

local function abrirFecharLoja()
    local loja = acharBotaoLoja()
    if not loja then return false end
    clicarEm(loja)
    task.wait(1.2)
    if not fecharLoja() then
        clicarEm(loja) -- alguns jogos o mesmo botao abre e fecha
    end
    return true
end

task.spawn(function()
    while true do
        task.wait(120)
        pcall(function()
            if esteiraAfk then
                if abrirFecharLoja() then
                    print("[KoalaOvo] anti-AFK esteira: loja aberta/fechada")
                end
            end
        end)
    end
end)

-- anti-idle padrao (sempre ligado)
LP.Idled:Connect(function()
    pcall(function()
        local VU = game:GetService("VirtualUser")
        VU:CaptureController()
        VU:ClickButton2(Vector2.new())
    end)
end)

--==================================================================--
--  ESP dos ovos
--==================================================================--
local espObjs = {}

local function limparESP()
    for _, o in pairs(espObjs) do
        pcall(function() o.hl:Destroy() end)
        pcall(function() o.bb:Destroy() end)
    end
    espObjs = {}
end

task.spawn(function()
    while true do
        pcall(function()
            if espLigado then
                local vistos = {}
                for _, o in ipairs(atualizarOvos(false)) do
                    vistos[o.Uid] = true
                    if not espObjs[o.Uid] then
                        local pasta = Workspace:FindFirstChild("AreaEggSlotsClient")
                        local modelo = pasta and pasta:FindFirstChild(tostring(o.Uid))
                        local parte = modelo and (modelo.PrimaryPart or modelo:FindFirstChildWhichIsA("BasePart"))
                        if modelo and parte then
                            local cor = RAR_COR[o.Rar] or RAR_COR.Unknown
                            local hl = Instance.new("Highlight")
                            hl.FillColor = cor
                            hl.OutlineColor = cor
                            hl.FillTransparency = 0.6
                            hl.Adornee = modelo
                            hl.Parent = modelo
                            local bb = Instance.new("BillboardGui")
                            bb.Size = UDim2.new(0, 140, 0, 36)
                            bb.StudsOffset = Vector3.new(0, 3.5, 0)
                            bb.AlwaysOnTop = true
                            bb.Adornee = parte
                            local t = Instance.new("TextLabel")
                            t.Size = UDim2.new(1, 0, 1, 0)
                            t.BackgroundTransparency = 1
                            t.Text = string.format("%s\n%s", tostring(o.Cat), o.Rar)
                            t.TextColor3 = cor
                            t.TextStrokeTransparency = 0.3
                            t.Font = Enum.Font.GothamBold
                            t.TextSize = 12
                            t.Parent = bb
                            bb.Parent = modelo
                            espObjs[o.Uid] = { hl = hl, bb = bb }
                        end
                    end
                end
                for uid, o in pairs(espObjs) do
                    if not vistos[uid] then
                        pcall(function() o.hl:Destroy() end)
                        pcall(function() o.bb:Destroy() end)
                        espObjs[uid] = nil
                    end
                end
            else
                limparESP()
            end
        end)
        task.wait(3)
    end
end)

--==================================================================--
--  GUI — estilo Miranda Hub (lista + GO/STOP)
--==================================================================--
local function paiGUI()
    local ok, hui = pcall(function() return gethui() end)
    if ok and hui then return hui end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then return cg end
    return LP:WaitForChild("PlayerGui")
end

pcall(function()
    for _, g in ipairs(paiGUI():GetChildren()) do
        if g:IsA("ScreenGui") and g:GetAttribute("KoalaOvo") then g:Destroy() end
    end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = "KB" .. tostring(math.random(100000, 999999))
Gui:SetAttribute("KoalaOvo", true)
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.IgnoreGuiInset = true
Gui.DisplayOrder = 50
Gui.Parent = paiGUI()

local C = {
    fundo    = Color3.fromRGB(18, 18, 26),
    cartao   = Color3.fromRGB(28, 28, 40),
    cartaoOn = Color3.fromRGB(40, 40, 58),
    vermelho = Color3.fromRGB(230, 45, 60),
    verde    = Color3.fromRGB(60, 210, 120),
    texto    = Color3.fromRGB(240, 240, 245),
    sub      = Color3.fromRGB(150, 150, 165),
    escuro   = Color3.fromRGB(30, 30, 44),
}

-- botao flutuante K
local BotaoK = Instance.new("TextButton")
BotaoK.Size = UDim2.new(0, 44, 0, 44)
BotaoK.Position = UDim2.new(0, 12, 0, 120)
BotaoK.BackgroundColor3 = C.vermelho
BotaoK.Text = "K"
BotaoK.TextColor3 = Color3.new(1, 1, 1)
BotaoK.Font = Enum.Font.GothamBold
BotaoK.TextSize = 20
BotaoK.Parent = Gui
Instance.new("UICorner", BotaoK).CornerRadius = UDim.new(1, 0)

-- painel
local Painel = Instance.new("Frame")
Painel.Size = UDim2.new(0, 320, 0, 420)
Painel.Position = UDim2.new(0.5, -160, 0.5, -210)
Painel.BackgroundColor3 = C.fundo
Painel.BorderSizePixel = 0
Painel.Parent = Gui
Instance.new("UICorner", Painel).CornerRadius = UDim.new(0, 16)

-- titulo
local Titulo = Instance.new("TextLabel")
Titulo.Size = UDim2.new(1, 0, 0, 46)
Titulo.BackgroundTransparency = 1
Titulo.RichText = true
Titulo.Text = '<font color="rgb(230,45,60)"><b>KOALA</b></font> <font color="rgb(240,240,245)"><b>OVO</b></font>'
Titulo.Font = Enum.Font.GothamBold
Titulo.TextSize = 20
Titulo.Parent = Painel

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -24, 0, 18)
Status.Position = UDim2.new(0, 12, 0, 44)
Status.BackgroundTransparency = 1
Status.Text = statusTxt
Status.TextColor3 = C.sub
Status.Font = Enum.Font.Gotham
Status.TextSize = 11
Status.TextTruncate = Enum.TextTruncate.AtEnd
Status.Parent = Painel

-- lista de ovos
local Lista = Instance.new("ScrollingFrame")
Lista.Size = UDim2.new(1, -20, 1, -190)
Lista.Position = UDim2.new(0, 10, 0, 68)
Lista.BackgroundTransparency = 1
Lista.ScrollBarThickness = 3
Lista.ScrollBarImageColor3 = C.sub
Lista.CanvasSize = UDim2.new(0, 0, 0, 0)
Lista.Parent = Painel

local ListaLayout = Instance.new("UIListLayout")
ListaLayout.Padding = UDim.new(0, 8)
ListaLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListaLayout.Parent = Lista

ListaLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Lista.CanvasSize = UDim2.new(0, 0, 0, ListaLayout.AbsoluteContentSize.Y + 10)
end)

-- botoes GO / STOP
local GO = Instance.new("TextButton")
GO.Size = UDim2.new(0.58, 0, 0, 46)
GO.Position = UDim2.new(0, 10, 1, -110)
GO.BackgroundColor3 = C.vermelho
GO.Text = "GO"
GO.TextColor3 = Color3.new(1, 1, 1)
GO.Font = Enum.Font.GothamBold
GO.TextSize = 18
GO.Parent = Painel
Instance.new("UICorner", GO).CornerRadius = UDim.new(0, 12)

local STOP = Instance.new("TextButton")
STOP.Size = UDim2.new(0.38, 0, 0, 46)
STOP.Position = UDim2.new(0.60, 10, 1, -110)
STOP.BackgroundColor3 = C.escuro
STOP.Text = "STOP"
STOP.TextColor3 = C.vermelho
STOP.Font = Enum.Font.GothamBold
STOP.TextSize = 16
STOP.Parent = Painel
Instance.new("UICorner", STOP).CornerRadius = UDim.new(0, 12)

-- mini toggles embaixo
local function miniToggle(texto, x, inicial, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.46, 0, 0, 34)
    b.Position = UDim2.new(x, 10, 1, -52)
    b.BackgroundColor3 = inicial and C.verde or C.escuro
    b.TextColor3 = inicial and Color3.new(0, 0, 0) or C.sub
    b.Text = texto .. (inicial and " ON" or " off")
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Parent = Painel
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
    local est = inicial
    b.MouseButton1Click:Connect(function()
        est = not est
        b.BackgroundColor3 = est and C.verde or C.escuro
        b.TextColor3 = est and Color3.new(0, 0, 0) or C.sub
        b.Text = texto .. (est and " ON" or " off")
        cb(est)
    end)
    return b
end

miniToggle("Esteira AFK", 0, true, function(v) esteiraAfk = v end)
miniToggle("ESP ovos", 0.50, false, function(v) espLigado = v end)

GO.MouseButton1Click:Connect(function()
    task.spawn(goRoubo)
end)
STOP.MouseButton1Click:Connect(function()
    voando = false
    noclipFarm = false
    cancelarTween()
    statusTxt = "Parado"
end)
BotaoK.MouseButton1Click:Connect(function()
    Painel.Visible = not Painel.Visible
end)

-- arrastar painel e botao K
local function arrastavel(alvo, segurador)
    local UIS = game:GetService("UserInputService")
    local arrastando, inicio, posInicio
    segurador.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            arrastando = true
            inicio = input.Position
            posInicio = alvo.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then arrastando = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if arrastando and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - inicio
            alvo.Position = UDim2.new(posInicio.X.Scale, posInicio.X.Offset + delta.X,
                posInicio.Y.Scale, posInicio.Y.Offset + delta.Y)
        end
    end)
end
arrastavel(Painel, Titulo)
arrastavel(BotaoK, BotaoK)

--==================================================================--
--  CARTOES DA LISTA
--==================================================================--
local cartoes = {} -- uid -> frame

local function montarCartao(ovo)
    local f = cartoes[ovo.Uid]
    if not f then
        f = Instance.new("TextButton")
        f.Size = UDim2.new(1, 0, 0, 60)
        f.BackgroundColor3 = C.cartao
        f.Text = ""
        f.AutoButtonColor = false
        f.Parent = Lista
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Transparency = 1
        stroke.Parent = f

        local icone = Instance.new("Frame")
        icone.Name = "Icone"
        icone.Size = UDim2.new(0, 42, 0, 42)
        icone.Position = UDim2.new(0, 9, 0.5, -21)
        icone.Parent = f
        Instance.new("UICorner", icone).CornerRadius = UDim.new(0, 10)
        local letra = Instance.new("TextLabel")
        letra.Name = "Letra"
        letra.Size = UDim2.new(1, 0, 1, 0)
        letra.BackgroundTransparency = 1
        letra.TextColor3 = Color3.new(1, 1, 1)
        letra.Font = Enum.Font.GothamBold
        letra.TextSize = 20
        letra.Parent = icone

        local nome = Instance.new("TextLabel")
        nome.Name = "Nome"
        nome.Size = UDim2.new(1, -150, 0, 22)
        nome.Position = UDim2.new(0, 60, 0, 8)
        nome.BackgroundTransparency = 1
        nome.TextColor3 = C.texto
        nome.Font = Enum.Font.GothamBold
        nome.TextSize = 14
        nome.TextXAlignment = Enum.TextXAlignment.Left
        nome.TextTruncate = Enum.TextTruncate.AtEnd
        nome.Parent = f

        local rar = Instance.new("TextLabel")
        rar.Name = "Raridade"
        rar.Size = UDim2.new(1, -150, 0, 16)
        rar.Position = UDim2.new(0, 60, 0, 32)
        rar.BackgroundTransparency = 1
        rar.Font = Enum.Font.GothamBold
        rar.TextSize = 11
        rar.TextXAlignment = Enum.TextXAlignment.Left
        rar.Parent = f

        local valor = Instance.new("TextLabel")
        valor.Name = "Valor"
        valor.Size = UDim2.new(0, 85, 1, 0)
        valor.Position = UDim2.new(1, -92, 0, 0)
        valor.BackgroundTransparency = 1
        valor.TextColor3 = C.verde
        valor.Font = Enum.Font.GothamBold
        valor.TextSize = 13
        valor.TextXAlignment = Enum.TextXAlignment.Right
        valor.Parent = f

        f.MouseButton1Click:Connect(function()
            if selecionado == f:GetAttribute("Uid") then
                selecionado = nil
            else
                selecionado = f:GetAttribute("Uid")
            end
        end)
        cartoes[ovo.Uid] = f
    end

    f:SetAttribute("Uid", ovo.Uid)
    local cor = RAR_COR[ovo.Rar] or RAR_COR.Unknown
    f.Icone.BackgroundColor3 = cor
    f.Icone.Letra.Text = ovo.Rar:sub(1, 1):upper()
    f.Nome.Text = tostring(ovo.Cat)
    f.Raridade.Text = ovo.Rar
    f.Raridade.TextColor3 = cor
    f.Valor.Text = fmtDinheiro(ovo.Ganho)
    return f
end

local function atualizarLista()
    local ovos = atualizarOvos(false)
    local vivos = {}
    for i, ovo in ipairs(ovos) do
        vivos[ovo.Uid] = true
        local f = montarCartao(ovo)
        f.LayoutOrder = i
        local stroke = f:FindFirstChildOfClass("UIStroke")
        if stroke then
            if selecionado == ovo.Uid then
                stroke.Color = RAR_COR[ovo.Rar] or RAR_COR.Unknown
                stroke.Transparency = 0
                f.BackgroundColor3 = C.cartaoOn
            else
                stroke.Transparency = 1
                f.BackgroundColor3 = C.cartao
            end
        end
    end
    for uid, f in pairs(cartoes) do
        if not vivos[uid] then
            pcall(function() f:Destroy() end)
            cartoes[uid] = nil
            if selecionado == uid then selecionado = nil end
        end
    end
end

--==================================================================--
--  LOOPS FINAIS
--==================================================================--
task.spawn(function()
    task.wait(2)
    atualizarOvos(true)
    while Gui.Parent do
        pcall(atualizarLista)
        task.wait(4)
        atualizarOvos(true)
    end
end)

task.spawn(function()
    while Gui.Parent do
        pcall(function()
            Status.Text = string.format("%s  |  pegos: %d", statusTxt, roubados)
        end)
        task.wait(0.4)
    end
end)

if game.PlaceId ~= 107778070777162 then
    aviso("Esse script e pro Roube um Ovo (PlaceId diferente aqui)", 5)
end
aviso("Koala Ovo v2 carregado! Botao K abre/fecha.", 4)
