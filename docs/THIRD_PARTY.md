# Third-Party Dependencies - Tinyfolk: Realm of Giants

This document records vendored third-party source used by Tinyfolk: Realm of Giants.

## ProfileStore

- Dependency name: ProfileStore
- Upstream repository: https://github.com/MadStudioRoblox/ProfileStore
- Pinned upstream commit SHA: `45c9847cbcf1fc260369c50eb335aba7c35aecdd`
- Vendored file path: `src/ServerScriptService/Services/ThirdParty/ProfileStore.luau`
- License: Apache-2.0
- Retrieval date: 2026-05-13
- Local modifications: none

Gameplay code must not require this dependency directly. ProfileStore access is restricted to server-only owner-layer/gateway persistence plumbing, with `ProfilePersistenceGateway` remaining the gameplay-facing persistence contract.
