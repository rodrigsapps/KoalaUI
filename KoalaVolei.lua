--[[
  KoalaVolei.lua — v2
  Script para [UPD] Lendas do Vôlei / Volleyball Legends (PlaceId 73956553001240)
  Parte do Koala Hub — discord.gg/ZRFffEgQQM

  v2: corrigido hitbox (redimensiona a HitBox do jogo a cada frame, sem CanQuery=false),
      auto-recepção/ataque por simulação de toque (padrão comprovado),
      polyfills de funções de executor (corrige "Falha ao carregar UI"),
      carregamento da UI com retry + espelho, hooks por instância direta,
      ESP, anti-lag, noclip, farm de recompensas, códigos embutidos.

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
local Camera     = Workspace.CurrentCamera

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
  sequencia = 0, ultimoTime = "",
}
local function varrerBola()
  for _, m in ipairs(Workspace:GetChildren()) do
    if m.Name:find("CLIENT_BALL") then return m end
  end
  return nil
end
local function definirBola(m)
  Estado.bola = m
  Estado.bolaPart = nil
  Estado.bolaId = nil
  if not m then return end
  task.spawn(function()
    Estado.bolaId = m:GetAttribute("Id")
    m.PrimaryPart = m.PrimaryPart or m:WaitForChild("Ball.1", 3) or m:FindFirstChildWhichIsA("BasePart", true)
    Estado.bolaPart = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
  end)
end
definirBola(varrerBola())
Workspace.ChildAdded:Connect(function(f)
  if f.Name:find("CLIENT_BALL") then definirBola(f) end
end)
Workspace.ChildRemoved:Connect(function(f)
  if f == Estado.bola then definirBola(varrerBola()) end
end)

local function ligarAttr(obj, nome, campo)
  pcall(function()
    Estado[campo] = obj:GetAttribute(nome) or Estado[campo]
    obj:GetAttributeChangedSignal(nome):Connect(function()
      Estado[campo] = obj:GetAttribute(nome) or Estado[campo]
    end)
  end)
end
ligarAttr(RS, "IsBallInPlay", "emJogo")
ligarAttr(RS, "LastHitter", "ultimoBatedor")
ligarAttr(RS, "LastHitType", "ultimoTipo")
ligarAttr(RS, "TeamHitStreak", "sequencia")
ligarAttr(RS, "LastHitTeam", "ultimoTime")

local function meuTime() return tostring(LP.Team) end
local function meuEstilo()
  local s = LP:GetAttribute("Gameplay_Style") or ""
  return (s:gsub("%d", ""))
end
local function noAr()
  local ok, ar = pcall(function()
    return LP.Character and LP.Character:FindFirstChildOfClass("Humanoid").FloorMaterial == Enum.Material.Air
  end)
  return ok and ar or false
end
local function pingMs()
  local ok, v = pcall(function() return LP:GetNetworkPing() * 2000 end)
  return (ok and type(v) == "number") and v or 60
end

--============================================================================--
-- 5) Config
--============================================================================--
local F = {
  Hitbox = true, HitboxMult = 3, PingComp = true,
  AutoRecepcao = false, AutoAtaque = false,
  CorteNaMira = false, CargaMax = false, PasseFacil = false,
  RecepcaoPerfeita = false, SaquePerfeito = false,
  AutoEstilo = false, AlvoEstilo = "", AutoHab = false, AlvoHab = "",
  AutoClaim = false,
  Speed = false, SpeedVal = 16, Jump = false, JumpVal = 50, Noclip = false,
  ESPBola = false, ESPJogadores = false, Fullbright = false,
}

