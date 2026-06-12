import { NavLink, Outlet } from 'react-router-dom'
import ErrorBoundary from './ErrorBoundary'
import MobileNav from './MobileNav'
import StatusPulse from './StatusPulse'

const navItems = [
  { to: '/', label: 'Home', end: true },
  { to: '/dashboard', label: 'Dashboard' },
  { to: '/engine', label: 'Engine' },
  { to: '/agents', label: 'Agents' },
  { to: '/renderability', label: 'Renderability' },
  { to: '/token-economy', label: 'Token Economy' },
  { to: '/icp-coverage', label: 'ICP Coverage' },
  { to: '/reality-release', label: 'Reality → Release' },
  { to: '/executive', label: 'Executive' },
  { to: '/et', label: 'EffectTrace' },
]

export default function Layout() {
  return (
    <>
      <nav className="navbar">
        <div className="navbar__inner">
          <span className="navbar__brand">MEDINA / NOVA</span>
          <StatusPulse size="sm" showLabel={false} />
          <div className="navbar__links navbar__links--desktop">
            {navItems.map(({ to, label, end }) => (
              <NavLink
                key={to}
                to={to}
                end={end}
                className={({ isActive }) =>
                  'navbar__link' + (isActive ? ' active' : '')
                }
              >
                {label}
              </NavLink>
            ))}
          </div>
          <MobileNav items={navItems} />
        </div>
      </nav>

      <main className="main">
        <div className="container">
          <ErrorBoundary>
            <Outlet />
          </ErrorBoundary>
        </div>
      </main>

      <footer className="footer">
        <span>Casa de Medina — Architectos de Architectura Inteligente</span>
        <span className="footer__version">Node ≥20 · TypeScript · React · φ-Mathematics</span>
      </footer>
    </>
  )
}
