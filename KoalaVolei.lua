--[[
  KoalaVolei.lua — v5
  Script para [UPD] Lendas do Vôlei / Volleyball Legends (PlaceId 73956553001240)
  Parte do Koala Hub — discord.gg/ZRFffEgQQM

  v5 (revisão de código):
    FIX loops por frame protegidos com pcall (um erro não mata mais tudo em silêncio)
    FIX auto saque não dispara por falso positivo (checa Enabled do ScreenGui)
    FIX auto ataque conta o pulo do próprio script (janela de 0.45s após auto pular)
    FIX câmera sempre atual (não quebra se o jogo recriar a câmera)
    FIX reconecta o toque se a HitBox do jogo aparecer depois da bola
    FIX previsão de queda protegida contra gravidade zero / NaN
    FIX AUTO JOGAR agora também garante a hitbox ligada
    OPT ping cacheado 2x/s (antes: 60x/s), estilo cacheado, alocações por frame reduzidas

  ATENÇÃO: uso por sua conta e risco.
]]

--============================================================================--
-- 0) Polyfills de executor (antes de qualquer coisa — a UI depende disso)
--============================================================================--
local genv = (typeof(getgenv) == "function") and getgenv() or _G
local function def(nome, fn)
  local ok, atual = pcall(function() return genv[nome] end)
  if not ok or typeof(atual) ~= "function" then
    pcall(function() genv[nome] = fn end)
  end
end
def("identifyexecutor", function() return "Arceus X", "2.3.4" end)
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
-- 1) Serviços base e notificações
--============================================================================--
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local Lighting   = game:GetService("Lighting")
local VU         = game:GetService("VirtualUser")
local VIM        = game:GetService("VirtualInputManager")
local LP         = Players.LocalPlayer

local function cam()
  return Workspace.CurrentCamera
end

local function aviso(t, txt, dur)
  pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", { Title = t, Text = txt, Duration = dur or 4 })
  end)
end

--============================================================================--
-- 2) Carregamento robusto da UI (retry + espelho + erro visível)
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
  aviso("Koala Vôlei", "Falha na UI: " .. tostring(errUI), 10)
  return
end

--============================================================================--
-- 3) Remotes (cache único, por instância)
--============================================================================--
local Services = RS:WaitForChild("Packages", 15)
  and RS.Packages:WaitForChild("_Index", 15)
  and RS.Packages._Index:WaitForChild("sleitnick_knit@1.7.0", 15)
  and RS.Packages._Index["sleitnick_knit@1.7.0"]:WaitForChild("knit", 15)
  and RS.Packages._Index["sleitnick_knit@1.7.0"].knit:WaitForChild("Services", 15)
if not Services then
  aviso("Koala Vôlei", "Serviços do jogo não encontrados. Entre num servidor do jogo.", 8)
  return
end

local function rf(servico, nome)
  local ok, s = pcall(function() return Services:WaitForChild(servico, 8) end)
  if not ok or not s then return nil end
  local pasta = s:FindFirstChild("RF")
  return pasta and pasta:FindFirstChild(nome) or nil
end
local function re(servico, nome)
  local ok, s = pcall(function() return Services:WaitForChild(servico, 8) end)
  if not ok or not s then return nil end
  local pasta = s:FindFirstChild("RE")
  return pasta and pasta:FindFirstChild(nome) or nil
end

local R = {
  Interact        = rf("BallService", "Interact"),
  CreateHitbox    = rf("BallService", "CreateHitbox"),
  SpawnBall       = rf("BallService", "SpawnBall"),
  SpawnServeBall  = rf("BallService", "SpawnServeBall"),
  Serve           = rf("GameService", "Serve"),
  ReturnParty     = rf("GameService", "ReturnPartyToLobby"),
  ReturnLobby     = rf("GameService", "ReturnToLobby"),
  ToggleAdv       = rf("GameService", "ToggleAdvancedMoves"),
  DailyReward     = rf("GameService", "AwardDailyReward"),
  Teleport        = rf("PartyService", "RequestTeleport"),
  RetryVote       = rf("RankedService", "RetryServerVote"),
  RollEstilo      = rf("StyleService", "Roll"),
  RollHab         = rf("AbilityService", "Roll"),
  ClaimNivel      = rf("LevelService", "ClaimLevelRewards"),
  ClaimMissoes    = rf("QuestService", "ClaimAll"),
  DailyPresent    = rf("SeasonService", "ClaimDailyPresent"),
  RefreshPresents = rf("SeasonService", "RefreshDailyPresents"),
  PackOpen        = rf("PackService", "Open"),
  ResgatarCodigo  = rf("CodeService", "Redeem"),
  DoMove          = re("BallService", "DoMove"),
}
local function invocar(remote, ...)
  if not remote then return nil end
  local ok, r = pcall(remote.InvokeServer, remote, ...)
  return ok and r or nil
end

--============================================================================--
-- 4) Estado cacheado (listeners, sem polling)
--============================================================================--
local Estado = {
  bola = nil, bolaPart = nil, bolaId = nil,
  emJogo = false, ultimoBatedor = "", ultimoTipo = "",
  sequencia = 0, ultimoTime = "", hitboxRaio = 3,
}
local tamanhoOriginal = {}

-- ping cacheado (2x/s)
local pingCache = 60
task.spawn(function()
  while true do
    task.wait(0.5)
    local ok, v = pcall(function() return LP:GetNetworkPing() * 2000 end)
    if ok and type(v) == "number" then pingCache = v end
  end
end)
local function pingMs() return pingCache end

-- estilo cacheado (listener no atributo)
local estiloCache = ""
local function atualizarEstilo()
  local s = LP:GetAttribute("Gameplay_Style") or ""
  estiloCache = (s:gsub("%d", ""))
end
pcall(function()
  atualizarEstilo()
  LP:GetAttributeChangedSignal("Gameplay_Style"):Connect(atualizarEstilo)
end)
local function meuEstilo() return estiloCache end

local conexaoToque
local conexaoHBChild
local function ligarToque(bola) -- forward declare (definida na seção 7)
end

