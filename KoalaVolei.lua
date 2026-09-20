--[[
  KoalaVolei.lua — v1
  Script para [UPD] Lendas do Vôlei / Volleyball Legends (PlaceId 73956553001240)
  Parte do Koala Hub — discord.gg/ZRFffEgQQM
  Framework do jogo: Knit (ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"].knit.Services)
  ATENÇÃO: uso por sua conta e risco. Hitbox/auto-receive alteram detecção de toque na bola.
]]

local BASE = "https://raw.githubusercontent.com/rodrigsapps/KoalaUI/main/"
local function aviso(t, txt, dur)
  pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {Title = t, Text = txt, Duration = dur or 4})
  end)
end

local okUI, Koala = pcall(function()
  return loadstring(game:HttpGet(BASE .. "KoalaUI_v3.lua"))()
end)
if not okUI or not Koala then
  aviso("KoalaVôlei", "Falha ao carregar a UI. Verifique a internet.", 6)
  return
end

--============================================================================--
-- Serviços e atalhos
--============================================================================--
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local VU         = game:GetService("VirtualUser")
local LP         = Players.LocalPlayer
local Camera     = Workspace.CurrentCamera

local function esperarCaminho(root, ...)
  local atual = root
  for _, nome in ipairs({...}) do
    if not atual then return nil end
    atual = atual:WaitForChild(nome, 10)
  end
  return atual
end

local Services = esperarCaminho(RS, "Packages", "_Index", "sleitnick_knit@1.7.0", "knit", "Services")
if not Services then
  aviso("KoalaVôlei", "Serviços do jogo não encontrados. Entre no jogo primeiro.", 6)
  return
end

local function rf(servico, nome)
  local ok, s = pcall(function() return Services:WaitForChild(servico, 5) end)
  if not ok or not s then return nil end
  local pasta = s:FindFirstChild("RF")
  return pasta and pasta:FindFirstChild(nome) or nil
end
local function re(servico, nome)
  local ok, s = pcall(function() return Services:WaitForChild(servico, 5) end)
  if not ok or not s then return nil end
  local pasta = s:FindFirstChild("RE")
  return pasta and pasta:FindFirstChild(nome) or nil
end
local function invocar(remote, ...)
  if not remote then return nil end
  local ok, r = pcall(function(...) return remote:InvokeServer(...) end, ...)
  return ok and r or nil
end

--============================================================================--
-- Estado
--============================================================================--
local F = {
  Hitbox       = false,
  HitboxMult   = 3,
  PingComp     = true,
  AutoReceive  = false,
  RedirectCorte= false,
  CargaMax     = false,
  CorteMudo    = false,
  AutoEstilo   = false,
  AlvoEstilo   = "",
  AutoHab      = false,
  AlvoHab      = "",
  Speed        = false,
  SpeedVal     = 16,
}

local function pingSegundos()
  local ok, item = pcall(function()
    return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
  end)
  if ok and type(item) == "number" then return item / 1000 end
  return 0.05
end

local function bolaAtual()
  for _, m in ipairs(Workspace:GetChildren()) do
    if m.Name:sub(1, 12) == "CLIENT_BALL_" then
      return m:GetAttribute("Id"), m
    end
  end
  return nil, nil
end

local function attrEstilo()  return LP:GetAttribute("Gameplay_Style")   or "?" end
local function attrHab()     return LP:GetAttribute("Gameplay_Ability") or "?" end
local function attrNivel()   return LP:GetAttribute("User_Level")       or 0  end
local function attrCarga()   return LP:GetAttribute("Ability_Charge")   or 0  end

--============================================================================--
-- Listas de estilos/habilidades (direto do jogo)
--============================================================================--
local function listarConteudo(pasta)
  local nomes = {}
  local p = RS:FindFirstChild("Content") and RS.Content:FindFirstChild(pasta)
  if p then
    for _, m in ipairs(p:GetChildren()) do
      table.insert(nomes, m.Name)
    end
    table.sort(nomes)
  end
  if #nomes == 0 then nomes = { "(nenhum encontrado)" } end
  return nomes
end

--============================================================================--
-- UI
--============================================================================--
local Window = Koala:CreateWindow({
  Title = "Koala Vôlei",
  Icon = "volleyball",
  Author = "discord.gg/ZRFffEgQQM",
  Folder = "KoalaVolei",
  Size = UDim2.fromOffset(580, 460),
  Theme = "Dark",
  ToggleKey = Enum.KeyCode.RightControl,
})

