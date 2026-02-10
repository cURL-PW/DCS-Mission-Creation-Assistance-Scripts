// IADS状態の型定義

export interface Position {
  x: number;
  y: number;
  z: number;
  lat: number;
  lon: number;
}

// コアリション定義
export enum Coalition {
  NEUTRAL = 0,
  RED = 1,
  BLUE = 2,
  ALL = -1
}

// アクセスレベル
export enum AccessLevel {
  NONE = 0,
  VIEW = 1,
  OPERATOR = 2,
  COMMANDER = 3,
  ADMIN = 4
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
  coalition: Coalition;
}

export interface EWRSite {
  name: string;
  type: string;
  position: Position;
  range: number;
  isActive: boolean;
  detectedThreats: number;
  coalition: Coalition;
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
  coalition: Coalition;
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

// マルチプレイヤー情報
export interface Player {
  id: number;
  name: string;
  coalition: Coalition;
  slot: string;
  ping: number;
}

export interface CoalitionInfo {
  name: string;
  playerCount: number;
}

export interface MultiplayerInfo {
  isMultiplayer: boolean;
  isServer: boolean;
  serverName: string;
  players: Player[];
  coalitions: {
    red: CoalitionInfo;
    blue: CoalitionInfo;
    neutral?: CoalitionInfo;
  };
}

// コアリション別データ
export interface CoalitionData {
  samSites: Record<string, SAMSite>;
  ewrSites: Record<string, EWRSite>;
  threats: Record<string, Threat>;
  statistics: Statistics;
}

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
  multiplayer?: MultiplayerInfo;
  coalitionData?: {
    red: CoalitionData;
    blue: CoalitionData;
  };
}

// セッション
export interface Session {
  id: string;
  coalition: Coalition;
  accessLevel: AccessLevel;
  playerName: string;
  createdAt?: number;
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