local function definirBola(m)
  Estado.bola = m
  Estado.bolaPart = nil
  Estado.bolaId = nil
  table.clear(tamanhoOriginal)
  if conexaoHBChild then pcall(function() conexaoHBChild:Disconnect() end) conexaoHBChild = nil end
  if not m then return end
  -- se a HitBox do jogo aparecer depois, reconecta o toque
  conexaoHBChild = m.ChildAdded:Connect(function(f)
    if f.Name == "HitBox" then ligarToque(m) end
  end)
  task.spawn(function()
    Estado.bolaId = m:GetAttribute("Id")
    m.PrimaryPart = m.PrimaryPart or m:WaitForChild("Ball.1", 3) or m:FindFirstChildWhichIsA("BasePart", true)
    Estado.bolaPart = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
  end)
end
local function varrerBola()
  for _, m in ipairs(Workspace:GetChildren()) do
    if m.Name:find("CLIENT_BALL") then return m end
  end
  return nil
end
definirBola(varrerBola())
Workspace.ChildAdded:Connect(function(f)
  if f.Name:find("CLIENT_BALL") then definirBola(f) ligarToque(f) end
end)
Workspace.ChildRemoved:Connect(function(f)
  if f == Estado.bola then definirBola(varrerBola()) end
end)

local function ligarAttr(obj, nome, campo, padrao)
  pcall(function()
    Estado[campo] = obj:GetAttribute(nome) or padrao
    obj:GetAttributeChangedSignal(nome):Connect(function()
      Estado[campo] = obj:GetAttribute(nome) or padrao
    end)
  end)
end
ligarAttr(RS, "IsBallInPlay", "emJogo", false)
ligarAttr(RS, "LastHitter", "ultimoBatedor", "")
ligarAttr(RS, "LastHitType", "ultimoTipo", "")
ligarAttr(RS, "TeamHitStreak", "sequencia", 0)
ligarAttr(RS, "LastHitTeam", "ultimoTime", "")

local function meuTime() return tostring(LP.Team) end
local function meuHRP()
  local char = LP.Character
  return char and char:FindFirstChild("HumanoidRootPart")
end
local function meuHum()
  local char = LP.Character
  return char and char:FindFirstChildOfClass("Humanoid")
end
local function noAr()
  local hum = meuHum()
  return hum and hum.FloorMaterial == Enum.Material.Air or false
end

--============================================================================--
-- 5) Config
--============================================================================--
local F = {
  -- hitbox
  Hitbox = true, HitboxMult = 3, PingComp = true, HitboxDinamica = true,
  MostrarHitbox = false,
  ImaBola = false, ImaDist = 14,
  -- reação
  ReacaoMs = 30,
  AutoRecepcao = false, AutoAtaque = false, AutoPular = true,
  -- auto jogar
  AutoJogar = false, SeguirBola = false,
  -- hooks
  CorteNaMira = false, CargaMax = false, PasseFacil = false, RecepcaoPerfeita = false,
  SuperCorte = false, SuperCorteForca = 35,
  -- saque
  SaquePerfeito = true, AutoSaque = false, SaqueForca = 100,
  -- spins / recompensas
  AutoEstilo = false, AlvoEstilo = "", AutoHab = false, AlvoHab = "", AutoClaim = false,
  -- física / visual
  Speed = false, SpeedVal = 16, Jump = false, JumpVal = 50, Noclip = false,
  ESPBola = false, ESPJogadores = false, Trajetoria = false, MiraJogadores = false,
  Fullbright = false,
}

--============================================================================--
-- 6) UI
--============================================================================--
local okWin, Window = pcall(function()
  return Koala:CreateWindow({
    Title = "Koala Vôlei v5",
    Icon = "volleyball",
    Author = "discord.gg/ZRFffEgQQM",
    Folder = "KoalaVolei",
    Size = UDim2.fromOffset(580, 460),
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightControl,
  })
end)
if not okWin or not Window then
  aviso("Koala Vôlei", "Erro ao criar janela: " .. tostring(Window), 10)
  return
end

local function listarConteudo(pasta)
  local nomes = {}
  local p = RS:FindFirstChild("Content") and RS.Content:FindFirstChild(pasta)
  if p then
    for _, m in ipairs(p:GetChildren()) do table.insert(nomes, m.Name) end
    table.sort(nomes)
  end
  if #nomes == 0 then nomes = { "(vazio)" } end
  return nomes
end

-----------------------------------------------------------
-- Aba Jogo
-----------------------------------------------------------
local TabJogo = Window:Tab({ Title = "Jogo", Icon = "volleyball" })

TabJogo:Section({ Title = "★ Auto jogar" })
TabJogo:Toggle({
  Title = "AUTO JOGAR PARTIDA",
  Desc = "Liga tudo junto: recepção + ataque + saque + seguir bola + pular + hitbox.",
  Value = false,
  Callback = function(v)
    F.AutoJogar = v
    F.AutoRecepcao = v
    F.AutoAtaque = v
    F.AutoSaque = v
    F.SeguirBola = v
    if v then F.Hitbox = true end
    aviso("Koala Vôlei", v and "AUTO JOGAR ligado. Segure o celular e assista." or "AUTO JOGAR desligado.")
  end,
})
TabJogo:Toggle({
  Title = "Seguir bola",
  Desc = "Anda sozinho até o ponto onde a bola vai cair (sem sair do seu lado).",
  Value = false,
  Callback = function(v) F.SeguirBola = v end,
})

TabJogo:Section({ Title = "Hitbox da bola" })
TabJogo:Toggle({
  Title = "Hitbox expandida",
  Desc = "Aumenta a zona de toque da bola (redimensionada a cada frame).",
  Value = true,
  Callback = function(v) F.Hitbox = v end,
})
TabJogo:Toggle({
  Title = "MOSTRAR hitbox",
  Desc = "Deixa a hitbox visível (roxa) para você ver o tamanho real.",
  Value = false,
  Callback = function(v) F.MostrarHitbox = v end,
})
TabJogo:Slider({
  Title = "Tamanho da hitbox",
  Desc = "Multiplicador (1 = normal, 3~5 = forte, 10 = absurdo).",
  Value = { Min = 1, Max = 10, Default = 3 },
  Callback = function(v) F.HitboxMult = tonumber(v) or 3 end,
})
TabJogo:Toggle({
  Title = "Hitbox dinâmica",
  Desc = "Cresce 60% extra quando a bola vem rápido na sua direção.",
  Value = true,
  Callback = function(v) F.HitboxDinamica = v end,
})
TabJogo:Toggle({
  Title = "Compensar ping",
  Desc = "Soma um bônus baseado na sua latência.",
  Value = true,
  Callback = function(v) F.PingComp = v end,
})
TabJogo:Toggle({
  Title = "Imã de bola",
  Desc = "Puxa a bola na sua direção quando ela chega perto (experimental).",
  Value = false,
  Callback = function(v) F.ImaBola = v end,
})
TabJogo:Slider({
  Title = "Distância do imã",
  Value = { Min = 6, Max = 30, Default = 14 },
  Callback = function(v) F.ImaDist = tonumber(v) or 14 end,
})

