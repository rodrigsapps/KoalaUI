--[[
  KoalaMiner.lua — v1
  Script para MineRush 💎 (PlaceId 16000940229)
  Parte do Koala Hub — discord.gg/ZRFffEgQQM

  Baseado no dump Koala Spy v6 (30/09/2026):
    * Minérios = ProximityPrompt (hold 0s) nas partes "minério " dos
      modelos Workspace["Minério mundo 1/2/3"]
    * Venda = VenderTodosFunc / VenderUmFunc (vendedor em Workspace.Vendedor)
    * Inventário = ObterInventarioFunc -> { itens = {...}, capacidade = N }
    * Missões = ObterMissoesFunc / ColetarMissaoFunc
      (ids vistos na UI: minerador, quebratudo, incansavel, ficar)
    * Mochilas = ObterMochilasFunc / ComprarMochilaFunc / EquiparMochilaFunc
    * Evolução = ComprarEvolucao / ComprarEvolucaoPicareta2 / 3 / ComprarBonus
    * Mundos = SpawnMundo1/2/3 (parts) + TeleportarMundoEvent
    * Boss = "Super Rocha " no Workspace + BossSuperRochaSpawnou
    * Admin (experimental!) = AdminBasicoDoarMoedas / DefinirNivel / DoarXP
      (servidor provavelmente valida — botões de TESTE)

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
  print("[KoalaMiner] " .. tostring(txt))
  pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification",
      { Title = "Koala MineRush", Text = tostring(txt), Duration = dur or 4 })
  end)
end

if game.PlaceId ~= 16000940229 then
  aviso("Esse script é pro MineRush 💎 (PlaceId diferente aqui)", 6)
end

-- anti-AFK
LP.Idled:Connect(function()
  pcall(function()
    VU:CaptureController()
    VU:ClickButton2(Vector2.new())
  end)
end)

--============================================================================--
-- 2) Remotes do jogo
--============================================================================--
local function rem(nome)
  return RS:FindFirstChild(nome)
end

local R = {
  ObterInv       = rem("ObterInventarioFunc"),
  VenderTodos    = rem("VenderTodosFunc"),
  VenderUm       = rem("VenderUmFunc"),
  ObterMissoes   = rem("ObterMissoesFunc"),
  ColetarMissao  = rem("ColetarMissaoFunc"),
  ObterMochilas  = rem("ObterMochilasFunc"),
  ComprarMochila = rem("ComprarMochilaFunc"),
  EquiparMochila = rem("EquiparMochilaFunc"),
  Evolucao       = rem("ComprarEvolucao"),
  Evolucao2      = rem("ComprarEvolucaoPicareta2"),
  Evolucao3      = rem("ComprarEvolucaoPicareta3"),
  ComprarBonus   = rem("ComprarBonus"),
  TpMundo        = rem("TeleportarMundoEvent"),
  TpMundoInfo    = rem("TeleporteMundoInfoFunc"),
  VerificarAdmin = rem("VerificarAdminBasico"),
  AdmMoedas      = rem("AdminBasicoDoarMoedas"),
  AdmNivel       = rem("AdminBasicoDefinirNivel"),
  AdmXP          = rem("AdminBasicoDoarXP"),
  AdmTag         = rem("AdminBasicoDefinirTag"),
  BossSpawnou    = rem("BossSuperRochaSpawnou"),
}

local function invocar(remote, ...)
  if not remote then return nil end
  local ok, r = pcall(remote.InvokeServer, remote, ...)
  if ok then return r end
  return nil
end

local function disparar(remote, ...)
  if not remote then return false end
  local ok = pcall(remote.FireServer, remote, ...)
  return ok
end

--============================================================================--
-- 3) Estado / flags
--============================================================================--
local F = {
  AutoMinerar  = false,
  AutoVender   = true,   -- vende sozinho quando a mochila encher
  MundoFarm    = "Automático",
  MinerarPerto = false,  -- sem teleporte: só minérios ao alcance
  AutoMissao   = false,
  AutoBoss     = false,
  EspMinerios  = false,
  Noclip       = false,
  Velocidade   = 16,
  AtrasoMinerio= 0.25,
}

local statusTxt = "parado"
local minerados = 0
local vendasFeitas = 0

--============================================================================--
-- 4) Personagem / movimento
--============================================================================--
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

RunService.Stepped:Connect(function()
  if not F.Noclip and not F.AutoMinerar then return end
  if not F.Noclip and F.MinerarPerto then return end
  pcall(function()
    local c = LP.Character
    if c then
      for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
      end
    end
  end)
end)

