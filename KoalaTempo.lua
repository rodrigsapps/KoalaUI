--[[
  KoalaTempo.lua — v2 (AUTO PLAYER com IA + parada perfeita)
  Script para Pare o Temporizador (PlaceId 139988436996662)
  Parte do Koala Hub — discord.gg/ZRFffEgQQM

  Baseado no código decompilado do jogo:
    * PlayerTurn: args[2] = instante perfeito (início + alvo),
      args[3] = alvo em s, args[5] = token, args[8] = alvos (modo contínuo)
    * Clique legítimo: PlayerResponse:Fire(TimeCodec.encode(t, args[5], args[2]))
      -> timestamp vai DENTRO do pacote: paramos no tempo exato, sem erro
    * Entrar na estação = SENTAR na cadeira (Seat) da estação
    * Sozinho na estação: StartBotMatch:Fire() inicia partida contra IA
    * Sair: RequestLeaveGameStation:Fire()
    * "Outra chance" (paga): DenyAnotherChance:Fire() recusa na hora
    * Vencedor: AnnounceGameWinner args[1] = Player

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
  PlayerTurn       = bridge("PlayerTurn"),
  PlayerResponse   = bridge("PlayerResponse"),
  SubmitTimer      = bridge("SubmitChosenTimer"),
  PromptChoose     = bridge("PromptChooseTimer"),
  GameStarted      = bridge("GameStarted"),
  GameStopped      = bridge("GameStopped"),
  JoinedStation    = bridge("PlayerJoinedStation"),
  LeftStation      = bridge("PlayerLeftStation"),
  StartBotMatch    = bridge("StartBotMatch"),
  RequestLeave     = bridge("RequestLeaveGameStation"),
  AnnounceWinner   = bridge("AnnounceGameWinner"),
  PromptAnother    = bridge("PromptPlayerAnotherChance"),
  DenyAnother      = bridge("DenyAnotherChance"),
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
  AutoFarm     = false,  -- auto player: senta + joga contra IA em loop
  AutoEscolher = true,
  TempoEscolha = 10.0,
  CompMs       = 0,
  CompPing     = false,
}

local geracao = 0
local ultimoTurno = "nenhum"
local disparosFeitos = 0
local vitorias = 0
local estadoFarm = "desligado"

-- estado da estação (atualizado pelos eventos do jogo)
local InStation = false
local InGame = false
local minhaEstacao = nil

local function hrp()
  local c = LP.Character
  return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum()
  local c = LP.Character
  return c and c:FindFirstChildOfClass("Humanoid")
end

local function teleportar(cf)
  local h = hrp()
  if h then
    pcall(function() h.CFrame = cf end)
  end
end

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

--============================================================================--
-- 4) Parada perfeita
--============================================================================--
local function agendarDisparo(quando, arg5, arg2, rotulo)
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
      aviso("PARADO no tempo exato! (" .. tostring(rotulo) .. ")", 3)
    else
      aviso("Erro ao disparar: " .. tostring(err):sub(1, 60), 5)
    end
  end)
end