TabJogo:Section({ Title = "Reação automática (previsão de trajetória)" })
TabJogo:Toggle({
  Title = "Auto recepção",
  Desc = "Defende sozinho ataques e saques adversários.",
  Value = false,
  Callback = function(v) F.AutoRecepcao = v end,
})
TabJogo:Toggle({
  Title = "Auto ataque",
  Desc = "Corta sozinho quando você está no ar após levantamento do time.",
  Value = false,
  Callback = function(v) F.AutoAtaque = v end,
})
TabJogo:Toggle({
  Title = "Auto pular",
  Desc = "Pula sozinho na hora certa para cortar bolas altas.",
  Value = true,
  Callback = function(v) F.AutoPular = v end,
})
TabJogo:Slider({
  Title = "Janela de reação (ms)",
  Desc = "Menor = clique mais em cima da hora. 30 ms é um bom começo.",
  Value = { Min = 0, Max = 150, Default = 30 },
  Callback = function(v) F.ReacaoMs = tonumber(v) or 30 end,
})

TabJogo:Section({ Title = "Saque" })
TabJogo:Toggle({
  Title = "Auto saque perfeito",
  Desc = "Detecta seu saque, mira pro lado adversário e saca sozinho.",
  Value = false,
  Callback = function(v) F.AutoSaque = v end,
})
TabJogo:Slider({
  Title = "Força do saque (%)",
  Desc = "100 = força total. Se a bola sair pra fora, baixe para 90~95.",
  Value = { Min = 50, Max = 100, Default = 100 },
  Callback = function(v) F.SaqueForca = tonumber(v) or 100 end,
})
TabJogo:Toggle({
  Title = "Saque manual perfeito",
  Desc = "Quando VOCÊ saca, a força é corrigida automaticamente.",
  Value = true,
  Callback = function(v) F.SaquePerfeito = v end,
})
TabJogo:Button({
  Title = "Sacar perfeito AGORA (teste)",
  Desc = "Mira e saca imediatamente. Use quando for seu saque.",
  Callback = function() _G.KoalaSacarAgora = true end,
})

TabJogo:Section({ Title = "Assistências (hooks)" })
TabJogo:Toggle({
  Title = "SUPER CORTE",
  Desc = "Corte com carga máxima e mergulho pra baixo — mais forte e dentro da quadra.",
  Value = false,
  Callback = function(v) F.SuperCorte = v end,
})
TabJogo:Slider({
  Title = "Mergulho do super corte (%)",
  Desc = "Quanto o corte aponta pra baixo. 30~40 costuma ser ideal.",
  Value = { Min = 0, Max = 80, Default = 35 },
  Callback = function(v) F.SuperCorteForca = tonumber(v) or 35 end,
})
TabJogo:Toggle({
  Title = "Corte na mira",
  Desc = "O corte vai para onde a câmera aponta.",
  Value = false,
  Callback = function(v) F.CorteNaMira = v end,
})
TabJogo:Toggle({
  Title = "Carga máxima no corte",
  Desc = "Carga e especial sempre 100% no Spike.",
  Value = false,
  Callback = function(v) F.CargaMax = v end,
})
TabJogo:Toggle({
  Title = "Passe fácil",
  Desc = "Bump/Set saem limpos, na direção da câmera.",
  Value = false,
  Callback = function(v) F.PasseFacil = v end,
})
TabJogo:Toggle({
  Title = "Recepção perfeita",
  Desc = "Ajusta a carga do Bump/Set na criação da hitbox.",
  Value = false,
  Callback = function(v) F.RecepcaoPerfeita = v end,
})

-----------------------------------------------------------
-- Aba Spins
-----------------------------------------------------------
local TabSpins = Window:Tab({ Title = "Spins", Icon = "dices" })

TabSpins:Section({ Title = "Estilo" })
local ddEstilo = TabSpins:Dropdown({
  Title = "Estilo alvo",
  Values = listarConteudo("Style"),
  Multi = false,
  Callback = function(v) F.AlvoEstilo = v end,
})
TabSpins:Button({
  Title = "Atualizar lista de estilos",
  Callback = function() pcall(function() ddEstilo:Refresh(listarConteudo("Style")) end) end,
})
TabSpins:Toggle({
  Title = "Auto girar estilo",
  Desc = "Gira até conseguir o alvo (consome seus spins).",
  Value = false,
  Callback = function(v) F.AutoEstilo = v end,
})

TabSpins:Section({ Title = "Habilidade" })
local ddHab = TabSpins:Dropdown({
  Title = "Habilidade alvo",
  Values = listarConteudo("Ability"),
  Multi = false,
  Callback = function(v) F.AlvoHab = v end,
})
TabSpins:Toggle({
  Title = "Auto girar habilidade",
  Value = false,
  Callback = function(v) F.AutoHab = v end,
})

-----------------------------------------------------------
-- Aba Recompensas
-----------------------------------------------------------
local TabRec = Window:Tab({ Title = "Recompensas", Icon = "gift" })

TabRec:Section({ Title = "Resgates rápidos" })
TabRec:Button({
  Title = "Resgatar TUDO (nível + missões + presentes)",
  Callback = function()
    invocar(R.ClaimNivel)
    invocar(R.ClaimMissoes, true)
    invocar(R.RefreshPresents)
    task.wait(0.3)
    invocar(R.DailyPresent)
    invocar(R.DailyReward)
    aviso("Koala Vôlei", "Resgates enviados.")
  end,
})
TabRec:Toggle({
  Title = "Auto resgatar (a cada 60s)",
  Value = false,
  Callback = function(v) F.AutoClaim = v end,
})
TabRec:Button({
  Title = "Farm de recompensas do lobby",
  Desc = "Dispara os prompts de recompensa por like/evento (precisa estar no lobby).",
  Callback = function()
    task.spawn(function()
      local n = 0
      local lobby = Workspace:FindFirstChild("Volleyball Lobby")
      local gr = lobby and lobby:FindFirstChild("Interactables") and lobby.Interactables:FindFirstChild("GameRewards")
      if gr and typeof(fireproximityprompt) == "function" then
        for _, d in ipairs(gr:GetDescendants()) do
          if d:IsA("ProximityPrompt") then
            pcall(fireproximityprompt, d)
            n = n + 1
            task.wait(0.3)
          end
        end
      end
      aviso("Koala Vôlei", n > 0 and ("Prompts disparados: " .. n) or "Nenhum prompt achado (vá ao lobby).")
    end)
  end,
})

