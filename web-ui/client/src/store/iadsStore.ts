import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { IADSState, SAMSite, Threat, Session, Coalition, AccessLevel } from '../types/iads';

interface IADSStore {
  // 状態
  state: IADSState | null;
  connected: boolean;
  lastUpdate: number | null;
  error: string | null;

  // アクション
  setState: (state: IADSState) => void;
  setConnected: (connected: boolean) => void;
  setError: (error: string | null) => void;

  // セレクタ
  getSAMSites: () => SAMSite[];
  getActiveSAMs: () => SAMSite[];
  getThreats: () => Threat[];
  getSEADThreats: () => Threat[];
}

export const useIADSStore = create<IADSStore>((set, get) => ({
  // 初期状態
  state: null,
  connected: false,
  lastUpdate: null,
  error: null,

  // アクション
  setState: (state: IADSState) => set({
    state,
    lastUpdate: Date.now(),
    error: null
  }),

  setConnected: (connected: boolean) => set({ connected }),

  setError: (error: string | null) => set({ error }),

  // セレクタ
  getSAMSites: () => {
    const state = get().state;
    if (!state) return [];
    return Object.values(state.samSites);
  },

  getActiveSAMs: () => {
    const state = get().state;
    if (!state) return [];
    return Object.values(state.samSites).filter(
      sam => sam.state === 'GREEN' || sam.state === 'TRACKING' || sam.state === 'ENGAGING'
    );
  },

  getThreats: () => {
    const state = get().state;
    if (!state) return [];
    return Object.values(state.threats);
  },

  getSEADThreats: () => {
    const state = get().state;
    if (!state) return [];
    return Object.values(state.threats).filter(t => t.isSEAD);
  }
}));

// セッションストア（永続化）
interface SessionStore {
  session: Session | null;
  isLoggedIn: boolean;

  login: (session: Session) => void;
  logout: () => void;
  getSessionId: () => string | null;
  getCoalition: () => Coalition;
  getAccessLevel: () => AccessLevel;
  canControl: () => boolean;
  isGameMaster: () => boolean;
}

export const useSessionStore = create<SessionStore>()(
  persist(
    (set, get) => ({
      session: null,
      isLoggedIn: false,

      login: (session: Session) => set({
        session,
        isLoggedIn: true
      }),

      logout: () => set({
        session: null,
        isLoggedIn: false
      }),

      getSessionId: () => get().session?.id || null,

      getCoalition: () => get().session?.coalition ?? Coalition.NEUTRAL,

      getAccessLevel: () => get().session?.accessLevel ?? AccessLevel.NONE,

      canControl: () => {
        const level = get().session?.accessLevel ?? AccessLevel.NONE;
        return level >= AccessLevel.OPERATOR;
      },

      isGameMaster: () => {
        const session = get().session;
        return session?.coalition === Coalition.ALL && session?.accessLevel >= AccessLevel.ADMIN;
      }
    }),
    {
      name: 'iads-session',
      partialize: (state) => ({ session: state.session, isLoggedIn: state.isLoggedIn })
    }
  )
);

// UI状態用のストア
interface UIStore {
  selectedSAM: string | null;
  selectedThreat: string | null;
  mapCenter: [number, number];
  mapZoom: number;
  showRangeCircles: boolean;
  showThreats: boolean;
  showEWRs: boolean;
  showEnemyUnits: boolean;  // 敵ユニット表示（GMモード用）

  setSelectedSAM: (name: string | null) => void;
  setSelectedThreat: (id: string | null) => void;
  setMapView: (center: [number, number], zoom: number) => void;
  toggleRangeCircles: () => void;
  toggleThreats: () => void;
  toggleEWRs: () => void;
  toggleEnemyUnits: () => void;
}

export const useUIStore = create<UIStore>((set) => ({
  selectedSAM: null,
  selectedThreat: null,
  mapCenter: [42.0, 43.0], // Caucasus default
  mapZoom: 8,
  showRangeCircles: true,
  showThreats: true,
  showEWRs: true,
  showEnemyUnits: false,

  setSelectedSAM: (name) => set({ selectedSAM: name }),
  setSelectedThreat: (id) => set({ selectedThreat: id }),
  setMapView: (center, zoom) => set({ mapCenter: center, mapZoom: zoom }),
  toggleRangeCircles: () => set((state) => ({ showRangeCircles: !state.showRangeCircles })),
  toggleThreats: () => set((state) => ({ showThreats: !state.showThreats })),
  toggleEWRs: () => set((state) => ({ showEWRs: !state.showEWRs })),
  toggleEnemyUnits: () => set((state) => ({ showEnemyUnits: !state.showEnemyUnits }))
}));
