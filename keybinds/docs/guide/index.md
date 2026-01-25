# Getting Started

keybinds is a declarative, contextual keybinding system for web applications.

## Installation

```bash
npm install keybinds
```

## Quick Start

```js
import { keybinds } from 'keybinds'

const commands = [
  {
    id: 'save',
    label: 'Save document',
    category: 'File',
    keys: ['$mod+s'],
    execute: () => saveDocument()
  },
  {
    id: 'delete',
    label: 'Delete selected',
    category: 'Edit',
    keys: ['Backspace', 'Delete'],
    when: ctx => ctx.hasSelection,
    execute: () => deleteSelected()
  }
]

// Start listening
const cleanup = keybinds(commands, () => ({
  hasSelection: selection.length > 0
}))

// Stop listening
cleanup()
```

## Zero-config UI

For instant discoverability, add the web components:

```html
<command-palette auto-trigger></command-palette>
<keybind-cheatsheet auto-trigger></keybind-cheatsheet>

<script type="module">
  import { registerComponents } from 'keybinds'
  import 'keybinds/styles/palette.css'

  registerComponents()

  document.querySelector('command-palette').commands = commands
  document.querySelector('keybind-cheatsheet').commands = commands
</script>
```

- `auto-trigger` on palette: `$mod+K` toggles it
- `auto-trigger` on cheatsheet: hold Control for 400ms

## Key Concepts

- **[Commands](/guide/commands)** - Actions with bindings, labels, and conditions
- **[Context](/guide/context)** - Application state that controls command activation
- **[Components](/guide/components)** - Web components for discoverability
- **[Styling](/guide/styling)** - Customizing component appearance
