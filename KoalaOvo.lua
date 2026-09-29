--[[
    KOALA HUB — ROUBE UM OVO (Steal An Egg) — PlaceId 107778070777162
    ------------------------------------------------------------------
    v1 — GUI propria, leve, sem biblioteca externa.

    Por que essa GUI nao chama atencao:
      * Nome do ScreenGui aleatorio a cada execucao
      * Fica fora do PlayerGui (gethui/CoreGui)
      * Nao usa identifyexecutor nem nada que entregue o executor
      * Tudo dentro de pcall — um erro nao derruba o script

    Secoes:
      Farm      = auto roubar (com filtro de raridade), chocar, colocar, esteira
      ESP       = ovos com cor e nome da raridade atraves da parede
      Movimento = velocidade, pulo, pulo infinito, atravessar paredes
      Teleporte = base, entrega, zonas do mapa
      Outros    = anti-AFK, anti-lag, status ao vivo

    Uso:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaOvo.lua"))()
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local LP = Players.LocalPlayer

--==================================================================--
--  ESTADO
--==================================================================--
local cfg = {
    autoRoubar   = false,
    autoChocar   = false,
    autoColocar  = false,
    autoEsteira  = false,
    espOvos      = false,
    espSoRaros   = false,
    velocidade   = 16,
    pulo         = 50,
    puloInfinito = false,
    noclip       = false,
    antiAfk      = true,
    raridadeMin  = "Rare",
    zonaAlvo     = "Forest",
}

local stats = { roubados = 0, chocados = 0 }
local statusAtual = "Parado"
local farmOcupado = false   -- true enquanto esta roubando (liga noclip no trajeto)

local RARIDADES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Secret", "Eternal", "Divine" }
local RAR_IDX = {}
for i, r in ipairs(RARIDADES) do RAR_IDX[r] = i end
local RAR_COR = {
    Common    = Color3.fromRGB(180, 180, 180),
    Uncommon  = Color3.fromRGB(80, 220, 100),
    Rare      = Color3.fromRGB(60, 140, 255),
    Epic      = Color3.fromRGB(170, 85, 247),
    Legendary = Color3.fromRGB(251, 191, 36),
    Mythic    = Color3.fromRGB(139, 92, 246),
    Cosmic    = Color3.fromRGB(6, 182, 212),
    Secret    = Color3.fromRGB(249, 115, 22),
    Eternal   = Color3.fromRGB(217, 70, 239),
    Divine    = Color3.fromRGB(244, 63, 94),
}

local ZONAS = { "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark" }

--==================================================================--
--  UTILITARIOS
--==================================================================--
local function aviso(msg, dur)
    print("[KoalaOvo] " .. tostring(msg))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",
            { Title = "Koala Ovo", Text = tostring(msg), Duration = dur or 3 })
    end)
end

local function pegarChar()
    return LP.Character
end
local function pegarHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function pegarHum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function paraVector3(p)
    local ok, tipo = pcall(typeof, p)
    if not ok then return nil end
    if tipo == "Vector3" then return p end
    if tipo == "CFrame" then return p.Position end
    if tipo == "table" then
        local x = p.X or p.x or p[1]
        local y = p.Y or p.y or p[2]
        local z = p.Z or p.z or p[3]
        if x and y and z then return Vector3.new(x, y, z) end
    end
    return nil
end

--==================================================================--
--  REMOTES (nomes reais, conferidos em scripts abertos do jogo)
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
    -- plano B: procura so pelo nome final em qualquer lugar
    local curto = nome:match("([^/]+)$") or nome
    local achado = ReplicatedStorage:FindFirstChild(curto, true)
    return achado
end

local function rfCarry()    return net("RF/EggWorld/AskFieldEggCarry")    end
local function rfSnapshot() return net("RF/EggWorld/AskFieldEggSnapshot") end
local function rfLive()     return net("RF/EggWorld/AskLiveSnapshot")     end
local function rfHatch()    return net("RF/EggWorld/AskHatch")            end
local function rfFinish()   return net("RF/EggWorld/AskFinishHatch")      end
local function rfPlace()    return net("RF/EggWorld/AskPlaceEgg")         end
local function rfPlots()    return net("RF/Plots/AskState") or net("RF/Homestead/AskState") end
local function rfTierUp()   return net("RF/Treadmill/AskTierRaise")       end
local function rfDon()      return net("RF/Treadmill/AskDon") or net("RF/Treadmill/AskMount") end
local function rfWearStill() return net("RF/Treadmill/AskWearStill")      end

