# Example: ProfileStore Integration

Integrating ReplicatedRegistry2 with ProfileService for persistent player data.

## Server Script

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local ProfileService = require(ServerScriptService.ProfileService)
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)
local server = ReplicatedRegistry.server

-- Setup remotes
ReplicatedRegistry.server.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- ProfileStore setup
local ProfileStore = ProfileService.GetProfileStore(
    "PlayerData",
    {
        coins = 0,
        level = 1,
        inventory = {},
        stats = {
            kills = 0,
            deaths = 0,
            playtime = 0
        }
    }
)

local Profiles = {}

-- Filter for player profiles
local profileFilter = ReplicatedRegistry.get_filter({
    rate_limit = 10,
    custom = function(sender, register_key, tbl, changes)
        -- Ensure player only modifies their own profile
        return register_key == sender.UserId
    end
})

Players.PlayerAdded:Connect(function(player)
    local profile = ProfileStore:LoadProfileAsync(`Player_{player.UserId}`)
    
    if not profile then
        player:Kick("Failed to load data")
        return
    end
    
    profile:AddUserId(player.UserId)
    profile:Reconcile()
    
    profile:ListenToRelease(function()
        Profiles[player] = nil
        server.deregister(player.UserId)
        player:Kick("Profile released")
    end)
    
    if not player:IsDescendantOf(Players) then
        profile:Release()
        return
    end
    
    Profiles[player] = profile
    
    -- Register profile data with ReplicatedRegistry
    local key = player.UserId
    server.register(key, profile.Data, profileFilter)
    
    -- Listen for changes from client
    ReplicatedRegistry.on_recieve(key, function(sender, tbl, changes)
        print(`{sender.Name} updated profile:`)
        for _, change in changes do
            print(`  {table.concat(change.p, ".")} = {change.v}`)
        end
    end)
    
    -- Periodic sync to client (every 10 seconds)
    task.spawn(function()
        while Profiles[player] do
            task.wait(10)
            if Profiles[player] then
                server.to_clients(key, {player})
            end
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local profile = Profiles[player]
    if profile then
        profile:Release()
        Profiles[player] = nil
        server.deregister(player.UserId)
    end
end)

-- Example: Give rewards
function giveReward(player, coins, xp)
    local profile = Profiles[player]
    if not profile then return end
    
    local proxy = ReplicatedRegistry.server.view_as_proxy(player.UserId)
    
    proxy.incr("coins")(coins)
    proxy.incr("level")(xp)
    
    -- Replicate to player
    proxy.replicate({player})
end

-- Example: Add item to inventory
function giveItem(player, itemName)
    local profile = Profiles[player]
    if not profile then return end
    
    local data = ReplicatedRegistry.server.view(player.UserId)
    data.inventory[itemName] = true
    
    ReplicatedRegistry.server.to_clients(player.UserId, {player})
end

-- Example: Update stats
function recordKill(player)
    local profile = Profiles[player]
    if not profile then return end
    
    local proxy = ReplicatedRegistry.server.view_as_proxy(player.UserId)
    proxy.incr("stats", "kills")(1)
    proxy.replicate({player})
end
```

## Client Script

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)

-- Setup remotes
ReplicatedRegistry.client.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

local player = Players.LocalPlayer
local key = player.UserId

-- Wait for data to be ready
local playerData = ReplicatedRegistry.client.view(key)

-- Listen for profile updates
ReplicatedRegistry.on_recieve(key, function(sender, tbl, changes)
    for _, change in changes do
        local path = table.concat(change.p, ".")
        print(`Profile updated: {path} = {change.v}`)
        
        -- Update UI based on what changed
        if change.p[1] == "coins" then
            updateCoinsUI(tbl.coins)
        elseif change.p[1] == "level" then
            updateLevelUI(tbl.level)
        elseif change.p[1] == "stats" then
            updateStatsUI(tbl.stats)
        end
    end
end)

-- Initial UI setup
updateCoinsUI(playerData.coins)
updateLevelUI(playerData.level)
updateStatsUI(playerData.stats)

-- Example: Purchase system
function tryPurchase(itemName, cost)
    local data = ReplicatedRegistry.client.view(key)
    
    if data.coins >= cost then
        -- Optimistic update
        data.coins -= cost
        data.inventory[itemName] = true
        
        -- Server will validate
        ReplicatedRegistry.client.to_server(key)
        return true
    end
    
    return false
end
```

## Notes

- ProfileStore handles persistence
- ReplicatedRegistry handles real-time sync
- Server validates all client changes
- Client gets immediate feedback with optimistic updates
- Profile data automatically reconciles on load