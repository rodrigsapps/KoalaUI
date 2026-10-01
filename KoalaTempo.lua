--[[
  KoalaTempo.lua — v1
  Script para Pare o Temporizador (PlaceId 139988436996662)
  Parte do Koala Hub — discord.gg/ZRFffEgQQM

  Como funciona (baseado no código decompilado do jogo):
    * O servidor manda no evento PlayerTurn:
        args[1] = jogador da vez
        args[2] = tempoServidorInicio + alvo   <- o instante PERFEITO
        args[3] = alvo em segundos
        args[4] = multiplicador de velocidade (modo Hard)
        args[5] = token/id da rodada
        args[8] = tabela de alvos (modo contínuo) ou nil
        args[9] = tolerância (modo contínuo)
    * O clique legítimo envia:
        PlayerResponse:Fire(TimeCodec.encode(agora, args[5], args[2]))
      -> o timestamp vai DENTRO do payload. O script agenda o disparo
         pro instante exato e codifica o timestamp perfeito.
    * Modo contínuo: alvo i = args[2] - args[3] + args[8][i].

  ATENÇÃO: uso por sua conta e risco.
]]

--============================================================================--
-- 0) Polyfills de executor (a UI depende disso)
--============================================================================--
local genv = (typeof(getgenv) == "function") and getgenv() or _G
local function def(nome, fn)
  local ok, atual = pcall(function() return genv[nome] end)
  if not ok or typeof(atual) ~= "function" then
    pcall(function() genv[nome] = fn end)
  end
end
def("identifyexecutor", function() return "Arceus X", "2.3.5" end)
def("getexecutorname", function() return "Arceus X" end)
def("cloneref", function(o) return o end)
def("clonereference", function(o) return o end)
def("gethui", function() return game:GetService("CoreGui") end)
def("getcustomasset", function(p) return p end)
def("setclipboard", function() end)
def("makefolder", function() end)
def("delfolder", function() end)
def("isfolder", function() return true end)
def("writefile", function() end)
def("appendfile", function() end)
def("readfile", function() return "" end)
def("isfile", function() return true end)
def("listfiles", function() return {} end)
def("delfile", function() end)
def("queue_on_teleport", function() end)
def("setfpscap", function() end)
local function reqFallback(t)
  local corpo = game:HttpGet(t.Url or t.url)
  return { Body = corpo, StatusCode = 200, Success = true }
end
def("request", reqFallback)
def("http_request", reqFallback)

--============================================================================--
-- 1) Serviços e helpers
--============================================================================--
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local VU         = game:GetService("VirtualUser")
local LP         = Players.LocalPlayer

local function aviso(txt, dur)
  print("[KoalaTempo] " .. tostring(txt))
  pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification",
      { Title = "Koala Pare o Tempo", Text = tostring(txt), Duration = dur or 4 })
  end)
end

if game.PlaceId ~= 139988436996662 then
  aviso("Esse script é pro Pare o Temporizador (PlaceId diferente aqui)", 6)
end

-- anti-AFK
LP.Idled:Connect(function()
  pcall(function()
    VU:CaptureController()
    VU:ClickButton2(Vector2.new())
  end)
end)

--============================================================================--
-- 2) Módulos e bridges do jogo
--============================================================================--
local BN, TimeCodec
do
  local ok1, r1 = pcall(function()
    return require(RS:WaitForChild("Packages", 10):WaitForChild("BridgeNet2", 10))
  end)
  if ok1 then BN = r1 end
  local ok2, r2 = pcall(function()
    return require(RS:WaitForChild("Shared", 10):WaitForChild("TimeCodec", 10))
  end)
  if ok2 then TimeCodec = r2 end
end

if not BN then
  aviso("BridgeNet2 não carregou — script abortado.", 8)
  return
end
if not TimeCodec then
  aviso("TimeCodec não carregou — script abortado.", 8)
  return
end

local function bridge(nome)
  local ok, b = pcall(BN.ReferenceBridge, nome)
  if ok then return b end
  return nil
end

local B = {
  PlayerTurn      = bridge("PlayerTurn"),
  PlayerResponse  = bridge("PlayerResponse"),
  SubmitTimer     = bridge("SubmitChosenTimer"),
  PromptChoose    = bridge("PromptChooseTimer"),
  GameStarted     = bridge("GameStarted"),
  GameStopped     = bridge("GameStopped"),
}