local function chamarRF(remote, ...)
    if not remote then return false, nil end
    local args = { ... }
    local ok, ret = pcall(function()
        if remote:IsA("RemoteFunction") then
            return remote:InvokeServer(unpack(args))
        else
            remote:FireServer(unpack(args))
            return true
        end
    end)
    return ok, ret
end

--==================================================================--
--  SNAPSHOT DOS OVOS DO MAPA (cache de 5s)
--==================================================================--
local ovosCache = {}
local ovosCacheTempo = 0

local function atualizarSnapshot(forcar)
    if not forcar and (os.clock() - ovosCacheTempo) < 5 and #ovosCache > 0 then
        return ovosCache
    end
    local r = rfSnapshot()
    local ok, ret = pcall(function() return r and r:InvokeServer() end)
    if ok and type(ret) == "table" then
        local lista = {}
        local recs = type(ret.Records) == "table" and ret.Records or ret
        for chave, rec in pairs(recs) do
            if type(rec) == "table" then
                if not rec.Uid and type(chave) == "string" then
                    rec.Uid = chave
                end
                if rec.Uid then
                    table.insert(lista, rec)
                end
            end
        end
        if #lista > 0 then
            ovosCache = lista
            ovosCacheTempo = os.clock()
        end
    end
    return ovosCache
end

local function modeloDoOvo(uid)
    local pasta = Workspace:FindFirstChild("AreaEggSlotsClient")
    if not pasta then return nil end
    return pasta:FindFirstChild(tostring(uid))
end

local function raridadeDoModelo(modelo)
    local ok, rar = pcall(function()
        local data = modelo:FindFirstChild("Data")
        local r = data and data:FindFirstChild("Rarity")
        return r and r.Value
    end)
    if ok and type(rar) == "string" then return rar end
    return nil
end

local function posicaoDoOvo(rec)
    local modelo = modeloDoOvo(rec.Uid)
    if modelo then
        local p = modelo.PrimaryPart or modelo:FindFirstChildWhichIsA("BasePart")
        if p then return p.Position end
    end
    return paraVector3(rec.Position)
end

--==================================================================--
--  BASE / PLOT DO JOGADOR
--==================================================================--
local plotCache, penCache = nil, nil

local function acharPlot()
    if plotCache and plotCache.Parent then return plotCache, penCache end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil, nil end

    -- caminho 1: pergunta ao servidor qual slot e meu
    local r = rfPlots()
    local ok, ret = pcall(function() return r and r:InvokeServer() end)
    if ok and type(ret) == "table" and type(ret.OwnersBySlot) == "table" then
        for slot, dono in pairs(ret.OwnersBySlot) do
            if tostring(dono) == tostring(LP.UserId) or dono == LP.Name then
                local p = plots:FindFirstChild(tostring(slot))
                if p then
                    plotCache = p
                    penCache = p:FindFirstChild("PetArea") or p:FindFirstChildWhichIsA("BasePart", true)
                    return plotCache, penCache
                end
            end
        end
    end
    -- caminho 2: procura plot com meu nome/userid
    for _, p in ipairs(plots:GetChildren()) do
        local dono = p:GetAttribute("Owner") or p:GetAttribute("OwnerId") or p:GetAttribute("UserId")
        if tostring(dono) == tostring(LP.UserId) or tostring(dono) == LP.Name then
            plotCache = p
            penCache = p:FindFirstChild("PetArea") or p:FindFirstChildWhichIsA("BasePart", true)
            return plotCache, penCache
        end
    end
    return nil, nil
end

local function posicaoBase()
    local plot, pen = acharPlot()
    if pen and pen:IsA("BasePart") then return pen.Position end
    if plot then
        local p = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart", true)
        if p then return p.Position end
    end
    local entrega = Workspace:FindFirstChild("DeliveryHitbox", true)
    if entrega and entrega:IsA("BasePart") then return entrega.Position end
    return nil
end

--==================================================================--
--  CARREGANDO OVO?
--==================================================================--
local function ferramentaOvo(inst)
    if not inst:IsA("Tool") then return false end
    if inst:GetAttribute("UID") or inst:GetAttribute("EggUid") then return true end
    return inst.Name:lower():find("egg", 1, true) ~= nil
