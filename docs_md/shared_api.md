# Shared API

## Change Management

### `get_changes(key: any) -> ()`

Gets all pending changes since last commit.

```lua
local changes = ReplicatedRegistry.get_changes("player_123")
-- changes = {{v = 150, p = {"coins"}}, {v = 2, p = {"level"}}}
```

### `commit_changes(key: any, changes: TableChanges?) -> ()`

Commits changes, updating the internal copy.

```lua
ReplicatedRegistry.commit_changes("player_123")
```

### `revert_changes(key: any, changes: TableChanges?) -> ()`

Reverts uncommitted changes.

```lua
local data = ReplicatedRegistry.server.await_view("player_123")
data.coins = 999 -- Oops, mistake

ReplicatedRegistry.revert_changes("player_123")
-- coins reverted to previous committed value
```

## Util

### `get_registered_keys() -> {any}`

Returns an array of currently registered register keys. Useful for mass replication of keys