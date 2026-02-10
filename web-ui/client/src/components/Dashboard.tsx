import { useIADSStore, useUIStore } from '../store/iadsStore';
import MapView from './map/MapView';
import StatusPanel from './status/StatusPanel';
import QuickActions from './status/QuickActions';

export default function Dashboard() {
  const state = useIADSStore((s) => s.state);
  const connected = useIADSStore((s) => s.connected);

  if (!connected) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mx-auto mb-4"></div>
          <p className="text-gray-400">Connecting to DCS...</p>
          <p className="text-gray-500 text-sm mt-2">Make sure the bridge server is running</p>
        </div>
      </div>
    );
  }

  if (!state) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center">
          <div className="animate-pulse text-gray-400">
            <p>Waiting for DCS data...</p>
            <p className="text-gray-500 text-sm mt-2">Start a mission with IADS scripts loaded</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full flex">
      {/* Map View - Main Area */}
      <div className="flex-1 relative">
        <MapView />
      </div>

      {/* Side Panel */}
      <div className="w-80 bg-gray-800 border-l border-gray-700 flex flex-col overflow-hidden">
        {/* Status Panel */}
        <StatusPanel />

        {/* Quick Actions */}
        <QuickActions />

        {/* Recent Events */}
        <div className="flex-1 p-4 overflow-auto">
          <h3 className="text-sm font-semibold text-gray-400 mb-2">Statistics</h3>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-gray-400">Total SAMs:</span>
              <span className="text-white">{state.statistics.totalSAMs}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Active SAMs:</span>
              <span className="text-green-400">{state.statistics.activeSAMs}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Dark SAMs:</span>
              <span className="text-gray-400">{state.statistics.darkSAMs}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Active Threats:</span>
              <span className="text-red-400">{state.statistics.activeThreats}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Missiles Fired:</span>
              <span className="text-white">{state.statistics.missilesFired}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Kills:</span>
              <span className="text-green-400">{state.statistics.kills}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
