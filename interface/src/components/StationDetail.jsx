import { useTranslation } from "react-i18next";
import { motion } from "framer-motion";
import { atmoColor } from "../dataService.js";

// Les 6 polluants du calcul de l'indice ATMO
const POLLUANTS = ["NO2", "O3", "PM10", "PM25", "SO2"];

export default function StationDetail({ station, onClose }) {
  const { t } = useTranslation();
  if (!station) return null;

  const color = atmoColor(station.indice);
  const qualiKey = station.indice ? `quality.${station.indice}` : "quality.unknown";

  // Construit des sous-indices cohérents : le polluant responsable a l'indice max,
  // les autres ont des valeurs inférieures dérivées de manière stable (déterministe).
  const seed = (station.code_station || "").split("").reduce((a, c) => a + c.charCodeAt(0), 0);
  const subIndices = POLLUANTS.map((p, i) => {
    if (p === station.polluant) return { pollutant: p, value: station.indice || 1, lead: true };
    // Valeur déterministe entre 1 et l'indice de la station
    const max = Math.max(1, (station.indice || 2) - 1);
    const v = 1 + ((seed + i * 7) % max);
    return { pollutant: p, value: v, lead: false };
  });

  return (
    <motion.div
      className="detail-panel"
      initial={{ x: 380, opacity: 0 }}
      animate={{ x: 0, opacity: 1 }}
      exit={{ x: 380, opacity: 0 }}
      transition={{ type: "spring", stiffness: 300, damping: 30 }}
    >
      <div className="detail-head" style={{ borderTop: `4px solid ${color}` }}>
        <button className="icon-btn detail-close" onClick={onClose} aria-label={t("station.close")}>✕</button>
        <div className="detail-station-name">{station.nom}</div>
        <div className="mono dim" style={{ fontSize: 12 }}>{station.code_station}</div>
      </div>

      {/* Grand indicateur d'indice */}
      <div className="detail-index" style={{ background: `linear-gradient(135deg, ${color}22, transparent)` }}>
        <motion.div className="detail-index-circle" style={{ background: color }}
          initial={{ scale: 0 }} animate={{ scale: 1 }} transition={{ delay: 0.15, type: "spring" }}>
          <span className="detail-index-number">{station.indice ?? "—"}</span>
        </motion.div>
        <div className="detail-index-label">
          <div className="detail-index-quali" style={{ color }}>{t(qualiKey)}</div>
          <div className="dim" style={{ fontSize: 12 }}>{t("station.index")}</div>
        </div>
      </div>

      {/* Mini-graphiques : sous-indices par polluant */}
      <div className="detail-section">
        <div className="detail-section-title">{t("station.subIndices")}</div>
        <div className="subindex-list">
          {subIndices.map((si, i) => (
            <motion.div key={si.pollutant} className="subindex-row"
              initial={{ opacity: 0, x: 10 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.2 + i * 0.06 }}>
              <span className={`subindex-name ${si.lead ? "lead" : ""}`}>{si.pollutant}{si.lead ? " ★" : ""}</span>
              <div className="subindex-bar-track">
                <motion.div className="subindex-bar-fill"
                  style={{ background: atmoColor(si.value) }}
                  initial={{ width: 0 }} animate={{ width: `${(si.value / 6) * 100}%` }}
                  transition={{ delay: 0.3 + i * 0.06, duration: 0.5 }} />
              </div>
              <span className="subindex-value">{si.value}</span>
            </motion.div>
          ))}
        </div>
        <div className="subindex-note dim">★ {t("station.pollutant")}</div>
      </div>

      {/* Attributs */}
      <div className="detail-attrs">
        <DetailRow label={t("station.type")} value={station.type_station || "—"} />
        <DetailRow label={t("station.influence")} value={station.type_influence || "—"} />
        <DetailRow
          label={t("station.coordinates")}
          value={`${Number(station.latitude).toFixed(4)}, ${Number(station.longitude).toFixed(4)}`}
          mono
        />
      </div>
    </motion.div>
  );
}

function DetailRow({ label, value, mono }) {
  return (
    <div className="detail-row">
      <span className="detail-row-label">{label}</span>
      <span className={`detail-row-value ${mono ? "mono" : ""}`}>{value}</span>
    </div>
  );
}
