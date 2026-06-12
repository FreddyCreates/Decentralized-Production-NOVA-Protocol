/**
 * NotFound — 404 page with sovereign styling
 *
 * Casa de Medina — Architectos de Architectura Inteligente
 */

import { Link } from 'react-router-dom'

export default function NotFound() {
  return (
    <div className="not-found">
      <div className="not-found__code">404</div>
      <h1 className="not-found__title">Substrate Not Found</h1>
      <p className="not-found__message">
        The organism path you seek does not exist in this dimension.
        The architecture has no record of this coordinate.
      </p>
      <Link to="/" className="not-found__link">
        ← Return to Organism Root
      </Link>
    </div>
  )
}
