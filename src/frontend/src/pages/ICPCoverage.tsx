/**
 * ICP Coverage Dashboard — Protocol-wide ICP Position Tracker
 * 
 * Casa de Medina — Architectos de Architectura Inteligente
 */

import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'

// Types matching the icp_coverage canister
interface ICPPosition {
  id: number
  source: string
  description: string
  amountE8s: bigint
  isStaked: boolean
  yieldBPS: number
  lastUpdated: bigint
  metadata: string
}

interface CoverageSnapshot {
  totalCoverageE8s: bigint
  stakedE8s: bigint
  liquidE8s: bigint
  backedE8s: bigint
  revenueAccruedE8s: bigint
  neuronCount: number
  avgNeuronAPY_BPS: number
  estimatedYieldE8s: bigint
  coverageRatio: number
  phiPortfolioIndex: number
  positionCount: number
  flowCountYTD: number
  timestamp: bigint
}

// Mock data for demonstration (replace with actual canister calls)
const mockSnapshot: CoverageSnapshot = {
  totalCoverageE8s: BigInt(215_000_000_000),   // 2150 ICP
  stakedE8s: BigInt(200_000_000_000),          // 2000 ICP in neurons
  liquidE8s: BigInt(10_000_000_000),           // 100 ICP liquid
  backedE8s: BigInt(5_000_000_000),            // 50 ICP backing NNC
  revenueAccruedE8s: BigInt(2_500_000_000),    // 25 ICP revenue YTD
  neuronCount: 200,
  avgNeuronAPY_BPS: 1200,                      // 12% average
  estimatedYieldE8s: BigInt(24_000_000_000),   // ~240 ICP annual yield
  coverageRatio: 0.93,                         // 93% staked
  phiPortfolioIndex: 3200.5,                   // φ-weighted score
  positionCount: 4,
  flowCountYTD: 127,
  timestamp: BigInt(Date.now() * 1_000_000),
}

const mockPositions: ICPPosition[] = [
  {
    id: 0,
    source: 'NNSNeurons',
    description: 'NNS 200-Neuron Fleet (8 Fibonacci Tiers)',
    amountE8s: BigInt(200_000_000_000),
    isStaked: true,
    yieldBPS: 1200,
    lastUpdated: BigInt(Date.now() * 1_000_000),
    metadata: '{"neurons":200,"tiers":8,"manager":"nns_proxy"}',
  },
  {
    id: 1,
    source: 'Treasury',
    description: 'Protocol Treasury (Liquid Reserve)',
    amountE8s: BigInt(10_000_000_000),
    isStaked: false,
    yieldBPS: 0,
    lastUpdated: BigInt(Date.now() * 1_000_000),
    metadata: '{"manager":"parallax","purpose":"operations"}',
  },
  {
    id: 2,
    source: 'CycleConversion',
    description: 'NNC Floor Rate Backing',
    amountE8s: BigInt(5_000_000_000),
    isStaked: false,
    yieldBPS: 0,
    lastUpdated: BigInt(Date.now() * 1_000_000),
    metadata: '{"nncBacked":"3.82T","floor":"1/PHI^2"}',
  },
  {
    id: 3,
    source: 'RevenueStream',
    description: 'Revenue Engine Accumulator',
    amountE8s: BigInt(2_500_000_000),
    isStaked: false,
    yieldBPS: 500,
    lastUpdated: BigInt(Date.now() * 1_000_000),
    metadata: '{"manager":"revenue_engine","streams":["sns_swap","nnc_sales","premium"]}',
  },
]

