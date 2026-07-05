import { useTranslation } from "react-i18next";
import { motion } from "framer-motion";

// Écran d'accueil : une entrée en matière élégante avant la carte.
// Animation de particules évoquant des stations de mesure qui s'allument.
export default function Splash({ data, onEnter }) {
  const { t } = useTranslation();
  const s = data.stats || {};

  // Positions pseudo-aléatoires mais stables pour les particules décoratives
  const particles = Array.from({ length: 40 }, (_, i) => ({
    x: (i * 37) % 100,
    y: (i * 53) % 100,
    delay: (i % 10) * 0.15,
    color: ["#50CCAA", "#50CCF0", "#F0E641", "#FF5050"][i % 4],
  }));

  return (
    <motion.div className="splash" initial={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.6 }}>
      {/* Particules d'arrière-plan */}
      <div className="splash-particles">
        {particles.map((p, i) => (
          <motion.span
            key={i}
            className="splash-particle"
            style={{ left: `${p.x}%`, top: `${p.y}%`, background: p.color }}
            initial={{ opacity: 0, scale: 0 }}
            animate={{ opacity: [0, 0.8, 0.3], scale: [0, 1.4, 1] }}
            transition={{ duration: 2.5, delay: p.delay, repeat: Infinity, repeatType: "reverse" }}
          />
        ))}
      </div>

      {/* Contenu central */}
      <motion.div className="splash-content"
        initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3, duration: 0.7 }}>
        <motion.div className="splash-logo"
          initial={{ scale: 0, rotate: -90 }} animate={{ scale: 1, rotate: 0 }} transition={{ delay: 0.2, type: "spring", stiffness: 200 }}>
          <svg width="90" height="90" viewBox="0 0 90 90" fill="none">
            <circle cx="45" cy="45" r="42" stroke="#50CCF0" strokeWidth="2" opacity="0.2" />
            <circle cx="45" cy="45" r="30" stroke="#50CCF0" strokeWidth="2" opacity="0.4" />
            <circle cx="45" cy="45" r="18" stroke="#50CCF0" strokeWidth="2" opacity="0.7" />
            <circle cx="45" cy="45" r="7" fill="#50CCF0" />
          </svg>
        </motion.div>

        <h1 className="splash-title">Atmo<span style={{ color: "#50CCF0" }}>France</span></h1>
        <p className="splash-tagline">{t("tagline")}</p>

        {/* Compteurs animés */}
        <div className="splash-stats">
          <SplashStat value={s.nb_stations || 483} label={t("kpi.stations")} delay={0.6} />
          <SplashStat value={s.nb_stations_geolocalisees || 410} label={t("kpi.located")} delay={0.75} />
          <SplashStat value={(s.nb_depassements_alerte || 112) + (s.nb_depassements_info || 267)} label={t("nav.alerts")} delay={0.9} />
        </div>

        <motion.button className="splash-enter" onClick={onEnter}
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 1.1 }}
          whileHover={{ scale: 1.05 }} whileTap={{ scale: 0.97 }}>
          {t("splash.enter")} →
        </motion.button>
      </motion.div>
    </motion.div>
  );
}

// Compteur qui s'incrémente à l'apparition
function SplashStat({ value, label, delay }) {
  return (
    <motion.div className="splash-stat"
      initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay }}>
      <div className="splash-stat-value">{value}</div>
      <div className="splash-stat-label">{label}</div>
    </motion.div>
  );
}
