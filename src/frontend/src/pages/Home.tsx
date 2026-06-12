/**
 * Casa de Medina — Architectos de Architectura Inteligente
 */

import { Link } from 'react-router-dom'

const cards = [
  { title: 'Organism Dashboard', to: '/dashboard' },
  { title: 'The Architectonic Engine', to: '/engine' },
  { title: 'Activated Agents', to: '/agents' },
  { title: 'Renderability Architecture', to: '/renderability' },
  { title: 'Token Economy', to: '/token-economy' },
  { title: 'Reality → Release', to: '/reality-release' },
  { title: 'Executive View', to: '/executive' },
]

export default function Home() {
  return (
    <>
      <div className="page-hero">
        <h1>Medina / <span>The Architectonic Engine</span></h1>
        <p className="subheading">
          A computational organism built from renderable primitives, autonomous architecture,
          and activated thought systems.
        </p>
      </div>

      <div className="prose" style={{ marginBottom: '56px' }}>
        <p>Medina is not a product.</p>
        <p>
          It is a living stack — a structure that thinks, evolves, and expresses itself through
          architecture.
          At its core is the Architectonic Engine, the self‑evolving layer where Activated Agents
          operate as a coordinated micro‑civilization.
        </p>
        <p>
          Every packet, every build, every surface is part of a single organism learning how to
          become itself.
        </p>
      </div>

      <div className="cards-section">
        <h2>Explore the organism</h2>
        <div className="cards-grid">
          {cards.map(({ title, to }) => (
            <Link key={to} to={to} className="card">
              <div className="card__title">{title}</div>
              <div className="card__arrow">Explore →</div>
            </Link>
          ))}
        </div>
      </div>
    </>
  )
}