TabRec:Section({ Title = "Packs" })
TabRec:Button({ Title = "Abrir pack Básico",  Callback = function() invocar(R.PackOpen, "Basic") end })
TabRec:Button({ Title = "Abrir pack Médio",   Callback = function() invocar(R.PackOpen, "Medium") end })
TabRec:Button({ Title = "Abrir pack Extremo", Callback = function() invocar(R.PackOpen, "Extreme") end })

TabRec:Section({ Title = "Códigos" })
local codigoDigitado = ""
pcall(function()
  TabRec:Input({
    Title = "Código",
    Placeholder = "digite o código",
    Callback = function(t) codigoDigitado = tostring(t or "") end,
  })
end)
TabRec:Button({
  Title = "Resgatar código digitado",
  Callback = function()
    if codigoDigitado == "" then aviso("Koala Vôlei", "Digite um código primeiro.") return end
    invocar(R.ResgatarCodigo, codigoDigitado)
    aviso("Koala Vôlei", "Código enviado: " .. codigoDigitado)
  end,
})
TabRec:Button({
  Title = "Resgatar códigos conhecidos (set/2026)",
  Desc = "Testa a lista de códigos ativos um por um.",
  Callback = function()
    task.spawn(function()
      local codigos = { "UPDATE_88", "GET_SLIMED", "XP_BOOST", "UPDATE_87", "UPDATE_86", "HAKKA_RETURN", "SPIKER" }
      for _, c in ipairs(codigos) do
        invocar(R.ResgatarCodigo, c)
        task.wait(0.6)
      end
      aviso("Koala Vôlei", "Todos os códigos foram testados.", 5)
    end)
  end,
})

-----------------------------------------------------------
-- Aba Movimento
-----------------------------------------------------------
local TabMov = Window:Tab({ Title = "Movimento", Icon = "move" })

TabMov:Section({ Title = "Teletransporte" })
TabMov:Button({ Title = "Ir para Treino", Callback = function() invocar(R.Teleport, "Training") end })
TabMov:Button({ Title = "Ir para 2v2", Callback = function() invocar(R.Teleport, "Twos") end })
TabMov:Button({ Title = "Voltar ao lobby (refazer fila)", Callback = function() invocar(R.ReturnParty, true) end })
TabMov:Button({ Title = "Voltar ao lobby (sair)", Callback = function() invocar(R.ReturnParty, false) end })

TabMov:Section({ Title = "Voto de retry (ranked)" })
TabMov:Button({ Title = "Votar SIM", Callback = function() invocar(R.RetryVote, true) end })
TabMov:Button({ Title = "Votar NÃO", Callback = function() invocar(R.RetryVote, false) end })

TabMov:Section({ Title = "Física" })
TabMov:Toggle({ Title = "Speed", Value = false, Callback = function(v) F.Speed = v end })
TabMov:Slider({
  Title = "Velocidade",
  Value = { Min = 16, Max = 100, Default = 16 },
  Callback = function(v) F.SpeedVal = tonumber(v) or 16 end,
})
TabMov:Toggle({ Title = "Pulo forte", Value = false, Callback = function(v) F.Jump = v end })
TabMov:Slider({
  Title = "Força do pulo",
  Value = { Min = 50, Max = 150, Default = 50 },
  Callback = function(v) F.JumpVal = tonumber(v) or 50 end,
})
TabMov:Toggle({ Title = "Noclip", Desc = "Atravessa paredes.", Value = false, Callback = function(v) F.Noclip = v end })

-----------------------------------------------------------
-- Aba Visual
-----------------------------------------------------------
local TabVis = Window:Tab({ Title = "Visual", Icon = "eye" })

TabVis:Section({ Title = "Leitura de jogo" })
TabVis:Toggle({
  Title = "Trajetória da bola",
  Desc = "Linha mostrando para onde a bola vai + marcador onde ela cai (vermelho = seu lado, verde = lado deles).",
  Value = false,
  Callback = function(v) F.Trajetoria = v end,
})
TabVis:Toggle({
  Title = "Mira dos jogadores",
  Desc = "Linhas mostrando para onde cada jogador está olhando.",
  Value = false,
  Callback = function(v) F.MiraJogadores = v end,
})

TabVis:Section({ Title = "ESP" })
TabVis:Toggle({ Title = "ESP da bola", Desc = "Highlight + distância.", Value = false, Callback = function(v) F.ESPBola = v end })
TabVis:Toggle({ Title = "ESP de jogadores", Desc = "Highlight colorido por time.", Value = false, Callback = function(v) F.ESPJogadores = v end })

TabVis:Section({ Title = "Desempenho" })
TabVis:Button({
  Title = "Anti-lag (FPS boost)",
  Desc = "Desliga sombras, efeitos e partículas. Não desfaz.",
  Callback = function()
    task.spawn(function()
      pcall(function() Lighting.GlobalShadows = false end)
      pcall(function() Lighting.FogEnd = 9e9 end)
      pcall(function() settings().Rendering.QualityLevel = 1 end)
      for _, e in ipairs(Lighting:GetDescendants()) do
        pcall(function() if e:IsA("PostEffect") then e.Enabled = false end end)
      end
      local n = 0
      for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Beam") or o:IsA("Smoke") or o:IsA("Fire") then
          pcall(function() o.Enabled = false end)
          n = n + 1
        end
      end
      aviso("Koala Vôlei", "Anti-lag aplicado (" .. n .. " efeitos desligados).")
    end)
  end,
})
TabVis:Toggle({
  Title = "Fullbright",
  Value = false,
  Callback = function(v)
    F.Fullbright = v
    pcall(function()
      if v then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 9e9
        Lighting.GlobalShadows = false
      else
        Lighting.Brightness = 1
        Lighting.ClockTime = 13
        Lighting.GlobalShadows = true
      end
    end)
  end,
})