if not (B.PlayerTurn and B.PlayerResponse) then
  aviso("Bridges principais não achadas — script abortado.", 8)
  return
end

--============================================================================--
-- 3) Estado
--============================================================================--
local F = {
  AutoParar    = true,
  AutoEscolher = false,
  TempoEscolha = 10.0,   -- segundos pra escolher pro oponente
  CompMs       = 0,      -- compensação fixa em ms
  CompPing     = false,  -- soma o ping real na compensação
}

local geracao = 0        -- invalida disparos agendados de turnos antigos
local ultimoTurno = "nenhum"
local acertos = 0
local disparosFeitos = 0

local function compensacao()
  local c = F.CompMs / 1000
  if F.CompPing then
    local ok, p = pcall(function() return LP:GetNetworkPing() end)
    if ok and type(p) == "number" then
      c = c + p
    end
  end
  return c
end

-- agenda um disparo perfeito: espera até (quando - comp) e manda o timestamp exato
local function agendarDisparo(quando, arg5, arg2, rotulo)
  geracao = geracao + 0  -- só pra deixar claro que usa a geração atual
  local minhaGer = geracao
  task.spawn(function()
    local alvoLocal = quando - compensacao()
    while Workspace:GetServerTimeNow() < alvoLocal do
      if minhaGer ~= geracao or not F.AutoParar then return end
      RunService.Heartbeat:Wait()
    end
    if minhaGer ~= geracao or not F.AutoParar then return end
    local payload = TimeCodec.encode(quando, arg5, arg2)
    local ok, err = pcall(function()
      B.PlayerResponse:Fire(payload)
    end)
    if ok then
      disparosFeitos = disparosFeitos + 1
      acertos = acertos + 1
      aviso("PARADO no tempo exato! (" .. tostring(rotulo) .. ")", 3)
    else
      aviso("Erro ao disparar: " .. tostring(err):sub(1, 60), 5)
    end
  end)
end

