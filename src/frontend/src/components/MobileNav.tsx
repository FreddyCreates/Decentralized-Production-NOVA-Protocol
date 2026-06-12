/**
 * MobileNav — Responsive hamburger navigation for NOVA Platform
 *
 * Casa de Medina — Architectos de Architectura Inteligente
 */

import { useState, useEffect } from 'react'
import { NavLink, useLocation } from 'react-router-dom'

interface NavItem {
  to: string
  label: string
  end?: boolean
}

interface MobileNavProps {
  items: NavItem[]
}

export default function MobileNav({ items }: MobileNavProps) {
  const [isOpen, setIsOpen] = useState(false)
  const location = useLocation()

  // Close menu on route change
  useEffect(() => {
    setIsOpen(false)
  }, [location.pathname])

  // Prevent scroll when menu is open
  useEffect(() => {
    document.body.style.overflow = isOpen ? 'hidden' : ''
    return () => { document.body.style.overflow = '' }
  }, [isOpen])

  return (
    <>
      <button
        className="mobile-nav__toggle"
        onClick={() => setIsOpen(!isOpen)}
        aria-label={isOpen ? 'Close navigation' : 'Open navigation'}
        aria-expanded={isOpen}
      >
        <span className={`mobile-nav__bar ${isOpen ? 'mobile-nav__bar--open' : ''}`} />
        <span className={`mobile-nav__bar ${isOpen ? 'mobile-nav__bar--open' : ''}`} />
        <span className={`mobile-nav__bar ${isOpen ? 'mobile-nav__bar--open' : ''}`} />
      </button>

      {isOpen && (
        <div className="mobile-nav__overlay" onClick={() => setIsOpen(false)} />
      )}

      <nav className={`mobile-nav__drawer ${isOpen ? 'mobile-nav__drawer--open' : ''}`}>
        <div className="mobile-nav__header">
          <span className="navbar__brand">MEDINA / NOVA</span>
        </div>
        <div className="mobile-nav__links">
          {items.map(({ to, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                'mobile-nav__link' + (isActive ? ' active' : '')
              }
            >
              {label}
            </NavLink>
          ))}
        </div>
      </nav>
    </>
  )
}