-----------------------------------------------------------
-- Aba Status
-----------------------------------------------------------
local TabStatus = Window:Tab({ Title = "Status", Icon = "activity" })
local parStatus = TabStatus:Paragraph({ Title = "Jogador", Desc = "Carregando..." })
local parJogo   = TabStatus:Paragraph({ Title = "Partida", Desc = "Carregando..." })
TabStatus:Section({ Title = "Sobre" })
TabStatus:Paragraph({
  Title = "Koala Vôlei v5",
  Desc = "Revisão de estabilidade: loops protegidos, menos alocações, correções de timing. Em partida pública, use com moderação.",
})

--============================================================================--
-- 7) Núcleo de reação rápida
--============================================================================--
local ATAQUES   = { Spike = true, JumpSet = true, Block = true, Serve = true }
local RECEBIDAS = { Dive = true, Bump = true, Set = true }
local ultimoGolpe = 0
local ultimoPulo = 0

local function simularClique()
  pcall(function()
    local c = cam()
    if not c then return end
    local vp = c.ViewportSize
    local x, y = math.floor(vp.X / 2), math.floor(vp.Y / 2)
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.wait(0.02)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
  end)
end
local function apertarQ()
  pcall(function()
    VIM:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
    task.wait(0.02)
    VIM:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
  end)
end
local function executarGolpe()
  if meuEstilo() == "TeamCaptain" then apertarQ() else simularClique() end
end

local function condicaoDefesa()
  return F.AutoRecepcao
    and Estado.ultimoTime ~= meuTime()
    and ATAQUES[Estado.ultimoTipo] == true
end
local function condicaoAtaqueBase()
  return F.AutoAtaque
    and Estado.ultimoTime == meuTime()
    and Estado.ultimoBatedor ~= LP.Name
    and (ATAQUES[Estado.ultimoTipo] or RECEBIDAS[Estado.ultimoTipo]) == true
end
-- conta o pulo do próprio script: por 0.45s após pular, considera "no ar"
local function consideradoNoAr()
  return noAr() or (tick() - ultimoPulo < 0.45)
end

local function tentarGolpear()
  local agora = tick()
  if agora - ultimoGolpe < 0.2 then return end
  if condicaoDefesa() or (condicaoAtaqueBase() and consideradoNoAr()) then
    ultimoGolpe = agora
    executarGolpe()
  end
end

-- Toque físico na hitbox = reação instantânea
local function aoTocarHitbox(parte)
  local char = LP.Character
  if not (char and parte and parte:IsDescendantOf(char)) then return end
  tentarGolpear()
end

ligarToque = function(bola)
  if conexaoToque then pcall(function() conexaoToque:Disconnect() end) conexaoToque = nil end
  if not bola then return end
  task.spawn(function()
    local hb = bola:WaitForChild("HitBox", 8)
    if hb and bola == Estado.bola then
      if conexaoToque then pcall(function() conexaoToque:Disconnect() end) end
      conexaoToque = hb.Touched:Connect(aoTocarHitbox)
    end
  end)
end
ligarToque(Estado.bola)

--============================================================================--
-- 8) Previsão de trajetória (física de projétil)
--============================================================================--
local function preverAterrissagem(p0, v0, chaoY)
  local g = Workspace.Gravity
  if not g or g <= 0 then return nil end
  local a = -0.5 * g
  local b = v0.Y
  local c = p0.Y - chaoY
  local disc = b * b - 4 * a * c
  if disc < 0 or disc ~= disc then return nil end -- NaN guard
  local sq = math.sqrt(disc)
  local t1 = (-b + sq) / (2 * a)
  local t2 = (-b - sq) / (2 * a)
  local t
  if t1 > 0 and t2 > 0 then t = math.min(t1, t2)
  elseif t1 > 0 then t = t1
  elseif t2 > 0 then t = t2 end
  if not t or t ~= t or t > 6 then return nil end
  return p0 + Vector3.new(v0.X * t, v0.Y * t - 0.5 * g * t * t, v0.Z * t), t
end

--============================================================================--
-- 9) Visuais de leitura de jogo (trajetória + marcador + mira)
--============================================================================--
local function novaParteVisual(nome, cor)
  local p = Instance.new("Part")
  p.Name = nome
  p.Anchored = true
  p.CanCollide = false
  p.CanTouch = false
  p.CanQuery = false
  p.Material = Enum.Material.Neon
  p.Color = cor
  p.Transparency = 1
  p.Parent = Workspace
  return p
end
local trajLinha    = novaParteVisual("KoalaTrajLinha", Color3.fromRGB(255, 255, 0))
local trajMarcador = novaParteVisual("KoalaTrajMarcador", Color3.fromRGB(0, 255, 120))
trajMarcador.Shape = Enum.PartType.Cylinder

local linhasMira = {}
local function limparMiras()
  for pl, part in pairs(linhasMira) do
    pcall(function() part:Destroy() end)
    linhasMira[pl] = nil
  end
end
task.spawn(function() -- mira dos jogadores (8 Hz)
  while true do
    task.wait(0.12)
    local ok = pcall(function()
      if not F.MiraJogadores then
        if next(linhasMira) then limparMiras() end
      else
        for _, p in ipairs(Players:GetPlayers()) do
          if p ~= LP then
            local char = p.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
              local part = linhasMira[p]
              if not part then
                part = novaParteVisual("KoalaMira", Color3.new(1, 1, 1))
                linhasMira[p] = part
              end
              local aliado = tostring(p.Team) == meuTime()
              part.Color = aliado and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(255, 60, 60)
              local origem = hrp.Position + Vector3.new(0, 1.5, 0)
              local alvo = origem + hrp.CFrame.LookVector * 12
              part.Size = Vector3.new(0.12, 0.12, 12)
              part.CFrame = CFrame.lookAt((origem + alvo) / 2, alvo)
              part.Transparency = 0.35
            elseif linhasMira[p] then
              pcall(function() linhasMira[p]:Destroy() end)
              linhasMira[p] = nil
            end
          end
        end
      end
    end)
  end
end)
Players.PlayerRemoving:Connect(function(p)
  if linhasMira[p] then
    pcall(function() linhasMira[p]:Destroy() end)
    linhasMira[p] = nil
  end
end)

