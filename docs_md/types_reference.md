# Types Reference

Type definitions for ReplicatedRegistry2.

## Core Types

### `Table`

```luau
export type Table = {[any]: any}
```

A generic table type used for registree data.

### `TableChanges`

```luau
export type TableChanges = {
    {v: any, p: {any}}
}
```

An array of changes where:
- `v`: The new value
- `p`: The path to the value as an array

**Example:**

```lua
{
    {v = 100, p = {"coins"}},
    {v = 5, p = {"level"}},
    {v = true, p = {"inventory", "sword"}}
}
```

## Filter Types

### `Filter`

```luau
export type Filter = (sender: Player?, register_key: any, tbl: Table, changes: TableChanges) -> boolean
```

A function that validates changes.

**Parameters:**
- `sender`: The player who sent the change (nil if from server)
- `register_key`: The register key being sent changes for.
- `tbl`: The old table.
- `changes`: Changes waiting to be applied.

**Returns:** `true` to accept, `false` to reject

### `FilterList`

```luau
type FilterList = {
    player_blacklist: {number}?,
    player_whitelist: {number}?,
    rate_limit: number?,
    no_recieve: boolean?,
    custom: Filter?,
}
```

Configuration object for `get_filter()`.

## Interface Types

### `RegistreeInterface`

```lua
export type RegistreeInterface<T=Table, ReplicateArgs...=()> = {
    set: (...any) -> (any) -> (),
    get: (...any) -> any,
    incr: (...any) -> (number) -> (),
    replicate: (ReplicateArgs...) -> (),
    full: () -> T,
}
```

The proxy interface returned by the methods of `view().as_proxy()`.

**Methods:**
- `set(path: {any}, value: any) -> ()`: Set a value at path
- `get(path: {any}) -> any`: Get a value at path
- `incr(path: {any}, delta: number) -> ()`: Increment a number at path
- `replicate(args...) -> ()`: Replicate changes
- `data() -> Table`: Get the full table

**Server `replicate()` args:** `{Player}?, RemoteEvent?`
**Client `replicate()` args:** `RemoteEvent?`

## View

```luau
export type View<T = Table, ProxyType = any> = {
	await: () -> T,
	unwrap: () -> T?,
	expect: () -> T,
	as_proxy: () -> {
		await: () -> ProxyType,
		unwrap: () -> ProxyType?,
		expect: () -> ProxyType
	}
}
```

An interface for viewing non-gauranteed registree data.

**Methods:**

- `expect() -> RegistreeInterface`: Errors if the viewed value does not exist, else returns it
- `unwrap() -> RegistreeInterface?`: Returns the viewed value, regardless if it exists or not
- `await() -> RegistreeInterface`: If the viewed value does not exist, then it will yield the calling thread until it does, and return it.
- `as_proxy() -> ProxyView`: Returns a sub-view for viewing the registree data as proxies.

## Internal Types

### `Registree`

```luau
type Registree<T=Table> = {
    value: T,
    copy: Table,
    filter: Filter?,
    onRecievedListeners: {(...any) -> ()},
    onUpdatedListeners: {(...any) -> ()},
    onKeyChangedListeners: {[string]: {(...any) -> ()}}
}
```

Internal structure for registered tables.

### `Sender_Server`

```lua
type Sender_Server = (plr: Player, register_key: any, changes: TableChanges) -> ()
```

Function signature for sending changes to a client.

### `Sender_Client`

```lua
type Sender_Client = (register_key: any, changes: TableChanges) -> ()
```

Function signature for sending changes to the server.

### `RequestFull`

```lua
type RequestFull = (register_key: any) -> TableChanges?
```

Function signature for requesting full table from server.

## Callback Types

### `on_changes_recieved`

```lua
(sender: Player?, register_key: any, changes: TableChanges) -> 
    ("pass" | "return" | "disable", string?)
```

**Returns:**
- `"pass"`: Continue normal processing
- `"return"`: Stop processing without applying changes
- `"disable"`: Disable this key entirely
- Optional second return: reason string (for "disable")

### `validate_full_request`

```lua
(player: Player, key: any) -> boolean
```

**Returns:** `true` to allow request, `false` to deny

### `on_key_disabled`

```lua
(register_key: any, reason: string) -> ()
```

Called when a key is disabled.

## Usage Examples

```lua
-- Filter function
local myFilter: Filter = function(sender, path, value)
    if path[1] == "coins" and type(value) ~= "number" then
        return false
    end
    return true
end

-- Server proxy
local serverProxy: RegistreeInterface<any, ({Player}?, RemoteEvent?)> = 
    ReplicatedRegistry.server.view_as_proxy("key")

serverProxy.set("coins")(100)
serverProxy.replicate({player})

-- Client proxy
local clientProxy: RegistreeInterface<any, (RemoteEvent?)> = 
    ReplicatedRegistry.client.view_as_proxy("key")

clientProxy.incr("level")(1)
clientProxy.replicate()

-- Changes
local changes: TableChanges = ReplicatedRegistry.get_changes("key")
for _, change in changes do
    print(`Path: {table.concat(change.p, ".")}`)
    print(`Value: {change.v}`)
end
```