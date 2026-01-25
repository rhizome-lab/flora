import { createSignal, createEffect, For, Show, onMount, Index } from 'solid-js';
import { searchCommands, formatKey, fuzzyMatcher } from 'keybinds';

/**
 * Render label with highlighted positions
 * @param {{ label: string, positions?: number[] }} props
 */
function HighlightedLabel(props) {
  const chars = () => {
    const positions = new Set(props.positions || []);
    return props.label.split('').map((char, i) => ({
      char,
      highlighted: positions.has(i)
    }));
  };

  return (
    <Index each={chars()}>
      {(item) => (
        <Show when={item().highlighted} fallback={item().char}>
          <mark class="palette__item-label-match">{item().char}</mark>
        </Show>
      )}
    </Index>
  );
}

/**
 * Command palette component
 * @param {{ commands: import('keybinds').Command[], context: () => Record<string, unknown>, onClose: () => void }} props
 */
export default function CommandPalette(props) {
  const [query, setQuery] = createSignal('');
  const [selectedIndex, setSelectedIndex] = createSignal(0);
  /** @type {HTMLInputElement | undefined} */
  let inputRef;

  const results = () => searchCommands(props.commands, query(), props.context(), { matcher: fuzzyMatcher });

  // Reset selection when results change
  createEffect(() => {
    results();
    setSelectedIndex(0);
  });

  /** @param {KeyboardEvent} e */
  function handleKeyDown(e) {
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        setSelectedIndex(i => Math.min(i + 1, results().length - 1));
        break;
      case 'ArrowUp':
        e.preventDefault();
        setSelectedIndex(i => Math.max(i - 1, 0));
        break;
      case 'Enter':
        e.preventDefault();
        const cmd = results()[selectedIndex()];
        if (cmd?.active) {
          cmd.execute(props.context());
          props.onClose();
        }
        break;
      case 'Escape':
        e.preventDefault();
        props.onClose();
        break;
    }
  }

  onMount(() => {
    inputRef?.focus();
  });

  return (
    <div class="palette-overlay" onClick={() => props.onClose()}>
      <div class="palette" onClick={e => e.stopPropagation()}>
        <input
          ref={inputRef}
          class="palette__input"
          type="text"
          placeholder="Type a command..."
          value={query()}
          onInput={e => setQuery(e.target.value)}
          onKeyDown={handleKeyDown}
        />
        <div class="palette__results">
          <Show when={results().length === 0}>
            <div class="palette__empty">No commands found</div>
          </Show>
          <For each={results()}>
            {(cmd, index) => (
              <button
                class="palette__item"
                classList={{
                  'palette__item--selected': index() === selectedIndex(),
                  'palette__item--disabled': !cmd.active
                }}
                onClick={() => {
                  if (cmd.active) {
                    cmd.execute(props.context());
                    props.onClose();
                  }
                }}
                onMouseEnter={() => setSelectedIndex(index())}
              >
                <span class="palette__item-label">
                  <HighlightedLabel label={cmd.label} positions={cmd.positions} />
                </span>
                <Show when={cmd.category}>
                  <span class="palette__item-category">{cmd.category}</span>
                </Show>
                <Show when={cmd.keys?.[0]}>
                  <span class="palette__item-key">{formatKey(/** @type {string} */ (cmd.keys?.[0]))}</span>
                </Show>
              </button>
            )}
          </For>
        </div>
      </div>
    </div>
  );
}