end

local function ovoNaMao()
    local c = LP.Character
    if not c then return nil, nil end
    for _, filho in ipairs(c:GetChildren()) do
        if ferramentaOvo(filho) then
            local uid = filho:GetAttribute("UID") or filho:GetAttribute("EggUid") or filho.Name
            return filho, uid
        end
    end
    return nil, nil
end

local function ovosNaMochila()
    local lista = {}
    local mochila = LP:FindFirstChild("Backpack")
    if mochila then
        for _, filho in ipairs(mochila:GetChildren()) do
            if ferramentaOvo(filho) then
                local uid = filho:GetAttribute("UID") or filho:GetAttribute("EggUid") or filho.Name
                table.insert(lista, uid)
            end
        end
    end
    return lista
end

--==================================================================--
--  MOVIMENTO (tween com cancelamento)
--==================================================================--
local tweenAtivo = nil

local function cancelarTween()
    if tweenAtivo then
        pcall(function() tweenAtivo:Cancel() end)
        tweenAtivo = nil
    end
end

local function irPara(pos, velocidade)
    local hrp = pegarHRP()
    if not hrp then return false end
    cancelarTween()
    local dist = (hrp.Position - pos).Magnitude
    if dist < 3 then return true end
    local tempo = math.clamp(dist / (velocidade or 60), 0.1, 30)
    local alvo = CFrame.new(pos + Vector3.new(0, 2, 0))
    local ok, tw = pcall(function()
        return TweenService:Create(hrp, TweenInfo.new(tempo, Enum.EasingStyle.Linear), { CFrame = alvo })
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
    local hrp2 = pegarHRP()
    return hrp2 and (hrp2.Position - pos).Magnitude < 12
end

--==================================================================--
--  ROUBO
--==================================================================--
local function escolherMelhorOvo()
    local lista = atualizarSnapshot(false)
    local minIdx = RAR_IDX[cfg.raridadeMin] or 3
    local hrp = pegarHRP()
    local melhor, melhorScore = nil, -1
    for _, rec in ipairs(lista) do
        local rar = rec.Rarity
        if not rar then
            local modelo = modeloDoOvo(rec.Uid)
            rar = modelo and raridadeDoModelo(modelo) or "Common"
        end
        local idx = RAR_IDX[rar] or 1
        if idx >= minIdx then
            local pos = posicaoDoOvo(rec)
            if pos then
                local dist = hrp and (hrp.Position - pos).Magnitude or 500
                local score = idx * 10000 - dist
                if score > melhorScore then
                    melhorScore = score
                    melhor = { Uid = rec.Uid, Rarity = rar, Pos = pos }
                end
            end
        end
    end
    return melhor
end

local function tentarPegar(uid)
    local r = rfCarry()
    if not r then return false end
    chamarRF(r, { Uid = uid })
    chamarRF(r, uid)
    -- aperta prompts de pegar perto do ovo (plano B)
    pcall(function()
        local modelo = modeloDoOvo(uid)
        if modelo then
            for _, d in ipairs(modelo:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    fireproximityprompt(d)
                end
            end
        end
    end)
    return true
end

local function guardarOvoNaBase(uid)
    -- coloca o ovo num slot da base via remote oficial
    local plot, pen = acharPlot()
    if not plot then return end
    local rp = rfPlace()
    if not rp then return end
    local baseCF = nil
    if pen and pen:IsA("BasePart") then
        baseCF = pen.CFrame
    else
        local p = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart", true)
        if p then baseCF = p.CFrame end
    end
    if not baseCF then return end
    local offset = CFrame.new(math.random(-6, 6), 2, math.random(-6, 6))
    chamarRF(rp, { Uid = uid, LocalCFrame = baseCF:ToObjectSpace(baseCF * offset) })
end

local function roubarUmaVez()
    if farmOcupado then return false end
    farmOcupado = true
    local ok, erro = pcall(function()
        atualizarSnapshot(true)
        local alvo = escolherMelhorOvo()
        if not alvo then
            statusAtual = "Nenhum ovo com essa raridade"
            task.wait(2)
            return
        end
        statusAtual = "Indo ao ovo " .. alvo.Rarity
        if not irPara(alvo.Pos, 65) then
            statusAtual = "Nao cheguei no ovo"
            return
        end
        statusAtual = "Pegando " .. alvo.Rarity .. "..."
        local pegou = false
        for _ = 1, 12 do
            tentarPegar(alvo.Uid)
            task.wait(0.25)
            local _, uidMao = ovoNaMao()
            if uidMao then pegou = true break end
        end
        if not pegou then
            statusAtual = "Falha ao pegar (guarda?)"
            task.wait(1)
            return
        end
        stats.roubados = stats.roubados + 1
        statusAtual = "Voltando pra base..."
        local base = posicaoBase()
        if base then irPara(base, 65) end
        local _, uidMao = ovoNaMao()
        if uidMao then
            guardarOvoNaBase(uidMao)
        end
        statusAtual = "Ovo entregue!"
        task.wait(0.5)
    end)
    farmOcupado = false
    cancelarTween()
    if not ok then
        statusAtual = "Erro: " .. tostring(erro):sub(1, 40)
    end
    return ok
end

task.spawn(function()
    while true do
        local ok, erro = pcall(function()
            if cfg.autoRoubar and not farmOcupado then
                roubarUmaVez()
            end
        end)
        if not ok then farmOcupado = false end
        task.wait(0.5)
    end
end)

--==================================================================--
--  AUTO CHOCAR
--==================================================================--
task.spawn(function()
    while true do
        pcall(function()
            if cfg.autoChocar then
                local rh, rf2 = rfHatch(), rfFinish()
                if rh and rf2 then
                    local uids = {}
                    -- ovos colocados na base (live snapshot)
                    local ok, ret = pcall(function()
                        local rl = rfLive()
                        return rl and rl:InvokeServer()
                    end)
                    if ok and type(ret) == "table" then
                        for chave, rec in pairs(ret.Records or ret) do
                            if type(rec) == "table" then
                                local uid = rec.Uid or (type(chave) == "string" and chave)
                                if uid then table.insert(uids, uid) end
                            end
                        end
                    end
                    -- ovos na mochila tambem tentam chocar
                    for _, uid in ipairs(ovosNaMochila()) do
                        table.insert(uids, uid)
                    end
                    for _, uid in ipairs(uids) do
                        if not cfg.autoChocar then break end
                        local okH = chamarRF(rh, uid)
                        if okH then
                            task.wait(0.9)
                            local okF, retF = chamarRF(rf2, uid)
                            if okF and retF ~= false then
                                stats.chocados = stats.chocados + 1
                                statusAtual = "Chocou um ovo!"
                            end
                        end
                        task.wait(0.1)
                    end
                end
            end
        end)
        task.wait(2)
    end
end)

--==================================================================--
--  AUTO COLOCAR (ovos da mochila -> base)
--==================================================================--
task.spawn(function()
    while true do
        pcall(function()
            if cfg.autoColocar then
                for _, uid in ipairs(ovosNaMochila()) do
                    if not cfg.autoColocar then break end
                    guardarOvoNaBase(uid)
                    task.wait(0.2)
                end
            end
        end)
        task.wait(1.5)
    end
end)

--==================================================================--
--  AUTO ESTEIRA (upgrada velocidade do personagem no jogo)
--==================================================================--
task.spawn(function()
    local montou = false
    while true do
        pcall(function()
            if cfg.autoEsteira then
                if not montou then
                    local rd = rfDon()
                    if rd then chamarRF(rd) end
                    montou = true
                end
                local rw = rfWearStill()
                if rw then chamarRF(rw, true) end
                local rt = rfTierUp()
                if rt then chamarRF(rt) end
            else
                montou = false
            end
        end)
        task.wait(1.5)
    end
end)

--==================================================================--
--  ESP DE OVOS
--==================================================================--
local espMapa = {} -- modelo -> {hl, bb}

local function limparESP()
    for modelo, objs in pairs(espMapa) do
        pcall(function() objs.hl:Destroy() end)
        pcall(function() objs.bb:Destroy() end)
        espMapa[modelo] = nil
    end
end

local function criarESP(modelo, raridade)
    local parte = modelo.PrimaryPart or modelo:FindFirstChildWhichIsA("BasePart")
    if not parte then return end
    local cor = RAR_COR[raridade] or RAR_COR.Common

    local hl = Instance.new("Highlight")
    hl.FillColor = cor
    hl.OutlineColor = cor
    hl.FillTransparency = 0.65
    hl.OutlineTransparency = 0.1
    hl.Adornee = modelo
    hl.Parent = modelo

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 120, 0, 30)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = parte

    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.BackgroundTransparency = 1
    txt.Text = raridade
    txt.TextColor3 = cor
    txt.TextStrokeTransparency = 0.3
    txt.Font = Enum.Font.GothamBold
    txt.TextSize = 13
    txt.Parent = bb

    bb.Parent = modelo
    espMapa[modelo] = { hl = hl, bb = bb }
end

task.spawn(function()
    while true do
        pcall(function()
            if cfg.espOvos then
                local pasta = Workspace:FindFirstChild("AreaEggSlotsClient")
                if pasta then
                    local minIdx = cfg.espSoRaros and (RAR_IDX["Rare"] or 3) or 1
                    for _, modelo in ipairs(pasta:GetChildren()) do
                        if modelo:IsA("Model") and not espMapa[modelo] then
                            local rar = raridadeDoModelo(modelo)
                            if rar and (RAR_IDX[rar] or 1) >= minIdx then
                                criarESP(modelo, rar)
                            end
                        end
                    end
                end
                -- remove ESP de modelos que sumiram
                for modelo in pairs(espMapa) do
                    if not modelo.Parent then
                        pcall(function() espMapa[modelo].hl:Destroy() end)
                        pcall(function() espMapa[modelo].bb:Destroy() end)
                        espMapa[modelo] = nil
                    end
                end
            else
                limparESP()
            end
        end)
        task.wait(2)
    end
end)

--==================================================================--
--  MOVIMENTO DO PERSONAGEM
--==================================================================--
RunService.Heartbeat:Connect(function()
    pcall(function()
        local hum = pegarHum()
        if hum then
            if cfg.velocidade ~= 16 then hum.WalkSpeed = cfg.velocidade end
            if cfg.pulo ~= 50 then hum.JumpPower = cfg.pulo end
        end
    end)
end)

RunService.Stepped:Connect(function()
    pcall(function()
        if cfg.noclip or farmOcupado then
            local c = LP.Character
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end
    end)
end)

game:GetService("UserInputService").JumpRequest:Connect(function()
    pcall(function()
        if cfg.puloInfinito then
            local hum = pegarHum()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)
end)

--==================================================================--
--  ANTI-AFK / ANTI-LAG
--==================================================================--
LP.Idled:Connect(function()
    pcall(function()
        if cfg.antiAfk then
            local VU = game:GetService("VirtualUser")
            VU:CaptureController()
            VU:ClickButton2(Vector2.new())
        end
    end)
end)

local function antiLag()
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") then
                d.Enabled = false
            elseif d:IsA("PostEffect") then
                d.Enabled = false
            end
        end
        local terra = Workspace:FindFirstChildOfClass("Terrain")
        if terra then
            terra.Decoration = false
        end
    end)
    aviso("Anti-lag aplicado")
