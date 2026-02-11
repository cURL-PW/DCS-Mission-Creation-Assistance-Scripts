import { useEffect } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { wsService } from './services/websocket';
import { useIADSStore, useSessionStore } from './store/iadsStore';
import Layout from './components/common/Layout';
import Dashboard from './components/Dashboard';
import SAMList from './components/sam/SAMList';
import ThreatMonitor from './components/threat/ThreatMonitor';
import MapView from './components/map/MapView';
import LoginPage from './components/LoginPage';

function App() {
  const connected = useIADSStore((state) => state.connected);
  const isLoggedIn = useSessionStore((state) => state.isLoggedIn);

  useEffect(() => {
    // ログイン済みの場合のみWebSocket接続
    if (isLoggedIn) {
      wsService.connect();
    }

    return () => {
      wsService.disconnect();
    };
  }, [isLoggedIn]);

  // 未ログインの場合はログインページを表示
  if (!isLoggedIn) {
    return <LoginPage />;
  }

  return (
    <BrowserRouter>
      <Layout connected={connected}>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/map" element={<MapView />} />
          <Route path="/sams" element={<SAMList />} />
          <Route path="/threats" element={<ThreatMonitor />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  );
}

export default App;
