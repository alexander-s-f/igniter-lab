import { writable } from 'svelte/store'
import type { IdeSettings } from '$lib/types'

const STORAGE_KEY = 'igniter-ide-settings'

export const DEFAULTS: IdeSettings = {
  editor: {
    tabSize: 2,
    fontSize: 13,
    wordWrap: 'on',
    minimap: false,
    fontFamily: 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace',
  },
  appearance: {
    accentColor: 'blue',
  },
  ai: {
    provider: 'anthropic',
    model: 'claude-sonnet-4-6',
    apiKey: '',
    baseUrl: 'http://localhost:11434',
  },
  workflow: {
    autoSave: true,
    autoSaveDelay: 3000,
    autoCompile: false,
    autoSnapshot: false,
  },
}

function deepMerge(defaults: IdeSettings, stored: Partial<IdeSettings>): IdeSettings {
  return {
    editor: { ...defaults.editor, ...(stored.editor ?? {}) },
    appearance: { ...defaults.appearance, ...(stored.appearance ?? {}) },
    ai: { ...defaults.ai, ...(stored.ai ?? {}) },
    workflow: { ...defaults.workflow, ...(stored.workflow ?? {}) },
  }
}

function loadSettings(): IdeSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return deepMerge(DEFAULTS, JSON.parse(raw))
  } catch {}
  return { ...DEFAULTS, editor: { ...DEFAULTS.editor }, appearance: { ...DEFAULTS.appearance }, ai: { ...DEFAULTS.ai } }
}

function persist(v: IdeSettings) {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(v)) } catch {}
}

function createSettingsStore() {
  const { subscribe, set, update } = writable<IdeSettings>(loadSettings())

  return {
    subscribe,
    set(v: IdeSettings) {
      persist(v)
      set(v)
    },
    update(fn: (s: IdeSettings) => IdeSettings) {
      update(s => {
        const next = fn(s)
        persist(next)
        return next
      })
    },
    reset() {
      const fresh = deepMerge(DEFAULTS, {})
      persist(fresh)
      set(fresh)
    },
  }
}

export const settings = createSettingsStore()
