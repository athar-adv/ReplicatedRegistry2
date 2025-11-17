# Filters

Filters are a on-recieved per register key validation system everytime your context recieves TableChanges from the opposite context.

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
local function filter(sender, register_key, tbl, changes)
    -- Only allow owner to modify their own data
    if sender.UserId ~= register_key then
        return false
    end
    for _, c in changes do
        local path, value = c.p, c.v
        -- Only allow positive coin values
        if path[1] == "coins" and value < 0 then
            return false
        end
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
    custom = function(sender, _, _, changes)
        for _, c in changes do
            -- Additional validation
            if type(value) ~= "number" then return false end
        end
        return true
    end
})
```

## Composite Filter Behavior

- All filters in a composite filter must pass for a change to be accepted
- If `custom` filter is provided, it runs after built-in filters
- If any filter returns `false`, the change is rejected
