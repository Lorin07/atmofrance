import { useState, useRef, useEffect } from "react";
import { useTranslation } from "react-i18next";
import { motion, AnimatePresence } from "framer-motion";

// Assistant qui interroge les données chargées. Détection de mots-clés multilingue.
export default function ChatBot({ data, open, onToggle }) {
  const { t } = useTranslation();
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [thinking, setThinking] = useState(false);
  const endRef = useRef(null);

  useEffect(() => {
    if (open && messages.length === 0) setMessages([{ from: "bot", text: t("chat.greeting") }]);
  }, [open]);
  useEffect(() => { endRef.current?.scrollIntoView({ behavior: "smooth" }); }, [messages, thinking]);

  function answer(question) {
    const q = question.toLowerCase();
    const stations = data.stations || [];
    const deps = data.depassements || [];
    const stats = data.stats || {};
    const withIndex = stations.filter((s) => s.indice != null);

    // Détecteurs multilingues (mots-clés dans plusieurs langues)
    const has = (...words) => words.some((w) => q.includes(w));

    // 1. Nombre de stations
    if (has("combien", "how many", "cuánt", "wie viele", "quant", "mélòó", "多少", "何") && has("station", "esta", "地点", "站", "ibùdó")) {
      return `${stats.nb_stations || stations.length} stations sont suivies, dont ${stats.nb_stations_geolocalisees || "—"} géolocalisées sur la carte.`;
    }
    // 2. Alertes / dépassements
    if (has("alerte", "alert", "警報", "警报", "alarm", "ìkìlọ̀", "excede", "dépass", "超過", "超标", "überschr")) {
      const alertes = deps.filter((d) => d.depassement === "alerte");
      const top = deps.slice(0, 3).map((d) => `${d.nom_site} (${d.code_polluant} ${d.valeur} ${d.unite})`).join(", ");
      return `${stats.nb_depassements_alerte ?? alertes.length} dépassements d'alerte et ${stats.nb_depassements_info ?? "—"} d'information ont été détectés. Exemples récents : ${top || "aucun"}.`;
    }
    // 3. Station la plus polluée
    if (has("plus pollu", "most pollut", "汚染", "污染", "contamin", "bàjẹ́", "schlecht", "belast", "pire", "worst")) {
      const worst = [...withIndex].sort((a, b) => b.indice - a.indice)[0];
      if (worst) return `La station la plus exposée est ${worst.nom}, avec un indice de ${worst.indice} sur 6 (${worst.qualificatif}). Le polluant responsable est ${worst.polluant || "non précisé"}.`;
      return "Je n'ai pas d'indice disponible pour le moment.";
    }
    // 4. Meilleure qualité / station la moins polluée
    if (has("meilleur", "best", "moins pollu", "cleanest", "最も良い", "最好", "mejor", "beste", "melhor")) {
      const best = [...withIndex].sort((a, b) => a.indice - b.indice)[0];
      if (best) return `La station avec la meilleure qualité de l'air est ${best.nom}, avec un indice de ${best.indice} (${best.qualificatif}).`;
    }
    // 5. Polluant dominant
    if (has("polluant", "pollutant", "汚染物質", "污染物", "contaminante", "schadstoff", "poluente")) {
      const byPol = {};
      withIndex.forEach((s) => { if (s.polluant) byPol[s.polluant] = (byPol[s.polluant] || 0) + 1; });
      const top = Object.entries(byPol).sort((a, b) => b[1] - a[1])[0];
      if (top) return `Le polluant le plus souvent responsable de l'indice est ${top[0]}, présent dans ${top[1]} stations. Viennent ensuite les particules fines et l'ozone.`;
    }
    // 6. Qualité générale / aujourd'hui
    if (has("qualité", "quality", "質", "质量", "calidad", "qualidade", "ìmọ́tótó", "luftqual", "aujourd", "today", "hoy", "heute", "lónìí", "今日", "今天", "état", "situation")) {
      const rep = stats.repartition_indices || [];
      const parts = rep.map((r) => `${r.qualificatif} : ${r.n}`).join(", ");
      const bon = rep.find((r) => r.qualificatif === "Bon")?.n || 0;
      const total = rep.reduce((a, r) => a + r.n, 0) || 1;
      const pct = Math.round((bon / total) * 100);
      return `Répartition actuelle : ${parts}. Environ ${pct}% des relevés sont de bonne qualité. La situation est globalement favorable, avec quelques pics localisés d'ozone et de particules.`;
    }
    // 7. Salutations
    if (has("bonjour", "salut", "hello", "hi ", "hola", "こんにち", "你好", "olá", "ẹ nlẹ", "hallo", "merci", "thanks", "gracias")) {
      return t("chat.greeting");
    }
    // 8. Aide / que peux-tu faire
    if (has("aide", "help", "que peux", "what can", "ayuda", "hilfe", "何ができ", "能做什么", "ajuda")) {
      return "Je peux vous renseigner sur : le nombre de stations, la qualité de l'air globale, les alertes et dépassements, la station la plus (ou la moins) exposée, le polluant dominant, ou la situation d'une ville précise. Essayez par exemple : « qualité de l'air à Lyon ».";
    }
    // 9. Recherche par ville (nom de station)
    const found = stations.find((s) => {
      if (!s.nom) return false;
      const firstWord = s.nom.toLowerCase().split(" ")[0];
      return firstWord.length > 3 && q.includes(firstWord);
    });
    if (found) {
      return `À ${found.nom}, l'indice de qualité de l'air est de ${found.indice ?? "—"} sur 6 (${found.qualificatif ?? "non mesuré"}). Polluant principal : ${found.polluant || "non précisé"}. Type de station : ${found.type_station || "—"}.`;
    }
    // Réponse par défaut
    return "Je n'ai pas bien saisi votre question. Je peux vous parler de la qualité de l'air, du nombre de stations, des alertes, ou d'une ville précise. Utilisez les suggestions ci-dessous ou reformulez !";
  }

  function send(text) {
    const question = (text ?? input).trim();
    if (!question) return;
    setMessages((m) => [...m, { from: "user", text: question }]);
    setInput("");
    setThinking(true);
    setTimeout(() => {
      setMessages((m) => [...m, { from: "bot", text: answer(question) }]);
      setThinking(false);
    }, 500 + Math.random() * 400);
  }

  const quickQuestions = [t("chat.quick1"), t("chat.quick2"), t("chat.quick3"), t("chat.quick4")];

  return (
    <>
      <motion.button className="chat-fab" onClick={onToggle} aria-label={t("chat.title")}
        whileHover={{ scale: 1.08 }} whileTap={{ scale: 0.95 }}>
        {open ? "✕" : "💬"}
      </motion.button>

      <AnimatePresence>
        {open && (
          <motion.div className="chat-panel"
            initial={{ opacity: 0, y: 20, scale: 0.96 }} animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 20, scale: 0.96 }} transition={{ type: "spring", stiffness: 300, damping: 28 }}>
            <div className="chat-header">
              <span className="chat-header-dot" />
              {t("chat.title")}
            </div>
            <div className="chat-messages">
              {messages.map((m, i) => (
                <motion.div key={i} className={`chat-msg chat-msg-${m.from}`}
                  initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}>
                  {m.text}
                </motion.div>
              ))}
              {thinking && (
                <motion.div className="chat-msg chat-msg-bot chat-thinking" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
                  <span className="typing-dot" /><span className="typing-dot" /><span className="typing-dot" />
                </motion.div>
              )}
              <div ref={endRef} />
            </div>
            <div className="chat-quick">
              {quickQuestions.map((qq, i) => (
                <button key={i} className="chat-quick-btn" onClick={() => send(qq)}>{qq}</button>
              ))}
            </div>
            <div className="chat-input-row">
              <input className="chat-input" value={input} onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && send()} placeholder={t("chat.placeholder")} />
              <button className="chat-send" onClick={() => send()}>{t("chat.send")}</button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
