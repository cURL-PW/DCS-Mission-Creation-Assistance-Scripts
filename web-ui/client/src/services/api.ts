import { IADSState, SAMSite, SAMState, DEFCONLevel, TacticalMode, Threat, Coalition, AccessLevel, MultiplayerInfo, CoalitionData } from '../types/iads';
import { useSessionStore } from '../store/iadsStore';

const API_BASE = '/api';

// セッションIDを取得するヘルパー
function getSessionId(): string | null {
  return useSessionStore.getState().getSessionId();
}

async function fetchAPI<T>(endpoint: string, options?: RequestInit): Promise<T> {
  const sessionId = getSessionId();
  const headers: HeadersInit = {
    'Content-Type': 'application/json',
    ...(sessionId ? { 'X-Session-Id': sessionId } : {}),
    ...options?.headers,
  };

  const response = await fetch(`${API_BASE}${endpoint}`, {
    ...options,
    headers,
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }));
    throw new Error(error.error || error.message || 'Request failed');
  }

  return response.json();
}

// ========== セッション ==========

export interface SessionResponse {
  sessionId: string;
  coalition: Coalition;
  accessLevel: AccessLevel;
  playerName: string;
  expiresIn?: number;
}

export async function createSession(
  coalition: Coalition,
  playerName?: string,
  accessLevel?: AccessLevel
): Promise<SessionResponse> {
  return fetchAPI('/session', {
    method: 'POST',
    body: JSON.stringify({ coalition, playerName, accessLevel }),
  });
}

export async function getSession(): Promise<SessionResponse> {
  return fetchAPI('/session');
}

export async function deleteSession(): Promise<{ success: boolean }> {
  return fetchAPI('/session', { method: 'DELETE' });
}

// ========== マルチプレイヤー ==========

export async function getMultiplayerInfo(): Promise<MultiplayerInfo> {
  return fetchAPI('/multiplayer');
}

export async function getCoalitionData(coalitionId: Coalition): Promise<CoalitionData & { coalition: number; coalitionName: string }> {
  return fetchAPI(`/coalition/${coalitionId}`);
}

// ========== ステータス ==========

export async function getStatus(): Promise<{
  connected: boolean;
  timestamp: number;
  missionTime: string;
  defcon: DEFCONLevel;
  tacticalMode: TacticalMode;
}> {
  return fetchAPI('/status');
}

export async function getFullState(): Promise<IADSState> {
  return fetchAPI('/state');
}

// ========== SAMサイト ==========

export async function getSAMs(filters?: { state?: SAMState; type?: string; coalition?: Coalition }): Promise<{
  count: number;
  sams: SAMSite[];
}> {
  const params = new URLSearchParams();
  if (filters?.state) params.set('state', filters.state);
  if (filters?.type) params.set('type', filters.type);
  if (filters?.coalition !== undefined) params.set('coalition', String(filters.coalition));

  const query = params.toString();
  return fetchAPI(`/sams${query ? `?${query}` : ''}`);
}

export async function getSAM(name: string): Promise<SAMSite> {
  return fetchAPI(`/sams/${encodeURIComponent(name)}`);
}

export async function setSAMState(name: string, state: SAMState): Promise<void> {
  return fetchAPI(`/sams/${encodeURIComponent(name)}/state`, {
    method: 'POST',
    body: JSON.stringify({ state }),
  });
}

export async function setAllSAMsState(state: SAMState): Promise<void> {
  return fetchAPI('/sams/all/state', {
    method: 'POST',
    body: JSON.stringify({ state }),
  });
}

// ========== 脅威 ==========

export async function getThreats(filters?: { category?: string; level?: string }): Promise<{
  count: number;
  threats: Threat[];
}> {
  const params = new URLSearchParams();
  if (filters?.category) params.set('category', filters.category);
  if (filters?.level) params.set('level', filters.level);

  const query = params.toString();
  return fetchAPI(`/threats${query ? `?${query}` : ''}`);
}

export async function getThreat(id: string): Promise<Threat> {
  return fetchAPI(`/threats/${encodeURIComponent(id)}`);
}

// ========== DEFCON ==========

export async function getDEFCON(): Promise<{
  level: DEFCONLevel;
  validLevels: DEFCONLevel[];
}> {
  return fetchAPI('/defcon');
}

export async function setDEFCON(level: DEFCONLevel): Promise<void> {
  return fetchAPI('/defcon', {
    method: 'POST',
    body: JSON.stringify({ level }),
  });
}

// ========== 戦術モード ==========

export async function getTacticalMode(): Promise<{
  mode: TacticalMode;
  validModes: TacticalMode[];
}> {
  return fetchAPI('/tactical');
}

export async function setTacticalMode(mode: TacticalMode): Promise<void> {
  return fetchAPI('/tactical', {
    method: 'POST',
    body: JSON.stringify({ mode }),
  });
}

// ========== カスタムコマンド ==========

export async function sendCommand(command: unknown): Promise<unknown> {
  return fetchAPI('/command', {
    method: 'POST',
    body: JSON.stringify(command),
  });
}

export async function sendCommands(commands: unknown[]): Promise<unknown> {
  return fetchAPI('/commands', {
    method: 'POST',
    body: JSON.stringify({ commands }),
  });
}

// ========== ヘルスチェック ==========

export async function getHealth(): Promise<{
  status: string;
  dcsConnected: boolean;
  lastUpdate: number | null;
}> {
  return fetchAPI('/health');
}
