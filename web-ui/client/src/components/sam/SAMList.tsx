import { useState } from 'react';
import { useIADSStore } from '../../store/iadsStore';
import { SAMSite, SAMState } from '../../types/iads';
import * as api from '../../services/api';

function getSAMStateColor(state: SAMState): string {
  switch (state) {
    case 'GREEN': return 'text-green-400';
    case 'DARK': return 'text-gray-400';
    case 'TRACKING': return 'text-yellow-400';
    case 'ENGAGING': return 'text-red-400';
    default: return 'text-gray-400';
  }
}

function getSAMStateBg(state: SAMState): string {
  switch (state) {
    case 'GREEN': return 'bg-green-500';
    case 'DARK': return 'bg-gray-500';
    case 'TRACKING': return 'bg-yellow-500';
    case 'ENGAGING': return 'bg-red-500';
    default: return 'bg-gray-500';
  }
}

interface SAMRowProps {
  sam: SAMSite;
  onStateChange: (name: string, state: SAMState) => Promise<void>;
}

function SAMRow({ sam, onStateChange }: SAMRowProps) {
  const [isLoading, setIsLoading] = useState(false);

  const handleToggle = async () => {
    setIsLoading(true);
    try {
      const newState = sam.state === 'DARK' ? 'GREEN' : 'DARK';
      await onStateChange(sam.name, newState);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <tr className="hover:bg-gray-700 transition-colors">
      <td className="px-4 py-3">
        <div className="flex items-center space-x-2">
          <span className={`w-2 h-2 rounded-full ${getSAMStateBg(sam.state)}`}></span>
          <span className="font-medium text-white">{sam.name}</span>
        </div>
      </td>
      <td className="px-4 py-3 text-gray-300">{sam.type}</td>
      <td className="px-4 py-3">
        <span className={`font-semibold ${getSAMStateColor(sam.state)}`}>
          {sam.state}
        </span>
      </td>
      <td className="px-4 py-3">
        <div className="flex items-center">
          <div className="w-16 bg-gray-600 rounded-full h-2 mr-2">
            <div
              className="bg-green-500 h-2 rounded-full"
              style={{ width: `${sam.ammo}%` }}
            ></div>
          </div>
          <span className="text-gray-300 text-sm">{sam.ammo}%</span>
        </div>
      </td>
      <td className="px-4 py-3">
        <div className="flex items-center">
          <div className="w-16 bg-gray-600 rounded-full h-2 mr-2">
            <div
              className={`h-2 rounded-full ${sam.health > 50 ? 'bg-green-500' : sam.health > 25 ? 'bg-yellow-500' : 'bg-red-500'}`}
              style={{ width: `${sam.health}%` }}
            ></div>
          </div>
          <span className="text-gray-300 text-sm">{sam.health}%</span>
        </div>
      </td>
      <td className="px-4 py-3">
        <div className="flex space-x-2">
          <button
            onClick={handleToggle}
            disabled={isLoading}
            className={`px-3 py-1 rounded text-white text-sm transition-colors ${
              sam.state === 'DARK'
                ? 'bg-green-600 hover:bg-green-500'
                : 'bg-gray-600 hover:bg-gray-500'
            } disabled:opacity-50`}
          >
            {isLoading ? '...' : sam.state === 'DARK' ? 'ON' : 'OFF'}
          </button>
        </div>
      </td>
    </tr>
  );
}

export default function SAMList() {
  const state = useIADSStore((s) => s.state);
  const [filter, setFilter] = useState<SAMState | 'ALL'>('ALL');
  const [search, setSearch] = useState('');

  if (!state) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-gray-400">No data available</p>
      </div>
    );
  }

  const handleStateChange = async (name: string, newState: SAMState) => {
    try {
      await api.setSAMState(name, newState);
    } catch (error) {
      console.error('Failed to change SAM state:', error);
    }
  };

  const sams = Object.values(state.samSites);

  // フィルタリング
  let filteredSams = sams;
  if (filter !== 'ALL') {
    filteredSams = filteredSams.filter((s) => s.state === filter);
  }
  if (search) {
    const searchLower = search.toLowerCase();
    filteredSams = filteredSams.filter(
      (s) =>
        s.name.toLowerCase().includes(searchLower) ||
        s.type.toLowerCase().includes(searchLower)
    );
  }

  // ソート（名前順）
  filteredSams.sort((a, b) => a.name.localeCompare(b.name));

  return (
    <div className="h-full flex flex-col p-4">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold text-white">SAM Sites</h2>

        <div className="flex items-center space-x-4">
          {/* Search */}
          <input
            type="text"
            placeholder="Search..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="px-3 py-2 bg-gray-700 border border-gray-600 rounded text-white text-sm focus:outline-none focus:border-blue-500"
          />

          {/* Filter */}
          <select
            value={filter}
            onChange={(e) => setFilter(e.target.value as SAMState | 'ALL')}
            className="px-3 py-2 bg-gray-700 border border-gray-600 rounded text-white text-sm focus:outline-none focus:border-blue-500"
          >
            <option value="ALL">All States</option>
            <option value="GREEN">GREEN</option>
            <option value="DARK">DARK</option>
            <option value="TRACKING">TRACKING</option>
            <option value="ENGAGING">ENGAGING</option>
          </select>
        </div>
      </div>

      {/* Summary */}
      <div className="flex space-x-4 mb-4">
        <div className="bg-gray-800 px-4 py-2 rounded">
          <span className="text-gray-400 text-sm">Total:</span>{' '}
          <span className="text-white font-bold">{sams.length}</span>
        </div>
        <div className="bg-gray-800 px-4 py-2 rounded">
          <span className="text-gray-400 text-sm">Active:</span>{' '}
          <span className="text-green-400 font-bold">
            {sams.filter((s) => s.state === 'GREEN' || s.state === 'TRACKING' || s.state === 'ENGAGING').length}
          </span>
        </div>
        <div className="bg-gray-800 px-4 py-2 rounded">
          <span className="text-gray-400 text-sm">Dark:</span>{' '}
          <span className="text-gray-400 font-bold">
            {sams.filter((s) => s.state === 'DARK').length}
          </span>
        </div>
      </div>

      {/* Table */}
      <div className="flex-1 overflow-auto bg-gray-800 rounded-lg">
        <table className="w-full">
          <thead className="bg-gray-700 sticky top-0">
            <tr>
              <th className="px-4 py-3 text-left text-gray-300 font-semibold">Name</th>
              <th className="px-4 py-3 text-left text-gray-300 font-semibold">Type</th>
              <th className="px-4 py-3 text-left text-gray-300 font-semibold">State</th>
              <th className="px-4 py-3 text-left text-gray-300 font-semibold">Ammo</th>
              <th className="px-4 py-3 text-left text-gray-300 font-semibold">Health</th>
              <th className="px-4 py-3 text-left text-gray-300 font-semibold">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-700">
            {filteredSams.map((sam) => (
              <SAMRow key={sam.name} sam={sam} onStateChange={handleStateChange} />
            ))}
          </tbody>
        </table>

        {filteredSams.length === 0 && (
          <div className="text-center py-8 text-gray-400">
            No SAM sites found
          </div>
        )}
      </div>
    </div>
  );
}