--============================================================================--
-- 6) UI
--============================================================================--
local okWin, Window = pcall(function()
  return Koala:CreateWindow({
    Title = "Koala Vôlei v2",
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

TabJogo:Section({ Title = "Hitbox da bola" })
TabJogo:Toggle({
  Title = "Hitbox expandida",
  Desc = "Aumenta a zona de toque da bola. Redimensiona a HitBox do jogo a cada frame.",
  Value = true,
  Callback = function(v) F.Hitbox = v end,
})
TabJogo:Slider({
  Title = "Tamanho da hitbox",
  Desc = "Multiplicador (1 = normal, 3~5 = forte, 10 = absurdo).",
  Value = { Min = 1, Max = 10, Default = 3 },
  Callback = function(v) F.HitboxMult = tonumber(v) or 3 end,
})
TabJogo:Toggle({
  Title = "Compensar ping",
  Desc = "Soma um bônus baseado na sua latência.",
  Value = true,
  Callback = function(v) F.PingComp = v end,
})

TabJogo:Section({ Title = "Automação de jogadas" })
TabJogo:Toggle({
  Title = "Auto recepção",
  Desc = "Clica sozinho quando um ataque adversário chega em você.",
  Value = false,
  Callback = function(v) F.AutoRecepcao = v end,
})
TabJogo:Toggle({
  Title = "Auto ataque",
  Desc = "Corta sozinho quando você pula após levantamento do time.",
  Value = false,
  Callback = function(v) F.AutoAtaque = v end,
})

TabJogo:Section({ Title = "Assistências (hooks)" })
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
TabJogo:Toggle({
  Title = "Saque perfeito",
  Desc = "Força força máxima em todo saque.",
  Value = false,
  Callback = function(v) F.SaquePerfeito = v end,
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

TabVis:Section({ Title = "ESP" })
TabVis:Toggle({ Title = "ESP da bola", Desc = "Highlight + distância.", Value = false, Callback = function(v) F.ESPBola = v end })
TabVis:Toggle({ Title = "ESP de jogadores", Desc = "Highlight + nome.", Value = false, Callback = function(v) F.ESPJogadores = v end })

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
  Title = "Koala Vôlei v2",
  Desc = "Hitbox e auto-jogadas mexem com a detecção de toque da bola. Comece com multiplicador baixo (2~3) para não chamar atenção.",
})

--============================================================================--
-- 7) Hitbox — loop por frame (o jogo reseta o tamanho; a gente vence na marra)
--============================================================================--
local tamanhoOriginal = {}
RunService.RenderStepped:Connect(function()
  if not (F.Hitbox or F.AutoRecepcao or F.AutoAtaque) then return end
  local bola, part = Estado.bola, Estado.bolaPart
  if not (bola and bola.Parent and part) then return end
  local hb = bola:FindFirstChild("HitBox")
  if not hb then
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
  if not hb then return end
  if not tamanhoOriginal[hb] then
    tamanhoOriginal[hb] = part.Size
  end
  if F.Hitbox or hb:GetAttribute("Koala") then
    local extra = 0
    if F.PingComp then extra = math.max(0, math.floor((pingMs() - 50) / 50)) end
    local mult = (F.Hitbox and F.HitboxMult or 1) + extra
    pcall(function()
      hb.Size = tamanhoOriginal[hb] * mult
      if hb:GetAttribute("Koala") then hb.CFrame = part.CFrame end
    end)
  elseif tamanhoOriginal[hb] and hb.Size ~= tamanhoOriginal[hb] then
    pcall(function() hb.Size = tamanhoOriginal[hb] end)
  end
end)

--============================================================================--
-- 8) Auto recepção / ataque — toque na HitBox + simulação de input
--============================================================================--
local ATAQUES  = { Spike = true, JumpSet = true, Block = true }
local RECEBIDAS = { Dive = true, Bump = true, Set = true }

local function simularClique()
  pcall(function()
    local vp = Camera.ViewportSize
    local x, y = math.floor(vp.X / 2), math.floor(vp.Y / 2)
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.wait(0.05)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
  end)
end
local function apertarQ()
  pcall(function()
    VIM:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
    task.wait(0.05)
    VIM:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
  end)
end
local function executarGolpe()
  if meuEstilo() == "TeamCaptain" then apertarQ() else simularClique() end
end

local toquePendente = false
RS:GetAttributeChangedSignal("LastHitter"):Connect(function() toquePendente = false end)

local function aoTocarHitbox(parte)
  if toquePendente then return end
  if not (F.AutoRecepcao or F.AutoAtaque) then return end
  local char = LP.Character
  if not (char and parte and parte:IsDescendantOf(char)) then return end
  local part = Estado.bolaPart
  if not part then return end
  local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
  if not hrp then return end

  local defesa = F.AutoRecepcao
    and Estado.ultimoTime ~= meuTime()
    and ATAQUES[Estado.ultimoTipo]
    and part.Position.Y >= hrp.Position.Y
  local ataque = F.AutoAtaque
    and noAr()
    and Estado.ultimoTime == meuTime()
    and Estado.ultimoBatedor ~= LP.Name
    and (ATAQUES[Estado.ultimoTipo] or RECEBIDAS[Estado.ultimoTipo])

  if not (defesa or ataque) then return end
  toquePendente = true
  task.spawn(function()
    local limite = (math.floor(hrp.Position.Z) < 0) and -0.5 or 0.5
    local t0 = tick()
    while tick() - t0 < 1.5 do
      local p = Estado.bolaPart
      if not p then break end
      local z = p.Position.Z
      if (limite < 0 and z < limite) or (limite > 0 and z > limite) then break end
      task.wait()
    end
    executarGolpe()
    task.wait(0.3)
    toquePendente = false
  end)
end

local conexaoToque
local function ligarToque(bola)
  if conexaoToque then pcall(function() conexaoToque:Disconnect() end) end
  if not bola then return end
  task.spawn(function()
    local hb = bola:WaitForChild("HitBox", 8)
    if hb and bola == Estado.bola then
      conexaoToque = hb.Touched:Connect(aoTocarHitbox)
    end
  end)
end
ligarToque(Estado.bola)
Workspace.ChildAdded:Connect(function(f)
  if f.Name:find("CLIENT_BALL") then ligarToque(f) end
end)

--============================================================================--
-- 9) Hooks de remote (por instância, preservando Key do jogo)
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

      if self == R.Serve and F.SaquePerfeito then
        return velho(self, args[1], 1)
      end

      if self == R.Interact and type(args[1]) == "table" then
        local d = args[1]
        if d.Move == "Spike" then
          if F.CargaMax then
            d.Charge = 1
            d.SpecialCharge = 1
            d.ClientCanRunSpecial = true
          end
          if F.CorteNaMira and Camera then
            d.LookVector = Camera.CFrame.LookVector
          end
        elseif (d.Move == "Bump" or d.Move == "Set") and F.PasseFacil then
          d.Charge = (d.Move == "Bump") and 0 or 1
          d.SpecialCharge = 0
          d.TiltDirection = Vector3.yAxis
          d.MoveDirection = Vector3.zero
          if Camera then d.LookVector = Camera.CFrame.LookVector end
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
-- 10) Loops de física / spins / claim / status
--============================================================================--
task.spawn(function() -- speed + pulo
  while true do
    task.wait(0.25)
    pcall(function()
      local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
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
  local char = LP.Character
  if not char then return end
  for _, p in ipairs(char:GetDescendants()) do
    if p:IsA("BasePart") and p.CanCollide then
      p.CanCollide = false
    end
  end
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
        math.floor(pingMs())
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
-- 11) ESP
--============================================================================--
local espBolaHL, espBolaTag
task.spawn(function()
  while true do
    task.wait(0.4)
    -- bola
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
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
          espBolaTag.Txt.Text = string.format("BOLA • %dm", math.floor((Estado.bolaPart.Position - hrp.Position).Magnitude))
        end
      end)
    else
      pcall(function() if espBolaHL then espBolaHL:Destroy() espBolaHL = nil end end)
      pcall(function() if espBolaTag then espBolaTag:Destroy() espBolaTag = nil end end)
    end
    -- jogadores
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
  end
end)

--============================================================================--
-- 12) Extras: advanced moves automático + anti-AFK
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
    VU:Button2Down(Vector2.new(0, 0), Camera.CFrame)
    task.wait(1)
    VU:Button2Up(Vector2.new(0, 0), Camera.CFrame)
  end)
end)

task.defer(function()
  if hooksOk then
    aviso("Koala Vôlei v2", "Carregado! RightControl abre/fecha o menu.", 5)
  else
    aviso("Koala Vôlei v2", "Carregado (hooks indisponíveis — assistências desligadas).", 6)
  end
end)
