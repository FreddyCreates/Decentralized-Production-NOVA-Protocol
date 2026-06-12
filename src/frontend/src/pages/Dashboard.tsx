/**
 * Dashboard — Live organism health visualization
 *
 * Displays canister states, connections, and system metrics
 * with φ-mathematics driven layout and real-time updates.
 *
 * Casa de Medina — Architectos de Architectura Inteligente
 */

import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import {
  useNovaStore,
  selectCanistersByPriority,
  selectActiveCanisters,
  PHI,
  fib,
} from '../store/nova-store'
import StatusPulse from '../components/StatusPulse'

export default function Dashboard() {
  const canisters = useNovaStore(selectCanistersByPriority)
  const activeCanisters = useNovaStore(selectActiveCanisters)
  const connections = useNovaStore((s) => s.connections)
  const totalCycles = useNovaStore((s) => s.totalCycles)
  const totalMemory = useNovaStore((s) => s.totalMemory)
  const syncWithBackend = useNovaStore((s) => s.syncWithBackend)

  // φ-timed auto-sync
  useEffect(() => {
    const interval = setInterval(() => {
      syncWithBackend()
    }, Math.round(PHI * 1000))
    return () => clearInterval(interval)
  }, [syncWithBackend])

  const formatCycles = (cycles: number): string => {
    if (cycles >= 1_000_000_000) return `${(cycles / 1_000_000_000).toFixed(2)}B`
    if (cycles >= 1_000_000) return `${(cycles / 1_000_000).toFixed(2)}M`
    if (cycles >= 1_000) return `${(cycles / 1_000).toFixed(1)}K`
    return String(cycles)
  }

  const formatMemory = (bytes: number): string => {
    if (bytes >= 1_073_741_824) return `${(bytes / 1_073_741_824).toFixed(2)} GB`
    if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(1)} MB`
    if (bytes >= 1_024) return `${(bytes / 1_024).toFixed(0)} KB`
    return `${bytes} B`
  }

  return (
    <>
      <Link to="/" className="back-link">← Back</Link>
      <div className="page-hero">
        <h1>Organism <span>Dashboard</span></h1>
        <p className="subheading">
          Live system telemetry with φ-weighted priority ordering
        </p>
      </div>

      {/* Metrics Bar */}
      <div className="dashboard-metrics">
        <div className="dashboard-metrics__item">
          <span className="dashboard-metrics__label">System Health</span>
          <StatusPulse size="lg" />
        </div>
        <div className="dashboard-metrics__item">
          <span className="dashboard-metrics__label">Active Canisters</span>
          <span className="dashboard-metrics__value">{activeCanisters.length}</span>
        </div>
        <div className="dashboard-metrics__item">
          <span className="dashboard-metrics__label">Connections</span>
          <span className="dashboard-metrics__value">{connections.length}</span>
        </div>
        <div className="dashboard-metrics__item">
          <span className="dashboard-metrics__label">Total Cycles</span>
          <span className="dashboard-metrics__value">{formatCycles(totalCycles)}</span>
        </div>
        <div className="dashboard-metrics__item">
          <span className="dashboard-metrics__label">Memory Used</span>
          <span className="dashboard-metrics__value">{formatMemory(totalMemory)}</span>
        </div>
      </div>

      {/* Canister Grid */}
      {canisters.length > 0 ? (
        <section className="dashboard-section">
          <h2>Canister Registry — φ-Priority Order</h2>
          <div className="dashboard-grid">
            {canisters.map((canister) => (
              <div
                key={canister.id}
                className={`dashboard-card dashboard-card--${canister.elementClass}`}
              >
                <div className="dashboard-card__header">
                  <span className="dashboard-card__name">{canister.name}</span>
                  <span className={`dashboard-card__status dashboard-card__status--${canister.status}`}>
                    {canister.status}
                  </span>
                </div>
                <div className="dashboard-card__meta">
                  <span>Cycles: {formatCycles(canister.cycleBalance)}</span>
                  <span>Memory: {formatMemory(canister.memoryUsed)}</span>
                </div>
                <div className="dashboard-card__element">
                  {canister.elementClass}
                </div>
              </div>
            ))}
          </div>
        </section>
      ) : (
        <section className="dashboard-section">
          <div className="dashboard-empty">
            <p>No canisters registered yet.</p>
            <p className="dashboard-empty__hint">
              The organism is dormant. Deploy canisters to activate the substrate.
              Fibonacci threshold: F({fib(8)}) cycles minimum for metric updates.
            </p>
          </div>
        </section>
      )}
    </>
  )
}
