import { useState } from 'react';
import { useIADSStore } from '../../store/iadsStore';
import { Threat, ThreatLevel, ThreatCategory } from '../../types/iads';

function getThreatLevelColor(level: ThreatLevel): string {
  switch (level) {
    case 'LOW': return 'text-green-400';
    case 'MEDIUM': return 'text-yellow-400';
    case 'HIGH': return 'text-orange-400';
    case 'CRITICAL': return 'text-red-400';
    default: return 'text-gray-400';
  }
}

function getThreatLevelBg(level: ThreatLevel): string {
  switch (level) {
    case 'LOW': return 'bg-green-500';
    case 'MEDIUM': return 'bg-yellow-500';
    case 'HIGH': return 'bg-orange-500';
    case 'CRITICAL': return 'bg-red-500';
    default: return 'bg-gray-500';
  }
}

function formatTime(timestamp: number): string {
  const seconds = Math.floor(timestamp);
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  return `${hours.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

interface ThreatCardProps {
  threat: Threat;
}

function ThreatCard({ threat }: ThreatCardProps) {
  return (
    <div className={`bg-gray-800 rounded-lg p-4 border-l-4 ${threat.isSEAD ? 'border-orange-500' : 'border-red-500'}`}>
      <div className="flex items-start justify-between mb-2">
        <div>
          <div className="flex items-center space-x-2">
            <span className="font-bold text-white">{threat.type}</span>
            {threat.isSEAD && (
              <span className="px-2 py-0.5 bg-orange-500 text-white text-xs rounded font-bold">
                SEAD
              </span>
            )}
          </div>
          <span className="text-gray-400 text-sm">{threat.category}</span>
        </div>
        <span className={`px-2 py-1 rounded text-xs font-bold text-white ${getThreatLevelBg(threat.threatLevel)}`}>
          {threat.threatLevel}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-2 text-sm">
        <div>
          <span className="text-gray-400">Heading:</span>{' '}
          <span className="text-white">{Math.round(threat.heading)}°</span>
        </div>
        <div>
          <span className="text-gray-400">Speed:</span>{' '}
          <span className="text-white">{Math.round(threat.speed)} m/s</span>
        </div>
        <div>
          <span className="text-gray-400">Altitude:</span>{' '}
          <span className="text-white">{Math.round(threat.altitude)} m</span>
        </div>
        <div>
          <span className="text-gray-400">Position:</span>{' '}
          <span className="text-white">
            {threat.position.lat.toFixed(2)}°, {threat.position.lon.toFixed(2)}°
          </span>
        </div>
      </div>

      <div className="mt-2 text-xs text-gray-500">
        First detected: {formatTime(threat.firstDetected)}
      </div>
    </div>
  );
}

export default function ThreatMonitor() {
  const state = useIADSStore((s) => s.state);
  const [levelFilter, setLevelFilter] = useState<ThreatLevel | 'ALL'>('ALL');
  const [categoryFilter, setCategoryFilter] = useState<ThreatCategory | 'ALL'>('ALL');
  const [showSEADOnly, setShowSEADOnly] = useState(false);

  if (!state) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-gray-400">No data available</p>
      </div>
    );
  }

  const threats = Object.values(state.threats);

  // フィルタリング
  let filteredThreats = threats;
  if (levelFilter !== 'ALL') {
    filteredThreats = filteredThreats.filter((t) => t.threatLevel === levelFilter);
  }
  if (categoryFilter !== 'ALL') {
    filteredThreats = filteredThreats.filter((t) => t.category === categoryFilter);
  }
  if (showSEADOnly) {
    filteredThreats = filteredThreats.filter((t) => t.isSEAD);
  }

  // 脅威レベルでソート
  const levelOrder: Record<ThreatLevel, number> = {
    CRITICAL: 0,
    HIGH: 1,
    MEDIUM: 2,
    LOW: 3
  };
  filteredThreats.sort((a, b) => levelOrder[a.threatLevel] - levelOrder[b.threatLevel]);

  const seadCount = threats.filter((t) => t.isSEAD).length;

  return (
    <div className="h-full flex flex-col p-4">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold text-white">Threat Monitor</h2>

        <div className="flex items-center space-x-4">
          {/* SEAD Filter */}
          <label className="flex items-center space-x-2 cursor-pointer">
            <input
              type="checkbox"
              checked={showSEADOnly}
              onChange={(e) => setShowSEADOnly(e.target.checked)}
              className="form-checkbox"
            />
            <span className="text-gray-300 text-sm">SEAD Only</span>
          </label>

          {/* Level Filter */}
          <select
            value={levelFilter}
            onChange={(e) => setLevelFilter(e.target.value as ThreatLevel | 'ALL')}
            className="px-3 py-2 bg-gray-700 border border-gray-600 rounded text-white text-sm focus:outline-none focus:border-blue-500"
          >
            <option value="ALL">All Levels</option>
            <option value="CRITICAL">CRITICAL</option>
            <option value="HIGH">HIGH</option>
            <option value="MEDIUM">MEDIUM</option>
            <option value="LOW">LOW</option>
          </select>

          {/* Category Filter */}
          <select
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value as ThreatCategory | 'ALL')}
            className="px-3 py-2 bg-gray-700 border border-gray-600 rounded text-white text-sm focus:outline-none focus:border-blue-500"
          >
            <option value="ALL">All Categories</option>
            <option value="AIR">AIR</option>
            <option value="SURFACE">SURFACE</option>
            <option value="SUBSURFACE">SUBSURFACE</option>
          </select>
        </div>
      </div>

      {/* Summary */}
      <div className="flex space-x-4 mb-4">
        <div className="bg-gray-800 px-4 py-2 rounded">
          <span className="text-gray-400 text-sm">Active Threats:</span>{' '}
          <span className="text-red-400 font-bold">{threats.length}</span>
        </div>
        <div className="bg-gray-800 px-4 py-2 rounded">
          <span className="text-gray-400 text-sm">SEAD Threats:</span>{' '}
          <span className="text-orange-400 font-bold">{seadCount}</span>
        </div>
        <div className="bg-gray-800 px-4 py-2 rounded">
          <span className="text-gray-400 text-sm">Critical:</span>{' '}
          <span className="text-red-400 font-bold">
            {threats.filter((t) => t.threatLevel === 'CRITICAL').length}
          </span>
        </div>
        <div className="bg-gray-800 px-4 py-2 rounded">
          <span className="text-gray-400 text-sm">High:</span>{' '}
          <span className="text-orange-400 font-bold">
            {threats.filter((t) => t.threatLevel === 'HIGH').length}
          </span>
        </div>
      </div>

      {/* Threat List */}
      <div className="flex-1 overflow-auto">
        {filteredThreats.length > 0 ? (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {filteredThreats.map((threat) => (
              <ThreatCard key={threat.id} threat={threat} />
            ))}
          </div>
        ) : (
          <div className="flex items-center justify-center h-full">
            <div className="text-center">
              <p className="text-gray-400 text-lg">No threats detected</p>
              <p className="text-gray-500 text-sm mt-1">The sky is clear</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