--============================================================================--
-- 10) Loop único por frame: hitbox + imã + previsão + trajetória + pulo
--     (corpo protegido por pcall: um erro não derruba o loop)
--============================================================================--
local V3_ZERO = Vector3.zero
local OFFSET_PULO = Vector3.new(0, 2, 0)

local function corpoFrame(dt)
  local bola, part = Estado.bola, Estado.bolaPart
  local bolaOk = bola and bola.Parent and part and part.Parent
  local hrp = meuHRP()

  ---------- HITBOX ----------
  if bolaOk then
    local hb = bola:FindFirstChild("HitBox")
    if not hb and (F.Hitbox or F.AutoRecepcao or F.AutoAtaque) then
      local ok, novo = pcall(function()
        local p = Instance.new("Part")
        p.Name = "HitBox"
        p.Shape = Enum.PartType.Ball
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = true
        p.Transparency = 1
        p:SetAttribute("Koala", true)
        p.CFrame = part.CFrame
        p.Parent = bola
        return p
      end)
      if ok then hb = novo end
    end
    if hb then
      if not tamanhoOriginal[hb] then tamanhoOriginal[hb] = part.Size end
      local gerenciando = F.Hitbox or hb:GetAttribute("Koala")
      if gerenciando then
        local mult = F.Hitbox and F.HitboxMult or 1
        if F.HitboxDinamica and hrp then
          local paraMim = hrp.Position - part.Position
          local dist = paraMim.Magnitude
          if dist > 0.001 and part.AssemblyLinearVelocity:Dot(paraMim / dist) > 20 then
            mult = mult * 1.6
          end
        end
        if F.PingComp then
          mult = mult + math.max(0, math.floor((pingCache - 50) / 50))
        end
        pcall(function()
          hb.Size = tamanhoOriginal[hb] * mult
          hb.CanTouch = true
          if hb:GetAttribute("Koala") then hb.CFrame = part.CFrame end
          if F.MostrarHitbox then
            hb.Transparency = 0.55
            hb.Material = Enum.Material.ForceField
            hb.Color = Color3.fromRGB(180, 0, 255)
          else
            hb.Transparency = 1
          end
        end)
        Estado.hitboxRaio = (tamanhoOriginal[hb].X * mult) / 2
      else
        if hb.Size ~= tamanhoOriginal[hb] then
          pcall(function() hb.Size = tamanhoOriginal[hb] hb.Transparency = 1 end)
        end
        Estado.hitboxRaio = tamanhoOriginal[hb].X / 2
      end
    end
  end

  if not (bolaOk and hrp) then
    if F.Trajetoria then
      trajLinha.Transparency = 1
      trajMarcador.Transparency = 1
    end
    return
  end

  local posBola = part.Position
  local posMim = hrp.Position
  local vel = part.AssemblyLinearVelocity

  ---------- TRAJETÓRIA VISUAL ----------
  if F.Trajetoria then
    local pouso = preverAterrissagem(posBola, vel, posMim.Y - 3)
    if pouso then
      local meio = (posBola + pouso) / 2
      local comp = (pouso - posBola).Magnitude
      trajLinha.Size = Vector3.new(0.15, 0.15, comp)
      trajLinha.CFrame = CFrame.lookAt(meio, pouso)
      trajLinha.Transparency = 0.25
      local perigo = (pouso.Z < 0) == (posMim.Z < 0)
      trajMarcador.Color = perigo and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(0, 255, 120)
      trajMarcador.Size = Vector3.new(0.25, 5, 5)
      trajMarcador.CFrame = CFrame.new(pouso + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
      trajMarcador.Transparency = 0.35
    else
      trajLinha.Transparency = 1
      trajMarcador.Transparency = 1
    end
  end

  ---------- IMÃ DE BOLA ----------
  if F.ImaBola and Estado.emJogo then
    local paraMim = (posMim + OFFSET_PULO) - posBola
    local dist = paraMim.Magnitude
    if dist > 2 and dist < F.ImaDist then
      local vindo = vel.Magnitude < 5 or vel:Dot(paraMim / dist) > 0
      if vindo then
        local passo = math.clamp(45 * dt / dist, 0, 0.5)
        local nova = posBola:Lerp(posMim + OFFSET_PULO, passo)
        pcall(function()
          bola:PivotTo(CFrame.new(nova) * (part.CFrame - posBola))
        end)
      end
    end
  end

  ---------- PREVISÃO + REAÇÃO ----------
  if F.AutoRecepcao or F.AutoAtaque then
    local agora = tick()
    if agora - ultimoGolpe >= 0.2 then
      local paraMim = posMim - posBola
      local dist = paraMim.Magnitude
      if dist <= 60 then
        local velAprox = dist > 0.001 and vel:Dot(paraMim / dist) or 0
        local raio = Estado.hitboxRaio + 1.5
        local janela = (F.ReacaoMs / 1000) + (pingCache / 2000)
        local iminente = dist <= raio
          or (velAprox > 5 and ((dist - raio) / velAprox) <= janela)
        if iminente then tentarGolpear() end

        -- AUTO PULAR
        if F.AutoPular and condicaoAtaqueBase() and not consideradoNoAr() then
          if agora - ultimoPulo >= 0.9 then
            local dx = posBola.X - posMim.X
            local dz = posBola.Z - posMim.Z
            local distH = math.sqrt(dx * dx + dz * dz)
            local altura = posBola.Y - posMim.Y
            if distH <= raio + 5 and altura >= 2.5 and altura <= 12 then
              local hum = meuHum()
              if hum then
                ultimoPulo = agora
                hum.Jump = true
              end
            end
          end
        end
      end
    end
  end
end

RunService.RenderStepped:Connect(function(dt)
  local ok = pcall(corpoFrame, dt)
end)

--============================================================================--
-- 11) Seguir bola (auto posicionamento)
--============================================================================--
task.spawn(function()
  while true do
    task.wait(0.15)
    if F.SeguirBola and Estado.emJogo then
      pcall(function()
        local hum = meuHum()
        local hrp = meuHRP()
        local part = Estado.bolaPart
        if not (hum and hrp and part) then return end
        local pouso = preverAterrissagem(part.Position, part.AssemblyLinearVelocity, hrp.Position.Y - 3) or part.Position
        local ladoNeg = hrp.Position.Z < 0
        local alvoZ = pouso.Z
        if ladoNeg then alvoZ = math.min(alvoZ, -2.5) else alvoZ = math.max(alvoZ, 2.5) end
        local alvo = Vector3.new(pouso.X, hrp.Position.Y, alvoZ)
        if (alvo - hrp.Position).Magnitude > 2 then
          hum:MoveTo(alvo)
        end
      end)
    end
  end
end)

