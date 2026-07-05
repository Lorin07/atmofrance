import { useTranslation } from "react-i18next";
import { motion } from "framer-motion";
import {
  PieChart, Pie, Cell, ResponsiveContainer, BarChart, Bar, XAxis, YAxis,
  Tooltip, Legend, RadialBarChart, RadialBar, LineChart, Line, CartesianGrid,
} from "recharts";
import { atmoColor } from "../dataService.js";

const QUALI_COLOR = {
  Bon: "#50CCAA", Moyen: "#50CCF0", Degrade: "#F0E641",
  Dégradé: "#F0E641", Mauvais: "#FF5050",
  "Très mauvais": "#960032", "Extrêmement mauvais": "#7D2181",
};

function tooltipStyle() {
  return { background: "var(--bg-elevated)", border: "1px solid var(--border)", borderRadius: 8, color: "var(--text)", fontSize: 12 };
}

// Compte les occurrences d'une clé dans un tableau
function countBy(arr, keyFn) {
  const out = {};
  arr.forEach((x) => { const k = keyFn(x); if (k) out[k] = (out[k] || 0) + 1; });
  return out;
}

// ---------- TABLEAU DE BORD ENRICHI ----------
export function DashboardView({ data }) {
  const { t } = useTranslation();
  const stations = data.stations || [];
  const deps = data.depassements || [];
  const rep = data.stats?.repartition_indices || [];

  // 1. Indice moyen global (pour la jauge)
  const withIndex = stations.filter((s) => s.indice != null);
  const avgIndex = withIndex.length
    ? (withIndex.reduce((a, s) => a + s.indice, 0) / withIndex.length)
    : 0;
  const avgRounded = Math.round(avgIndex * 10) / 10;
  const gaugeColor = atmoColor(Math.round(avgIndex));

  // 2. Répartition des indices (camembert)
  const pieData = rep.map((r) => ({ name: r.qualificatif, value: r.n }));

  // 3. Répartition par polluant responsable
  const byPollutant = countBy(withIndex, (s) => s.polluant);
  const pollutantData = Object.entries(byPollutant).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value);

  // 4. Dépassements par polluant
  const depByPollutant = countBy(deps, (d) => d.code_polluant);
  const depPollutantData = Object.entries(depByPollutant).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value);

  // 5. Dépassements par jour (tendance)
  const depByDay = countBy(deps, (d) => d.jour);
  const dayData = Object.entries(depByDay).map(([jour, value]) => ({ jour: jour?.slice(5) || jour, value })).sort((a, b) => a.jour.localeCompare(b.jour));

  // 6. Répartition par type d'influence
  const byInfluence = countBy(stations, (s) => s.type_influence);
  const influenceData = Object.entries(byInfluence).map(([name, value]) => ({ name, value }));

  return (
    <motion.div className="view-scroll" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}>
      <h2 className="view-title">{t("dashboard.title")}</h2>

      {/* Ligne 1 : jauge de qualité + répartition indices */}
      <div className="dash-grid">
        <motion.div className="card chart-card gauge-card" initial={{ scale: 0.96, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ delay: 0.1 }}>
          <div className="card-title">{t("dashboard.quality")}</div>
          <div className="gauge-wrap">
            <ResponsiveContainer width="100%" height={200}>
              <RadialBarChart innerRadius="70%" outerRadius="100%" data={[{ value: avgIndex, fill: gaugeColor }]} startAngle={225} endAngle={-45}>
                <RadialBar minAngle={15} background={{ fill: "var(--bg-panel-2)" }} dataKey="value" cornerRadius={12} max={6} />
              </RadialBarChart>
            </ResponsiveContainer>
            <div className="gauge-center">
              <div className="gauge-number" style={{ color: gaugeColor }}>{avgRounded}</div>
              <div className="gauge-sub dim">{t("dashboard.quality")}</div>
            </div>
          </div>
        </motion.div>

        <motion.div className="card chart-card" initial={{ scale: 0.96, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ delay: 0.15 }}>
          <div className="card-title">{t("dashboard.distribution")}</div>
          <ResponsiveContainer width="100%" height={240}>
            <PieChart>
              <Pie data={pieData} dataKey="value" nameKey="name" innerRadius={55} outerRadius={90} paddingAngle={2} animationDuration={800}>
                {pieData.map((entry, i) => (<Cell key={i} fill={QUALI_COLOR[entry.name] || "#8A94A6"} stroke="none" />))}
              </Pie>
              <Tooltip contentStyle={tooltipStyle()} />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </motion.div>
      </div>

      {/* Ligne 2 : polluant responsable + dépassements par polluant */}
      <div className="dash-grid" style={{ marginTop: 18 }}>
        <motion.div className="card chart-card" initial={{ y: 20, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={{ delay: 0.2 }}>
          <div className="card-title">{t("dashboard.byPollutant")}</div>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={pollutantData} layout="vertical" margin={{ left: 10 }}>
              <XAxis type="number" tick={{ fontSize: 11, fill: "var(--text-dim)" }} />
              <YAxis type="category" dataKey="name" tick={{ fontSize: 11, fill: "var(--text-dim)" }} width={50} />
              <Tooltip contentStyle={tooltipStyle()} cursor={{ fill: "rgba(128,128,128,0.08)" }} />
              <Bar dataKey="value" fill="var(--accent)" radius={[0, 6, 6, 0]} animationDuration={800} />
            </BarChart>
          </ResponsiveContainer>
        </motion.div>

        <motion.div className="card chart-card" initial={{ y: 20, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={{ delay: 0.25 }}>
          <div className="card-title">{t("dashboard.depByPollutant")}</div>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={depPollutantData}>
              <XAxis dataKey="name" tick={{ fontSize: 11, fill: "var(--text-dim)" }} />
              <YAxis tick={{ fontSize: 11, fill: "var(--text-dim)" }} />
              <Tooltip contentStyle={tooltipStyle()} cursor={{ fill: "rgba(128,128,128,0.08)" }} />
              <Bar dataKey="value" fill="#FF5050" radius={[6, 6, 0, 0]} animationDuration={800} />
            </BarChart>
          </ResponsiveContainer>
        </motion.div>
      </div>

      {/* Ligne 3 : tendance des dépassements + type d'influence */}
      <div className="dash-grid" style={{ marginTop: 18 }}>
        <motion.div className="card chart-card" initial={{ y: 20, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={{ delay: 0.3 }}>
          <div className="card-title">{t("dashboard.trend")}</div>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={dayData}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-soft)" />
              <XAxis dataKey="jour" tick={{ fontSize: 11, fill: "var(--text-dim)" }} />
              <YAxis tick={{ fontSize: 11, fill: "var(--text-dim)" }} />
              <Tooltip contentStyle={tooltipStyle()} />
              <Line type="monotone" dataKey="value" stroke="var(--accent)" strokeWidth={3} dot={{ r: 5, fill: "var(--accent)" }} animationDuration={1000} />
            </LineChart>
          </ResponsiveContainer>
        </motion.div>

        <motion.div className="card chart-card" initial={{ y: 20, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={{ delay: 0.35 }}>
          <div className="card-title">{t("dashboard.byInfluence")}</div>
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie data={influenceData} dataKey="value" nameKey="name" outerRadius={85} animationDuration={800} label={{ fontSize: 11, fill: "var(--text-dim)" }}>
                {influenceData.map((e, i) => (<Cell key={i} fill={["#50CCF0", "#50CCAA", "#F0E641", "#FF5050"][i % 4]} stroke="none" />))}
              </Pie>
              <Tooltip contentStyle={tooltipStyle()} />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </motion.div>
      </div>
    </motion.div>
  );
}

// ---------- CLASSEMENTS ----------
export function RankingView({ data }) {
  const { t } = useTranslation();
  const ranked = [...(data.stations || [])].filter((s) => s.indice != null).sort((a, b) => b.indice - a.indice).slice(0, 15);
  return (
    <motion.div className="view-scroll" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}>
      <h2 className="view-title">{t("ranking.title")}</h2>
      <div className="card">
        <div className="card-title">{t("ranking.mostPolluted")}</div>
        <table className="rank-table">
          <thead>
            <tr>
              <th style={{ width: 50 }}>{t("ranking.rank")}</th>
              <th>{t("ranking.station")}</th>
              <th style={{ width: 120 }}>{t("station.pollutant")}</th>
              <th style={{ width: 150, textAlign: "right" }}>{t("station.index")}</th>
            </tr>
          </thead>
          <tbody>
            {ranked.map((s, i) => (
              <motion.tr key={s.code_station + i} initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: i * 0.03 }}>
                <td className="rank-num">{i + 1}</td>
                <td>{s.nom}</td>
                <td className="dim">{s.polluant || "—"}</td>
                <td style={{ textAlign: "right" }}>
                  <span className="chip" style={{ background: atmoColor(s.indice) + "22", color: atmoColor(s.indice) }}>
                    {s.indice} · {t(`quality.${s.indice}`)}
                  </span>
                </td>
              </motion.tr>
            ))}
          </tbody>
        </table>
      </div>
    </motion.div>
  );
}

// ---------- ALERTES ----------
export function AlertsView({ data }) {
  const { t } = useTranslation();
  const deps = data.depassements || [];
  return (
    <motion.div className="view-scroll" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}>
      <h2 className="view-title">{t("alerts.title")}</h2>
      <p className="dim" style={{ marginBottom: 18 }}>{t("alerts.subtitle")}</p>
      {deps.length === 0 ? (
        <div className="card dim">{t("alerts.none")}</div>
      ) : (
        <div className="alert-list">
          {deps.map((d, i) => {
            const isAlert = d.depassement === "alerte";
            const col = isAlert ? "#FF5050" : "#F0E641";
            return (
              <motion.div key={i} className="card alert-card" style={{ borderLeft: `4px solid ${col}` }}
                initial={{ opacity: 0, x: -12 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: i * 0.04 }}>
                <div className="alert-main">
                  <div className="alert-site">{d.nom_site}</div>
                  <div className="dim mono" style={{ fontSize: 12 }}>{d.code_polluant} · {d.valeur} {d.unite}</div>
                </div>
                <div className="alert-side">
                  <span className="chip" style={{ background: col + "22", color: col }}>
                    {isAlert ? t("alerts.alertLevel") : t("alerts.infoLevel")}
                  </span>
                  <div className="dim" style={{ fontSize: 11, marginTop: 4 }}>{d.jour}</div>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
    </motion.div>
  );
}

// ---------- À PROPOS ----------
export function AboutView({ data }) {
  const { t } = useTranslation();
  const tech = ["PostgreSQL / PostGIS", "MongoDB", "MinIO", "Apache Kafka", "Apache Spark", "Apache Airflow", "FastAPI", "React"];
  return (
    <motion.div className="view-scroll" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}>
      <h2 className="view-title">{t("about.title")}</h2>
      <div className="card" style={{ marginBottom: 16 }}>
        <p style={{ lineHeight: 1.7 }}>{t("about.description")}</p>
      </div>
      <div className="dash-grid">
        <div className="card">
          <div className="card-title">{t("about.tech")}</div>
          <div className="tech-tags">{tech.map((x) => <span key={x} className="tech-tag">{x}</span>)}</div>
        </div>
        <div className="card">
          <div className="card-title">{t("about.sources")}</div>
          <ul className="source-list">
            <li>Geod'Air · Mesures de qualité de l'air</li>
            <li>Base Adresse Nationale · Géocodage</li>
            <li>Indice ATMO · Référentiel officiel</li>
          </ul>
        </div>
      </div>
    </motion.div>
  );
}
