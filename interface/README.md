# AtmoFrance — Interface de surveillance

Interface React de démonstration pour la plateforme AtmoFrance (qualité de l'air).

## Fonctionnalités

- **Carte interactive** : stations colorées selon l'indice ATMO, panneau de détail au clic
- **5 vues** : Carte, Tableau de bord, Classements, Alertes, À propos
- **8 langues** : français, anglais, espagnol, allemand, japonais, chinois, portugais, yoruba
- **Thème clair / sombre** (change aussi le fond de carte)
- **Assistant conversationnel** : questions rapides + saisie libre
- **Données en direct** depuis l'API locale, avec repli automatique si indisponible

## Démarrage

### Prérequis
- Node.js 18 ou supérieur
- L'API AtmoFrance qui tourne sur http://localhost:8000 (pour les données en direct)

### Installation et lancement

```bash
# 1. Installer les dépendances (une seule fois)
npm install

# 2. Lancer en mode développement
npm run dev
```

L'interface s'ouvre sur http://localhost:5173

### Pour la démonstration (recommandé)

Assurez-vous que votre API tourne AVANT de lancer l'interface :

```bash
# Dans le dossier du projet AtmoFrance :
cd /home/pourtoi/taf/bahut/atmofrance
.venv/bin/python -m uvicorn api.main:app --port 8000 &

# Puis dans ce dossier d'interface :
npm run dev
```

Si l'API est joignable, l'indicateur en haut à droite affiche « Données en direct » (point vert).
Si l'API est absente, l'interface bascule automatiquement en « Mode hors ligne » avec des données de démonstration : la présentation ne plante jamais.

### Construire la version de production

```bash
npm run build      # génère le dossier dist/
npm run preview    # prévisualise la version de production
```

## Configuration

- L'adresse de l'API se règle dans `src/dataService.js` (constante `API_BASE`)
- Le jour affiché se règle dans `src/dataService.js` (constante `JOUR_DEFAUT`)

## Structure

```
src/
  App.jsx              Application principale (en-tête, navigation, vues)
  i18n.js              Traductions des 8 langues
  dataService.js       Accès aux données + repli automatique
  fallbackData.js      Données de repli (mode hors ligne)
  components/
    MapView.jsx        Carte interactive
    StationDetail.jsx  Panneau de détail d'une station
    Views.jsx          Tableau de bord, classements, alertes, à propos
    ChatBot.jsx        Assistant conversationnel
```
