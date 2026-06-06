<script lang="ts">
  export let variant: 'original' | 'oval' = 'oval'
  export let ground: 'ink' | 'amber' | 'paper' = 'ink'
  export let glow: boolean | null = null

  $: effectiveGlow = glow !== null ? glow : ground === 'ink'

  const IGNITE = '#ff6a3d'
  const AMBER_INK = '#1a1109'
  const WHITE = '#fff2e4'
  const PAPER_INK = '#2a2018'

  $: armColor = ground === 'amber' ? AMBER_INK : IGNITE
  $: pearlColor = ground === 'paper' ? PAPER_INK : WHITE

  const SPOKES = [
    { x1: 50, y1: 50, x2: 50, y2: 12 },
    { x1: 50, y1: 50, x2: 82.91, y2: 31 },
    { x1: 50, y1: 50, x2: 82.91, y2: 69 },
    { x1: 50, y1: 50, x2: 50, y2: 88 },
    { x1: 50, y1: 50, x2: 17.09, y2: 69 },
    { x1: 50, y1: 50, x2: 17.09, y2: 31 }
  ]
</script>

<svg
  viewBox="0 0 100 100"
  class="mk shrink-0 overflow-visible select-none {$$props.class || 'w-6 h-6'}"
  aria-hidden="true"
>
  {#if effectiveGlow}
    <circle cx="50" cy="50" r="34" fill="url(#ig-glow)"/>
  {/if}

  {#each SPOKES as s}
    <line x1={s.x1} y1={s.y1} x2={s.x2} y2={s.y2} stroke={armColor} stroke-width="10" stroke-linecap="round"/>
  {/each}

  {#if ground === 'ink'}
    <circle cx="50" cy="50" r="9" fill="url(#ig-spark)"/>
  {:else}
    <circle cx="50" cy="50" r="9" fill={armColor}/>
  {/if}

  <circle cx="50" cy="50" r="3.8" fill={pearlColor}/>

  {#if variant === 'oval'}
    <ellipse cx="50" cy="31" rx="3" ry="6.5" fill={pearlColor}/>
  {/if}
</svg>
