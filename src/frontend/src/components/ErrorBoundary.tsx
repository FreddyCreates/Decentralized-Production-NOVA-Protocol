/**
 * ErrorBoundary — Graceful failure capture with φ-styled recovery UI
 *
 * Casa de Medina — Architectos de Architectura Inteligente
 */

import { Component, type ReactNode, type ErrorInfo } from 'react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
}

interface State {
  hasError: boolean
  error: Error | null
}

export default class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[NOVA] ErrorBoundary caught:', error, info.componentStack)
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null })
  }

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback

      return (
        <div className="error-boundary">
          <div className="error-boundary__icon">⚠</div>
          <h2 className="error-boundary__title">Organism Fault Detected</h2>
          <p className="error-boundary__message">
            {this.state.error?.message || 'An unexpected error occurred in the substrate.'}
          </p>
          <button className="error-boundary__btn" onClick={this.handleReset}>
            Reinitialize Component
          </button>
        </div>
      )
    }

    return this.props.children
  }
}
