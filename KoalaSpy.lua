--[[
    KOALA HUB — MODULO SPY / DUMP DE REMOTES
    -----------------------------------------
    1) Ao carregar: varre o jogo inteiro e manda para o webhook do Discord
       uma lista com TODOS os RemoteEvent / RemoteFunction / BindableEvent /
       BindableFunction encontrados (caminho completo + classe).
    2) Fica ouvindo (spy): toda chamada FireServer / InvokeServer feita
       pelo jogo e capturada e enviada pro webhook com nome, caminho e
       argumentos serializados.
    3) Se a aba "Spy" existir no Koala Hub, aparecem toggles para ligar/
       desligar o spy e o dump inicial. Se a UI nao abrir, o modulo
       continua funcionando em segundo plano (spy ligado por padrao).

    Uso standalone (dentro do jogo, com executor):
        loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaSpy.lua"))()

    Integracao no KoalaHub.lua (opcional, adiciona a aba Spy):
        pcall(function()
            local Spy = loadstring(game:HttpGet("https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaSpy.lua"))()
            Spy(Koala, Window, Flags)
        end)

    ATENCAO: o webhook fica visivel no codigo. Quem tiver acesso ao script
    pode postar no seu canal. Se isso for problema, gere um webhook novo
    e troque a constante WEBHOOK_URL abaixo.

    Executores: precisa de getnamecallmethod + hookmetamethod (ou
    hookfunction) para o spy. Sem eles, so o dump inicial funciona.
    HttpPost/request sao detectados automaticamente; na ultima opcao
    usa HttpService:PostAsync.
]]

return function(Koala, Window, Flags)

local Players    = game:GetService("Players")
local HttpService= game:GetService("HttpService")

local LP = Players.LocalPlayer

--==================================================================--
--  CONFIG
--==================================================================--
local WEBHOOK_URL = "https://discord.com/api/webhooks/1546164688994177112/FVxL0qlwRYpI6ITaoTbK0qqchk2cxCrxB_r_5DDDV_HGEAzmYB5lDBwCyqtLI2GYiZ52"
local INTERVALO_FILA   = 5      -- segundos entre envios em lote
local MAX_MSG          = 1800   -- limite seguro por mensagem (Discord: 2000)
local MAX_FILA         = 400    -- descarta o mais antigo alem disso
local MAX_ARG_STR      = 300    -- corta strings gigantes nos argumentos
local MAX_PROFUND      = 4      -- profundidade max. ao serializar tabelas

--==================================================================--
--  FLAGS PADRAO
--==================================================================--
Flags = Flags or {}
if Flags.SpyAtivo  == nil then Flags.SpyAtivo  = true end
if Flags.DumpInicio == nil then Flags.DumpInicio = true end

--==================================================================--
--  HELPERS
--==================================================================--
local function notify(msg, dur)
    pcall(function()
        if Koala and Koala.Notify then
            Koala:Notify({ Title = "Koala Spy", Content = msg, Duration = dur or 3 })
        end
    end)
end

local function env(nome)
    local ok, f = pcall(function() return getfenv()[nome] end)
    if ok then return f end
    return nil
end

-- funcao de HTTP request do executor (synapse/sirhurt/fluxus/etc)
local httpRequest = env("request") or env("http_request")
    or (syn and syn.request) or (http and http.request)
    or (fluxus and fluxus.request)

local function postWebhook(content)
    if not content or #content == 0 then return false end
    if #content > 1990 then content = content:sub(1, 1990) end

    local body = HttpService:JSONEncode({ content = content })

    -- 1) request do executor (permite header customizado)
    if httpRequest then
        local ok, res = pcall(function()
            return httpRequest({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        if ok and res and (res.StatusCode == 200 or res.StatusCode == 204) then
            return true
        end
    end

    -- 2) HttpService:PostAsync (funciona se o jogo permitir HttpEnabled)
    local ok2 = pcall(function()
        HttpService:PostAsync(WEBHOOK_URL, body, Enum.HttpContentType.ApplicationJson)
    end)
    return ok2
end

-- fila de mensagens -> envio em lote (evita rate limit do Discord)
local fila = {}
local enviando = false

local function enfileirar(texto)
    if #fila >= MAX_FILA then table.remove(fila, 1) end
    table.insert(fila, texto)
end

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
                    table.insert(fila, 1, parte) -- devolve pro proximo lote
                    break
                end
                table.insert(lote, parte)
            end
            if #lote > 0 then
                postWebhook(table.concat(lote, "\n"))
            end
            enviando = false
        end
    end
end)

--==================================================================--
--  SERIALIZACAO DE VALORES (para logar argumentos)
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
    elseif t == "BrickColor" then
        return "BrickColor(" .. tostring(v) .. ")"
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "UDim2" then
        return "UDim2(" .. tostring(v) .. ")"
    elseif t == "table" then
        if prof >= MAX_PROFUND then return "{...}" end
        local partes = {}
        local n = 0
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
--  1) DUMP INICIAL — todos os remotes do jogo
--==================================================================--
local CLASSES_REMOTE = {
    RemoteEvent = true, RemoteFunction = true,
    BindableEvent = true, BindableFunction = true,
}

