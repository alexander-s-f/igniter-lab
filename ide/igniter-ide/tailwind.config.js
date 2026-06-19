export default {
  content: ['./src/**/*.{html,svelte,ts,js}'],
  theme: {
    extend: {
      colors: {
        ink:    { DEFAULT: '#15110d', 1: '#1a1510', 2: '#221b15', line: '#2b221b' },
        ignite: '#ff6a3d',
        ember:  '#ffb07a',
        amber:  '#f0a868',
        warm:   { DEFAULT: '#9a8a7c', 3: '#e7ddd2' },
        // semantic retuned for ink ground
        core:     '#5db87a',
        escape:   '#f0a868',
        temporal: '#5ec8d8',
        oof:      '#d9694a',
      },
    },
  },
  plugins: [],
}
