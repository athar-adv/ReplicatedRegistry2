# Server API

## Registering Tables

### `server.register(key, table, filter?)`

Registers a table on the server for replication.

```lua
local playerData = {
    coins = 100,
    level = 1,
    inventory = {}
}

ReplicatedRegistry.server.register("player_123", playerData)
```

**With filter:**

```lua
local filter = ReplicatedRegistry.get_filter({
    rate_limit = 10, -- 10 changes per second max
    player_whitelist = {123, 456} -- Only these user IDs
})

ReplicatedRegistry.server.register("shared_data", sharedTable, filter)
```

## Accessing Tables

### `server.view(key)`

Returns the registered table directly.

```lua
local data = ReplicatedRegistry.server.view("player_123")
data.coins = 150
data.level = 2
```

### `server.view_as_proxy(key)`

Returns a proxy interface with helper methods.

```lua
local proxy = ReplicatedRegistry.server.view_as_proxy("player_123")

-- Set values
proxy.set({"coins"}, 200)
proxy.set({"inventory", "sword"}, true)

-- Get values
local coins = proxy.get({"coins"})

-- Increment values
proxy.incr({"coins"}, 50)
proxy.incr({"level"}, 1)

-- Replicate to specific players
proxy.replicate({player1, player2})

-- Replicate to all players
proxy.replicate()

-- Get full table
local fullTable = proxy.full()
```

## Replication

### `server.to_clients(key, players, sender?, changes?, auto_commit?)`

Sends changes to specified clients.

```lua
-- Replicate to specific players
ReplicatedRegistry.server.to_clients(
    "player_123",
    {player1, player2}
)

-- Replicate to all players
ReplicatedRegistry.server.to_clients(
    "global_data",
    game.Players:GetPlayers()
)
```

## Change Management

### `get_changes(key)`

Gets all pending changes since last commit.

```lua
local changes = ReplicatedRegistry.get_changes("player_123")
-- changes = {{v = 150, p = {"coins"}}, {v = 2, p = {"level"}}}
```

### `commit_changes(key, changes?)`

Commits changes, updating the internal copy.

```lua
ReplicatedRegistry.commit_changes("player_123")
```

### `revert_changes(key, changes?)`

Reverts uncommitted changes.

```lua
local data = ReplicatedRegistry.server.view("player_123")
data.coins = 999 -- Oops, mistake

ReplicatedRegistry.revert_changes("player_123")
-- coins reverted to previous committed value
```