// IADS状態の型定義

export interface Position {
  x: number;
  y: number;
  z: number;
  lat: number;
  lon: number;
}

export type SAMState = 'GREEN' | 'DARK' | 'TRACKING' | 'ENGAGING' | 'DESTROYED' | 'UNKNOWN';

export interface SAMSite {
  name: string;
  state: SAMState;
  type: string;
  position: Position;
  range: number;
  ammo: number;
  health: number;
  isActive: boolean;
  lastEngagement: number | null;
  linkedEWRs: string[];
}

export interface EWRSite {
  name: string;
  type: string;
  position: Position;
  range: number;
  isActive: boolean;
  detectedThreats: number;
}

export type ThreatCategory = 'AIR' | 'SURFACE' | 'SUBSURFACE';
export type ThreatLevel = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';

export interface Threat {
  id: string;
  type: string;
  category: ThreatCategory;
  position: Position;
  heading: number;
  speed: number;
  altitude: number;
  isSEAD: boolean;
  threatLevel: ThreatLevel;
  firstDetected: number;
  lastSeen: number;
}

export interface Statistics {
  totalSAMs: number;
  activeSAMs: number;
  darkSAMs: number;
  totalEWRs: number;
  activeThreats: number;
  missilesRemaining: number;
  missilesFired: number;
  kills: number;
}

export type DEFCONLevel = 'PEACE' | 'ELEVATED' | 'HIGH' | 'SEVERE' | 'CRITICAL';
export type TacticalMode = 'CONSERVATIVE' | 'BALANCED' | 'AGGRESSIVE' | 'AMBUSH';

export interface IADSState {
  timestamp: number;
  missionTime: string;
  exportTime: string;
  defcon: DEFCONLevel;
  tacticalMode: TacticalMode;
  samSites: Record<string, SAMSite>;
  ewrSites: Record<string, EWRSite>;
  threats: Record<string, Threat>;
  statistics: Statistics;
}

// WebSocket events
export type WebSocketEventType =
  | 'state:update'
  | 'sam:stateChange'
  | 'threat:new'
  | 'threat:update'
  | 'threat:lost'
  | 'defcon:change'
  | 'command:result';

export interface WebSocketEvent<T = unknown> {
  type: WebSocketEventType;
  timestamp: number;
  data: T;
}