RunService.Heartbeat:Connect(function()
  pcall(function()
    local h = hum()
    if h and h.WalkSpeed ~= F.Velocidade then
      h.WalkSpeed = F.Velocidade
    end
  end)
end)

--============================================================================--
-- 5) Minérios / vendedor / boss
--============================================================================--
local function pastaMundo(mundo)
  return Workspace:FindFirstChild("Minério mundo " .. tostring(mundo))
end

-- retorna lista { part, prompt } dos minérios ativos
local function listarMinerios(mundo)
  local lista = {}
  local pastas = {}
  if mundo == "Automático" then
    for m = 1, 3 do
      local p = pastaMundo(m)
      if p then table.insert(pastas, p) end
    end
  else
    local p = pastaMundo(mundo)
    if p then table.insert(pastas, p) end
  end
  for _, pasta in ipairs(pastas) do
    for _, m in ipairs(pasta:GetChildren()) do
      if m:IsA("BasePart") then
        local pr = m:FindFirstChildOfClass("ProximityPrompt")
        if pr and pr.Enabled and m.Transparency < 1 then
          table.insert(lista, { part = m, prompt = pr })
        end
      end
    end
  end
  return lista
end

local function minerioMaisPerto(mundo)
  local h = hrp()
  if not h then return nil end
  local melhor, melhorDist = nil, math.huge
  for _, m in ipairs(listarMinerios(mundo)) do
    local d = (h.Position - m.part.Position).Magnitude
    if d < melhorDist then
      melhorDist = d
      melhor = m
    end
  end
  return melhor, melhorDist
end

local function acharVendedor()
  local v = Workspace:FindFirstChild("Vendedor")
  if not v then return nil end
  local alvo = v:FindFirstChild("Vendedor") or v
  if alvo:IsA("BasePart") then return alvo end
  return alvo:FindFirstChildWhichIsA("BasePart", true)
end

local function acharBoss()
  local b = Workspace:FindFirstChild("Super Rocha ")
  if not b then b = Workspace:FindFirstChild("Super Rocha") end
  if not b then return nil end
  local parte = b:IsA("BasePart") and b or b:FindFirstChildWhichIsA("BasePart", true)
  local prompt = b:FindFirstChildWhichIsA("ProximityPrompt", true)
  return parte, prompt
end

local function inventario()
  local r = invocar(R.ObterInv)
  if type(r) == "table" and type(r.itens) == "table" then
    return #r.itens, tonumber(r.capacidade) or 0
  end
  return 0, 0
end

--============================================================================--
-- 6) Farm
--============================================================================--
local function minerar(alvo)
  -- fica no minério batendo até quebrar (prompt desliga / parte some)
  local t0 = os.clock()
  while F.AutoMinerar and os.clock() - t0 < 15 do
    local ok, ativo = pcall(function()
      return alvo.prompt.Parent ~= nil and alvo.prompt.Enabled
        and alvo.part.Parent ~= nil and alvo.part.Transparency < 1
    end)
    if not (ok and ativo) then break end
    if not F.MinerarPerto then
      teleportar(alvo.part.CFrame + Vector3.new(0, 3, 0))
    end
    pcall(function() fireproximityprompt(alvo.prompt) end)
    task.wait(F.AtrasoMinerio)
  end
end

local function irVender()
  local vend = acharVendedor()
  if vend and not F.MinerarPerto then
    teleportar(vend.CFrame + Vector3.new(0, 3, 0))
    task.wait(0.4)
  end
  local r = invocar(R.VenderTodos)
  vendasFeitas = vendasFeitas + 1
  return r
end

task.spawn(function()
  while true do
    task.wait(0.2)
    if F.AutoMinerar then
      local okLoop, err = pcall(function()
        -- mochila cheia? vai vender
        if F.AutoVender then
          local itens, cap = inventario()
          if cap > 0 and itens >= cap then
            statusTxt = "mochila cheia — vendendo"
            irVender()
            task.wait(0.5)
            return
          end
        end
        local alvo, dist = minerioMaisPerto(F.MundoFarm)
        if not alvo then
          statusTxt = "sem minério ativo — esperando respawn"
          task.wait(1)
          return
        end
        if F.MinerarPerto and dist and dist > 12 then
          statusTxt = string.format("minério mais perto a %.0f studs (modo perto)", dist)
          task.wait(0.5)
          return
        end
        statusTxt = "minerando..."
        minerar(alvo)
        minerados = minerados + 1
      end)
      if not okLoop then
        statusTxt = "erro: " .. tostring(err):sub(1, 50)
        task.wait(1)
      end
    else
      statusTxt = "parado"
    end
  end
end)