end

--==================================================================--
--  GUI — simples, leve, nome aleatorio
--==================================================================--
local function paiGUI()
    local ok, hui = pcall(function() return gethui() end)
    if ok and hui then return hui end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then return cg end
    return LP:WaitForChild("PlayerGui")
end

-- se ja existe uma GUI nossa de uma execucao anterior, apaga ela
pcall(function()
    for _, g in ipairs(paiGUI():GetChildren()) do
        if g:IsA("ScreenGui") and g:GetAttribute("KoalaOvo") then
            g:Destroy()
        end
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

local COR = {
    fundo   = Color3.fromRGB(16, 16, 22),
    painel  = Color3.fromRGB(24, 24, 34),
    destaque= Color3.fromRGB(130, 95, 230),
    ligado  = Color3.fromRGB(60, 200, 110),
    desligado = Color3.fromRGB(70, 70, 90),
    texto   = Color3.fromRGB(235, 235, 240),
    subtexto= Color3.fromRGB(150, 150, 170),
}

-- botao flutuante (abre/fecha)
local BotaoK = Instance.new("TextButton")
BotaoK.Size = UDim2.new(0, 46, 0, 46)
BotaoK.Position = UDim2.new(0, 12, 0, 100)
BotaoK.BackgroundColor3 = COR.destaque
BotaoK.Text = "K"
BotaoK.TextColor3 = Color3.new(1, 1, 1)
BotaoK.Font = Enum.Font.GothamBold
BotaoK.TextSize = 22
BotaoK.ZIndex = 60
BotaoK.Parent = Gui
Instance.new("UICorner", BotaoK).CornerRadius = UDim.new(1, 0)

-- janela principal
local Janela = Instance.new("Frame")
Janela.Size = UDim2.new(0, 320, 0, 440)
Janela.Position = UDim2.new(0.5, -160, 0.5, -220)
Janela.BackgroundColor3 = COR.fundo
Janela.BorderSizePixel = 0
Janela.Parent = Gui
Instance.new("UICorner", Janela).CornerRadius = UDim.new(0, 14)

local Titulo = Instance.new("TextLabel")
Titulo.Size = UDim2.new(1, 0, 0, 40)
Titulo.BackgroundColor3 = COR.destaque
Titulo.Text = "  Koala Ovo  v1"
Titulo.TextColor3 = Color3.new(1, 1, 1)
Titulo.Font = Enum.Font.GothamBold
Titulo.TextSize = 16
Titulo.TextXAlignment = Enum.TextXAlignment.Left
Titulo.Parent = Janela
Instance.new("UICorner", Titulo).CornerRadius = UDim.new(0, 14)

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 24)
Status.Position = UDim2.new(0, 10, 0, 44)
Status.BackgroundTransparency = 1
Status.Text = "..."
Status.TextColor3 = COR.subtexto
Status.Font = Enum.Font.Gotham
Status.TextSize = 12
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextTruncate = Enum.TextTruncate.AtEnd
Status.Parent = Janela

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -16, 1, -76)
Scroll.Position = UDim2.new(0, 8, 0, 70)
Scroll.BackgroundTransparency = 1
Scroll.ScrollBarThickness = 4
Scroll.ScrollBarImageColor3 = COR.destaque
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.Parent = Janela

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 6)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent = Scroll

Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scroll.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y + 12)
end)

