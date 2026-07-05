import { useEffect, useRef, useMemo, useState } from "react";
import { MapContainer, TileLayer, CircleMarker, useMap } from "react-leaflet";
import { useTranslation } from "react-i18next";
import { atmoColor } from "../dataService.js";
import "leaflet/dist/leaflet.css";

// Fonds de carte selon le thème (clair / sombre)
const TILES = {
  dark: {
    url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
    attribution: '&copy; OpenStreetMap &copy; CARTO',
  },
  light: {
    url: "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
    attribution: '&copy; OpenStreetMap &copy; CARTO',
  },
};

// Recentre la carte quand on change de sélection (petit vol vers la station)
function FlyTo({ target }) {
  const map = useMap();
  useEffect(() => {
    if (target) map.flyTo([target.latitude, target.longitude], 9, { duration: 0.8 });
  }, [target, map]);
  return null;
}

// Ajuste la vue aux données au premier chargement
function FitOnce({ points }) {
  const map = useMap();
  const done = useRef(false);
  useEffect(() => {
    if (done.current || !points.length) return;
    // Se centrer sur la France métropolitaine par défaut
    map.setView([46.6, 2.4], 6);
    done.current = true;
  }, [points, map]);
  return null;
}

export default function MapView({ stations, theme, selected, onSelect }) {
  const { t } = useTranslation();
  const tiles = theme === "light" ? TILES.light : TILES.dark;

  // Rayon d'un point selon l'indice (les mauvais ressortent un peu plus)
  const radiusFor = (indice) => 5 + (indice ? Math.min(indice, 6) * 0.8 : 0);

  return (
    <div className="map-wrap">
      <MapContainer
        center={[46.6, 2.4]}
        zoom={6}
        minZoom={5}
        maxBounds={[[40.0, -6.0], [52.5, 11.0]]}
        maxBoundsViscosity={1.0}
        worldCopyJump={false}
        style={{ height: "100%", width: "100%", background: theme === "light" ? "#EEF2F9" : "#0A0E1A" }}
        zoomControl={true}
        attributionControl={false}
      >
        <TileLayer key={theme} url={tiles.url} attribution={tiles.attribution} noWrap={true} />
        <FitOnce points={stations} />
        <FlyTo target={selected} />

        {stations.map((s, idx) => {
          const color = atmoColor(s.indice);
          const isSel = selected && selected.code_station === s.code_station;
          return (
            <CircleMarker
              key={`${s.code_station}-${idx}`}
              center={[s.latitude, s.longitude]}
              radius={isSel ? radiusFor(s.indice) + 4 : radiusFor(s.indice)}
              pathOptions={{
                color: isSel ? "#FFFFFF" : color,
                weight: isSel ? 2.5 : 1,
                fillColor: color,
                fillOpacity: 0.85,
              }}
              eventHandlers={{ click: () => onSelect(s) }}
              className={`station-marker atmo-${s.indice || "none"}`}
            />
          );
        })}
      </MapContainer>

      {/* Légende de l'indice ATMO */}
      <div className="map-legend card">
        <div className="legend-title">{t("map.legend")}</div>
        {[1, 2, 3, 4, 5, 6].map((n) => (
          <div key={n} className="legend-row">
            <span className="legend-dot" style={{ background: atmoColor(n) }} />
            <span className="legend-label">{t(`quality.${n}`)}</span>
          </div>
        ))}
        <div className="legend-row">
          <span className="legend-dot" style={{ background: atmoColor(null) }} />
          <span className="legend-label">{t("quality.unknown")}</span>
        </div>
      </div>
    </div>
  );
}