pcall(function()
  B.PlayerTurn:Connect(function(args)
    if type(args) ~= "table" then return end
    local vezDe   = args[1]
    local a2      = tonumber(args[2])
    local a3      = tonumber(args[3])
    local a5      = args[5]
    local alvos   = args[8]
    if not (a2 and a3 and a5) then return end

    geracao = geracao + 1

    if vezDe ~= LP then
      ultimoTurno = "vez do oponente"
      return
    end

    if type(alvos) == "table" then
      local base = a2 - a3
      ultimoTurno = string.format("contínuo: %d alvos", #alvos)
      if not F.AutoParar then return end
      for i, t in ipairs(alvos) do
        local perfeito = base + tonumber(t)
        agendarDisparo(perfeito, a5, a2, "alvo " .. i .. "/" .. #alvos)
      end
    else
      ultimoTurno = string.format("alvo: %.2fs", a3)
      if not F.AutoParar then return end
      agendarDisparo(a2, a5, a2, string.format("%.2fs", a3))
    end
  end)
end)

pcall(function()
  B.GameStarted:Connect(function()
    InGame = true
    estadoFarm = F.AutoFarm and "partida rolando" or estadoFarm
  end)
end)

pcall(function()
  B.GameStopped:Connect(function()
    InGame = false
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

pcall(function()
  B.AnnounceWinner:Connect(function(args)
    if type(args) ~= "table" then return end
    if args[1] == LP then
      vitorias = vitorias + 1
      aviso(string.format("VITÓRIA #%d! Score: %s%%", vitorias, tostring(args[2])), 5)
    end
  end)
end)

-- recusa "outra chance" paga automaticamente (nunca gasta Robux)
pcall(function()
  B.PromptAnother:Connect(function(args)
    if type(args) ~= "table" then return end
    if args[1] == LP and B.DenyAnother then
      task.delay(0.5, function()
        pcall(function() B.DenyAnother:Fire() end)
      end)
    end
  end)
end)

--============================================================================--
-- 5) Auto Player (farm com IA)
--============================================================================--
pcall(function()
  B.JoinedStation:Connect(function(estacao)
    InStation = true
    minhaEstacao = estacao
    estadoFarm = F.AutoFarm and "na estação" or estadoFarm
  end)
end)

pcall(function()
  B.LeftStation:Connect(function()
    InStation = false
    InGame = false
    minhaEstacao = nil
  end)
end)

local function estacaoTemOutroJogador(estacao)
  local ok, ocupada = pcall(function()
    local cadeiras = estacao:FindFirstChild("Chairs")
    if not cadeiras then return false end
    for _, cadeira in ipairs(cadeiras:GetChildren()) do
      local seat = cadeira:FindFirstChild("Seat")
      if seat and seat.Occupant then
        local dono = seat.Occupant.Parent
        if dono and dono ~= LP.Character then
          return true
        end
      end
    end
    return false
  end)
  if ok then return ocupada end
  return true -- na dúvida, considera ocupada
end

local function acharEstacaoLivre()
  local pasta = Workspace:FindFirstChild("GameStations")
  if not pasta then return nil end
  for _, categoria in ipairs(pasta:GetChildren()) do
    for _, estacao in ipairs(categoria:GetChildren()) do
      local cadeiras = estacao:FindFirstChild("Chairs")
      if cadeiras and not estacaoTemOutroJogador(estacao) then
        for _, cadeira in ipairs(cadeiras:GetChildren()) do
          local seat = cadeira:FindFirstChild("Seat")
          if seat and not seat.Occupant then
            return estacao, seat
          end
        end
      end
    end
  end
  return nil
end

local function sentarNaCadeira(seat)
  local h = hrp()
  local hu = hum()
  if not (h and hu) then return false end
  -- teleporta em cima do assento: a física do servidor solda a gente no Seat
  h.CFrame = seat.CFrame + Vector3.new(0, 1.5, 0)
  task.wait(0.15)
  pcall(function() hu.Sit = true end)
  task.wait(0.35)
  local occ = seat.Occupant
  return occ ~= nil and occ.Parent == LP.Character
end

local function voltarProSpawn()
  local spawn = LP.RespawnLocation
  if not spawn then
    spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
  end
  if spawn then
    teleportar(spawn.CFrame + Vector3.new(0, 4, 0))
  end
end

local ultimoBotFire = 0
local ultimaTentativaSentar = 0

task.spawn(function()
  while true do
    task.wait(0.5)
    if F.AutoFarm then
      local okLoop, err = pcall(function()
        if not InStation then
          estadoFarm = "procurando estação livre..."
          local estacao, seat = acharEstacaoLivre()
          if estacao and seat then
            if os.clock() - ultimaTentativaSentar > 1.5 then
              ultimaTentativaSentar = os.clock()
              estadoFarm = "sentando na estação " .. estacao.Name
              sentarNaCadeira(seat)
            end
          else
            estadoFarm = "todas as estações ocupadas — esperando"
            task.wait(2)
          end
        elseif not InGame then
          estadoFarm = "na estação — chamando a IA..."
          if os.clock() - ultimoBotFire > 2.5 then
            ultimoBotFire = os.clock()
            if not estacaoTemOutroJogador(minhaEstacao) then
              pcall(function() B.StartBotMatch:Fire() end)
            else
              estadoFarm = "outro jogador entrou — aguardando"
            end
          end
        else
          estadoFarm = "jogando contra a IA (parada perfeita ativa)"
        end
      end)
      if not okLoop then
        estadoFarm = "erro: " .. tostring(err):sub(1, 50)
        task.wait(1)
      end
    else
      if estadoFarm ~= "desligado" then
        estadoFarm = "desligado"
      end
    end
  end
end)

--============================================================================--
-- 6) UI (WindUI)
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
    Title = "Koala Pare o Tempo v2",
    Icon = "timer",
    Author = "discord.gg/ZRFffEgQQM",
    Folder = "KoalaTempo",
    Size = UDim2.fromOffset(580, 460),
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightControl,
  })