-----------------------------------------------------------
-- Aba Jogo
-----------------------------------------------------------
local TabJogo = Window:Tab({ Title = "Jogo", Icon = "volleyball" })

TabJogo:Section({ Title = "Hitbox da bola" })
TabJogo:Toggle({
  Title = "Hitbox expandida",
  Desc = "Cria uma zona de toque maior na bola (só no seu cliente).",
  Value = false,
  Callback = function(v) F.Hitbox = v end,
})
TabJogo:Slider({
  Title = "Tamanho da hitbox",
  Desc = "Multiplicador do tamanho (1 = normal).",
  Value = { Min = 1, Max = 10, Default = 3 },
  Callback = function(v) F.HitboxMult = tonumber(v) or 3 end,
})
TabJogo:Toggle({
  Title = "Compensar ping",
  Desc = "Aumenta um pouco a hitbox conforme sua latência.",
  Value = true,
  Callback = function(v) F.PingComp = v end,
})

TabJogo:Section({ Title = "Corte / Recepção" })
TabJogo:Toggle({
  Title = "Auto recepção",
  Desc = "Tenta receber/levantar automaticamente bolas difíceis.",
  Value = false,
  Callback = function(v) F.AutoReceive = v end,
})
TabJogo:Toggle({
  Title = "Corte na mira",
  Desc = "Redireciona o corte para onde a câmera aponta.",
  Value = false,
  Callback = function(v) F.RedirectCorte = v end,
})
TabJogo:Toggle({
  Title = "Carga máxima no corte",
  Desc = "Força carga 100% (normal e especial) em todo corte.",
  Value = false,
  Callback = function(v) F.CargaMax = v end,
})
TabJogo:Toggle({
  Title = "Corte sem animação",
  Desc = "Corta sem tocar a animação (mais rápido, mais suspeito).",
  Value = false,
  Callback = function(v) F.CorteMudo = v end,
})

-----------------------------------------------------------
-- Aba Spins
-----------------------------------------------------------
local TabSpins = Window:Tab({ Title = "Spins", Icon = "dices" })

local ddEstilo
TabSpins:Section({ Title = "Estilo" })
ddEstilo = TabSpins:Dropdown({
  Title = "Estilo alvo",
  Values = listarConteudo("Style"),
  Value = "...",
  Multi = false,
  Callback = function(v) F.AlvoEstilo = v end,
})
TabSpins:Button({
  Title = "Atualizar lista de estilos",
  Callback = function()
    pcall(function() ddEstilo:Refresh(listarConteudo("Style")) end)
  end,
})
TabSpins:Toggle({
  Title = "Auto girar estilo",
  Desc = "Gira até conseguir o estilo alvo (usa seus spins).",
  Value = false,
  Callback = function(v) F.AutoEstilo = v end,
})

local ddHab
TabSpins:Section({ Title = "Habilidade" })
ddHab = TabSpins:Dropdown({
  Title = "Habilidade alvo",
  Values = listarConteudo("Ability"),
  Value = "...",
  Multi = false,
  Callback = function(v) F.AlvoHab = v end,
})
TabSpins:Toggle({
  Title = "Auto girar habilidade",
  Desc = "Gira até conseguir a habilidade alvo.",
  Value = false,
  Callback = function(v) F.AutoHab = v end,
})

TabSpins:Section({ Title = "Recompensas e packs" })
TabSpins:Button({
  Title = "Resgatar recompensas de nível",
  Callback = function()
    invocar(rf("LevelService", "ClaimLevelRewards"))
    aviso("KoalaVôlei", "Recompensas de nível solicitadas.")
  end,
})
TabSpins:Button({
  Title = "Resgatar todas as missões",
  Callback = function()
    invocar(rf("QuestService", "ClaimAll"), true)
    aviso("KoalaVôlei", "Missões resgatadas.")
  end,
})
TabSpins:Button({
  Title = "Abrir pack Básico",
  Callback = function() invocar(rf("PackService", "Open"), "Basic") end,
})
TabSpins:Button({
  Title = "Abrir pack Médio",
  Callback = function() invocar(rf("PackService", "Open"), "Medium") end,
})
TabSpins:Button({
  Title = "Abrir pack Extremo",
  Callback = function() invocar(rf("PackService", "Open"), "Extreme") end,
})