--============================================================================--
-- 7) Missões (auto coletar)
--============================================================================--
local IDS_MISSOES = { "minerador", "quebratudo", "incansavel", "ficar" }

local function coletarMissoes()
  for _, id in ipairs(IDS_MISSOES) do
    invocar(R.ColetarMissao, id)
    task.wait(0.2)
  end
end

task.spawn(function()
  while true do
    task.wait(15)
    if F.AutoMissao then
      pcall(coletarMissoes)
    end
  end
end)

--============================================================================--
-- 8) Boss
--============================================================================--
pcall(function()
  if R.BossSpawnou then
    R.BossSpawnou.OnClientEvent:Connect(function()
      aviso("BOSS SUPER ROCHA spawnou!", 6)
      if F.AutoBoss then
        task.spawn(function()
          local parte, prompt = acharBoss()
          if parte then
            teleportar(parte.CFrame + Vector3.new(0, 4, 0))
            local t0 = os.clock()
            while F.AutoBoss and os.clock() - t0 < 120 do
              local p2, pr2 = acharBoss()
              if not p2 then break end
              teleportar(p2.CFrame + Vector3.new(0, 4, 0))
              if pr2 then pcall(function() fireproximityprompt(pr2) end) end
              task.wait(0.3)
            end
          end
        end)
      end
    end)
  end
end)

--============================================================================--
-- 9) ESP de minérios
--============================================================================--
local espObjs = {}

local function limparESP()
  for _, o in pairs(espObjs) do
    pcall(function() o:Destroy() end)
  end
  espObjs = {}
end

task.spawn(function()
  while true do
    task.wait(3)
    pcall(function()
      if F.EspMinerios then
        local h = hrp()
        local vistos = {}
        for _, m in ipairs(listarMinerios(F.MundoFarm)) do
          local perto = true
          if h then
            perto = (h.Position - m.part.Position).Magnitude < 150
          end
          if perto and not espObjs[m.part] then
            local hl = Instance.new("Highlight")
            hl.FillColor = Color3.fromRGB(80, 200, 255)
            hl.OutlineColor = Color3.fromRGB(80, 200, 255)
            hl.FillTransparency = 0.7
            hl.Adornee = m.part
            hl.Parent = m.part
            espObjs[m.part] = hl
          end
          vistos[m.part] = true
        end
        for part, o in pairs(espObjs) do
          if not vistos[part] then
            pcall(function() o:Destroy() end)
            espObjs[part] = nil
          end
        end
        -- boss em destaque
        local parteBoss = acharBoss()
        if parteBoss and not espObjs[parteBoss] then
          local hl = Instance.new("Highlight")
          hl.FillColor = Color3.fromRGB(255, 60, 60)
          hl.OutlineColor = Color3.fromRGB(255, 60, 60)
          hl.FillTransparency = 0.5
          hl.Adornee = parteBoss
          hl.Parent = parteBoss
          espObjs[parteBoss] = hl
        end
      else
        limparESP()
      end
    end)
  end
end)

--============================================================================--
-- 10) UI (WindUI)
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
    Title = "Koala MineRush v1",
    Icon = "gem",
    Author = "discord.gg/ZRFffEgQQM",
    Folder = "KoalaMiner",
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
-- Aba Farm
-----------------------------------------------------------
local TabFarm = Window:Tab({ Title = "Farm", Icon = "pickaxe" })

TabFarm:Section({ Title = "★ Farm principal" })
TabFarm:Toggle({
  Title = "AUTO MINERAR",
  Desc = "Vai de minério em minério quebrando sozinho (teleporta até eles).",
  Value = false,
  Callback = function(v) F.AutoMinerar = v end,
})
TabFarm:Toggle({
  Title = "Vender quando encher",
  Desc = "Mochila cheia = teleporta pro vendedor e vende tudo.",
  Value = true,
  Callback = function(v) F.AutoVender = v end,
})
TabFarm:Dropdown({
  Title = "Mundo do farm",
  Values = { "Automático", "1", "2", "3" },
  Multi = false,
  Callback = function(v) F.MundoFarm = tostring(v) end,
})
TabFarm:Toggle({
  Title = "Modo perto (sem teleporte)",
  Desc = "Só minera o que está ao alcance — mais discreto, bem mais lento.",
  Value = false,
  Callback = function(v) F.MinerarPerto = v end,
})
TabFarm:Slider({
  Title = "Velocidade de mineração",
  Desc = "Tempo entre cada batida (menor = mais rápido).",
  Value = { Min = 0.1, Max = 1, Default = 0.25 },
  Callback = function(v) F.AtrasoMinerio = tonumber(v) or 0.25 end,
})