--============================================================================--
-- 12) Saque perfeito (mira automática + força ideal)
--============================================================================--
local function mirarQuadraAdversaria()
  local hrp = meuHRP()
  if not hrp then return nil end
  local alvoZ = (hrp.Position.Z < 0) and 25 or -25
  local alvo = Vector3.new(0, hrp.Position.Y, alvoZ)
  pcall(function()
    hrp.CFrame = CFrame.lookAt(hrp.Position, alvo)
  end)
  pcall(function()
    local c = cam()
    if c then
      c.CFrame = CFrame.lookAt(c.CFrame.Position, Vector3.new(0, hrp.Position.Y + 2, alvoZ))
    end
  end)
  return alvo
end

local saqueEmAndamento = false
local function sacarPerfeito()
  if saqueEmAndamento then return end
  saqueEmAndamento = true
  task.spawn(function()
    mirarQuadraAdversaria()
    task.wait(0.08)
    if not Estado.bola then
      invocar(R.SpawnServeBall)
      task.wait(0.15)
    end
    mirarQuadraAdversaria()
    invocar(R.Serve, 1, F.SaqueForca / 100)
    task.wait(1.5)
    saqueEmAndamento = false
  end)
end

task.spawn(function()
  while true do
    task.wait(0.1)
    if _G.KoalaSacarAgora then
      _G.KoalaSacarAgora = false
      sacarPerfeito()
    end
  end
end)

local serveUIs = {}
local function cachearServeUI()
  table.clear(serveUIs)
  local pg = LP:FindFirstChild("PlayerGui")
  if not pg then return end
  for _, d in ipairs(pg:GetDescendants()) do
    if d:IsA("GuiObject") and d.Name:lower():find("serve") then
      table.insert(serveUIs, d)
    end
  end
end
local function cadeiaVisivel(ui)
  local p = ui
  while p and p ~= game do
    if p:IsA("GuiObject") and not p.Visible then return false end
    -- ScreenGui/GuiLayerCollector desligado = tudo dentro invisível
    if p:IsA("LayerCollector") and not p.Enabled then return false end
    p = p.Parent
  end
  return true
end
local function serveAtivo()
  for _, ui in ipairs(serveUIs) do
    if ui.Visible and cadeiaVisivel(ui) then return true end
  end
  for k, v in pairs(RS:GetAttributes()) do
    local kl = k:lower()
    if kl:find("serv") and not kl:find("server") then
      if v == true or tostring(v) == LP.Name then return true end
    end
  end
  return false
end

task.spawn(function()
  task.wait(3)
  cachearServeUI()
  local recache = 0
  local estavaAtivo = false
  while true do
    task.wait(0.15)
    recache = recache + 1
    if recache >= 40 then
      recache = 0
      pcall(cachearServeUI)
    end
    if F.AutoSaque then
      local ativo = false
      pcall(function() ativo = serveAtivo() end)
      if ativo and not estavaAtivo then
        estavaAtivo = true
        task.wait(0.1)
        sacarPerfeito()
      elseif not ativo then
        estavaAtivo = false
      end
    else
      estavaAtivo = false
    end
  end
end)

--============================================================================--
-- 13) Hooks de remote (por instância, preservando Key do jogo)
--============================================================================--
local hooksOk = false
if typeof(hookmetamethod) == "function" and typeof(getnamecallmethod) == "function" then
  hooksOk = pcall(function()
    local ncc = (typeof(newcclosure) == "function") and newcclosure or function(f) return f end
    local velho
    velho = hookmetamethod(game, "__namecall", ncc(function(self, ...)
      local metodo = getnamecallmethod()
      if checkcaller() or metodo ~= "InvokeServer" then
        return velho(self, ...)
      end
      local args = { ... }

      -- Saque manual com força corrigida
      if self == R.Serve and F.SaquePerfeito then
        return velho(self, args[1], F.SaqueForca / 100)
      end

      if self == R.Interact and type(args[1]) == "table" then
        local d = args[1]
        if d.Move == "Spike" then
          local c = cam()
          if F.SuperCorte and c then
            local lv = c.CFrame.LookVector
            local mergulho = Vector3.new(0, -F.SuperCorteForca / 100, 0)
            local dir = (lv + mergulho).Unit
            d.LookVector = dir
            d.TiltDirection = dir
            d.Charge = 1
            d.SpecialCharge = 1
            d.ClientCanRunSpecial = true
          else
            if F.CargaMax then
              d.Charge = 1
              d.SpecialCharge = 1
              d.ClientCanRunSpecial = true
            end
            if F.CorteNaMira and c then
              d.LookVector = c.CFrame.LookVector
            end
          end
        elseif (d.Move == "Bump" or d.Move == "Set") and F.PasseFacil then
          local c = cam()
          d.Charge = (d.Move == "Bump") and 0 or 1
          d.SpecialCharge = 0
          d.TiltDirection = Vector3.yAxis
          d.MoveDirection = Vector3.zero
          if c then d.LookVector = c.CFrame.LookVector end
          d.ClientCanRunSpecial = false
        end
        return velho(self, d)
      end

      if self == R.CreateHitbox and type(args[1]) == "table" and F.RecepcaoPerfeita then
        local d = args[1]
        if d.Move == "Bump" or d.Move == "Set" then
          d.Charge = (d.Move == "Bump") and 0 or 0.6
        end
        return velho(self, d)
      end

      return velho(self, ...)
    end))
  end)
end

--============================================================================--
-- 14) Loops de física / spins / claim / status
--============================================================================--
task.spawn(function() -- speed + pulo forte
  while true do
    task.wait(0.25)
    pcall(function()
      local hum = meuHum()
      if not hum then return end
      if F.Speed and hum.WalkSpeed ~= F.SpeedVal then hum.WalkSpeed = F.SpeedVal end
      if F.Jump then
        if hum.UseJumpPower then
          if hum.JumpPower ~= F.JumpVal then hum.JumpPower = F.JumpVal end
        elseif hum.JumpHeight ~= F.JumpVal / 10 then
          hum.JumpHeight = F.JumpVal / 10
        end
      end
    end)
  end
end)

