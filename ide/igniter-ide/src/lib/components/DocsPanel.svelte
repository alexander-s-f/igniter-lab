<script lang="ts">
  import { createEventDispatcher } from 'svelte'

  const dispatch = createEventDispatcher<{
    selectChapter: { path: string; title: string }
  }>()

  interface Chapter {
    id: string
    title: string
    subtitle: string
    path: string
    section: 'covenant' | 'spec'
  }

  const CHAPTERS: Chapter[] = [
    {
      id: 'covenant',
      title: 'Language Covenant',
      subtitle: 'Core design values and paradigms',
      path: './igniter-ide/static/docs/language-covenant.md',
      section: 'covenant'
    },
    {
      id: 'spec-readme',
      title: 'Spec: Overview',
      subtitle: 'Igniter-Lang Specification introduction',
      path: './igniter-ide/static/docs/spec/README.md',
      section: 'spec'
    },
    {
      id: 'spec-ch1',
      title: 'Ch 1: Identity',
      subtitle: 'Identity and Semantic Model',
      path: './igniter-ide/static/docs/spec/ch1-identity.md',
      section: 'spec'
    },
    {
      id: 'spec-ch2',
      title: 'Ch 2: Source Surface',
      subtitle: 'Grammar and Syntax Surface',
      path: './igniter-ide/static/docs/spec/ch2-source-surface.md',
      section: 'spec'
    },
    {
      id: 'spec-ch3',
      title: 'Ch 3: Type System',
      subtitle: 'Contract native type rules',
      path: './igniter-ide/static/docs/spec/ch3-type-system.md',
      section: 'spec'
    },
    {
      id: 'spec-ch4',
      title: 'Ch 4: Fragments',
      subtitle: 'Fragment classification & boundary check',
      path: './igniter-ide/static/docs/spec/ch4-fragment-classification.md',
      section: 'spec'
    },
    {
      id: 'spec-ch5',
      title: 'Ch 5: Compiler Pipeline',
      subtitle: 'Four-stage compilation phases',
      path: './igniter-ide/static/docs/spec/ch5-compiler-pipeline.md',
      section: 'spec'
    },
    {
      id: 'spec-ch6',
      title: 'Ch 6: SemanticIR',
      subtitle: 'Intermediate representation & golden assembly',
      path: './igniter-ide/static/docs/spec/ch6-semanticir.md',
      section: 'spec'
    },
    {
      id: 'spec-ch7',
      title: 'Ch 7: RuntimeMachine',
      subtitle: 'Evaluation, state transition, and replay',
      path: './igniter-ide/static/docs/spec/ch7-runtime.md',
      section: 'spec'
    },
    {
      id: 'spec-ch8',
      title: 'Ch 8: Stdlib',
      subtitle: 'Decimal maths and collections',
      path: './igniter-ide/static/docs/spec/ch8-stdlib.md',
      section: 'spec'
    },
    {
      id: 'spec-ch10',
      title: 'Ch 10: Contract Modifiers',
      subtitle: 'Pure, observed, and irreversible scopes',
      path: './igniter-ide/static/docs/spec/ch10-contract-modifiers.md',
      section: 'spec'
    },
    {
      id: 'spec-ch11',
      title: 'Ch 11: Profiles',
      subtitle: 'Verification profile system',
      path: './igniter-ide/static/docs/spec/ch11-profile-system.md',
      section: 'spec'
    },
    {
      id: 'spec-ch12',
      title: 'Ch 12: Effect Surface',
      subtitle: 'Effects, subscriptions, and metrics',
      path: './igniter-ide/static/docs/spec/ch12-effect-surface.md',
      section: 'spec'
    },
    {
      id: 'spec-ch13',
      title: 'Ch 13: Service Loops',
      subtitle: 'Managed recursion and service loops',
      path: './igniter-ide/static/docs/spec/ch13-managed-recursion.md',
      section: 'spec'
    }
  ]

  let search = ''
  let activeId = ''

  $: filtered = CHAPTERS.filter(c => {
    const s = search.toLowerCase()
    return c.title.toLowerCase().includes(s) || c.subtitle.toLowerCase().includes(s)
  })

  function select(c: Chapter) {
    activeId = c.id
    dispatch('selectChapter', { path: c.path, title: c.title })
  }
</script>

<div class="flex flex-col h-full overflow-hidden bg-gray-900 border-r border-gray-800">
  <!-- Search Header -->
  <div class="p-3 border-b border-gray-800 shrink-0">
    <input
      type="text"
      bind:value={search}
      placeholder="Search chapters..."
      class="w-full bg-gray-950 border border-gray-700 rounded-lg px-2.5 py-1.5
             text-xs text-gray-200 outline-none focus:border-blue-500 transition-colors
             placeholder-gray-600"
    />
  </div>

  <!-- List -->
  <div class="flex-1 overflow-y-auto p-2 space-y-2">
    <!-- Covenant Section -->
    {#if filtered.some(c => c.section === 'covenant')}
      <div class="px-2.5 py-1 text-[9px] uppercase tracking-wider text-gray-600 font-bold select-none">
        Covenant
      </div>
      {#each filtered.filter(c => c.section === 'covenant') as c}
        <button
          on:click={() => select(c)}
          class="w-full text-left p-2.5 rounded-lg border transition-all flex flex-col gap-0.5
                 {activeId === c.id
                   ? 'bg-blue-600/15 border-blue-500 text-blue-100 shadow-md shadow-blue-500/5'
                   : 'bg-gray-950/40 border-gray-800 hover:border-gray-700 hover:bg-gray-800/40 text-gray-300'}"
        >
          <span class="text-xs font-semibold">{c.title}</span>
          <span class="text-[10px] text-gray-500 leading-normal">{c.subtitle}</span>
        </button>
      {/each}
    {/if}

    <!-- Spec Section -->
    {#if filtered.some(c => c.section === 'spec')}
      <div class="px-2.5 py-1 pt-3 text-[9px] uppercase tracking-wider text-gray-600 font-bold select-none">
        Specification Chapters
      </div>
      {#each filtered.filter(c => c.section === 'spec') as c}
        <button
          on:click={() => select(c)}
          class="w-full text-left p-2.5 rounded-lg border transition-all flex flex-col gap-0.5
                 {activeId === c.id
                   ? 'bg-blue-600/15 border-blue-500 text-blue-100 shadow-md shadow-blue-500/5'
                   : 'bg-gray-950/40 border-gray-800 hover:border-gray-700 hover:bg-gray-800/40 text-gray-300'}"
        >
          <span class="text-xs font-semibold">{c.title}</span>
          <span class="text-[10px] text-gray-500 leading-normal">{c.subtitle}</span>
        </button>
      {/each}
    {/if}

    {#if filtered.length === 0}
      <div class="text-center py-6 text-gray-600 text-xs italic">
        No chapters match "{search}"
      </div>
    {/if}
  </div>
</div>
