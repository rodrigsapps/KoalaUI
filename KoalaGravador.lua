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
