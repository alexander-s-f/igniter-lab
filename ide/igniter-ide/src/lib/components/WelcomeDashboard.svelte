<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import IgMark from './IgMark.svelte'

  const dispatch = createEventDispatcher<{
    tryDemoBlueprint: void
    newFile: { templateId: string }
    openDoc: { path: string; title: string }
  }>()

  interface TemplateItem {
    id: string
    title: string
    description: string
    icon: string
    color: string
  }

  const TEMPLATES: TemplateItem[] = [
    { id: 'empty',     title: 'Empty Contract',     description: 'Minimal schema, single input & output', icon: '���', color: 'border-core/30 text-core bg-core/5' },
    { id: 'transform', title: 'Data Transform',     description: 'Multi-step pure function pipeline',      icon: '���', color: 'border-temporal/30 text-temporal bg-temporal/5' },
    { id: 'projection',title: 'observed Projection', description: 'Observable state with durable store reads',icon: '���', color: 'border-escape/30 text-escape bg-escape/5' },
    { id: 'windowed',  title: 'Windowed Projection', description: 'Aggregates collection over calendar time', icon: '���', color: 'border-temporal/30 text-temporal bg-temporal/5' },
    { id: 'validator', title: 'Monadic Validator',  description: 'Input sanity check using Result monad',   icon: '���', color: 'border-core/30 text-core bg-core/5' },
    { id: 'loop',      title: 'Loop Contract',      description: 'Iterative reduction over an array',       icon: '���', color: 'border-ignite/30 text-ignite bg-ignite/5' },
    { id: 'extension', title: 'Stdlib Extension',  description: 'Pure helper functions block module',       icon: '���', color: 'border-warm/30 text-warm bg-warm/5' }
  ]

  interface DocLink {
    title: string
    path: string
  }

  const DOCS: DocLink[] = [
    { title: 'Language Covenant', path: './igniter-ide/static/docs/language-covenant.md' },
    { title: 'Ch 2: Source Surface & Grammar', path: './igniter-ide/static/docs/spec/ch2-source-surface.md' },
    { title: 'Ch 3: Type System Rules', path: './igniter-ide/static/docs/spec/ch3-type-system.md' },
    { title: 'Ch 7: Runtime Machine', path: './igniter-ide/static/docs/spec/ch7-runtime.md' }
  ]
</script>

<div class="h-full w-full ig-field overflow-y-auto px-8 py-10 flex flex-col items-center">
  <div class="max-w-4xl w-full space-y-10">
    <!-- Welcome Header -->
    <div class="text-center space-y-4 flex flex-col items-center">
      <!-- Center Oval Mark & Wordmark -->
      <div class="flex items-center gap-3 mb-2">
        <IgMark variant="oval" class="w-16 h-16" />
        <div class="wm text-3xl">
          <span class="ig">igniter</span><span class="dash">-</span><span class="lang">ide</span>
        </div>
      </div>

      <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-ignite/25 bg-ignite/5 text-ignite text-[10px] font-bold uppercase tracking-wider">
        <span>Igniter Lang Lab</span>
        <span class="w-1.5 h-1.5 rounded-full bg-ignite animate-ping"></span>
      </div>
      <h1 class="text-4xl font-extrabold tracking-tight text-warm-3 sm:text-5xl font-mono">
        Develop Validate <span class="text-ignite">Execute</span>
      </h1>
      <p class="text-warm text-sm max-w-xl mx-auto leading-relaxed font-sans">
        Declarative business logic as validation-sound dependency graphs with compile-time check gates. Start coding visually or read the specs.
      </p>
    </div>

    <!-- Quick Entry Split -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
      <!-- Try visual blueprint sandbox -->
      <button
        on:click={() => dispatch('tryDemoBlueprint')}
        class="group text-left p-5 bg-ink-1 border border-ink-line rounded-xl hover:border-ignite/40 transition-all duration-300 relative overflow-hidden cursor-pointer"
      >
        <div class="absolute inset-0 bg-ignite/5 opacity-0 group-hover:opacity-100 transition-opacity"></div>
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-lg bg-ignite/10 border border-ignite/30 flex items-center justify-center text-ignite text-lg font-bold">
            ���
          </div>
          <div class="space-y-1">
            <h3 class="text-sm font-bold text-warm-3 group-hover:text-ignite transition-colors font-mono">Visual Blueprint Sandbox</h3>
            <p class="text-xs text-warm leading-normal font-sans">
              Toggle the graphical builder to inspect node data flows, window scopes, and validation invariants interactively.
            </p>
          </div>
        </div>
      </button>

      <!-- Read reference textbook -->
      <div
        class="p-5 bg-ink-1 border border-ink-line rounded-xl space-y-3"
      >
        <div class="flex items-center gap-2">
          <span class="text-temporal text-sm">����</span>
          <h3 class="text-xs font-bold text-warm uppercase tracking-wider font-mono">Specs Textbook</h3>
        </div>
        <div class="grid grid-cols-2 gap-2">
          {#each DOCS as doc}
            <button
              on:click={() => dispatch('openDoc', { path: doc.path, title: doc.title })}
              class="text-left text-xs text-warm hover:text-temporal transition-colors truncate p-1.5 rounded hover:bg-ink-2/60 cursor-pointer font-mono"
            >
              ��� {doc.title}
            </button>
          {/each}
        </div>
      </div>
    </div>

    <!-- Educational Scaffolds Checklist -->
    <div class="space-y-4 font-mono">
      <div class="flex items-center justify-between border-b border-ink-line pb-2">
        <h2 class="text-xs font-bold text-warm uppercase tracking-widest">Create from Scaffold</h2>
        <span class="text-[10px] text-warm/60">Zero-config compilable structures</span>
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
        {#each TEMPLATES as t}
          <button
            on:click={() => dispatch('newFile', { templateId: t.id })}
            class="group text-left p-3.5 bg-ink-1 border border-ink-line/60 rounded-xl hover:border-warm/30 hover:bg-ink-2 transition-all duration-200 cursor-pointer"
          >
            <div class="flex items-center gap-3">
              <div class="w-8 h-8 rounded-lg border flex items-center justify-center font-bold text-sm shrink-0 {t.color}">
                {t.icon}
              </div>
              <div class="min-w-0 flex-1">
                <div class="text-xs font-semibold text-warm-2 group-hover:text-warm-3 transition-colors">{t.title}</div>
                <div class="text-[10px] text-warm/60 truncate mt-0.5 font-sans">{t.description}</div>
              </div>
            </div>
          </button>
        {/each}
      </div>
    </div>
  </div>
</div>
