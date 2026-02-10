import { IADSState, SAMSite, SAMState, DEFCONLevel, TacticalMode, Threat } from '../types/iads';

const API_BASE = '/api';

async function fetchAPI<T>(endpoint: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${endpoint}`, {
    headers: {
      'Content-Type': 'application/json',
    },
    ...options,
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }));
    throw new Error(error.error || error.message || 'Request failed');
  }

  return response.json();
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

export async function getSAMs(filters?: { state?: SAMState; type?: string }): Promise<{
  count: number;
  sams: SAMSite[];
}> {
  const params = new URLSearchParams();
  if (filters?.state) params.set('state', filters.state);
  if (filters?.type) params.set('type', filters.type);

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