-- arrastar (funciona em toque e mouse)
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
            alvo.Position = UDim2.new(posInicio.X.Scale, posInicio.X.Offset + delta.X, posInicio.Y.Scale, posInicio.Y.Offset + delta.Y)
        end
    end)
end
arrastavel(Janela, Titulo)
arrastavel(BotaoK, BotaoK)

BotaoK.MouseButton1Click:Connect(function()
    Janela.Visible = not Janela.Visible
end)

-- fabrica de controles
local function secao(texto)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 22)
    l.BackgroundTransparency = 1
    l.Text = texto
    l.TextColor3 = COR.destaque
    l.Font = Enum.Font.GothamBold
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = Scroll
    return l
end

local function toggle(texto, inicial, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 36)
    b.BackgroundColor3 = inicial and COR.ligado or COR.desligado
    b.Text = texto .. (inicial and ": LIGADO" or ": desligado")
    b.TextColor3 = COR.texto
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Parent = Scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local estado = inicial
    b.MouseButton1Click:Connect(function()
        estado = not estado
        b.BackgroundColor3 = estado and COR.ligado or COR.desligado
        b.Text = texto .. (estado and ": LIGADO" or ": desligado")
        callback(estado)
    end)
    callback(inicial)
    return b
end

local function botao(texto, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 36)
    b.BackgroundColor3 = COR.painel
    b.Text = texto
    b.TextColor3 = COR.texto
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Parent = Scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    b.MouseButton1Click:Connect(function() pcall(callback) end)
    return b
