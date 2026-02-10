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

// コマンド関連の型定義

export type CommandType =
  | 'SET_SAM_STATE'
  | 'SET_ALL_SAMS_STATE'
  | 'RELOAD_SAM'
  | 'RELOCATE_SAM'
  | 'SET_DEFCON'
  | 'SET_TACTICAL_MODE'
  | 'SET_EMCON'
  | 'SET_COMMANDER_ENABLED'
  | 'SET_COMMANDER_AGGRESSION'
  | 'LINK_SAM_EWR'
  | 'UNLINK_SAM_EWR'
  | 'DEPLOY_DECOY'
  | 'ACTIVATE_DECOY'
  | 'DEACTIVATE_DECOY'
  | 'CUSTOM';

export interface BaseCommand {
  type: CommandType;
}

export interface SetSAMStateCommand extends BaseCommand {
  type: 'SET_SAM_STATE';
  samName: string;
  state: SAMState;
}

export interface SetAllSAMsStateCommand extends BaseCommand {
  type: 'SET_ALL_SAMS_STATE';
  state: SAMState;
}

export interface SetDEFCONCommand extends BaseCommand {
  type: 'SET_DEFCON';
  level: DEFCONLevel;
}

export interface SetTacticalModeCommand extends BaseCommand {
  type: 'SET_TACTICAL_MODE';
  mode: TacticalMode;
}

export interface SetEMCONCommand extends BaseCommand {
  type: 'SET_EMCON';
  samName: string;
  mode: string;
}

export interface SetCommanderEnabledCommand extends BaseCommand {
  type: 'SET_COMMANDER_ENABLED';
  enabled: boolean;
}

export interface ReloadSAMCommand extends BaseCommand {
  type: 'RELOAD_SAM';
  samName: string;
}

export interface RelocateSAMCommand extends BaseCommand {
  type: 'RELOCATE_SAM';
  samName: string;
  position: Position;
}

export type Command =
  | SetSAMStateCommand
  | SetAllSAMsStateCommand
  | SetDEFCONCommand
  | SetTacticalModeCommand
  | SetEMCONCommand
  | SetCommanderEnabledCommand
  | ReloadSAMCommand
  | RelocateSAMCommand;

export interface CommandBatch {
  commandId: string;
  timestamp: number;
  commands: Command[];
}

export interface CommandResult {
  type: CommandType;
  success: boolean;
  result: string;
}

export interface CommandResponse {
  commandId: string;
  timestamp: number;
  success: boolean;
  data: CommandResult[] | string;
}

// WebSocket イベント

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
