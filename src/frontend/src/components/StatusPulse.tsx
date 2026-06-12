/**
 * StatusPulse — Live organism health indicator with φ-animated pulse
 *
 * Casa de Medina — Architectos de Architectura Inteligente
 */

import { useEffect, useState } from 'react'
import { useNovaStore, PHI } from '../store/nova-store'

type HealthLevel = 'optimal' | 'nominal' | 'degraded' | 'critical'

function getHealthLevel(health: number): HealthLevel {
  if (health >= 0.9) return 'optimal'
  if (health >= 0.618) return 'nominal'   // φ⁻¹ threshold
  if (health >= 0.382) return 'degraded'  // φ⁻² threshold
  return 'critical'
}

function getHealthColor(level: HealthLevel): string {
  switch (level) {
    case 'optimal': return 'var(--color-health-optimal, #4caf50)'
    case 'nominal': return 'var(--color-health-nominal, #c9a84c)'
    case 'degraded': return 'var(--color-health-degraded, #ff9800)'
    case 'critical': return 'var(--color-health-critical, #f44336)'
  }
}

interface StatusPulseProps {
  size?: 'sm' | 'md' | 'lg'
  showLabel?: boolean
}

export default function StatusPulse({ size = 'md', showLabel = true }: StatusPulseProps) {
  const systemHealth = useNovaStore((s) => s.systemHealth)
  const [beat, setBeat] = useState(false)

  useEffect(() => {
    // φ-timed heartbeat pulse (1618ms interval)
    const interval = setInterval(() => {
      setBeat(true)
      setTimeout(() => setBeat(false), 300)
    }, Math.round(PHI * 1000))

    return () => clearInterval(interval)
  }, [])

  const level = getHealthLevel(systemHealth)
  const color = getHealthColor(level)
  const sizeMap = { sm: 8, md: 12, lg: 18 }
  const dotSize = sizeMap[size]

  return (
    <div className="status-pulse" aria-label={`System health: ${level}`}>
      <span
        className={`status-pulse__dot ${beat ? 'status-pulse__dot--beat' : ''}`}
        style={{
          width: dotSize,
          height: dotSize,
          backgroundColor: color,
          boxShadow: beat ? `0 0 ${dotSize}px ${color}` : 'none',
        }}
      />
      {showLabel && (
        <span className="status-pulse__label" style={{ color }}>
          {level.charAt(0).toUpperCase() + level.slice(1)} — {Math.round(systemHealth * 100)}%
        </span>
      )}
    </div>
  )
}
