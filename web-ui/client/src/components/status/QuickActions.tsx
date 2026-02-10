import { useState } from 'react';
import * as api from '../../services/api';

export default function QuickActions() {
  const [isLoading, setIsLoading] = useState(false);
  const [lastAction, setLastAction] = useState<string | null>(null);

  const handleAllOn = async () => {
    setIsLoading(true);
    try {
      await api.setAllSAMsState('GREEN');
      setLastAction('All SAMs activated');
    } catch (error) {
      console.error('Failed to activate all SAMs:', error);
      setLastAction('Failed to activate SAMs');
    } finally {
      setIsLoading(false);
    }
  };

  const handleAllOff = async () => {
    setIsLoading(true);
    try {
      await api.setAllSAMsState('DARK');
      setLastAction('All SAMs set to DARK');
    } catch (error) {
      console.error('Failed to deactivate all SAMs:', error);
      setLastAction('Failed to deactivate SAMs');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="p-4 border-b border-gray-700">
      <h3 className="text-sm font-semibold text-gray-400 mb-3">Quick Actions</h3>

      <div className="flex space-x-2">
        <button
          onClick={handleAllOn}
          disabled={isLoading}
          className="flex-1 px-3 py-2 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 text-white text-sm rounded transition-colors"
        >
          All ON
        </button>
        <button
          onClick={handleAllOff}
          disabled={isLoading}
          className="flex-1 px-3 py-2 bg-gray-600 hover:bg-gray-500 disabled:bg-gray-700 text-white text-sm rounded transition-colors"
        >
          All OFF
        </button>
      </div>

      {lastAction && (
        <p className="text-xs text-gray-400 mt-2">{lastAction}</p>
      )}
    </div>
  );
}