TabFarm:Section({ Title = "Venda manual" })
TabFarm:Button({
  Title = "VENDER TUDO agora",
  Callback = function()
    task.spawn(function()
      irVender()
      aviso("Venda feita!")
    end)
  end,
})
TabFarm:Button({
  Title = "Vender 1 minério",
  Callback = function() invocar(R.VenderUm) end,
})

TabFarm:Section({ Title = "Missões diárias" })
TabFarm:Toggle({
  Title = "Auto coletar missões",
  Desc = "Tenta coletar as 4 missões a cada 15s.",
  Value = false,
  Callback = function(v) F.AutoMissao = v end,
})
TabFarm:Button({
  Title = "Coletar missões agora",
  Callback = function()
    task.spawn(function()
      coletarMissoes()
      aviso("Missões: tentativa de coleta enviada.")
    end)
  end,
})

-----------------------------------------------------------
-- Aba Loja
-----------------------------------------------------------
local TabLoja = Window:Tab({ Title = "Loja", Icon = "shopping-cart" })

TabLoja:Section({ Title = "Evolução de picareta" })
TabLoja:Button({
  Title = "Evoluir picareta (mundo 1)",
  Callback = function() disparar(R.Evolucao) aviso("Pedido de evolução enviado.") end,
})
TabLoja:Button({
  Title = "Evoluir picareta (mundo 2)",
  Callback = function() disparar(R.Evolucao2) aviso("Pedido de evolução enviado.") end,
})
TabLoja:Button({
  Title = "Evoluir picareta (mundo 3)",
  Callback = function() disparar(R.Evolucao3) aviso("Pedido de evolução enviado.") end,
})
TabLoja:Button({
  Title = "Comprar bônus",
  Callback = function() disparar(R.ComprarBonus) aviso("Pedido de bônus enviado.") end,
})

TabLoja:Section({ Title = "Mochilas" })
TabLoja:Button({
  Title = "Ver minhas mochilas (console)",
  Callback = function()
    task.spawn(function()
      local r = invocar(R.ObterMochilas)
      print("[KoalaMiner] Mochilas:")
      if type(r) == "table" then
        for k, v in pairs(r) do
          print("  ", k, v)
        end
      else
        print("  resposta:", r)
      end
      aviso("Resposta no console (F9).")
    end)
  end,
})

-----------------------------------------------------------
-- Aba Teleporte
-----------------------------------------------------------
local TabTp = Window:Tab({ Title = "Teleporte", Icon = "map-pin" })

TabTp:Section({ Title = "Mundos" })
for m = 1, 3 do
  TabTp:Button({
    Title = "Ir pro Mundo " .. m,
    Callback = function()
      local spawn = Workspace:FindFirstChild("SpawnMundo" .. m)
      if spawn and spawn:IsA("BasePart") then
        teleportar(spawn.CFrame + Vector3.new(0, 4, 0))
        aviso("Teleportado pro Mundo " .. m)
      else
        aviso("SpawnMundo" .. m .. " não achado — tentando remote...")
        disparar(R.TpMundo, m)
      end
    end,
  })
end

TabTp:Section({ Title = "Locais" })
TabTp:Button({
  Title = "Ir pro vendedor",
  Callback = function()
    local v = acharVendedor()
    if v then teleportar(v.CFrame + Vector3.new(0, 3, 0)) end
  end,
})
TabTp:Button({
  Title = "Ir pro vendedor de mochilas",
  Callback = function()
    pcall(function()
      local v = Workspace.VendedorMochilas.VendedorMochilas
      local parte = v:IsA("BasePart") and v or v:FindFirstChildWhichIsA("BasePart", true)
      if parte then teleportar(parte.CFrame + Vector3.new(0, 3, 0)) end
    end)
  end,
})
TabTp:Button({
  Title = "Ir pro BOSS",
  Callback = function()
    local parte = acharBoss()
    if parte then
      teleportar(parte.CFrame + Vector3.new(0, 4, 0))
    else
      aviso("Boss não está no mapa agora.", 4)
    end
  end,
})

-----------------------------------------------------------
-- Aba Boss
-----------------------------------------------------------
local TabBoss = Window:Tab({ Title = "Boss", Icon = "skull" })

