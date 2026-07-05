import { useState, useEffect } from "react";
import { useTranslation } from "react-i18next";
import { AnimatePresence } from "framer-motion";
import { LANGUAGES } from "./i18n.js";
import { loadAllData, onSourceChange } from "./dataService.js";
import MapView from "./components/MapView.jsx";
import StationDetail from "./components/StationDetail.jsx";
import ChatBot from "./components/ChatBot.jsx";
import FilterBar from "./components/FilterBar.jsx";
import Splash from "./components/Splash.jsx";
import { DashboardView, RankingView, AlertsView, AboutView } from "./components/Views.jsx";

export default function App() {
  const { t, i18n } = useTranslation();
  const [theme, setTheme] = useState("dark");
  const [view, setView] = useState("map");
  const [data, setData] = useState({ stations: [], depassements: [], stats: {} });
  const [selected, setSelected] = useState(null);
  const [source, setSource] = useState("loading");
  const [langOpen, setLangOpen] = useState(false);
  const [chatOpen, setChatOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [showSplash, setShowSplash] = useState(true);
  const [showFilters, setShowFilters] = useState(false);
  const [presentation, setPresentation] = useState(false);
  const [filters, setFilters] = useState({ quality: [], pollutant: "", influence: "" });

  useEffect(() => { document.documentElement.setAttribute("data-theme", theme); }, [theme]);

  useEffect(() => {
    const unsub = onSourceChange(setSource);
    loadAllData().then((d) => { setData(d); setLoading(false); });
    return unsub;
  }, []);

  // Filtrage combiné : recherche + qualité + polluant + influence
  const filteredStations = data.stations.filter((s) => {
    if (search && !(s.nom && s.nom.toLowerCase().includes(search.toLowerCase()))) return false;
    if (filters.quality.length && !filters.quality.includes(s.indice)) return false;
    if (filters.pollutant && s.polluant !== filters.pollutant) return false;
    if (filters.influence && s.type_influence !== filters.influence) return false;
    return true;
  });

  const currentLang = LANGUAGES.find((l) => l.code === i18n.language) || LANGUAGES[0];
  const activeFilters = filters.quality.length + (filters.pollutant ? 1 : 0) + (filters.influence ? 1 : 0);

  const navItems = [
    { id: "map", label: t("nav.map") },
    { id: "dashboard", label: t("nav.dashboard") },
    { id: "ranking", label: t("nav.ranking") },
    { id: "alerts", label: t("nav.alerts") },
    { id: "about", label: t("nav.about") },
  ];

  return (
    <>
      {/* Écran d'accueil */}
      <AnimatePresence>
        {showSplash && <Splash data={data} onEnter={() => setShowSplash(false)} />}
      </AnimatePresence>

      <div className={`app ${presentation ? "presentation-mode" : ""}`}>
        <header className="topbar">
          <div className="brand">
            <div className="brand-mark"><AtmoLogo /></div>
            <div>
              <div className="brand-title">Atmo<span className="accent">France</span></div>
              <div className="brand-tagline">{t("tagline")}</div>
            </div>
          </div>

          <nav className="nav">
            {navItems.map((n) => (
              <button key={n.id} className={`nav-item ${view === n.id ? "active" : ""}`} onClick={() => setView(n.id)}>
                {n.label}
              </button>
            ))}
          </nav>

          <div className="topbar-spacer" />

          <div className={`source-badge source-${source}`}>
            <span className="source-dot" />
            {source === "live" ? t("status.live") : source === "offline" ? t("status.offline") : t("status.loading")}
          </div>

          {/* Mode présentation */}
          <button className="icon-btn" onClick={() => setPresentation((p) => !p)} aria-label="Presentation" title={t("presentation.toggle")}>
            {presentation ? "⊡" : "⊞"}
          </button>

          <div className="lang-select">
            <button className="icon-btn" onClick={() => setLangOpen((o) => !o)} aria-label="Language" style={{ width: "auto", padding: "0 12px", gap: 8 }}>
              <span className="lang-flag">{currentLang.flag}</span>
            </button>
            <AnimatePresence>
              {langOpen && (
                <div className="lang-menu">
                  {LANGUAGES.map((l) => (
                    <button key={l.code} className={`lang-option ${l.code === i18n.language ? "active" : ""}`}
                      onClick={() => { i18n.changeLanguage(l.code); setLangOpen(false); }}>
                      <span className="lang-flag">{l.flag}</span>
                      {l.native}
                    </button>
                  ))}
                </div>
              )}
            </AnimatePresence>
          </div>

          <button className="icon-btn" onClick={() => setTheme((th) => (th === "dark" ? "light" : "dark"))} aria-label="Theme">
            {theme === "dark" ? "☀" : "☾"}
          </button>
        </header>

        <main className="body">
          <KpiBar data={data} loading={loading} />

          {view === "map" && (
            <>
              <div className="map-controls">
                <div className="map-search-wrap">
                  <input className="map-search" placeholder={t("map.search")} value={search} onChange={(e) => setSearch(e.target.value)} />
                </div>
                <button className={`map-filter-btn ${showFilters ? "active" : ""} ${activeFilters ? "has-active" : ""}`} onClick={() => setShowFilters((f) => !f)}>
                  ⚙ {t("map.filters")}{activeFilters > 0 ? ` (${activeFilters})` : ""}
                </button>
              </div>

              <FilterBar filters={filters} setFilters={setFilters} stations={data.stations} open={showFilters} />

              {search && filteredStations.length === 0 && (<div className="map-search-empty-float">{t("map.noResult")}</div>)}

              <MapView stations={filteredStations} theme={theme} selected={selected} onSelect={setSelected} />
              <AnimatePresence>
                {selected && <StationDetail station={selected} onClose={() => setSelected(null)} />}
              </AnimatePresence>
            </>
          )}

          {view === "dashboard" && <DashboardView data={data} />}
          {view === "ranking" && <RankingView data={data} />}
          {view === "alerts" && <AlertsView data={data} />}
          {view === "about" && <AboutView data={data} />}

          <ChatBot data={data} open={chatOpen} onToggle={() => { setChatOpen((o) => !o); if (!chatOpen) setSelected(null); }} />
        </main>
      </div>
    </>
  );
}

function KpiBar({ data, loading }) {
  const { t } = useTranslation();
  const s = data.stats || {};
  const kpis = [
    { value: s.nb_stations, label: t("kpi.stations") },
    { value: s.nb_stations_geolocalisees, label: t("kpi.located") },
    { value: s.nb_jours_donnees, label: t("kpi.days") },
    { value: s.nb_depassements_alerte, label: t("kpi.alerts"), color: "#FF5050" },
    { value: s.nb_depassements_info, label: t("kpi.info"), color: "#F0E641" },
  ];
  return (
    <div className="kpi-bar">
      {kpis.map((k, i) => (
        <div key={i} className="kpi-cell">
          <div className="kpi-value" style={{ color: k.color }}>{loading ? "…" : (k.value ?? "—")}</div>
          <div className="kpi-label">{k.label}</div>
        </div>
      ))}
    </div>
  );
}

function AtmoLogo() {
  return (
    <svg width="34" height="34" viewBox="0 0 34 34" fill="none">
      <circle cx="17" cy="17" r="15" stroke="var(--accent)" strokeWidth="1.5" opacity="0.3" />
      <circle cx="17" cy="17" r="9" stroke="var(--accent)" strokeWidth="1.5" opacity="0.6" />
      <circle cx="17" cy="17" r="3.5" fill="var(--accent)" />
    </svg>
  );
}