TabSpins:Section({ Title = "Códigos" })
local codigoDigitado = ""
pcall(function()
  TabSpins:Input({
    Title = "Código",
    Placeholder = "digite o código aqui",
    Callback = function(t) codigoDigitado = tostring(t or "") end,
  })
end)
TabSpins:Button({
  Title = "Resgatar código",
  Callback = function()
    if codigoDigitado == "" then aviso("KoalaVôlei", "Digite um código primeiro.") return end
    local r = invocar(rf("CodeService", "Redeem"), codigoDigitado)
    aviso("KoalaVôlei", "Código enviado: " .. codigoDigitado)
  end,
})

-----------------------------------------------------------
-- Aba Movimento
-----------------------------------------------------------
local TabMov = Window:Tab({ Title = "Movimento", Icon = "move" })

TabMov:Section({ Title = "Teletransporte" })
TabMov:Button({
  Title = "Ir para Treino",
  Callback = function()
    invocar(rf("PartyService", "RequestTeleport"), "Training")
    aviso("KoalaVôlei", "Teleporte para Treino solicitado.")
  end,
})
TabMov:Button({
  Title = "Ir para 2v2",
  Callback = function()
    invocar(rf("PartyService", "RequestTeleport"), "Twos")
    aviso("KoalaVôlei", "Teleporte para 2v2 solicitado.")
  end,
})
TabMov:Button({
  Title = "Voltar ao lobby",
  Callback = function()
    invocar(rf("GameService", "ReturnPartyToLobby"), true)
    aviso("KoalaVôlei", "Retorno ao lobby solicitado.")
  end,
})

TabMov:Section({ Title = "Velocidade" })
TabMov:Toggle({
  Title = "Speed",
  Value = false,
  Callback = function(v) F.Speed = v end,
})
TabMov:Slider({
  Title = "Velocidade",
  Value = { Min = 16, Max = 100, Default = 16 },
  Callback = function(v) F.SpeedVal = tonumber(v) or 16 end,
})

-----------------------------------------------------------
-- Aba Status
-----------------------------------------------------------
local TabStatus = Window:Tab({ Title = "Status", Icon = "activity" })

local parStatus = TabStatus:Paragraph({ Title = "Jogador", Desc = "Carregando..." })
local parJogo   = TabStatus:Paragraph({ Title = "Partida", Desc = "Carregando..." })

TabStatus:Section({ Title = "Sobre" })
TabStatus:Paragraph({
  Title = "Koala Vôlei v1",
  Desc = "Feito para [UPD] Lendas do Vôlei. Funções de hitbox e corte mexem com a detecção da bola — use com moderação para não chamar atenção.",
})

--============================================================================--
-- Lógica: Hitbox
--============================================================================--
local ultimoTickHitbox = 0
RunService.Heartbeat:Connect(function()
  if not F.Hitbox then return end
  local agora = tick()
  if agora - ultimoTickHitbox < 0.1 then return end
  ultimoTickHitbox = agora
  pcall(function()
    local extra = 0
    if F.PingComp then extra = math.clamp(pingSegundos() / 10, 0, 0.15) end
    for _, m in ipairs(Workspace:GetChildren()) do
      if m.Name:sub(1, 12) == "CLIENT_BALL_" then
        local hb = m:FindFirstChild("HitBox")
        if not hb then
          hb = Instance.new("Part")
          hb.Name = "HitBox"
          hb.Shape = Enum.PartType.Ball
          hb.Anchored = true
          hb.CanCollide = false
          hb.CanTouch = true
          hb.CanQuery = false
          hb.Transparency = 1
          hb.Parent = m
        end
        local bola = m:FindFirstChild("Ball.1") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
        if bola then
          local base = math.max(bola.Size.X, bola.Size.Y, bola.Size.Z)
          hb.Size = Vector3.new(1, 1, 1) * (base * F.HitboxMult + extra)
          hb.CFrame = bola.CFrame
        end
      end
    end
  end)
end)

--============================================================================--
-- Lógica: Speed (loop)
--============================================================================--
task.spawn(function()
  while true do
    task.wait(0.2)
    if F.Speed then
      pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.WalkSpeed ~= F.SpeedVal then hum.WalkSpeed = F.SpeedVal end
      end)
    end
  end
end)

