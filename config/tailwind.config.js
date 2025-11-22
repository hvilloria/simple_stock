const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
      },
      colors: {
        // Rojo Corporativo (Gente del Sol) - SOLO para logo
        brand: {
          DEFAULT: '#DC3545',
          dark: '#C02E3C',
        },
        // Usamos las escalas nativas de Tailwind para el resto:
        // - slate: base neutral (grises fríos profesionales)
        // - emerald: success/confirmado/activo
        // - blue: pending/información
        // - amber: warning/stock bajo
        // - red: error/rechazado/cancelado
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/aspect-ratio'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/container-queries'),
  ]
}