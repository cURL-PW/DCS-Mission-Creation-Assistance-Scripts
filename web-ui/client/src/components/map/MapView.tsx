import { MapContainer, TileLayer, Circle, Marker, Popup, Polyline, useMap } from 'react-leaflet';
import { LatLngExpression, divIcon } from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { useIADSStore, useUIStore, useSessionStore } from '../../store/iadsStore';
import { SAMSite, Threat, EWRSite, Coalition } from '../../types/iads';
import { useMemo } from 'react';

// SAM状態に応じた色を取得
function getSAMColor(state: string): string {
  switch (state) {
    case 'GREEN': return '#22c55e';
    case 'DARK': return '#6b7280';
    case 'TRACKING': return '#eab308';
    case 'ENGAGING': return '#ef4444';
    default: return '#6b7280';
  }
}

// SAMマーカーアイコン作成
function createSAMIcon(sam: SAMSite) {
  const color = getSAMColor(sam.state);
  const isAnimated = sam.state === 'TRACKING' || sam.state === 'ENGAGING';

  return divIcon({
    className: 'sam-marker-wrapper',
    html: `
      <div style="
        width: 24px;
        height: 24px;
        background-color: ${color};
        border: 2px solid white;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 10px;
        font-weight: bold;
        color: white;
        box-shadow: 0 2px 4px rgba(0,0,0,0.5);
        ${isAnimated ? 'animation: pulse 1s infinite;' : ''}
      ">
        S
      </div>
    `,
    iconSize: [24, 24],
    iconAnchor: [12, 12],
    popupAnchor: [0, -12]
  });
}

// 脅威マーカーアイコン作成
function createThreatIcon(threat: Threat) {
  const color = threat.isSEAD ? '#f97316' : '#ef4444';

  return divIcon({
    className: 'threat-marker-wrapper',
    html: `
      <div style="
        width: 20px;
        height: 20px;
        background-color: ${color};
        border: 2px solid white;
        transform: rotate(45deg);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 2px 4px rgba(0,0,0,0.5);
      ">
      </div>
    `,
    iconSize: [20, 20],
    iconAnchor: [10, 10],
    popupAnchor: [0, -10]
  });
}

// EWRマーカーアイコン作成
function createEWRIcon(ewr: EWRSite) {
  return divIcon({
    className: 'ewr-marker-wrapper',
    html: `
      <div style="
        width: 24px;
        height: 24px;
        background-color: #3b82f6;
        border: 2px solid white;
        border-radius: 4px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 10px;
        font-weight: bold;
        color: white;
        box-shadow: 0 2px 4px rgba(0,0,0,0.5);
      ">
        E
      </div>
    `,
    iconSize: [24, 24],
    iconAnchor: [12, 12],
    popupAnchor: [0, -12]
  });
}

// SAMマーカーコンポーネント
function SAMMarker({ sam }: { sam: SAMSite }) {
  const setSelectedSAM = useUIStore((s) => s.setSelectedSAM);
  const position: LatLngExpression = [sam.position.lat, sam.position.lon];

  return (
    <>
      <Marker
        position={position}
        icon={createSAMIcon(sam)}
        eventHandlers={{
          click: () => setSelectedSAM(sam.name)
        }}
      >
        <Popup>
          <div className="text-sm">
            <div className="font-bold">{sam.name}</div>
            <div>Type: {sam.type}</div>
            <div>State: <span style={{ color: getSAMColor(sam.state) }}>{sam.state}</span></div>
            <div>Ammo: {sam.ammo}%</div>
            <div>Health: {sam.health}%</div>
          </div>
        </Popup>
      </Marker>
    </>
  );
}

// 射程範囲円コンポーネント
function RangeCircle({ sam }: { sam: SAMSite }) {
  const showRangeCircles = useUIStore((s) => s.showRangeCircles);
  if (!showRangeCircles) return null;

  const position: LatLngExpression = [sam.position.lat, sam.position.lon];
  const color = getSAMColor(sam.state);

  return (
    <Circle
      center={position}
      radius={sam.range}
      pathOptions={{
        color: color,
        fillColor: color,
        fillOpacity: 0.1,
        weight: 1,
        dashArray: sam.state === 'DARK' ? '5, 5' : undefined
      }}
    />
  );
}

// 脅威レベルに応じた色
function getThreatColor(level: string): string {
  switch (level) {
    case 'CRITICAL': return '#dc2626';
    case 'HIGH': return '#f97316';
    case 'MEDIUM': return '#eab308';
    case 'LOW': return '#22c55e';
    default: return '#9ca3af';
  }
}

