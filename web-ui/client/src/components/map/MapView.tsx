import { MapContainer, TileLayer, Circle, Marker, Popup, useMap } from 'react-leaflet';
import { LatLngExpression, divIcon } from 'leaflet';
import { useIADSStore, useUIStore } from '../../store/iadsStore';
import { SAMSite, Threat, EWRSite } from '../../types/iads';

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

// 脅威マーカーコンポーネント
function ThreatMarker({ threat }: { threat: Threat }) {
  const showThreats = useUIStore((s) => s.showThreats);
  if (!showThreats) return null;

  const position: LatLngExpression = [threat.position.lat, threat.position.lon];

  return (
    <Marker
      position={position}
      icon={createThreatIcon(threat)}
    >
      <Popup>
        <div className="text-sm">
          <div className="font-bold">{threat.type}</div>
          <div>Category: {threat.category}</div>
          <div>Threat Level: {threat.threatLevel}</div>
          <div>Speed: {Math.round(threat.speed)} m/s</div>
          <div>Altitude: {Math.round(threat.altitude)} m</div>
          {threat.isSEAD && <div className="text-orange-500 font-bold">SEAD THREAT</div>}
        </div>
      </Popup>
    </Marker>
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

export default function MapView() {
  const state = useIADSStore((s) => s.state);
  const { mapCenter, mapZoom } = useUIStore();

  if (!state) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-gray-800">
        <p className="text-gray-400">No map data available</p>
      </div>
    );
  }

  const sams = Object.values(state.samSites);
  const threats = Object.values(state.threats);
  const ewrs = Object.values(state.ewrSites);

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
    </div>
  );
}
