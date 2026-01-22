/**
 * keybinds - Declarative contextual keybindings
 *
 * Commands as data, context as state, zero dependencies.
 * Supports keyboard and mouse bindings.
 */

/**
 * Detect Mac platform
 */
const isMac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform)

/**
 * Parse modifiers from a binding string
 */
function parseMods(parts) {
  const mods = { ctrl: false, alt: false, shift: false, meta: false }
  const remaining = []

  for (const part of parts) {
    if (part === 'ctrl' || part === 'control') mods.ctrl = true
    else if (part === 'alt' || part === 'option') mods.alt = true
    else if (part === 'shift') mods.shift = true
    else if (part === 'meta' || part === 'cmd' || part === 'command') mods.meta = true
    else if (part === '$mod') {
      if (isMac) mods.meta = true
      else mods.ctrl = true
    }
    else remaining.push(part)
  }

  return { mods, remaining }
}

/**
 * Check if event modifiers match
 */
function modsMatch(event, mods) {
  return event.ctrlKey === mods.ctrl &&
    event.altKey === mods.alt &&
    event.shiftKey === mods.shift &&
    event.metaKey === mods.meta
}

// Valid key names (subset - common ones)
const VALID_KEYS = new Set([
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12',
  'escape', 'enter', 'tab', 'space', 'backspace', 'delete', 'insert',
  'home', 'end', 'pageup', 'pagedown',
  'arrowup', 'arrowdown', 'arrowleft', 'arrowright', 'up', 'down', 'left', 'right',
  '[', ']', '\\', ';', "'", ',', '.', '/', '`', '-', '=',
  'bracketleft', 'bracketright', 'backslash', 'semicolon', 'quote',
  'comma', 'period', 'slash', 'backquote', 'minus', 'equal'
])

const VALID_MOUSE = new Set([
  'click', 'leftclick', 'left',
  'rightclick', 'right',
  'middleclick', 'middle'
])

/**
 * Parse a key string like "Ctrl+Shift+K" into normalized form
 * @throws {Error} if key binding is invalid
 */
function parseKey(keyStr) {
  if (!keyStr || typeof keyStr !== 'string') {
    throw new Error(`Invalid key binding: ${keyStr}`)
  }

  const parts = keyStr.toLowerCase().split('+').map(p => p.trim()).filter(Boolean)
  if (parts.length === 0) {
    throw new Error(`Empty key binding: "${keyStr}"`)
  }

  const { mods, remaining } = parseMods(parts)

  if (remaining.length === 0) {
    throw new Error(`Key binding has no key (only modifiers): "${keyStr}"`)
  }
  if (remaining.length > 1) {
    throw new Error(`Key binding has multiple keys: "${keyStr}" (got: ${remaining.join(', ')})`)
  }

  const key = remaining[0]
  if (!VALID_KEYS.has(key)) {
    throw new Error(`Unknown key "${key}" in binding "${keyStr}"`)
  }

  return { mods, key }
}

/**
 * Parse a mouse binding like "$mod+Click" or "MiddleClick"
 * Supported: Click/LeftClick, RightClick, MiddleClick
 * @throws {Error} if mouse binding is invalid
 */
function parseMouse(binding) {
  if (!binding || typeof binding !== 'string') {
    throw new Error(`Invalid mouse binding: ${binding}`)
  }

  const parts = binding.toLowerCase().split('+').map(p => p.trim()).filter(Boolean)
  if (parts.length === 0) {
    throw new Error(`Empty mouse binding: "${binding}"`)
  }

  const { mods, remaining } = parseMods(parts)

  if (remaining.length === 0) {
    throw new Error(`Mouse binding has no button (only modifiers): "${binding}"`)
  }
  if (remaining.length > 1) {
    throw new Error(`Mouse binding has multiple buttons: "${binding}"`)
  }

  const btn = remaining[0]
  if (!VALID_MOUSE.has(btn)) {
    throw new Error(`Unknown mouse button "${btn}" in binding "${binding}". Valid: Click, RightClick, MiddleClick`)
  }

  let button = 0 // left
  if (btn === 'rightclick' || btn === 'right') button = 2
  else if (btn === 'middleclick' || btn === 'middle') button = 1

  return { mods, button }
}

/**
 * Check if a keyboard event matches a parsed key
 */
function matchesKey(event, parsed) {
  const keyMatch = event.key.toLowerCase() === parsed.key ||
                   event.code.toLowerCase() === parsed.key ||
                   event.code.toLowerCase() === `key${parsed.key}`

  return keyMatch && modsMatch(event, parsed.mods)
}

/**
 * Check if a mouse event matches a parsed mouse binding
 */
function matchesMouse(event, parsed) {
  return event.button === parsed.button && modsMatch(event, parsed.mods)
}

/**
 * Check if a command is active given current context
 */
function isActive(command, context) {
  if (!command.when) return true
  return command.when(context)
}

/**
 * Create keybind handler
 *
 * @param {Array} commands - Array of command definitions
 * @param {Function} getContext - Returns current context state
 * @param {Object} options - Options
 * @param {HTMLElement} options.target - Element to listen on (default: window)
 * @param {Function} options.onExecute - Called after command executes
 *
 * Command shape:
 *   id: string           - unique identifier
 *   label: string        - display name
 *   category?: string    - group for command palette
 *   keys?: string[]      - keyboard triggers (e.g., ['$mod+k', 'Escape'])
 *   mouse?: string[]     - mouse triggers (e.g., ['$mod+Click', 'MiddleClick'])
 *   when?: ctx => bool   - activation condition
 *   execute: ctx => any  - action (return false to propagate)
 *   hidden?: bool        - hide from search
 *   captureInput?: bool  - fire even when in input fields
 *
 * @example
 * const cleanup = keybinds([
 *   {
 *     id: 'delete',
 *     label: 'Delete selected',
 *     category: 'Edit',
 *     keys: ['Backspace', 'Delete'],
 *     when: ctx => ctx.hasSelection && !ctx.isEditing,
 *     execute: () => deleteSelected()  // return false to propagate
 *   },
 *   {
 *     id: 'pan',
 *     label: 'Pan canvas',
 *     category: 'Canvas',
 *     mouse: ['MiddleClick'],
 *     execute: () => startPan()
 *   }
 * ], () => ({
 *   hasSelection: selectedId() !== null,
 *   isEditing: editingId() !== null
 * }))
 */
