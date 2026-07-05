import { useTranslation } from "react-i18next";
import { motion, AnimatePresence } from "framer-motion";
import { atmoColor } from "../dataService.js";

// Barre de filtres pour la carte : par qualité (indice), par polluant, par type d'influence.
export default function FilterBar({ filters, setFilters, stations, open }) {
  const { t } = useTranslation();

  // Options de polluant présentes dans les données
  const pollutants = [...new Set(stations.map((s) => s.polluant).filter(Boolean))].sort();
  const influences = [...new Set(stations.map((s) => s.type_influence).filter((x) => x && x !== "—"))].sort();

  const toggleQuality = (n) => {
    setFilters((f) => {
      const q = f.quality.includes(n) ? f.quality.filter((x) => x !== n) : [...f.quality, n];
      return { ...f, quality: q };
    });
  };

  const activeCount =
    filters.quality.length + (filters.pollutant ? 1 : 0) + (filters.influence ? 1 : 0);

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="filter-bar card"
          initial={{ opacity: 0, y: -10, height: 0 }}
          animate={{ opacity: 1, y: 0, height: "auto" }}
          exit={{ opacity: 0, y: -10, height: 0 }}
          transition={{ duration: 0.25 }}
        >
          {/* Filtre par qualité (indices 1-6) */}
          <div className="filter-group">
            <span className="filter-label">{t("map.filterQuality")}</span>
            <div className="filter-chips">
              {[1, 2, 3, 4, 5, 6].map((n) => (
                <button
                  key={n}
                  className={`filter-chip ${filters.quality.includes(n) ? "active" : ""}`}
                  style={filters.quality.includes(n) ? { background: atmoColor(n), borderColor: atmoColor(n), color: "#0A0E1A" } : { borderColor: atmoColor(n) }}
                  onClick={() => toggleQuality(n)}
                >
                  {n}
                </button>
              ))}
            </div>
          </div>

          {/* Filtre par polluant */}
          <div className="filter-group">
            <span className="filter-label">{t("station.pollutant")}</span>
            <select
              className="filter-select"
              value={filters.pollutant}
              onChange={(e) => setFilters((f) => ({ ...f, pollutant: e.target.value }))}
            >
              <option value="">{t("map.all")}</option>
              {pollutants.map((p) => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>

          {/* Filtre par type d'influence */}
          <div className="filter-group">
            <span className="filter-label">{t("station.influence")}</span>
            <select
              className="filter-select"
              value={filters.influence}
              onChange={(e) => setFilters((f) => ({ ...f, influence: e.target.value }))}
            >
              <option value="">{t("map.all")}</option>
              {influences.map((x) => <option key={x} value={x}>{x}</option>)}
            </select>
          </div>

          {/* Réinitialiser */}
          {activeCount > 0 && (
            <button className="filter-reset" onClick={() => setFilters({ quality: [], pollutant: "", influence: "" })}>
              ✕ {activeCount}
            </button>
          )}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
