import { ReactNode } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useIADSStore } from '../../store/iadsStore';

interface LayoutProps {
  children: ReactNode;
  connected: boolean;
}

export default function Layout({ children, connected }: LayoutProps) {
  const location = useLocation();
  const state = useIADSStore((s) => s.state);

  const navItems = [
    { path: '/', label: 'Dashboard' },
    { path: '/sams', label: 'SAM Sites' },
    { path: '/threats', label: 'Threats' },
  ];

  const getDefconColor = (defcon: string | undefined) => {
    switch (defcon) {
      case 'PEACE': return 'bg-green-500';
      case 'ELEVATED': return 'bg-yellow-500';
      case 'HIGH': return 'bg-orange-500';
      case 'SEVERE': return 'bg-red-500';
      case 'CRITICAL': return 'bg-red-700';
      default: return 'bg-gray-500';
    }
  };

  return (
    <div className="min-h-screen bg-gray-900 flex flex-col">
      {/* Header */}
      <header className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-6">
            <h1 className="text-xl font-bold text-white">IADS Control Center</h1>

            <nav className="flex space-x-4">
              {navItems.map((item) => (
                <Link
                  key={item.path}
                  to={item.path}
                  className={`px-3 py-1 rounded ${
                    location.pathname === item.path
                      ? 'bg-blue-600 text-white'
                      : 'text-gray-300 hover:bg-gray-700'
                  }`}
                >
                  {item.label}
                </Link>
              ))}
            </nav>
          </div>

          <div className="flex items-center space-x-4">
            {/* DEFCON表示 */}
            {state && (
              <div className="flex items-center space-x-2">
                <span className="text-gray-400 text-sm">DEFCON:</span>
                <span className={`px-2 py-1 rounded text-white text-sm font-bold ${getDefconColor(state.defcon)}`}>
                  {state.defcon}
                </span>
              </div>
            )}

            {/* Mission Time */}
            {state && (
              <div className="text-gray-400 text-sm">
                <span className="text-gray-500">Time:</span>{' '}
                <span className="text-white font-mono">{state.missionTime}</span>
              </div>
            )}

            {/* 接続状態 */}
            <div className="flex items-center space-x-2">
              <span
                className={`w-2 h-2 rounded-full ${
                  connected ? 'bg-green-500' : 'bg-red-500 animate-pulse'
                }`}
              />
              <span className="text-gray-400 text-sm">
                {connected ? 'Connected' : 'Disconnected'}
              </span>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 overflow-auto">
        {children}
      </main>

      {/* Footer */}
      <footer className="bg-gray-800 border-t border-gray-700 px-4 py-2 text-center text-gray-500 text-sm">
        IADS Web UI v1.0.0
      </footer>
    </div>
  );
}