// 脅威マーカーコンポーネント
function ThreatMarker({ threat }: { threat: Threat }) {
  const showThreats = useUIStore((s) => s.showThreats);
  const { selectedThreat, setSelectedThreat } = useUIStore();
  if (!showThreats) return null;

  const position: LatLngExpression = [threat.position.lat, threat.position.lon];
  const isSelected = selectedThreat === threat.id;

  // 進行方向を示す矢印ライン
  const headingRad = (threat.heading * Math.PI) / 180;
  const lineLength = 0.03; // 約3km
  const endLat = threat.position.lat + Math.cos(headingRad) * lineLength;
  const endLon = threat.position.lon + Math.sin(headingRad) * lineLength;
  const color = getThreatColor(threat.threatLevel);

  return (
    <>
      <Marker
        position={position}
        icon={createThreatIcon(threat)}
        eventHandlers={{
          click: () => setSelectedThreat(threat.id)
        }}
      >
        <Popup>
          <div className="text-sm">
            <div className="font-bold">{threat.type}</div>
            <div>Category: {threat.category}</div>
            <div>Threat Level: <span style={{ color }}>{threat.threatLevel}</span></div>
            <div>Speed: {Math.round(threat.speed * 3.6)} km/h</div>
            <div>Altitude: {Math.round(threat.altitude)} m</div>
            <div>Heading: {Math.round(threat.heading)}°</div>
            {threat.isSEAD && <div className="text-orange-500 font-bold">⚠ SEAD THREAT</div>}
          </div>
        </Popup>
      </Marker>
      <Polyline
        positions={[position, [endLat, endLon]]}
        pathOptions={{
          color: threat.isSEAD ? '#f97316' : color,
          weight: isSelected ? 3 : 2,
          opacity: 0.8
        }}
      />
    </>
  );
}

// EWRマーカーコンポーネント
function EWRMarker({ ewr }: { ewr: EWRSite }) {
  const showEWRs = useUIStore((s) => s.showEWRs);
  if (!showEWRs) return null;

  const position: LatLngExpression = [ewr.position.lat, ewr.position.lon];

  return (
    <>
      <Marker
        position={position}
        icon={createEWRIcon(ewr)}
      >
        <Popup>
          <div className="text-sm">
            <div className="font-bold">{ewr.name}</div>
            <div>Type: {ewr.type}</div>
            <div>Range: {Math.round(ewr.range / 1000)} km</div>
            <div>Status: {ewr.isActive ? 'Active' : 'Inactive'}</div>
          </div>
        </Popup>
      </Marker>
      {showEWRs && (
        <Circle
          center={position}
          radius={ewr.range}
          pathOptions={{
            color: '#3b82f6',
            fillColor: '#3b82f6',
            fillOpacity: 0.05,
            weight: 1,
            dashArray: '10, 5'
          }}
        />
      )}
    </>
  );
}

// マップコントロールコンポーネント
function MapControls() {
  const { showRangeCircles, showThreats, showEWRs, toggleRangeCircles, toggleThreats, toggleEWRs } = useUIStore();

  return (
    <div className="absolute top-4 right-4 z-[1000] bg-gray-800 rounded-lg p-2 shadow-lg">
      <div className="space-y-2 text-sm">
        <label className="flex items-center space-x-2 cursor-pointer">
          <input
            type="checkbox"
            checked={showRangeCircles}
            onChange={toggleRangeCircles}
            className="form-checkbox"
          />
          <span className="text-gray-300">Range Circles</span>
        </label>
        <label className="flex items-center space-x-2 cursor-pointer">
          <input
            type="checkbox"
            checked={showThreats}
            onChange={toggleThreats}
            className="form-checkbox"
          />
          <span className="text-gray-300">Threats</span>
        </label>
        <label className="flex items-center space-x-2 cursor-pointer">
          <input
            type="checkbox"
            checked={showEWRs}
            onChange={toggleEWRs}
            className="form-checkbox"
          />
          <span className="text-gray-300">EWR Sites</span>
        </label>
      </div>
    </div>
  );
}

