import { ReactNode } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useIADSStore, useSessionStore } from '../../store/iadsStore';
import { Coalition } from '../../types/iads';
import * as api from '../../services/api';

interface LayoutProps {
  children: ReactNode;
  connected: boolean;
}

export default function Layout({ children, connected }: LayoutProps) {
  const location = useLocation();
  const state = useIADSStore((s) => s.state);
  const session = useSessionStore((s) => s.session);
  const logout = useSessionStore((s) => s.logout);
  const isGameMaster = useSessionStore((s) => s.isGameMaster());

  const navItems = [
    { path: '/', label: 'Dashboard' },
    { path: '/map', label: 'Map' },
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

  const getCoalitionColor = (coalition: Coalition | undefined) => {
    switch (coalition) {
      case Coalition.RED: return 'bg-red-600';
      case Coalition.BLUE: return 'bg-blue-600';
      case Coalition.ALL: return 'bg-purple-600';
      default: return 'bg-gray-600';
    }
  };

  const getCoalitionName = (coalition: Coalition | undefined) => {
    switch (coalition) {
      case Coalition.RED: return 'RED';
      case Coalition.BLUE: return 'BLUE';
      case Coalition.ALL: return 'GM';
      default: return 'NEUTRAL';
    }
  };

  const handleLogout = async () => {
    try {
      await api.deleteSession();
    } catch (e) {
      // ignore
    }
    logout();
  };

  return (
    <div className="min-h-screen bg-gray-900 flex flex-col">
      {/* Header */}
      <header className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-6">
            <div className="flex items-center space-x-3">
              <h1 className="text-xl font-bold text-white">IADS Control Center</h1>
              {/* Coalition Badge */}
              {session && (
                <span className={`px-2 py-0.5 rounded text-white text-xs font-bold ${getCoalitionColor(session.coalition)}`}>
                  {getCoalitionName(session.coalition)}
                </span>
              )}
            </div>

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
            {/* Multiplayer Info */}
            {state?.multiplayer?.isMultiplayer && (
              <div className="text-gray-400 text-sm">
                <span className="text-gray-500">Server:</span>{' '}
                <span className="text-white">{state.multiplayer.serverName || 'Multiplayer'}</span>
                <span className="text-gray-500 ml-2">Players:</span>{' '}
                <span className="text-white">{state.multiplayer.players?.length || 0}</span>
              </div>
            )}

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

            {/* User Info & Logout */}
            {session && (
              <div className="flex items-center space-x-2 border-l border-gray-600 pl-4">
                <span className="text-gray-300 text-sm">{session.playerName}</span>
                <button
                  onClick={handleLogout}
                  className="px-2 py-1 text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 rounded"
                >
                  Logout
                </button>
              </div>
            )}
          </div>
        </div>
      </header>

      {/* Game Master Banner */}
      {isGameMaster && (
        <div className="bg-purple-900/50 border-b border-purple-500 px-4 py-1 text-center text-purple-200 text-sm">
          Game Master Mode - Full access to all coalitions
        </div>
      )}

      {/* Main Content */}
      <main className="flex-1 overflow-auto">
        {children}
      </main>

      {/* Footer */}
      <footer className="bg-gray-800 border-t border-gray-700 px-4 py-2 text-center text-gray-500 text-sm">
        IADS Web UI v1.0.0 - Multiplayer Edition
      </footer>
    </div>
  );
}
