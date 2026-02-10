/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // DEFCON colors
        defcon: {
          peace: '#22c55e',
          elevated: '#eab308',
          high: '#f97316',
          severe: '#ef4444',
          critical: '#dc2626'
        },
        // SAM state colors
        sam: {
          green: '#22c55e',
          dark: '#6b7280',
          tracking: '#eab308',
          engaging: '#ef4444'
        },
        // Threat level colors
        threat: {
          low: '#22c55e',
          medium: '#eab308',
          high: '#f97316',
          critical: '#ef4444'
        }
      }
    },
  },
  plugins: [],
}