// マップ凡例
function MapLegend() {
  return (
    <div className="absolute bottom-4 left-4 z-[1000] bg-gray-800/95 rounded-lg p-3 shadow-lg text-xs">
      <div className="font-bold mb-2 text-gray-200">凡例</div>
      <div className="space-y-1 text-gray-300">
        <div className="flex items-center gap-2">
          <span className="w-4 h-4 rounded-full bg-green-500 inline-block"></span>
          SAM (GREEN)
        </div>
        <div className="flex items-center gap-2">
          <span className="w-4 h-4 rounded-full bg-yellow-500 inline-block"></span>
          SAM (TRACKING)
        </div>
        <div className="flex items-center gap-2">
          <span className="w-4 h-4 rounded-full bg-red-500 inline-block"></span>
          SAM (ENGAGING)
        </div>
        <div className="flex items-center gap-2">
          <span className="w-4 h-4 rounded-full bg-gray-500 inline-block"></span>
          SAM (DARK)
        </div>
        <div className="flex items-center gap-2">
          <span className="w-4 h-4 rounded bg-blue-500 inline-block"></span>
          EWR
        </div>
        <div className="flex items-center gap-2">
          <span className="w-4 h-4 bg-red-500 inline-block" style={{ transform: 'rotate(45deg)' }}></span>
          脅威
        </div>
      </div>
    </div>
  );
}

// 選択パネル
function SelectionPanel({ sam, onClose }: { sam: SAMSite; onClose: () => void }) {
  return (
    <div className="absolute bottom-4 right-4 z-[1000] bg-gray-800/95 rounded-lg p-4 shadow-lg min-w-[250px]">
      <div className="flex justify-between items-center mb-3">
        <span className="font-bold text-white">{sam.name}</span>
        <button
          onClick={onClose}
          className="text-gray-400 hover:text-white"
        >
          ✕
        </button>
      </div>
      <div className="text-sm space-y-1 text-gray-300">
        <div>Type: {sam.type}</div>
        <div>State: <span style={{ color: getSAMColor(sam.state) }}>{sam.state}</span></div>
        <div>Range: {(sam.range / 1000).toFixed(1)} km</div>
        <div>Ammo: {sam.ammo}%</div>
        <div>Health: {sam.health}%</div>
        <div className="pt-2 flex gap-2">
          <button className="px-3 py-1 bg-green-600 hover:bg-green-700 rounded text-xs text-white">
            ACTIVATE
          </button>
          <button className="px-3 py-1 bg-gray-600 hover:bg-gray-700 rounded text-xs text-white">
            DEACTIVATE
          </button>
        </div>
      </div>
    </div>
  );
}

export default function MapView() {
  const state = useIADSStore((s) => s.state);
  const { mapCenter, mapZoom, selectedSAM, setSelectedSAM } = useUIStore();
  const { getCoalition, isGameMaster } = useSessionStore();

  const coalition = getCoalition();
  const gameMaster = isGameMaster();

  // コアリションでフィルタリング
  const sams = useMemo(() => {
    if (!state?.samSites) return [];
    return Object.values(state.samSites).filter(sam =>
      gameMaster || sam.coalition === coalition
    );
  }, [state?.samSites, coalition, gameMaster]);

  const threats = useMemo(() => {
    if (!state?.threats) return [];
    return Object.values(state.threats).filter(threat =>
      gameMaster || threat.coalition !== coalition
    );
  }, [state?.threats, coalition, gameMaster]);

  const ewrs = useMemo(() => {
    if (!state?.ewrSites) return [];
    return Object.values(state.ewrSites).filter(ewr =>
      gameMaster || ewr.coalition === coalition
    );
  }, [state?.ewrSites, coalition, gameMaster]);

  const selectedSAMData = useMemo(() => {
    if (!selectedSAM) return null;
    return sams.find(s => s.name === selectedSAM) || null;
  }, [selectedSAM, sams]);

  if (!state) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-gray-800">
        <p className="text-gray-400">No map data available</p>
      </div>
    );
  }

  return (
    <div className="w-full h-full relative">
      <MapContainer
        center={mapCenter}
        zoom={mapZoom}
        className="w-full h-full"
        zoomControl={true}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        {/* EWR範囲と markers */}
        {ewrs.map((ewr) => (
          <EWRMarker key={ewr.name} ewr={ewr} />
        ))}

        {/* SAM射程範囲 */}
        {sams.map((sam) => (
          <RangeCircle key={`range-${sam.name}`} sam={sam} />
        ))}

        {/* SAMマーカー */}
        {sams.map((sam) => (
          <SAMMarker key={sam.name} sam={sam} />
        ))}

        {/* 脅威マーカー */}
        {threats.map((threat) => (
          <ThreatMarker key={threat.id} threat={threat} />
        ))}
      </MapContainer>

      <MapControls />
      <MapLegend />

      {selectedSAMData && (
        <SelectionPanel
          sam={selectedSAMData}
          onClose={() => setSelectedSAM(null)}
        />
      )}
    </div>
  );
}