end)
if not okWin or not Window then
  aviso("Erro ao criar janela: " .. tostring(Window), 10)
  return
end

-----------------------------------------------------------
-- Aba Farm (auto player)
-----------------------------------------------------------
local TabFarm = Window:Tab({ Title = "Auto Player", Icon = "bot" })

TabFarm:Section({ Title = "★ Farm automático com IA" })
TabFarm:Toggle({
  Title = "AUTO PLAYER (farm com IA)",
  Desc = "Senta numa estação livre, chama a IA, ganha todas as partidas com parada perfeita e repete. Desligar = sai da estação.",
  Value = false,
  Callback = function(v)
    F.AutoFarm = v
    if not v then
      pcall(function() B.RequestLeave:Fire() end)
      task.delay(0.5, voltarProSpawn)
      estadoFarm = "desligado"
    else
      F.AutoParar = true
      estadoFarm = "ligando..."
      aviso("Auto player ligado — vou sentar numa estação e farmar contra a IA.", 4)
    end
  end,
})
TabFarm:Button({
  Title = "Sair da estação agora",
  Callback = function()
    pcall(function() B.RequestLeave:Fire() end)
    task.delay(0.5, voltarProSpawn)
  end,
})

-----------------------------------------------------------
-- Aba Auto (parada perfeita)
-----------------------------------------------------------
local TabMain = Window:Tab({ Title = "Auto", Icon = "timer" })

TabMain:Section({ Title = "★ Parada perfeita" })
TabMain:Toggle({
  Title = "AUTO PARAR no tempo exato",
  Desc = "Quando for sua vez, para o temporizador no instante perfeito sozinho (modo simples e contínuo).",
  Value = true,
  Callback = function(v)
    F.AutoParar = v
    if not v then geracao = geracao + 1 end
  end,
})

TabMain:Section({ Title = "Compensação de rede" })
TabMain:Toggle({
  Title = "Compensar ping automaticamente",
  Desc = "Dispara um pouco antes, descontando seu ping real. Deixe DESLIGADO primeiro — o timestamp vai dentro do pacote.",
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
  Value = true,
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

local pFarm     = TabStatus:Paragraph({ Title = "Auto player", Desc = "..." })
local pWins     = TabStatus:Paragraph({ Title = "Wins (leaderstats)", Desc = "..." })
local pVitorias = TabStatus:Paragraph({ Title = "Vitórias nesta sessão", Desc = "..." })
local pTurno    = TabStatus:Paragraph({ Title = "Último turno", Desc = "..." })
local pDisparos = TabStatus:Paragraph({ Title = "Paradas perfeitas", Desc = "..." })
local pPing     = TabStatus:Paragraph({ Title = "Ping", Desc = "..." })

task.spawn(function()
  while Window do
    pcall(function()
      pFarm:SetDesc(estadoFarm)
      local ls = LP:FindFirstChild("leaderstats")
      local wins = ls and ls:FindFirstChild("Wins")
      pWins:SetDesc(tostring(wins and wins.Value or "?"))
      pVitorias:SetDesc(tostring(vitorias))
      pTurno:SetDesc(ultimoTurno)
      pDisparos:SetDesc(string.format("%d disparos perfeitos enviados", disparosFeitos))
      local ok, p = pcall(function() return LP:GetNetworkPing() end)
      if ok and type(p) == "number" then
        pPing:SetDesc(string.format("%d ms", math.floor(p * 1000 + 0.5)))
      else
        pPing:SetDesc("?")
      end
    end)
    task.wait(1)
  end
end)

aviso("Koala Pare o Tempo v2 carregado! Aba Auto Player liga o farm com IA.", 6)