--============================================================================--
-- 4) Escuta dos eventos do jogo
--============================================================================--
pcall(function()
  B.PlayerTurn:Connect(function(args)
    if type(args) ~= "table" then return end
    local vezDe   = args[1]
    local a2      = tonumber(args[2])  -- início + alvo (instante perfeito, modo simples)
    local a3      = tonumber(args[3])  -- alvo em segundos
    local a5      = args[5]            -- token da rodada
    local alvos   = args[8]            -- tabela (modo contínuo) ou nil
    if not (a2 and a3 and a5) then return end

    -- novo turno: cancela tudo que estava agendado
    geracao = geracao + 1

    if vezDe ~= LP then
      ultimoTurno = "vez do oponente"
      return
    end

    if type(alvos) == "table" then
      -- modo contínuo: vários alvos
      local base = a2 - a3
      ultimoTurno = string.format("contínuo: %d alvos", #alvos)
      if not F.AutoParar then return end
      for i, t in ipairs(alvos) do
        local perfeito = base + tonumber(t)
        agendarDisparo(perfeito, a5, a2, "alvo " .. i .. "/" .. #alvos)
      end
      aviso(string.format("Seu turno! %d alvos agendados nos tempos exatos.", #alvos), 4)
    else
      -- modo simples: instante perfeito = args[2]
      ultimoTurno = string.format("alvo: %.2fs", a3)
      if not F.AutoParar then return end
      agendarDisparo(a2, a5, a2, string.format("%.2fs", a3))
      aviso(string.format("Seu turno! Vou parar EXATAMENTE em %.2fs.", a3), 4)
    end
  end)
end)

pcall(function()
  B.GameStopped:Connect(function()
    geracao = geracao + 1
    ultimoTurno = "partida encerrada"
  end)
end)

pcall(function()
  B.PromptChoose:Connect(function(args)
    if not F.AutoEscolher then return end
    if type(args) ~= "table" then return end
    local escolhedor = args[3]
    if escolhedor ~= LP then return end
    task.delay(0.6, function()
      local v = math.round(F.TempoEscolha * 100) / 100
      v = math.clamp(v, 1, 50)
      pcall(function() B.SubmitTimer:Fire(v) end)
      aviso(string.format("Tempo %.2fs escolhido automaticamente.", v), 3)
    end)
  end)
end)

--============================================================================--
-- 5) UI (WindUI)
--============================================================================--
local URLS_UI = {
  "https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/KoalaUI_v3.lua",
  "https://cdn.jsdelivr.net/gh/rodrigsapps/KoalaUI@main/KoalaUI_v3.lua",
  "https://raw.githack.com/rodrigsapps/KoalaUI/main/KoalaUI_v3.lua",
}
local Koala, errUI
for tentativa = 1, 3 do
  for _, url in ipairs(URLS_UI) do
    local ok, res = pcall(function()
      local src = game:HttpGet(url)
      assert(type(src) == "string" and #src > 50000, "download inválido")
      local fn, cerr = loadstring(src)
      assert(fn, "loadstring: " .. tostring(cerr))
      return fn()
    end)
    if ok and res then Koala = res break end
    errUI = res
    task.wait(1)
  end
  if Koala then break end
end
if not Koala then
  aviso("Falha na UI: " .. tostring(errUI), 10)
  return
end

local okWin, Window = pcall(function()
  return Koala:CreateWindow({
    Title = "Koala Pare o Tempo v1",
    Icon = "timer",
    Author = "discord.gg/ZRFffEgQQM",
    Folder = "KoalaTempo",
    Size = UDim2.fromOffset(580, 440),
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightControl,
  })
end)
if not okWin or not Window then
  aviso("Erro ao criar janela: " .. tostring(Window), 10)
  return
end

-----------------------------------------------------------
-- Aba Principal
-----------------------------------------------------------
local TabMain = Window:Tab({ Title = "Auto", Icon = "timer" })

TabMain:Section({ Title = "★ Parada perfeita" })
TabMain:Toggle({
  Title = "AUTO PARAR no tempo exato",
  Desc = "Quando for sua vez, para o temporizador no instante perfeito sozinho (funciona no modo simples e no contínuo).",
  Value = true,
  Callback = function(v)
    F.AutoParar = v
    if not v then geracao = geracao + 1 end
  end,
})

TabMain:Section({ Title = "Compensação de rede" })
TabMain:Toggle({
  Title = "Compensar ping automaticamente",
  Desc = "Dispara um pouco antes, descontando seu ping real. Deixe DESLIGADO primeiro — o timestamp vai dentro do pacote, então geralmente não precisa.",
  Value = false,
  Callback = function(v) F.CompPing = v end,
})
TabMain:Slider({
  Title = "Compensação extra (ms)",
  Desc = "Adianta o disparo em milissegundos. Só mexa se estiver parando atrasado.",
  Value = { Min = 0, Max = 300, Default = 0 },
  Callback = function(v) F.CompMs = tonumber(v) or 0 end,
})

TabMain:Section({ Title = "Escolha de tempo (vez de escolher)" })
TabMain:Toggle({
  Title = "Auto escolher tempo pro oponente",
  Desc = "Quando couber a você escolher, envia o valor abaixo automaticamente.",
  Value = false,
  Callback = function(v) F.AutoEscolher = v end,
})
TabMain:Slider({
  Title = "Tempo escolhido (s)",
  Value = { Min = 1, Max = 50, Default = 10 },
  Callback = function(v) F.TempoEscolha = tonumber(v) or 10 end,
})

-----------------------------------------------------------
-- Aba Status
-----------------------------------------------------------
local TabStatus = Window:Tab({ Title = "Status", Icon = "activity" })

local pTurno    = TabStatus:Paragraph({ Title = "Último turno", Desc = "..." })
local pDisparos = TabStatus:Paragraph({ Title = "Paradas perfeitas", Desc = "..." })
local pPing     = TabStatus:Paragraph({ Title = "Ping", Desc = "..." })
local pRelogio  = TabStatus:Paragraph({ Title = "Relógio do servidor", Desc = "..." })

task.spawn(function()
  while Window do
    pcall(function()
      pTurno:SetDesc(ultimoTurno)
      pDisparos:SetDesc(string.format("%d disparos perfeitos enviados", disparosFeitos))
      local ok, p = pcall(function() return LP:GetNetworkPing() end)
      if ok and type(p) == "number" then
        pPing:SetDesc(string.format("%d ms", math.floor(p * 1000 + 0.5)))
      else
        pPing:SetDesc("?")
      end
      pRelogio:SetDesc(string.format("%.2f", Workspace:GetServerTimeNow()))
    end)
    task.wait(1)
  end
end)

aviso("Koala Pare o Tempo v1 carregado! Entra numa estação que o resto é automático.", 6)
