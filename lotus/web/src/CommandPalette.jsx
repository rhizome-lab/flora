import { createSignal, createEffect, For, Show, onMount, onCleanup } from 'solid-js';
import { searchCommands, formatKey } from 'keybinds';

/**
 * Command palette component
 * @param {{ commands: import('keybinds').Command[], context: () => Record<string, unknown>, onClose: () => void }} props
 */
export default function CommandPalette(props) {
  const [query, setQuery] = createSignal('');
  const [selectedIndex, setSelectedIndex] = createSignal(0);
  let inputRef;

  const results = () => searchCommands(props.commands, query(), props.context());

  // Reset selection when results change
  createEffect(() => {
    results();
    setSelectedIndex(0);
  });

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
                <span class="palette__item-label">{cmd.label}</span>
                <Show when={cmd.category}>
                  <span class="palette__item-category">{cmd.category}</span>
                </Show>
                <Show when={cmd.keys?.[0]}>
                  <span class="palette__item-key">{formatKey(cmd.keys[0])}</span>
                </Show>
              </button>
            )}
          </For>
        </div>
      </div>
    </div>
  );
}