export function keybinds(commands, getContext = () => ({}), options = {}) {
  const { target = window, onExecute } = options

  function tryExecute(cmd, context, event) {
    const result = cmd.execute(context, event)
    // Return false from execute to propagate (not consume)
    if (result !== false) {
      event.preventDefault()
      event.stopPropagation()
      onExecute?.(cmd, context)
      return true
    }
    return false
  }

  function handleKeyDown(event) {
    // Don't capture when typing in inputs (unless command explicitly allows it)
    const inInput = event.target.tagName === 'INPUT' ||
                    event.target.tagName === 'TEXTAREA' ||
                    event.target.isContentEditable

    const context = getContext()

    for (const cmd of commands) {
      if (!cmd.keys || cmd.keys.length === 0) continue
      if (inInput && !cmd.captureInput) continue
      if (!isActive(cmd, context)) continue

      for (const key of cmd.keys) {
        if (matchesKey(event, parseKey(key))) {
          if (tryExecute(cmd, context, event)) return
        }
      }
    }
  }

  function handleMouseDown(event) {
    const context = getContext()

    for (const cmd of commands) {
      if (!cmd.mouse || cmd.mouse.length === 0) continue
      if (!isActive(cmd, context)) continue

      for (const binding of cmd.mouse) {
        if (matchesMouse(event, parseMouse(binding))) {
          if (tryExecute(cmd, context, event)) return
        }
      }
    }
  }

  target.addEventListener('keydown', handleKeyDown)
  target.addEventListener('mousedown', handleMouseDown)

  // Return cleanup function
  return () => {
    target.removeEventListener('keydown', handleKeyDown)
    target.removeEventListener('mousedown', handleMouseDown)
  }
}

/**
 * Search commands for command palette
 *
 * @param {Array} commands - Array of command definitions
 * @param {string} query - Search query
 * @param {Object} context - Current context
 * @returns {Array} Matching commands sorted by relevance (active first, then by score)
 */
export function searchCommands(commands, query, context = {}) {
  const q = query.toLowerCase()
  const results = []

  for (const cmd of commands) {
    if (cmd.hidden) continue

    const label = cmd.label.toLowerCase()
    const id = cmd.id.toLowerCase()
    const category = (cmd.category || '').toLowerCase()

    let score = 0
    if (label.startsWith(q)) score = 3
    else if (id.startsWith(q)) score = 2
    else if (category.startsWith(q)) score = 2
    else if (label.includes(q) || id.includes(q) || category.includes(q)) score = 1
    else continue

    results.push({
      ...cmd,
      active: isActive(cmd, context),
      score
    })
  }

  return results.sort((a, b) => {
    if (a.active !== b.active) return b.active - a.active
    return b.score - a.score
  })
}

/**
 * Group commands by category
 *
 * @param {Array} commands - Array of command definitions
 * @param {Object} context - Current context (for active state)
 * @returns {Object} Commands grouped by category { [category]: Command[] }
 */
export function groupByCategory(commands, context = {}) {
  const groups = {}

  for (const cmd of commands) {
    if (cmd.hidden) continue
    const cat = cmd.category || 'Other'
    if (!groups[cat]) groups[cat] = []
    groups[cat].push({
      ...cmd,
      active: isActive(cmd, context)
    })
  }

  return groups
}

/**
 * Validate all commands upfront (call on init to catch typos early)
 * @throws {Error} if any binding is invalid
 */
export function validateCommands(commands) {
  for (const cmd of commands) {
    if (!cmd.id) {
      throw new Error('Command missing id')
    }
    if (cmd.keys) {
      for (const key of cmd.keys) {
        try {
          parseKey(key)
        } catch (e) {
          throw new Error(`Command "${cmd.id}": ${e.message}`)
        }
      }
    }
    if (cmd.mouse) {
      for (const binding of cmd.mouse) {
        try {
          parseMouse(binding)
        } catch (e) {
          throw new Error(`Command "${cmd.id}": ${e.message}`)
        }
      }
    }
  }
  return true
}

/**
 * Execute a command by id
 */
export function executeCommand(commands, id, context = {}) {
  const cmd = commands.find(c => c.id === id)
  if (cmd && isActive(cmd, context)) {
    cmd.execute(context)
    return true
  }
  return false
}

/**
 * Format key for display (e.g., "$mod+k" -> "⌘K" on Mac)
 */
export function formatKey(key) {
  return key
    .replace(/\$mod/gi, isMac ? '⌘' : 'Ctrl')
    .replace(/ctrl/gi, isMac ? '⌃' : 'Ctrl')
    .replace(/alt/gi, isMac ? '⌥' : 'Alt')
    .replace(/shift/gi, isMac ? '⇧' : 'Shift')
    .replace(/meta|cmd|command/gi, '⌘')
    .replace(/\+/g, '')
    .replace(/backspace/gi, '⌫')
    .replace(/delete/gi, '⌦')
    .replace(/escape/gi, 'Esc')
    .replace(/enter/gi, '↵')
    .toUpperCase()
}

export default keybinds
