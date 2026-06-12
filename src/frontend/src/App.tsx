/**
 * Casa de Medina — Architectos de Architectura Inteligente
 */

import { BrowserRouter, Routes, Route, Outlet } from 'react-router-dom'
import Layout from './components/Layout'
import Home from './pages/Home'
import Dashboard from './pages/Dashboard'
import Engine from './pages/Engine'
import Agents from './pages/Agents'
import Renderability from './pages/Renderability'
import TokenEconomy from './pages/TokenEconomy'
import ICPCoverage from './pages/ICPCoverage'
import RealityRelease from './pages/RealityRelease'
import Executive from './pages/Executive'
import NotFound from './pages/NotFound'
import ETHome from './pages/et/ETHome'
import ETPulse from './pages/et/ETPulse'
import ETProposals from './pages/et/ETProposals'
import ETProposalDetail from './pages/et/ETProposalDetail'
import ETCreateProposal from './pages/et/ETCreateProposal'
import ETCreateTrace from './pages/et/ETCreateTrace'
import ETTraceDetail from './pages/et/ETTraceDetail'
import ETRiskRadar from './pages/et/ETRiskRadar'
import ETOperator from './pages/et/ETOperator'
import ETExport from './pages/et/ETExport'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Layout />}>
          <Route index element={<Home />} />
          <Route path="dashboard" element={<Dashboard />} />
          <Route path="engine" element={<Engine />} />
          <Route path="agents" element={<Agents />} />
          <Route path="renderability" element={<Renderability />} />
          <Route path="token-economy" element={<TokenEconomy />} />
          <Route path="icp-coverage" element={<ICPCoverage />} />
          <Route path="reality-release" element={<RealityRelease />} />
          <Route path="executive" element={<Executive />} />
          <Route path="et" element={<Outlet />}>
            <Route index element={<ETHome />} />
            <Route path="pulse" element={<ETPulse />} />
            <Route path="proposals" element={<ETProposals />} />
            <Route path="proposals/:proposalId" element={<ETProposalDetail />} />
            <Route path="create-proposal" element={<ETCreateProposal />} />
            <Route path="create-trace" element={<ETCreateTrace />} />
            <Route path="traces/:traceId" element={<ETTraceDetail />} />
            <Route path="risk-radar" element={<ETRiskRadar />} />
            <Route path="operator" element={<ETOperator />} />
            <Route path="export/:traceId" element={<ETExport />} />
          </Route>
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