end

local function seletor(texto, opcoes, inicial, callback)
    local idx = inicial
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 36)
    b.BackgroundColor3 = COR.painel
    b.TextColor3 = COR.texto
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Text = texto .. ": " .. tostring(opcoes[idx])
    b.Parent = Scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    b.MouseButton1Click:Connect(function()
        idx = idx + 1
        if idx > #opcoes then idx = 1 end
        b.Text = texto .. ": " .. tostring(opcoes[idx])
        callback(opcoes[idx])
    end)
    callback(opcoes[idx])
    return b
end

local function contador(texto, minimo, maximo, passo, inicial, callback)
    local valor = inicial
    local quadro = Instance.new("Frame")
    quadro.Size = UDim2.new(1, 0, 0, 36)
    quadro.BackgroundColor3 = COR.painel
    quadro.Parent = Scroll
    Instance.new("UICorner", quadro).CornerRadius = UDim.new(0, 8)

    local rot = Instance.new("TextLabel")
    rot.Size = UDim2.new(1, -90, 1, 0)
    rot.Position = UDim2.new(0, 10, 0, 0)
    rot.BackgroundTransparency = 1
    rot.TextColor3 = COR.texto
    rot.Font = Enum.Font.GothamBold
    rot.TextSize = 13
    rot.TextXAlignment = Enum.TextXAlignment.Left
    rot.Text = texto .. ": " .. tostring(valor)
    rot.Parent = quadro

    local function mkBtn(txt, xoff, delta)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 36, 0, 26)
        b.Position = UDim2.new(1, xoff, 0.5, -13)
        b.BackgroundColor3 = COR.destaque
        b.Text = txt
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 16
        b.Parent = quadro
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(function()
            valor = math.clamp(valor + delta, minimo, maximo)
            if passo < 1 then valor = math.floor(valor * 10 + 0.5) / 10 end
            rot.Text = texto .. ": " .. tostring(valor)
            callback(valor)
        end)
    end
    mkBtn("-", -80, -passo)
    mkBtn("+", -40, passo)
    callback(inicial)
    return quadro
