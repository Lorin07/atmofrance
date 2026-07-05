// Couche d'accès aux données AtmoFrance.
// Interroge l'API locale ; en cas d'échec, bascule automatiquement
// sur un instantané figé pour que la démonstration ne plante jamais.

import { FALLBACK } from "./fallbackData.js";

const API_BASE = "http://localhost:8000";
const TIMEOUT_MS = 3500;
const JOUR_DEFAUT = "2026-07-03"; // jour le plus récent disponible

async function fetchWithTimeout(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: controller.signal });
    clearTimeout(timer);
    if (!res.ok) throw new Error("HTTP " + res.status);
    return await res.json();
  } catch (e) {
    clearTimeout(timer);
    throw e;
  }
}

// État de la source (live / offline / loading), observable par l'interface
let currentSource = "loading";
const listeners = new Set();
export function onSourceChange(cb) { listeners.add(cb); return () => listeners.delete(cb); }
function setSource(s) { currentSource = s; listeners.forEach((cb) => cb(s)); }
export function getSource() { return currentSource; }

// Normalise un enregistrement d'indice de l'API vers le format interne de l'interface
function normalizeIndice(i) {
  return {
    code_station: i.code_site || i.code_station,
    nom: i.nom_site || i.nom || "Station",
    indice: i.indice_atmo ?? i.indice ?? null,
    qualificatif: i.qualificatif || null,
    polluant: i.polluant_resp || i.polluant || null,
    latitude: i.latitude,
    longitude: i.longitude,
    jour: i.jour,
  };
}

// Récupère et consolide toutes les données nécessaires à l'interface.
export async function loadAllData() {
  try {
    const [stats, stationsRaw, indicesRaw, depassementsRaw] = await Promise.all([
      fetchWithTimeout(`${API_BASE}/stats`),
      fetchWithTimeout(`${API_BASE}/stations`),
      fetchWithTimeout(`${API_BASE}/indices?jour=${JOUR_DEFAUT}`),
      fetchWithTimeout(`${API_BASE}/depassements`),
    ]);

    const indicesRows = (indicesRaw.indices || []).map(normalizeIndice);
    const stationsMeta = stationsRaw.stations || [];
    const depassements = depassementsRaw.depassements || [];

    // Enrichir chaque indice avec le type de station (via le référentiel stations)
    const metaByCode = {};
    stationsMeta.forEach((s) => { metaByCode[s.code_station] = s; });

    const stations = indicesRows
      .filter((i) => i.latitude != null && i.longitude != null)
      .map((i) => {
        const meta = metaByCode[i.code_station] || {};
        return {
          ...i,
          type_station: meta.type_station || "—",
          type_influence: meta.type_influence || "—",
        };
      });

    setSource("live");
    return { stats, stations, indices: indicesRows, depassements, source: "live", jour: JOUR_DEFAUT };
  } catch (e) {
    setSource("offline");
    return { ...FALLBACK, source: "offline", jour: JOUR_DEFAUT };
  }
}

// Couleurs officielles de l'indice ATMO (1 à 6)
export const ATMO_COLORS = {
  1: "#50CCAA", 2: "#50CCF0", 3: "#F0E641",
  4: "#FF5050", 5: "#960032", 6: "#7D2181", null: "#8A94A6",
};
export function atmoColor(indice) { return ATMO_COLORS[indice] ?? ATMO_COLORS[null]; }