--============================================================================--
-- Lógica: Auto spins
--============================================================================--
task.spawn(function()
  while true do
    task.wait(0.7)
    if F.AutoEstilo and F.AlvoEstilo ~= "" and F.AlvoEstilo ~= "..." then
      if attrEstilo() == F.AlvoEstilo then
        F.AutoEstilo = false
        aviso("KoalaVôlei", "Conseguiu o estilo: " .. F.AlvoEstilo, 5)
      else
        invocar(rf("StyleService", "Roll"), true)
      end
    end
    if F.AutoHab and F.AlvoHab ~= "" and F.AlvoHab ~= "..." then
      if attrHab() == F.AlvoHab then
        F.AutoHab = false
        aviso("KoalaVôlei", "Conseguiu a habilidade: " .. F.AlvoHab, 5)
      else
        invocar(rf("AbilityService", "Roll"), true)
      end
    end
  end
end)

--============================================================================--
-- Lógica: Status ao vivo
--============================================================================--
task.spawn(function()
  while true do
    task.wait(1)
    pcall(function()
      parStatus:SetDesc(string.format(
        "Estilo: %s  |  Habilidade: %s\nNível: %s  |  Carga: %s",
        tostring(attrEstilo()), tostring(attrHab()), tostring(attrNivel()), tostring(attrCarga())
      ))
    end)
    pcall(function()
      local id = bolaAtual()
      parJogo:SetDesc(string.format(
        "Bola em jogo: %s  |  Último toque: %s (%s)\nSequência do time: %s  |  Bola: %s",
        tostring(RS:GetAttribute("IsBallInPlay")),
        tostring(RS:GetAttribute("LastHitter")),
        tostring(RS:GetAttribute("LastHitType")),
        tostring(RS:GetAttribute("TeamHitStreak")),
        tostring(id or "nenhuma")
      ))
    end)
  end
end)

--============================================================================--
-- Hooks (auto recepção, corte na mira, carga máx, corte mudo)
--============================================================================--
local hooksOk = false
if typeof(hookmetamethod) == "function" and typeof(getnamecallmethod) == "function" then
  hooksOk = pcall(function()
    local velho
    velho = hookmetamethod(game, "__namecall", function(self, ...)
      local metodo = getnamecallmethod()
      local args = { ... }

      if not checkcaller() and typeof(self) == "Instance" and metodo == "InvokeServer" then
        local nome = self.Name
        local pai = self.Parent and self.Parent.Name
        local avo = self.Parent and self.Parent.Parent and self.Parent.Parent.Name

        -- BallService.RF.CreateHitbox → auto recepção
        if nome == "CreateHitbox" and pai == "RF" and avo == "BallService" and F.AutoReceive then
          local dados = args[1]
          if type(dados) == "table" then
            local ultimoTime = RS:GetAttribute("LastHitTeam")
            local sequencia = RS:GetAttribute("TeamHitStreak") or 0
            local meuTime = LP:GetAttribute("Team")
            local deveReceber = true
            if meuTime ~= nil and ultimoTime ~= nil then
              deveReceber = (ultimoTime ~= meuTime) or (sequencia < 3)
            end
            if deveReceber then
              local ping = pingSegundos()
              dados.ClientTimestamp = Workspace:GetServerTimeNow() - ping
              dados.Charge = math.max(tonumber(dados.Charge) or 0, 0.5)
              return velho(self, unpack(args))
            end
            return "Missed"
          end
        end

        -- BallService.RF.Interact → corte na mira / carga máx / corte mudo
        if nome == "Interact" and pai == "RF" and avo == "BallService" then
          local dados = args[1]
          if type(dados) == "table" and dados.Move == "Spike" then
            if F.CargaMax then
              dados.Charge = 1
              dados.SpecialCharge = 1
            end
            if F.RedirectCorte and Camera then
              dados.LookVector = Camera.CFrame.LookVector
              dados.TiltDirection = Camera.CFrame.LookVector
            end
            if F.CorteMudo then
              local doMove = re("BallService", "DoMove")
              if doMove then
                pcall(function()
                  doMove:FireServer("Spike", false, false, Camera and Camera.CFrame.LookVector or Vector3.zAxis)
                end)
              end
              return nil
            end
          end
        end
      end

      return velho(self, ...)
    end)
  end)
end

--============================================================================--
-- Anti-AFK
--============================================================================--
pcall(function()
  LP.Idled:Connect(function()
    VU:Button2Down(Vector2.new(0, 0), Camera.CFrame)
    task.wait(1)
    VU:Button2Up(Vector2.new(0, 0), Camera.CFrame)
  end)
end)

task.defer(function()
  if hooksOk then
    aviso("Koala Vôlei", "Carregado! RightControl abre/fecha o menu.", 5)
  else
    aviso("Koala Vôlei", "Carregado (hooks indisponíveis neste executor).", 5)
  end
end)
