import { useEffect } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { wsService } from './services/websocket';
import { useIADSStore } from './store/iadsStore';
import Layout from './components/common/Layout';
import Dashboard from './components/Dashboard';
import SAMList from './components/sam/SAMList';
import ThreatMonitor from './components/threat/ThreatMonitor';

function App() {
  const connected = useIADSStore((state) => state.connected);

  useEffect(() => {
    // WebSocket接続
    wsService.connect();

    return () => {
      wsService.disconnect();
    };
  }, []);

  return (
    <BrowserRouter>
      <Layout connected={connected}>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/sams" element={<SAMList />} />
          <Route path="/threats" element={<ThreatMonitor />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  );
}

export default App;