// Utility functions
const formatICP = (e8s: bigint): string => {
  const icp = Number(e8s) / 100_000_000
  return icp.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

const formatPercent = (value: number): string => {
  return (value * 100).toFixed(1) + '%'
}

const formatBPS = (bps: number): string => {
  return (bps / 100).toFixed(2) + '%'
}

const sourceIcon = (source: string): string => {
  switch (source) {
    case 'NNSNeurons': return '🧠'
    case 'Treasury': return '🏦'
    case 'CycleConversion': return '⚡'
    case 'RevenueStream': return '📈'
    default: return '💰'
  }
}

export default function ICPCoverage() {
  const [snapshot, setSnapshot] = useState<CoverageSnapshot>(mockSnapshot)
  const [positions, setPositions] = useState<ICPPosition[]>(mockPositions)
  const [loading, setLoading] = useState(false)

  // In production, fetch from icp_coverage canister
  useEffect(() => {
    async function fetchCoverage() {
      setLoading(true)
      try {
        // TODO: Replace with actual canister calls when deployed
        // const actor = await createActor(canisterId)
        // const snap = await actor.getCoverageSnapshot()
        // setSnapshot(snap)
        // const pos = await actor.getPositions()
        // setPositions(pos)
        setSnapshot(mockSnapshot)
        setPositions(mockPositions)
      } finally {
        setLoading(false)
      }
    }
    fetchCoverage()
  }, [])

  return (
    <>
      <Link to="/" className="back-link">← Back</Link>
      <div className="page-hero">
        <h1>ICP Coverage — <span>Protocol-wide ICP Position Tracker</span></h1>
      </div>

      {loading && <div style={{ textAlign: 'center', padding: '2rem', color: 'var(--text-muted)' }}>Loading coverage data…</div>}

      {/* Summary Cards */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
        gap: '1rem',
        marginBottom: '2rem',
      }}>
        <div className="card" style={{ textAlign: 'center' }}>
          <div style={{ fontSize: '2rem', fontWeight: 700, color: 'var(--accent-gold)' }}>
            {formatICP(snapshot.totalCoverageE8s)} ICP
          </div>
          <div style={{ fontSize: '0.9rem', opacity: 0.8 }}>Total Coverage</div>
        </div>

        <div className="card" style={{ textAlign: 'center' }}>
          <div style={{ fontSize: '2rem', fontWeight: 700, color: 'var(--accent-green)' }}>
            {formatICP(snapshot.stakedE8s)} ICP
          </div>
          <div style={{ fontSize: '0.9rem', opacity: 0.8 }}>Staked in NNS</div>
        </div>

        <div className="card" style={{ textAlign: 'center' }}>
          <div style={{ fontSize: '2rem', fontWeight: 700, color: 'var(--accent-blue)' }}>
            {formatPercent(snapshot.coverageRatio)}
          </div>
          <div style={{ fontSize: '0.9rem', opacity: 0.8 }}>Coverage Ratio</div>
        </div>

        <div className="card" style={{ textAlign: 'center' }}>
          <div style={{ fontSize: '2rem', fontWeight: 700, color: 'var(--accent-purple)' }}>
            {formatBPS(snapshot.avgNeuronAPY_BPS)}
          </div>
          <div style={{ fontSize: '0.9rem', opacity: 0.8 }}>Avg Neuron APY</div>
        </div>
      </div>

      {/* Neuron Fleet Summary */}
      <div className="card" style={{ marginBottom: '2rem' }}>
        <h2 style={{ marginBottom: '1rem' }}>🧠 NNS Neuron Fleet</h2>
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))',
          gap: '1rem',
        }}>
          <div>
            <div style={{ fontSize: '1.5rem', fontWeight: 600 }}>{snapshot.neuronCount}</div>
            <div style={{ fontSize: '0.85rem', opacity: 0.7 }}>Active Neurons</div>
          </div>
          <div>
            <div style={{ fontSize: '1.5rem', fontWeight: 600 }}>8</div>
            <div style={{ fontSize: '0.85rem', opacity: 0.7 }}>Fibonacci Tiers</div>
          </div>
          <div>
            <div style={{ fontSize: '1.5rem', fontWeight: 600 }}>~{formatICP(snapshot.estimatedYieldE8s)}</div>
            <div style={{ fontSize: '0.85rem', opacity: 0.7 }}>Est. Annual Yield</div>
          </div>
          <div>
            <div style={{ fontSize: '1.5rem', fontWeight: 600 }}>{snapshot.phiPortfolioIndex.toFixed(1)}</div>
            <div style={{ fontSize: '0.85rem', opacity: 0.7 }}>φ Portfolio Index</div>
          </div>
        </div>

        {/* Tier Distribution */}
        <div style={{ marginTop: '1.5rem' }}>
          <h3 style={{ marginBottom: '0.5rem', fontSize: '1rem' }}>Dissolve Tier Distribution</h3>
          <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
            {['6mo', '1y', 'φy', 'φ²y', 'φ³y', 'φ⁴y', 'φ⁵y', 'φ⁶y'].map((tier, i) => (
              <div key={i} style={{
                padding: '0.5rem 1rem',
                background: 'rgba(255,215,0,0.1)',
                borderRadius: '8px',
                textAlign: 'center',
                minWidth: '60px',
              }}>
                <div style={{ fontWeight: 600 }}>25</div>
                <div style={{ fontSize: '0.75rem', opacity: 0.7 }}>{tier}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ICP Positions */}
      <div className="card" style={{ marginBottom: '2rem' }}>
        <h2 style={{ marginBottom: '1rem' }}>💰 ICP Positions</h2>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)' }}>
              <th style={{ textAlign: 'left', padding: '0.75rem' }}>Source</th>
              <th style={{ textAlign: 'left', padding: '0.75rem' }}>Description</th>
              <th style={{ textAlign: 'right', padding: '0.75rem' }}>Amount</th>
              <th style={{ textAlign: 'right', padding: '0.75rem' }}>Yield</th>
              <th style={{ textAlign: 'center', padding: '0.75rem' }}>Status</th>
            </tr>
          </thead>
          <tbody>
            {positions.map((pos) => (
              <tr key={pos.id} style={{ borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                <td style={{ padding: '0.75rem' }}>
                  <span style={{ marginRight: '0.5rem' }}>{sourceIcon(pos.source)}</span>
                  {pos.source}
                </td>
                <td style={{ padding: '0.75rem', opacity: 0.9 }}>{pos.description}</td>
                <td style={{ padding: '0.75rem', textAlign: 'right', fontFamily: 'monospace' }}>
                  {formatICP(pos.amountE8s)} ICP
                </td>
                <td style={{ padding: '0.75rem', textAlign: 'right' }}>
                  {pos.yieldBPS > 0 ? formatBPS(pos.yieldBPS) : '—'}
                </td>
                <td style={{ padding: '0.75rem', textAlign: 'center' }}>
                  <span style={{
                    padding: '0.25rem 0.75rem',
                    borderRadius: '999px',
                    fontSize: '0.75rem',
                    background: pos.isStaked ? 'rgba(34,197,94,0.2)' : 'rgba(59,130,246,0.2)',
                    color: pos.isStaked ? '#22c55e' : '#3b82f6',
                  }}>
                    {pos.isStaked ? 'Staked' : 'Liquid'}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Mainnet Canister IDs */}
      <div className="card" style={{ marginBottom: '2rem' }}>
        <h2 style={{ marginBottom: '1rem' }}>🔗 ICP Mainnet Canisters</h2>
        <div style={{ fontFamily: 'monospace', fontSize: '0.9rem', lineHeight: 1.8 }}>
          <div><strong>ICP Ledger:</strong> ryjl3-tyaaa-aaaaa-aaaba-cai</div>
          <div><strong>NNS Governance:</strong> rrkah-fqaaa-aaaaa-aaaaq-cai</div>
          <div><strong>Cycles Minting:</strong> rkp4c-7iaaa-aaaaa-aaaca-cai</div>
        </div>
      </div>

      {/* Protocol Overview */}
      <div className="prose">
        <h2>About ICP Coverage</h2>
        <p>
          ICP Coverage tracks all ICP-denominated positions across the Native Nova Protocol:
        </p>
        <ul>
          <li><strong>NNS Neurons</strong> — 200 neurons across 8 Fibonacci dissolve tiers earning ~12% voting rewards</li>
          <li><strong>Treasury</strong> — Liquid ICP for protocol operations and cycle purchases</li>
          <li><strong>Cycle Backing</strong> — ICP backing the NNC floor rate at 1/φ²</li>
          <li><strong>Revenue Streams</strong> — ICP from SNS swaps, NNC sales, and premium spreads</li>
        </ul>
        <p>
          The φ-weighted portfolio index measures governance alignment: higher tiers (longer dissolve)
          receive greater weight, incentivizing long-term commitment.
        </p>
      </div>
    </>
  )
}
