# Introduction

ReplicatedRegistry2 is a client-server synchronized table registry module for Roblox that provides two-way data replication with built-in filtering, change tracking, and automatic synchronization.

## Key Features

- **Two-way synchronization** between server and clients
- **Change tracking** with automatic diff calculation
- **Built-in filters** for access control and rate limiting
- **Commit/revert system** for managing changes
- **Proxy interface** for clean, chainable API
- **Custom callbacks** for validation and security

## Basic Concept

ReplicatedRegistry2 maintains a registry of tables that can be synchronized between server and clients. Each registered table:

- Has a unique key for identification
- Tracks changes automatically
- Can be replicated with filters
- Supports both direct and proxy access patterns

## When to Use

- Player data synchronization
- Shared game state (leaderboards, settings)
- Real-time collaborative data
- Any data that needs server-client sync with validation