RunService.Stepped:Connect(function() -- noclip
  if not F.Noclip then return end
  pcall(function()
    local char = LP.Character
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
      if p:IsA("BasePart") and p.CanCollide then
        p.CanCollide = false
      end
    end
  end)
end)

task.spawn(function() -- auto spins
  while true do
    task.wait(0.7)
    if F.AutoEstilo and F.AlvoEstilo ~= "" and F.AlvoEstilo ~= "(vazio)" then
      if (LP:GetAttribute("Gameplay_Style") or "") == F.AlvoEstilo then
        F.AutoEstilo = false
        aviso("Koala Vôlei", "Conseguiu o estilo: " .. F.AlvoEstilo, 5)
      else
        invocar(R.RollEstilo, true)
      end
    end
    if F.AutoHab and F.AlvoHab ~= "" and F.AlvoHab ~= "(vazio)" then
      if (LP:GetAttribute("Gameplay_Ability") or "") == F.AlvoHab then
        F.AutoHab = false
        aviso("Koala Vôlei", "Conseguiu a habilidade: " .. F.AlvoHab, 5)
      else
        invocar(R.RollHab, true)
      end
    end
  end
end)

task.spawn(function() -- auto claim
  while true do
    task.wait(60)
    if F.AutoClaim then
      invocar(R.ClaimNivel)
      invocar(R.ClaimMissoes, true)
      invocar(R.DailyPresent)
      invocar(R.DailyReward)
    end
  end
end)

task.spawn(function() -- status ao vivo
  while true do
    task.wait(1)
    pcall(function()
      parStatus:SetDesc(string.format(
        "Estilo: %s  |  Habilidade: %s\nNível: %s  |  Carga: %s  |  Ping: %d ms",
        tostring(LP:GetAttribute("Gameplay_Style") or "?"),
        tostring(LP:GetAttribute("Gameplay_Ability") or "?"),
        tostring(LP:GetAttribute("User_Level") or 0),
        tostring(LP:GetAttribute("Ability_Charge") or 0),
        math.floor(pingCache)
      ))
    end)
    pcall(function()
      parJogo:SetDesc(string.format(
        "Bola em jogo: %s  |  Último toque: %s (%s)\nSequência do time: %s  |  Bola: %s",
        tostring(Estado.emJogo), tostring(Estado.ultimoBatedor), tostring(Estado.ultimoTipo),
        tostring(Estado.sequencia), tostring(Estado.bolaId or "nenhuma")
      ))
    end)
  end
end)

--============================================================================--
-- 15) ESP
--============================================================================--
local espBolaHL, espBolaTag
task.spawn(function()
  while true do
    task.wait(0.4)
    pcall(function()
      if F.ESPBola and Estado.bola and Estado.bolaPart then
        if not espBolaHL or espBolaHL.Parent ~= Estado.bola then
          pcall(function() if espBolaHL then espBolaHL:Destroy() end end)
          pcall(function() if espBolaTag then espBolaTag:Destroy() end end)
          espBolaHL = Instance.new("Highlight")
          espBolaHL.FillColor = Color3.fromRGB(255, 200, 0)
          espBolaHL.OutlineColor = Color3.fromRGB(255, 255, 255)
          espBolaHL.Parent = Estado.bola
          espBolaTag = Instance.new("BillboardGui")
          espBolaTag.Size = UDim2.fromOffset(120, 30)
          espBolaTag.StudsOffset = Vector3.new(0, 3, 0)
          espBolaTag.AlwaysOnTop = true
          espBolaTag.Adornee = Estado.bolaPart
          local t = Instance.new("TextLabel")
          t.Name = "Txt"
          t.Size = UDim2.fromScale(1, 1)
          t.BackgroundTransparency = 1
          t.TextColor3 = Color3.fromRGB(255, 220, 0)
          t.TextStrokeTransparency = 0.5
          t.Font = Enum.Font.GothamBold
          t.TextSize = 14
          t.Parent = espBolaTag
          espBolaTag.Parent = Estado.bola
        end
        pcall(function()
          local hrp = meuHRP()
          if hrp then
            espBolaTag.Txt.Text = string.format("BOLA • %dm", math.floor((Estado.bolaPart.Position - hrp.Position).Magnitude))
          end
        end)
      else
        pcall(function() if espBolaHL then espBolaHL:Destroy() espBolaHL = nil end end)
        pcall(function() if espBolaTag then espBolaTag:Destroy() espBolaTag = nil end end)
      end
      for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
          local char = p.Character
          local hl = char and char:FindFirstChild("KoalaESP")
          if F.ESPJogadores and char then
            if not hl then
              hl = Instance.new("Highlight")
              hl.Name = "KoalaESP"
              hl.FillTransparency = 0.6
              hl.Parent = char
            end
            hl.FillColor = (tostring(p.Team) == meuTime()) and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(255, 60, 60)
          elseif hl then
            hl:Destroy()
          end
        end
      end
    end)
  end
end)

--============================================================================--
-- 16) Extras: advanced moves automático + anti-AFK
--============================================================================--
task.spawn(function()
  pcall(function()
    while not LP:GetAttribute("User_Level") do task.wait(1) end
    if tonumber(LP:GetAttribute("User_Level")) < 5 then return end
    task.wait(2)
    local txt = LP.PlayerGui:WaitForChild("Interface", 5)
      and LP.PlayerGui.Interface:FindFirstChild("TeamSelection")
      and LP.PlayerGui.Interface.TeamSelection:FindFirstChild("Options")
      and LP.PlayerGui.Interface.TeamSelection.Options:FindFirstChild("AdvancedMoves")
      and LP.PlayerGui.Interface.TeamSelection.Options.AdvancedMoves:FindFirstChild("Text")
    if txt and txt.Text:find("OFF") then
      invocar(R.ToggleAdv)
    end
  end)
end)

pcall(function()
  LP.Idled:Connect(function()
    pcall(function()
      local c = cam()
      if c then
        VU:Button2Down(Vector2.new(0, 0), c.CFrame)
        task.wait(1)
        VU:Button2Up(Vector2.new(0, 0), c.CFrame)
      end
    end)
  end)
end)

task.defer(function()
  if hooksOk then
    aviso("Koala Vôlei v5", "Carregado! RightControl abre/fecha o menu.", 5)
  else
    aviso("Koala Vôlei v5", "Carregado (hooks indisponíveis — assistências desligadas).", 6)
  end
end)