local function dumpRemotes()
    local linhas = {}
    for _, inst in ipairs(game:GetDescendants()) do
        if CLASSES_REMOTE[inst.ClassName] then
            table.insert(linhas, string.format("[%s] %s", inst.ClassName, caminhoDe(inst)))
        end
    end
    table.sort(linhas)

    local nomeJogo = "?"
    pcall(function()
        nomeJogo = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    end)
    enfileirar(string.format("**[Koala Spy] DUMP de remotes — %s em %s — %d encontrados**",
        LP and LP.Name or "?", nomeJogo, #linhas))
    for _, l in ipairs(linhas) do
        enfileirar(l)
    end
    return #linhas
end

--==================================================================--
--  2) SPY — escuta FireServer / InvokeServer em tempo real
--==================================================================--
local spyLigado = false
local getnamecallmethod = env("getnamecallmethod")
local hookmetamethod    = env("hookmetamethod")
local hookfunction      = env("hookfunction")
local newcclosure       = env("newcclosure") or function(f) return f end

local function ehRemoteValido(self)
    return typeof(self) == "Instance"
        and (self.ClassName == "RemoteEvent" or self.ClassName == "RemoteFunction")
end

local function logarChamada(self, metodo, args)
    if not Flags.SpyAtivo then return end
    if not ehRemoteValido(self) then return end
    local nome = self.Name
    local caminho = caminhoDe(self)
    local argStr = serializarArgs(args)
    enfileirar(string.format("[SPY] %s :%s( %s )\n      -> %s", nome, metodo, argStr, caminho))
end

local function ligarSpy()
    if spyLigado then return true end

    -- metodo 1: hookmetamethod (__namecall) — o mais comum nos executores
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

    -- metodo 2: hookfunction nos metodos das classes (fallback)
    if hookfunction then
        local re = Instance.new("RemoteEvent")
        local rf = Instance.new("RemoteFunction")
        local okFire = pcall(function()
            local velho
            velho = hookfunction(re.FireServer, newcclosure(function(self, ...)
                pcall(logarChamada, self, "FireServer", { ... })
                return velho(self, ...)
            end))
        end)
        local okInvoke = pcall(function()
            local velho
            velho = hookfunction(rf.InvokeServer, newcclosure(function(self, ...)
                pcall(logarChamada, self, "InvokeServer", { ... })
                return velho(self, ...)
            end))
        end)
        re:Destroy(); rf:Destroy()
        if okFire or okInvoke then
            spyLigado = true
            return true
        end
    end

    return false
end

--==================================================================--
--  3) ABA NA UI (opcional)
--==================================================================--
if Window then
    local ok, err = pcall(function()
        local SpyTab = Window:Tab({ Title = "Spy", Icon = "radar" })

        SpyTab:Paragraph({
            Title = "Koala Spy",
            Desc = "Dump de remotes + spy ao vivo, tudo enviado pro Discord (webhook configurado no script).",
        })

        SpyTab:Toggle({
            Title = "Spy ao vivo (FireServer/InvokeServer)",
            Value = Flags.SpyAtivo,
            Callback = function(v)
                Flags.SpyAtivo = v
                notify(v and "Spy ligado." or "Spy pausado.", 2)
            end,
        })

        SpyTab:Button({
            Title = "Reenviar DUMP de remotes agora",
            Callback = function()
                task.spawn(function()
                    local n = dumpRemotes()
                    notify("Dump enviado: " .. n .. " remotes.", 3)
                end)
            end,
        })

        SpyTab:Button({
            Title = "Testar webhook",
            Callback = function()
                task.spawn(function()
                    local okEnvio = postWebhook("**[Koala Spy] Teste de webhook OK — " .. (LP and LP.Name or "?") .. "**")
                    notify(okEnvio and "Webhook OK!" or "Falha no envio (verifique request/http).", 3)
                end)
            end,
        })
    end)
    if not ok then
        warn("[KoalaSpy] aba da UI nao criada: " .. tostring(err))
    end
end

--==================================================================--
--  BOOT
--==================================================================--
task.spawn(function()
    task.wait(2) -- deixa o jogo assentar antes de varrer

    local spyOk = ligarSpy()

    if Flags.DumpInicio then
        local n = dumpRemotes()
        notify(string.format("Dump: %d remotes | Spy: %s", n, spyOk and "ON" or "OFF (sem hook)"), 4)
    else
        notify("Spy: " .. (spyOk and "ON" or "OFF (executor sem hookmetamethod/hookfunction)"), 4)
    end
end)

end
