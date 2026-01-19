# Flora Servers: Brainstorm

Backend services for the flora ecosystem. UI handled by canopy (~/git/canopy); these are headless servers.

## Overview

Several potential server projects, possibly related:

1. **MOO-style object system** - Persistent programmable objects (its own thing)
2. **Notes / Knowledge base** - Could be standalone OR built on MOO
3. **Filesystem service** - Could be standalone OR built on MOO

The MOO architecture is attractive but should be evaluated separately for each use case.

## Architecture (Common)

```
Any Client (canopy, CLI, other) ←→ Flora Server ←→ Storage
                                       ↑
                                  Lua or Rust
```

### Protocol

**Principle**: Simplest possible for arbitrary consumers. Not canopy-specific.

Options to consider:
- HTTP/JSON (universal, simple, stateless)
- WebSocket (real-time, bidirectional)
- Unix socket (local, fast)

### Language Choice

| Use Case | Candidate | Rationale |
|----------|-----------|-----------|
| Notes/knowledge | Lua | Schema flexibility, rapid iteration |
| FS operations | Rust | Performance, safety |
| MOO object DB | Rust core + Lua verbs | Persistence needs perf, scripting needs flexibility |

**Principle**: Lua for rapid iteration, Rust when performance matters.

---

## Project: MOO-Style Object System

A standalone persistent programmable object database. Other projects could build on it, or not.

### What Made MOO Interesting

1. **Everything is an object**: Rooms, players, items, even verbs
2. **Inheritance**: Objects can inherit from parents
3. **Properties**: Key-value data on objects
4. **Verbs**: Programmable methods on objects
5. **Persistence**: Database survives restarts
6. **Multi-user**: Multiple connections, shared world
7. **Text-based**: Core interaction is text (UI optional)

### Modernizing MOO

What to keep:
- Object model with properties/verbs
- Persistence
- Programmability
- Text as first-class

What to reconsider:
- Single-server architecture → distributed?
- Custom scripting language → Lua?
- Telnet protocol → modern protocols?
- Global namespace → scoped/namespaced?

### Object References

**Question**: How do objects reference each other?

| Option | Pros | Cons |
|--------|------|------|
| Numeric IDs (`#123`) | Simple, fast | Opaque, fragile |
| Paths (`/room/kitchen/table`) | Human-readable | Implies hierarchy, renames break |
| UUIDs | Globally unique, stable | Opaque |
| Content-addressed (hash) | Immutable, dedupes | Awkward for mutable |
| Named + scoped (`@user/project/obj`) | Readable, namespaced | More complex |
| Hybrid (UUID internal, path display) | Best of both | More complexity |

**To decide**: What operations matter most? Rename? Move? Link? Copy?

### Open Questions (MOO)

- Storage backend: SQLite? Custom? Distributed?
- Authentication: How do multi-user systems handle identity?
- Permissions: Object-level? Verb-level? Both?
- Versioning: Do objects have history?
- Schema: Typed properties or free-form?

---

## Project: Notes / Knowledge Base

Persistent notes with rich linking. Could be:
- **Standalone**: Simple document store with linking
- **On MOO**: Notes as objects, links as references, queries as verbs

### Requirements
- Create, read, update, delete notes
- Link notes to each other
- Search / query
- Maybe: tags, hierarchy, backlinks

### Open Questions (Notes)
- Flat or hierarchical?
- Block-based (Notion) or document-based (Obsidian)?
- Plain text? Markdown? Rich text?
- Is MOO overhead worth it, or overkill?

---

## Project: Filesystem Service

High-performance file operations. Could be:
- **Standalone**: Direct FS access with watching/indexing
- **On MOO**: Files as objects, directories as containers

### Requirements
- Watch for changes
- Index contents
- Search by name/content
- Virtual FS abstractions?

### Open Questions (FS)
- Scope: Just watching? Or full VFS abstraction?
- Performance: Definitely Rust for the core
- Is MOO overhead worth it here? Probably not?

---

## Naming

Flora uses botanical names. Server candidates:
- **Taproot** - Deep, central storage
- **Tuber** - Underground storage organ
- **Bulb** - Storage + regeneration
- **Corm** - Similar to bulb, underground storage

Or project-specific names (more flowers).

---

## Prior Art

### LambdaMOO
The original MOO. Single-server, custom language. Still running after 30+ years.

### CouchDB
Document database. HTTP API, JSON documents. Multi-master replication.

### Notion / Roam / Obsidian
Modern notes with linking. Block-based or page-based. Graph structure.

### Plan 9 / 9P
Everything is a file. Network-transparent filesystem. Simple protocol.

---

## Next Steps

1. Decide: Start with MOO core, or a concrete use case (notes/fs)?
2. If MOO: Sketch object model, prototype storage
3. If notes/fs: Decide standalone vs on-MOO
4. Pick protocol (probably HTTP/JSON to start)
5. Connect to canopy for UI testing
