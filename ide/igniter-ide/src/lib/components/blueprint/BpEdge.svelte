<!--
  BpEdge.svelte ��� Renders a single bezier edge between two nodes.
  Called from BlueprintCanvas inside an <svg> element.
  Props: all positions are already in canvas space.
-->
<script lang="ts">
  export let x1: number  // source port x
  export let y1: number  // source port y
  export let x2: number  // target port x
  export let y2: number  // target port y
  export let label: string = ''
  export let selected: boolean = false
  export let dimmed: boolean = false

  // Cubic bezier control points ��� horizontal tension
  $: dx = Math.max(Math.abs(x2 - x1) * 0.5, 80)
  $: cx1 = x1 + dx
  $: cy1 = y1
  $: cx2 = x2 - dx
  $: cy2 = y2
  $: d   = `M ${x1} ${y1} C ${cx1} ${cy1}, ${cx2} ${cy2}, ${x2} ${y2}`

  // Mid-point for label positioning
  $: mx = (x1 + x2) / 2
  $: my = (y1 + y2) / 2 - 6
</script>

<!-- Shadow / glow for selected -->
{#if selected}
  <path {d} stroke="#ff6a3d" stroke-width="6" fill="none" stroke-opacity="0.2" />
{/if}

<!-- Main edge path -->
<path
  {d}
  stroke={selected ? '#ff885e' : dimmed ? '#251b14' : '#554235'}
  stroke-width={selected ? 2 : 1.5}
  fill="none"
  stroke-linecap="round"
  opacity={dimmed ? 0.35 : 1}
/>

<!-- Arrow head at target -->
<circle cx={x2} cy={y2} r={3}
  fill={selected ? '#ff885e' : dimmed ? '#251b14' : '#554235'}
  opacity={dimmed ? 0.35 : 1}
/>

<!-- Optional label at midpoint -->
{#if label}
  <text
    x={mx} y={my}
    text-anchor="middle"
    font-size="9"
    fill="#887568"
    class="select-none pointer-events-none font-mono"
  >{label}</text>
{/if}
