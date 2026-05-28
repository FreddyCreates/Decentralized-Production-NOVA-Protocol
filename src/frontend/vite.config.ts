import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => ({
  plugins: [react()],
  publicDir: false,
  define: {
    'process.env.DFX_NETWORK': JSON.stringify(
      mode === 'production' ? 'ic' : 'local'
    ),
  },
  build: {
    outDir: '../../public',
    emptyOutDir: false,
    target: 'es2020',
    sourcemap: mode !== 'production',
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', 'react-router-dom'],
          state: ['zustand', 'xstate', '@xstate/react', 'immer'],
          query: ['@tanstack/react-query'],
        },
      },
    },
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:4943',
        changeOrigin: true,
      },
    },
  },
}))
