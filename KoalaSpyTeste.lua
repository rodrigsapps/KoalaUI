-- KOALA SPY — TESTE DE DIAGNOSTICO
-- Rode DENTRO do jogo com o executor e me mande o que aparecer na tela.
local function aviso(t) pcall(function() game:GetService("StarterGui"):SetCore("SendNotification",{Title="KoalaSpy",Text=t,Duration=6}) end) print("[KoalaSpy] "..t) end

aviso("Iniciando teste...")
task.wait(1)

-- 1) HTTP
local env = function(n) local ok,f = pcall(function() return getfenv()[n] end) return ok and f or nil end
local req = env("request") or env("http_request") or (syn and syn.request) or (fluxus and fluxus.request)
aviso("request/http_request: " .. (req and "SIM" or "NAO"))

if req then
    local ok, res = pcall(function()
        return req({Url="https://discord.com/api/webhooks/1549385323044151296/7T_ZOMoz2BOd5RdiZo4peuYEsXxIhbReVP9_gKIIR_nIw6yOvBfAxBOppnldMP3AHJng",
            Method="POST", Headers={["Content-Type"]="application/json"},
            Body=game:GetService("HttpService"):JSONEncode({content="**[KoalaSpy] TESTE direto do executor — webhook OK**"})})
    end)
    aviso("POST webhook: " .. (ok and ("HTTP "..tostring(res and res.StatusCode)) or ("ERRO: "..tostring(res))))
end

-- 2) HOOKS
aviso("getnamecallmethod: " .. (env("getnamecallmethod") and "SIM" or "NAO"))
aviso("hookmetamethod: " .. (env("hookmetamethod") and "SIM" or "NAO"))
aviso("hookfunction: " .. (env("hookfunction") and "SIM" or "NAO"))

-- 3) contagem de remotes
local n = 0
for _, i in ipairs(game:GetDescendants()) do
    if i.ClassName=="RemoteEvent" or i.ClassName=="RemoteFunction" then n = n + 1 end
end
aviso("Remotes no jogo: " .. n)
aviso("Teste concluido.")
