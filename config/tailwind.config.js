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
        // Rojo Corporativo (Principal - Gente del Sol)
        primary: {
          DEFAULT: '#DC3545',
          dark: '#C02E3C',
          light: '#FDE8EA',
          50: '#FEF5F5',
        },
        
        // Teal/Cyan - Para ventas y métricas positivas
        teal: {
          DEFAULT: '#14B8A6',
          dark: '#0F766E',
          light: '#99F6E4',
        },
        
        // Coral/Naranja - Para alertas y warnings
        coral: {
          DEFAULT: '#FB923C',
          dark: '#EA580C',
          light: '#FED7AA',
        },
        
        // Púrpura - Para métricas secundarias
        purple: {
          DEFAULT: '#A855F7',
          dark: '#7C3AED',
          light: '#E9D5FF',
        },
        
        // Azul - Para información
        blue: {
          DEFAULT: '#3B82F6',
          dark: '#1E40AF',
          light: '#DBEAFE',
        },
        
        // Slate/Gris (ya lo tenías, pero lo mantengo)
        slate: {
          dark: '#4A5568',
          darker: '#2D3748',
        },
        
        // Success (verde)
        success: {
          DEFAULT: '#10B981',
          dark: '#059669',
          light: '#D1FAE5',
        },
        
        // Warning (amarillo)
        warning: {
          DEFAULT: '#F59E0B',
          dark: '#D97706',
          light: '#FEF3C7',
        },
        
        // Error (rojo - mismo que primary)
        error: {
          DEFAULT: '#DC3545',
          light: '#FEE2E2',
        },
      },
      
      // Sombras Premium
      boxShadow: {
        'soft': '0 2px 15px -3px rgba(0, 0, 0, 0.07), 0 10px 20px -2px rgba(0, 0, 0, 0.04)',
        'card': '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
        'card-hover': '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
        'premium': '0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)',
        'glow-teal': '0 0 20px rgba(20, 184, 166, 0.3)',
        'glow-primary': '0 0 20px rgba(220, 53, 69, 0.3)',
      },
      
      // Border Radius adicionales
      borderRadius: {
        'card': '16px',
        'card-lg': '20px',
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