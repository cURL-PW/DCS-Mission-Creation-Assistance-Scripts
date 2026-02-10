import { create } from 'zustand';
import { IADSState, SAMSite, Threat, DEFCONLevel, TacticalMode } from '../types/iads';

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

// UI状態用のストア
interface UIStore {
  selectedSAM: string | null;
  selectedThreat: string | null;
  mapCenter: [number, number];
  mapZoom: number;
  showRangeCircles: boolean;
  showThreats: boolean;
  showEWRs: boolean;

  setSelectedSAM: (name: string | null) => void;
  setSelectedThreat: (id: string | null) => void;
  setMapView: (center: [number, number], zoom: number) => void;
  toggleRangeCircles: () => void;
  toggleThreats: () => void;
  toggleEWRs: () => void;
}

export const useUIStore = create<UIStore>((set) => ({
  selectedSAM: null,
  selectedThreat: null,
  mapCenter: [42.0, 43.0], // Caucasus default
  mapZoom: 8,
  showRangeCircles: true,
  showThreats: true,
  showEWRs: true,

  setSelectedSAM: (name) => set({ selectedSAM: name }),
  setSelectedThreat: (id) => set({ selectedThreat: id }),
  setMapView: (center, zoom) => set({ mapCenter: center, mapZoom: zoom }),
  toggleRangeCircles: () => set((state) => ({ showRangeCircles: !state.showRangeCircles })),
  toggleThreats: () => set((state) => ({ showThreats: !state.showThreats })),
  toggleEWRs: () => set((state) => ({ showEWRs: !state.showEWRs }))
}));
