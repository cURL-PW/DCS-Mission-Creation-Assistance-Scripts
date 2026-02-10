import { useState } from 'react';
import { useIADSStore } from '../../store/iadsStore';
import { DEFCONLevel, TacticalMode } from '../../types/iads';
import * as api from '../../services/api';

const DEFCON_LEVELS: DEFCONLevel[] = ['PEACE', 'ELEVATED', 'HIGH', 'SEVERE', 'CRITICAL'];
const TACTICAL_MODES: TacticalMode[] = ['CONSERVATIVE', 'BALANCED', 'AGGRESSIVE', 'AMBUSH'];

function getDefconColor(defcon: DEFCONLevel): string {
  switch (defcon) {
    case 'PEACE': return 'bg-green-500';
    case 'ELEVATED': return 'bg-yellow-500';
    case 'HIGH': return 'bg-orange-500';
    case 'SEVERE': return 'bg-red-500';
    case 'CRITICAL': return 'bg-red-700';
    default: return 'bg-gray-500';
  }
}

function getTacticalColor(mode: TacticalMode): string {
  switch (mode) {
    case 'CONSERVATIVE': return 'bg-blue-500';
    case 'BALANCED': return 'bg-green-500';
    case 'AGGRESSIVE': return 'bg-orange-500';
    case 'AMBUSH': return 'bg-purple-500';
    default: return 'bg-gray-500';
  }
}

export default function StatusPanel() {
  const state = useIADSStore((s) => s.state);
  const [isChangingDefcon, setIsChangingDefcon] = useState(false);
  const [isChangingMode, setIsChangingMode] = useState(false);

  if (!state) return null;

  const handleDefconChange = async (level: DEFCONLevel) => {
    try {
      await api.setDEFCON(level);
      setIsChangingDefcon(false);
    } catch (error) {
      console.error('Failed to set DEFCON:', error);
    }
  };

  const handleModeChange = async (mode: TacticalMode) => {
    try {
      await api.setTacticalMode(mode);
      setIsChangingMode(false);
    } catch (error) {
      console.error('Failed to set tactical mode:', error);
    }
  };

  return (
    <div className="p-4 border-b border-gray-700">
      <h3 className="text-sm font-semibold text-gray-400 mb-3">System Status</h3>

      {/* DEFCON */}
      <div className="mb-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-gray-400 text-sm">DEFCON Level</span>
          <button
            onClick={() => setIsChangingDefcon(!isChangingDefcon)}
            className={`px-3 py-1 rounded text-white text-sm font-bold ${getDefconColor(state.defcon)}`}
          >
            {state.defcon}
          </button>
        </div>

        {isChangingDefcon && (
          <div className="flex flex-wrap gap-1 mt-2">
            {DEFCON_LEVELS.map((level) => (
              <button
                key={level}
                onClick={() => handleDefconChange(level)}
                className={`px-2 py-1 rounded text-xs text-white ${getDefconColor(level)} ${
                  level === state.defcon ? 'ring-2 ring-white' : ''
                }`}
              >
                {level}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Tactical Mode */}
      <div>
        <div className="flex items-center justify-between mb-2">
          <span className="text-gray-400 text-sm">Tactical Mode</span>
          <button
            onClick={() => setIsChangingMode(!isChangingMode)}
            className={`px-3 py-1 rounded text-white text-sm font-bold ${getTacticalColor(state.tacticalMode)}`}
          >
            {state.tacticalMode}
          </button>
        </div>

        {isChangingMode && (
          <div className="flex flex-wrap gap-1 mt-2">
            {TACTICAL_MODES.map((mode) => (
              <button
                key={mode}
                onClick={() => handleModeChange(mode)}
                className={`px-2 py-1 rounded text-xs text-white ${getTacticalColor(mode)} ${
                  mode === state.tacticalMode ? 'ring-2 ring-white' : ''
                }`}
              >
                {mode}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
