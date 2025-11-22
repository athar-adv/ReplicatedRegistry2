# Example: Shared Data

Examples of using ReplicatedRegistry2 for shared game state like leaderboards and settings.

## Global Leaderboard

### Server

```lua
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)

-- Setup remotes
ReplicatedRegistry.server.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Create global leaderboard
local leaderboard = {
    topPlayers = {},
    lastUpdate = os.time()
}

-- No filter = read-only for clients
ReplicatedRegistry.server.register("global_leaderboard", leaderboard)

-- Update leaderboard
function updateLeaderboard()
    local proxy = ReplicatedRegistry.server.view_as_proxy("global_leaderboard")
    
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
    proxy.replicate()
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

```lua
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)

ReplicatedRegistry.client.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Get leaderboard
local leaderboard = ReplicatedRegistry.client.view("global_leaderboard")

-- Listen for updates
ReplicatedRegistry.on_recieve("global_leaderboard", function(sender, tbl, changes)
    print("Leaderboard updated!")
    updateLeaderboardUI(tbl.topPlayers)
end)

-- Initial display
updateLeaderboardUI(leaderboard.topPlayers)
```

## Game Settings

### Server

```lua
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)

-- Setup remotes
ReplicatedRegistry.server.set_remote_instances(
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

ReplicatedRegistry.server.register("game_settings", gameSettings, adminFilter)

-- Listen for admin changes
ReplicatedRegistry.on_recieve("game_settings", function(sender, tbl, changes)
    print(`Admin {sender.Name} changed settings:`)
    for _, change in changes do
        print(`  {table.concat(change.p, ".")} = {change.v}`)
    end
    
    -- Broadcast to all players
    ReplicatedRegistry.server.to_clients(
        "game_settings",
        Players:GetPlayers()
    )
end)

-- Helper function to update settings
function updateGameSettings(newSettings)
    local proxy = ReplicatedRegistry.server.view_as_proxy("game_settings")
    
    for key, value in newSettings do
        proxy.set({key}, value)
    end
    
    -- Broadcast to everyone
    proxy.replicate()
end
```

### Client

```lua
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)

ReplicatedRegistry.client.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Get settings
local settings = ReplicatedRegistry.client.view("game_settings")

-- Listen for changes
ReplicatedRegistry.on_recieve("game_settings", function(sender, tbl, changes)
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
        local proxy = ReplicatedRegistry.client.view_as_proxy("game_settings")
        proxy.set({"roundTime"}, newTime)
        proxy.replicate()
    end
end
```

## Team Data

### Server

```lua
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

ReplicatedRegistry.server.register("team_data", teams, filter)

-- Update team scores
function addTeamScore(teamName, points)
    local proxy = ReplicatedRegistry.server.view_as_proxy("team_data")
    
    proxy.incr({teamName, "score"}, points)
    proxy.replicate() -- Broadcast to all
end

-- Update player counts
Players.PlayerAdded:Connect(function(player)
    local team = getPlayerTeam(player)
    local proxy = ReplicatedRegistry.server.view_as_proxy("team_data")
    
    proxy.incr({team, "players"}, 1)
    proxy.replicate()
end)
```

### Client

```lua
local teams = ReplicatedRegistry.client.view("team_data")

-- Update UI when teams change
ReplicatedRegistry.on_recieve("team_data", function(sender, tbl, changes)
    updateTeamScoreUI(tbl.red.score, tbl.blue.score)
    updateTeamCountUI(tbl.red.players, tbl.blue.players)
end)
```