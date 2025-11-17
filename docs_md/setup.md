# Setup

## Installation

Place the ReplicatedRegistry2 module in `ReplicatedStorage` or `ServerScriptService` depending on your project structure.

## Remote Setup

ReplicatedRegistry2 requires two remotes for communication:

```lua
-- In ReplicatedStorage
local RequestFullRemote = Instance.new("RemoteFunction")
RequestFullRemote.Name = "RequestFull"
RequestFullRemote.Parent = ReplicatedStorage

local SendChangesRemote = Instance.new("RemoteEvent")
SendChangesRemote.Name = "SendChanges"
SendChangesRemote.Parent = ReplicatedStorage
```

## Server Configuration

```lua
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)

-- Option 1: Using RemoteInstances directly
ReplicatedRegistry.server.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Option 2: Using custom callbacks (allows you to do modifications before send/recieve)
ReplicatedRegistry.server.set_remote_callbacks(
    function(handler)
        -- Initialize request handler
        ReplicatedStorage.RequestFullRemote.OnServerInvoke = handler
    end,
    function(player, key, changes)
        -- Send changes to client
        ReplicatedStorage.SendChangesRemote:FireClient(player, key, changes)
    end,
    function(receiver)
        -- Connect change receiver
        ReplicatedStorage.SendChangesRemote.OnServerEvent:Connect(receiver)
    end
)
```

## Client Configuration

```lua
local ReplicatedRegistry = require(ReplicatedStorage.ReplicatedRegistry2)

-- Option 1: Using RemoteInstances directly
ReplicatedRegistry.client.set_remote_instances(
    ReplicatedStorage.RequestFullRemote,
    ReplicatedStorage.SendChangesRemote
)

-- Option 2: Using custom callbacks (allows you to do modifications before send/recieve)
ReplicatedRegistry.client.set_remote_callbacks(
    function(key)
        -- Request full table
        return ReplicatedStorage.RequestFullRemote:InvokeServer(key)
    end,
    function(key, changes)
        -- Send changes to server
        ReplicatedStorage.SendChangesRemote:FireServer(key, changes)
    end,
    function(receiver)
        -- Connect change receiver
        ReplicatedStorage.SendChangesRemote.OnClientEvent:Connect(receiver)
    end
)
```