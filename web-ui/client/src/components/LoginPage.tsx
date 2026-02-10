import { useState } from 'react';
import { Coalition, AccessLevel } from '../types/iads';
import { useSessionStore } from '../store/iadsStore';
import * as api from '../services/api';

export default function LoginPage() {
  const [playerName, setPlayerName] = useState('');
  const [coalition, setCoalition] = useState<Coalition>(Coalition.BLUE);
  const [accessLevel, setAccessLevel] = useState<AccessLevel>(AccessLevel.OPERATOR);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const login = useSessionStore((s) => s.login);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setError(null);

    try {
      const response = await api.createSession(coalition, playerName || 'Anonymous', accessLevel);
      login({
        id: response.sessionId,
        coalition: response.coalition,
        accessLevel: response.accessLevel,
        playerName: response.playerName
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setIsLoading(false);
    }
  };

  const getCoalitionColor = (coal: Coalition) => {
    switch (coal) {
      case Coalition.RED: return 'bg-red-600 hover:bg-red-500';
      case Coalition.BLUE: return 'bg-blue-600 hover:bg-blue-500';
      case Coalition.ALL: return 'bg-purple-600 hover:bg-purple-500';
      default: return 'bg-gray-600 hover:bg-gray-500';
    }
  };

  return (
    <div className="min-h-screen bg-gray-900 flex items-center justify-center p-4">
      <div className="bg-gray-800 rounded-lg shadow-xl p-8 w-full max-w-md">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold text-white mb-2">IADS Control Center</h1>
          <p className="text-gray-400">Select your coalition to continue</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Player Name */}
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">
              Player Name
            </label>
            <input
              type="text"
              value={playerName}
              onChange={(e) => setPlayerName(e.target.value)}
              placeholder="Enter your name"
              className="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:border-blue-500"
            />
          </div>

          {/* Coalition Selection */}
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">
              Coalition
            </label>
            <div className="grid grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => setCoalition(Coalition.RED)}
                className={`py-3 px-4 rounded-lg text-white font-semibold transition-colors ${
                  coalition === Coalition.RED
                    ? 'bg-red-600 ring-2 ring-red-400'
                    : 'bg-red-800 hover:bg-red-700'
                }`}
              >
                RED
              </button>
              <button
                type="button"
                onClick={() => setCoalition(Coalition.BLUE)}
                className={`py-3 px-4 rounded-lg text-white font-semibold transition-colors ${
                  coalition === Coalition.BLUE
                    ? 'bg-blue-600 ring-2 ring-blue-400'
                    : 'bg-blue-800 hover:bg-blue-700'
                }`}
              >
                BLUE
              </button>
            </div>
          </div>

          {/* Access Level */}
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">
              Access Level
            </label>
            <select
              value={accessLevel}
              onChange={(e) => setAccessLevel(parseInt(e.target.value, 10) as AccessLevel)}
              className="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:border-blue-500"
            >
              <option value={AccessLevel.VIEW}>View Only</option>
              <option value={AccessLevel.OPERATOR}>Operator</option>
              <option value={AccessLevel.COMMANDER}>Commander</option>
            </select>
          </div>

          {/* Game Master Option */}
          <div className="border-t border-gray-700 pt-4">
            <button
              type="button"
              onClick={() => {
                setCoalition(Coalition.ALL);
                setAccessLevel(AccessLevel.ADMIN);
              }}
              className={`w-full py-2 px-4 rounded-lg text-white font-semibold transition-colors ${
                coalition === Coalition.ALL
                  ? 'bg-purple-600 ring-2 ring-purple-400'
                  : 'bg-purple-800 hover:bg-purple-700'
              }`}
            >
              Game Master (All Coalitions)
            </button>
          </div>

          {error && (
            <div className="bg-red-900/50 border border-red-500 rounded-lg p-3 text-red-300 text-sm">
              {error}
            </div>
          )}

          {/* Submit Button */}
          <button
            type="submit"
            disabled={isLoading}
            className={`w-full py-3 px-4 rounded-lg text-white font-semibold transition-colors ${getCoalitionColor(coalition)} disabled:opacity-50`}
          >
            {isLoading ? 'Connecting...' : 'Enter Control Center'}
          </button>
        </form>

        <div className="mt-6 text-center text-gray-500 text-sm">
          <p>Version 1.0.0 - Multiplayer Edition</p>
        </div>
      </div>
    </div>
  );
}
