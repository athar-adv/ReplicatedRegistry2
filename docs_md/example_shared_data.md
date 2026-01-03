# Example: Shared Data

Examples of using ReplicatedRegistry2 for shared game state like leaderboards and settings.

## Global Leaderboard

### Server

```luau
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)
local server = ReplicatedRegistry.server

-- Setup remotes
server.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Create global leaderboard
local leaderboard = {
    topPlayers = {},
    lastUpdate = os.time()
}

server.register("global_leaderboard", leaderboard, 
    ReplicatedRegistry.get_filter {no_recieve = true})

-- Update leaderboard
function updateLeaderboard()
    local proxy = server.view("global_leaderboard")
        .as_proxy()
        .expect()
    -- Sort players by score
    local players = {}
    for _, player in Players:GetPlayers() do
        table.insert(players, {
            name = player.Name,
            userId = player.UserId,
            score = getPlayerScore(player)
        })
    end
    
    table.sort(players, function(a, b)
        return a.score > b.score
    end)
    
    -- Take top 10
    local top10 = {}
    for i = 1, math.min(10, #players) do
        top10[i] = players[i]
    end
    
    proxy.set({"topPlayers"}, top10)
    proxy.set({"lastUpdate"}, os.time())
    
    -- Broadcast to all players
    proxy.replicate(game.Players:GetPlayers())
end

-- Update every 30 seconds
task.spawn(function()
    while true do
        task.wait(30)
        updateLeaderboard()
    end
end)
```

### Client

```luau
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)
local client = ReplicatedRegistry.client

client.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Get leaderboard
local leaderboard = client.view("global_leaderboard")
    .await()

-- Listen for updates
client.on_update("global_leaderboard", function(tbl)
    print("Leaderboard updated!")
    updateLeaderboardUI(tbl.topPlayers)
end)

-- Initial display
updateLeaderboardUI(leaderboard.topPlayers)
```

## Game Settings

### Server

```luau
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)
local server = ReplicatedRegistry.server

-- Setup remotes
server.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Game settings
local gameSettings = {
    maxPlayers = 16,
    roundTime = 300,
    gameMode = "FFA",
    mapName = "Arena1",
    friendly_fire = false
}

-- Only admins can modify
local adminFilter = ReplicatedRegistry.get_filter({
    player_whitelist = {123456, 789012}, -- Admin user IDs
    rate_limit = 5
})

server.register("game_settings", gameSettings, adminFilter)

-- Listen for admin changes
server.on_receive("game_settings", function(sender, tbl, changes)
    print(`Admin {sender.Name} changed settings:`)
    for _, change in changes do
        print(`  {table.concat(change.p, ".")} = {change.v}`)
    end
    
    -- Broadcast to all players
    server.to_clients(
        "game_settings",
        Players:GetPlayers()
    )
end)

-- Helper function to update settings
function updateGameSettings(newSettings)
    local proxy = server.view("game_settings")
        .as_proxy()
        .expect()
    for key, value in newSettings do
        proxy.set({key}, value)
    end
    
    -- Broadcast to everyone
    proxy.replicate(Players:GetPlayers())
end
```

### Client

```luau
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)
local client = ReplicatedRegistry.client

client.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Get settings
local settings = client.view("game_settings")
    .await()

-- Listen for changes
client.on_receive("game_settings", function(tbl, changes)
    print("Game settings updated:")
    for _, change in changes do
        local setting = change.p[1]
        local value = change.v
        print(`  {setting} = {value}`)
        
        -- Update UI or game logic
        if setting == "roundTime" then
            updateTimerUI(value)
        elseif setting == "gameMode" then
            updateGameMode(value)
        end
    end
end)

-- Admin panel (only works if player is whitelisted)
function isAdmin(player)
    -- Check if player is admin
    return table.find({123456, 789012}, player.UserId) ~= nil
end

if isAdmin(Players.LocalPlayer) then
    -- Admin can change settings
    function changeRoundTime(newTime)
        local proxy = client.view("game_settings")
            .as_proxy()
            .expect()
        proxy.set({"roundTime"}, newTime)
        proxy.replicate()
    end
end
```

## Team Data

### Server

```luau
local teams = {
    red = {
        score = 0,
        players = 0,
        color = Color3.fromRGB(255, 0, 0)
    },
    blue = {
        score = 0,
        players = 0,
        color = Color3.fromRGB(0, 0, 255)
    }
}

-- Allow server updates only
local filter = ReplicatedRegistry.get_filter({
    no_recieve = true -- No client updates
})

server.register("team_data", teams, filter)

-- Update team scores
function addTeamScore(teamName, points)
    local proxy = server.view("team_data")
        .as_proxy()
        .expect()
    
    proxy.incr({teamName, "score"}, points)
    proxy.replicate(Players:GetPlayers()) -- Broadcast to all
end

-- Update player counts
Players.PlayerAdded:Connect(function(player)
    local team = getPlayerTeam(player)
    local proxy = server.view("team_data")
        .as_proxy()
        .expect()
    
    proxy.incr({team, "players"}, 1)
    proxy.replicate(Players:GetPlayers())
end)
```

### Client

```lua
local teams = client.view("team_data")

-- Update UI when teams change
client.on_update("team_data", function(tbl)
    updateTeamScoreUI(tbl.red.score, tbl.blue.score)
    updateTeamCountUI(tbl.red.players, tbl.blue.players)
end)
```