end

--==================================================================--
--  MONTAR GUI
--==================================================================--
secao("FARM")
toggle("Auto Roubar", false, function(v) cfg.autoRoubar = v if not v then cancelarTween() farmOcupado = false end end)
seletor("Raridade minima", RARIDADES, 3, function(v) cfg.raridadeMin = v end)
botao("Roubar melhor ovo AGORA", function()
    task.spawn(roubarUmaVez)
end)
toggle("Auto Chocar", false, function(v) cfg.autoChocar = v end)
toggle("Auto Colocar ovos na base", false, function(v) cfg.autoColocar = v end)
toggle("Auto Esteira (upgrade vel.)", false, function(v) cfg.autoEsteira = v end)

secao("ESP")
toggle("ESP de ovos", false, function(v) cfg.espOvos = v end)
toggle("ESP so Rare+", false, function(v) cfg.espSoRaros = v end)

secao("MOVIMENTO")
contador("Velocidade", 16, 250, 8, 16, function(v) cfg.velocidade = v end)
contador("Forca do pulo", 50, 250, 10, 50, function(v) cfg.pulo = v end)
toggle("Pulo infinito", false, function(v) cfg.puloInfinito = v end)
toggle("Atravessar paredes", false, function(v) cfg.noclip = v end)

secao("TELEPORTE")
botao("Ir pra minha base", function()
    local base = posicaoBase()
    if base then
        statusAtual = "Indo pra base..."
        task.spawn(function() irPara(base, 65) end)
    else
        aviso("Base nao encontrada")
    end
end)
seletor("Zona", ZONAS, 1, function(v) cfg.zonaAlvo = v end)
botao("Ir pra zona selecionada", function()
    task.spawn(function()
        local lista = atualizarSnapshot(true)
        local alvo = cfg.zonaAlvo:gsub(" ", ""):lower()
        for _, rec in ipairs(lista) do
            local area = tostring(rec.Area or rec.Zone or ""):gsub(" ", ""):lower()
            if area == alvo then
                local pos = posicaoDoOvo(rec)
                if pos then
                    statusAtual = "Indo pra " .. cfg.zonaAlvo .. "..."
                    irPara(pos, 65)
                    return
                end
            end
        end
        aviso("Zona sem ovos no momento")
    end)
end)

secao("OUTROS")
toggle("Anti-AFK", true, function(v) cfg.antiAfk = v end)
botao("Anti-lag (aplicar uma vez)", antiLag)
botao("Fechar script", function()
    cfg.autoRoubar = false cfg.autoChocar = false cfg.autoColocar = false
    cfg.autoEsteira = false cfg.espOvos = false cfg.noclip = false
    cancelarTween()
    limparESP()
    task.wait(0.3)
    Gui:Destroy()
end)

-- status ao vivo
task.spawn(function()
    while Gui.Parent do
        pcall(function()
            local ovos = #ovosCache
            Status.Text = string.format("%s  |  roubados: %d  chocados: %d  ovos vistos: %d",
                statusAtual, stats.roubados, stats.chocados, ovos)
        end)
        task.wait(0.5)
    end
end)

--==================================================================--
--  FIM
--==================================================================--
if game.PlaceId ~= 107778070777162 then
    aviso("Aviso: esse script foi feito pro Roube um Ovo (PlaceId diferente aqui)", 5)
end
atualizarSnapshot(true)
aviso("Koala Ovo carregado! Toque no botao K.", 4)