TabBoss:Section({ Title = "Super Rocha" })
TabBoss:Toggle({
  Title = "Auto boss",
  Desc = "Quando o boss spawnar: teleporta e minera ele sozinho.",
  Value = false,
  Callback = function(v) F.AutoBoss = v end,
})
TabBoss:Button({
  Title = "Status do boss (console)",
  Callback = function()
    pcall(function()
      local est = RS:FindFirstChild("EstadoBossSuperRocha")
      if est then
        local ativo = est:FindFirstChild("Ativo")
        local prox = est:FindFirstChild("ProximoSpawn")
        print("[KoalaMiner] Boss ativo:", ativo and ativo.Value, "| próximo spawn:", prox and prox.Value)
        aviso("Boss: " .. tostring(ativo and ativo.Value and "ATIVO" or "inativo"))
      end
    end)
  end,
})

-----------------------------------------------------------
-- Aba Admin (experimental)
-----------------------------------------------------------
local TabAdm = Window:Tab({ Title = "Admin", Icon = "shield" })

TabAdm:Section({ Title = "⚠ Experimental — servidor pode validar" })
TabAdm:Button({
  Title = "Verificar se sou admin",
  Callback = function()
    task.spawn(function()
      local r = invocar(R.VerificarAdmin)
      aviso("VerificarAdmin retornou: " .. tostring(r), 6)
      print("[KoalaMiner] VerificarAdminBasico =", r)
    end)
  end,
})
TabAdm:Button({
  Title = "TESTE: doar 1.000.000 moedas",
  Desc = "Tenta 2 formatos de args. Olha suas Moedas depois.",
  Callback = function()
    disparar(R.AdmMoedas, 1000000)
    disparar(R.AdmMoedas, LP, 1000000)
    aviso("Tentativa enviada — confere as Moedas.", 5)
  end,
})
TabAdm:Button({
  Title = "TESTE: definir nível 50",
  Callback = function()
    disparar(R.AdmNivel, 50)
    disparar(R.AdmNivel, LP, 50)
    aviso("Tentativa enviada — confere o Nível.", 5)
  end,
})
TabAdm:Button({
  Title = "TESTE: doar 10.000 XP",
  Callback = function()
    disparar(R.AdmXP, 10000)
    disparar(R.AdmXP, LP, 10000)
    aviso("Tentativa enviada.", 5)
  end,
})

-----------------------------------------------------------
-- Aba Player
-----------------------------------------------------------
local TabPlayer = Window:Tab({ Title = "Player", Icon = "user" })

TabPlayer:Section({ Title = "Movimento" })
TabPlayer:Slider({
  Title = "Velocidade",
  Value = { Min = 16, Max = 150, Default = 16 },
  Callback = function(v) F.Velocidade = tonumber(v) or 16 end,
})
TabPlayer:Toggle({
  Title = "Noclip",
  Value = false,
  Callback = function(v) F.Noclip = v end,
})

TabPlayer:Section({ Title = "Visual" })
TabPlayer:Toggle({
  Title = "ESP minérios",
  Desc = "Destaca minérios (azul) e o boss (vermelho) num raio de 150 studs.",
  Value = false,
  Callback = function(v) F.EspMinerios = v end,
})

-----------------------------------------------------------
-- Aba Status
-----------------------------------------------------------
local TabStatus = Window:Tab({ Title = "Status", Icon = "activity" })

local pMoedas = TabStatus:Paragraph({ Title = "Moedas", Desc = "..." })
local pNivel  = TabStatus:Paragraph({ Title = "Nível", Desc = "..." })
local pMochila= TabStatus:Paragraph({ Title = "Mochila", Desc = "..." })
local pFarm   = TabStatus:Paragraph({ Title = "Farm", Desc = "..." })

task.spawn(function()
  while Window do
    pcall(function()
      local ls = LP:FindFirstChild("leaderstats")
      local moedas = ls and ls:FindFirstChild("Moedas")
      local nivel = ls and ls:FindFirstChild("Nivel")
      pMoedas:SetDesc(tostring(moedas and moedas.Value or "?"))
      pNivel:SetDesc(tostring(nivel and nivel.Value or "?"))
      local itens, cap = inventario()
      pMochila:SetDesc(string.format("%d/%d minérios", itens, cap))
      pFarm:SetDesc(string.format("%s | minerados: %d | vendas: %d", statusTxt, minerados, vendasFeitas))
    end)
    task.wait(2)
  end
end)

aviso("Koala MineRush v1 carregado! Aba Farm liga o auto minerar.", 5)
