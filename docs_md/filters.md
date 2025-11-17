# Filters

Filters are a per-key-value-pair validation system everytime your context recieves TableChanges from the opposite context.

## Built-in Filters

### `player_blacklist`

Blocks specific user IDs from sending changes.

```lua
local filter = ReplicatedRegistry.get_filter({
    player_blacklist = {123456, 789012}
})

ReplicatedRegistry.server.register("data", myTable, filter)
```

### `player_whitelist`

Only allows specific user IDs to send changes.

```lua
local filter = ReplicatedRegistry.get_filter({
    player_whitelist = {123456, 789012}
})

ReplicatedRegistry.server.register("admin_data", adminTable, filter)
```

### `rate_limit`

Limits how many changes per second can be received.

```lua
local filter = ReplicatedRegistry.get_filter({
    rate_limit = 5 -- Max 5 changes per second
})

ReplicatedRegistry.server.register("data", myTable, filter)
```

### `no_recieve`

Prevents receiving changes entirely (send-only).

```lua
local filter = ReplicatedRegistry.get_filter({
    no_recieve = true
})

ReplicatedRegistry.server.register("readonly_data", myTable, filter)
```

## Custom Filters

You can use custom validation logic.

```lua
local function filter(sender, path, value)
    -- sender: Player who sent the change
    -- path: Table path as array, e.g. {"inventory", "sword"}
    -- value: The new value
    
    -- Only allow positive coin values
    if path[1] == "coins" and value < 0 then
        return false
    end
    
    -- Only allow owner to modify their own data
    if sender.UserId ~= tonumber(path[1]) then
        return false
    end
    
    return true
end

ReplicatedRegistry.server.register("player_data", data, filter)
```

## Combining Filters

You can combine multiple filters together into a composite filter using `get_filter()`.

```lua
local filter = ReplicatedRegistry.get_filter({
    player_whitelist = {123456, 789012},
    rate_limit = 10,
    custom = function(sender, path, value)
        -- Additional validation
        return type(value) == "number"
    end
})
```

## Composite Filter Behavior

- All filters in a composite filter must pass for a change to be accepted
- If `custom` filter is provided, it runs after built-in filters
- If any filter returns `false`, the change is rejected
- Rejected changes are marked as `NO_CHANGE` and not applied