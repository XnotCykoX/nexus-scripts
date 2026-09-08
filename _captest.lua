local function t() return tostring((pcall(function() local s=Instance.new("ScreenGui") s.Parent=game:GetService("Players").LocalPlayer.PlayerGui s:Destroy() end))) end
print("CAPTEST direct="..t())
task.defer(function() print("CAPTEST defer="..t()) end)
task.spawn(function() print("CAPTEST spawn="..t()) end)
game:GetService("RunService").Heartbeat:Once(function() print("CAPTEST heartbeat="..t()) end)
local co=coroutine.wrap(function() print("CAPTEST coroutine="..t()) end) co()
