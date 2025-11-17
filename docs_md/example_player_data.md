# Example: Player Data

A complete example of synchronizing player data between server and client.

## Server Script

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)
local server = ReplicatedRegistry.server

-- Setup remotes
server.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Custom validation
server.callbacks.validate_full_request = function(player, key)
    -- Only allow players to access their own data
    return key == player.UserId
end

local playerDataFilter = ReplicatedRegistry.get_filter({
    rate_limit = 10, -- Max 10 updates per second
    custom = function(sender, register_key, tbl, changes)
    -- Player can only access their own keys
        if sender.UserId ~= register_key then
            return false
        end
        
        for _, c in changes do
            local value, path = c.v, c.p
            -- Prevent negative coins
            if path[1] == "coins" and type(value) == "number" and value < 0 then
                return false
            end
        end
        
        return true
    end
})

Players.PlayerAdded:Connect(function(player)
    local key = player.UserId
    
    -- Create player data
    local playerData = {
        coins = 100,
        level = 1,
        inventory = {},
        settings = {
            sound = true,
            music = true
        }
    }
    
    -- Register for replication
    server.register(key, playerData, playerDataFilter)
    
    -- Listen for changes from client
    ReplicatedRegistry.on_recieve(key, function(sender, tbl, changes)
        print(`Player {sender.Name} updated their data:`)
        for _, change in changes do
            print(`  {table.concat(change.p, ".")} = {change.v}`)
        end
        
        savePlayerData(sender, tbl)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local key = player.UserId
    local data = server.view(key)
    
    -- Save before player leaves
    savePlayerData(player, data)
end)

-- Example: Give coins to player
function giveCoins(player, amount)
    local proxy = server.view_as_proxy(player.UserId)
    
    proxy.incr("coins")(amount)
    proxy.replicate({player}) -- Send to client
end

-- Example: Update player level
function levelUp(player)
    local data = server.view(player.UserId)
    
    data.level += 1
    data.coins += data.level * 10 -- Bonus coins
    
    server.to_clients(player.UserId, {player})
end
```

## Client Script

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)
local client = ReplicatedRegistry.client

-- Setup remotes
client.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

local player = Players.LocalPlayer
local key = player.UserId

-- Access player data
local playerData = client.view(key)

-- Listen for updates from server
ReplicatedRegistry.on_recieve(key, function(sender, tbl, changes)
    print("Received update from server:")
    for _, change in changes do
        print(`  {table.concat(change.p, ".")} = {change.v}`)
    end
    
    -- Update UI
    updateCoinsDisplay(tbl.coins)
    updateLevelDisplay(tbl.level)
end)

-- Example: Update settings
function updateSettings(soundEnabled, musicEnabled)
    local proxy = client.view_as_proxy(key)
    
    proxy.set("settings", "sound")(soundEnabled)
    proxy.set("settings", "music")(musicEnabled)
    
    proxy.replicate() -- Send to server
end

-- Example: Purchase item
function purchaseItem(itemName, cost)
    local data = client.view(key)
    
    if data.coins >= cost then
        data.coins -= cost
        data.inventory[itemName] = true
        
        -- Send to server for validation
        client.to_server(key)
    else
        warn("Not enough coins!")
    end
end
```