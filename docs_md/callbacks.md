# Callbacks

Callbacks allow you to customize behavior at key points in the replication process.

## Global Callbacks

### `on_changes_recieved`

Called whenever changes are received from a remote.

```lua
ReplicatedRegistry.callbacks.on_changes_recieved = function(sender, register_key, changes)
    -- sender: Player who sent (nil on client)
    -- register_key: The key of the registree
    -- changes: Array of changes
    
    print(`Received {#changes} changes for {register_key}`)
    
    -- Return values:
    -- "pass" - Continue normal processing
    -- "return" - Stop processing, don't apply changes
    -- "disable" - Disable this key entirely
    
    return "pass"
end
```

**With validation:**

```lua
ReplicatedRegistry.callbacks.on_changes_recieved = function(sender, register_key, changes)
    -- Validate changes
    for _, change in changes do
        if not isValidChange(change) then
            return "disable", "Invalid change detected"
        end
    end
    
    return "pass"
end
```

### `on_key_disabled`

Called when a key is disabled due to an error or validation failure.

```lua
ReplicatedRegistry.callbacks.on_key_disabled = function(register_key, reason)
    warn(`Key {register_key} was disabled: {reason}`)
    
    -- Clean up or notify admins
    notifyAdmins(register_key, reason)
end
```

## Server Callbacks

### `validate_full_request`

Validates whether a client can request the full table.

```lua
ReplicatedRegistry.server.callbacks.validate_full_request = function(player, key)
    -- Check if player owns this data
    if type(key) == "number" then
        return player.UserId == key
    end
    
    -- Check if key contains player's UserId
    if type(key) == "string" then
        return string.find(key, tostring(player.UserId)) ~= nil
    end
    
    return true
end
```

**Default behavior:**

The default callback includes rate limiting and UserId validation:

```lua
-- Default implementation
on_request_with_validate_key = function(plr, key)
    -- Rate limit: 5 requests per second
    if not replication_filters.rate_limit(5)(plr) then 
        return false 
    end
    
    -- Wait up to 5 seconds for key to exist
    for i = 1, 5 do
        if registrees[key] then break end
        task.wait(1)
    end
    
    -- Validate ownership
    if type(key) == "number" then
        return plr.UserId == key
    end
    if type(key) == "string" then
        return string.find(key, tostring(plr.UserId)) ~= nil
    end
    
    return false
end
```

## Custom Default Callbacks

You can restore default callbacks if needed:

```lua
-- Use default callbacks
ReplicatedRegistry.server.callbacks.validate_full_request = 
    ReplicatedRegistry.default_callbacks.on_request

ReplicatedRegistry.callbacks.on_changes_recieved = 
    ReplicatedRegistry.default_callbacks.on_changes_recieved
```