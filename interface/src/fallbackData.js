// Instantané de repli, calqué sur les vraies données AtmoFrance.
// Utilisé automatiquement si l'API locale n'est pas joignable,
// pour que la démonstration reste fonctionnelle en toutes circonstances.

export const FALLBACK = {
  stats: {
    nb_stations: 483,
    nb_stations_geolocalisees: 410,
    nb_jours_donnees: 3,
    nb_depassements_alerte: 112,
    nb_depassements_info: 267,
    repartition_indices: [
      { qualificatif: "Bon", n: 651 },
      { qualificatif: "Moyen", n: 740 },
      { qualificatif: "Degrade", n: 48 },
      { qualificatif: "Mauvais", n: 9 },
    ],
  },
  // Échantillon représentatif de stations réelles (villes principales),
  // avec un indice attribué pour l'affichage de la carte en mode repli.
  stations: [
    { code_station: "FR04012", nom: "Paris Centre", type_station: "Urbaine", type_influence: "Fond", latitude: 48.8566, longitude: 2.3522, indice: 2, qualificatif: "Moyen", polluant: "NO2" },
    { code_station: "FR15013", nom: "Lyon Centre", type_station: "Urbaine", type_influence: "Fond", latitude: 45.7640, longitude: 4.8357, indice: 3, qualificatif: "Degrade", polluant: "O3" },
    { code_station: "FR03080", nom: "Marseille Longchamp", type_station: "Urbaine", type_influence: "Fond", latitude: 43.2965, longitude: 5.3698, indice: 3, qualificatif: "Degrade", polluant: "O3" },
    { code_station: "FR31009", nom: "Toulouse Berthelot", type_station: "Urbaine", type_influence: "Fond", latitude: 43.6047, longitude: 1.4442, indice: 2, qualificatif: "Moyen", polluant: "PM10" },
    { code_station: "FR24020", nom: "Bordeaux Talence", type_station: "Urbaine", type_influence: "Fond", latitude: 44.8378, longitude: -0.5792, indice: 1, qualificatif: "Bon", polluant: "NO2" },
    { code_station: "FR23124", nom: "Lille Fives", type_station: "Urbaine", type_influence: "Fond", latitude: 50.6292, longitude: 3.0573, indice: 2, qualificatif: "Moyen", polluant: "NO2" },
    { code_station: "FR44006", nom: "Nantes Bouteillerie", type_station: "Urbaine", type_influence: "Fond", latitude: 47.2184, longitude: -1.5536, indice: 1, qualificatif: "Bon", polluant: "PM25" },
    { code_station: "FR30030", nom: "Nice Arson", type_station: "Urbaine", type_influence: "Fond", latitude: 43.7102, longitude: 7.2620, indice: 2, qualificatif: "Moyen", polluant: "O3" },
    { code_station: "FR35012", nom: "Strasbourg Clemenceau", type_station: "Urbaine", type_influence: "Trafic", latitude: 48.5734, longitude: 7.7521, indice: 3, qualificatif: "Degrade", polluant: "NO2" },
    { code_station: "FR02004", nom: "Rennes Les Halles", type_station: "Urbaine", type_influence: "Fond", latitude: 48.1173, longitude: -1.6778, indice: 1, qualificatif: "Bon", polluant: "PM10" },
    { code_station: "FR07026", nom: "Montpellier Chaptal", type_station: "Urbaine", type_influence: "Fond", latitude: 43.6108, longitude: 3.8767, indice: 2, qualificatif: "Moyen", polluant: "O3" },
    { code_station: "FR19007", nom: "Grenoble Les Frenes", type_station: "Urbaine", type_influence: "Fond", latitude: 45.1885, longitude: 5.7245, indice: 4, qualificatif: "Mauvais", polluant: "O3" },
    { code_station: "FR12031", nom: "Dijon Centre", type_station: "Urbaine", type_influence: "Fond", latitude: 47.3220, longitude: 5.0415, indice: 2, qualificatif: "Moyen", polluant: "NO2" },
    { code_station: "FR16038", nom: "Metz Centre", type_station: "Urbaine", type_influence: "Fond", latitude: 49.1193, longitude: 6.1757, indice: 2, qualificatif: "Moyen", polluant: "PM10" },
    { code_station: "FR41007", nom: "Clermont Ferrand", type_station: "Urbaine", type_influence: "Fond", latitude: 45.7772, longitude: 3.0870, indice: 1, qualificatif: "Bon", polluant: "PM25" },
    { code_station: "FR43099", nom: "Kawéni Nord (Mayotte)", type_station: "Urbaine", type_influence: "Industrielle", latitude: -12.7736, longitude: 45.2286, indice: 4, qualificatif: "Mauvais", polluant: "PM10" },
    { code_station: "FR37040", nom: "Abymes (Guadeloupe)", type_station: "Périurbaine", type_influence: "Trafic", latitude: 16.2637, longitude: -61.4897, indice: 2, qualificatif: "Moyen", polluant: "PM10" },
    { code_station: "FR38012", nom: "Le Havre République", type_station: "Urbaine", type_influence: "Fond", latitude: 49.4944, longitude: 0.1079, indice: 1, qualificatif: "Bon", polluant: "SO2" },
    { code_station: "FR11018", nom: "Reims Jean Jaurès", type_station: "Urbaine", type_influence: "Trafic", latitude: 49.2583, longitude: 4.0317, indice: 2, qualificatif: "Moyen", polluant: "NO2" },
    { code_station: "FR29008", nom: "Angers Centre", type_station: "Urbaine", type_influence: "Fond", latitude: 47.4784, longitude: -0.5632, indice: 1, qualificatif: "Bon", polluant: "PM10" },
  ],
  indices: [],
  depassements: [
    { code_site: "FR43099", nom_site: "Kawéni Nord", code_polluant: "PM10", horodatage: "2026-07-03T20:00:00+00:00", jour: "2026-07-03", valeur: 73.8, unite: "ug/m3", depassement: "info" },
    { code_site: "FR04173", nom_site: "RD934 Coulommiers", code_polluant: "PM10", horodatage: "2026-07-03T19:00:00+00:00", jour: "2026-07-03", valeur: 52.0, unite: "ug/m3", depassement: "info" },
    { code_site: "FR19007", nom_site: "Grenoble Les Frenes", code_polluant: "O3", horodatage: "2026-07-03T16:00:00+00:00", jour: "2026-07-03", valeur: 187.0, unite: "ug/m3", depassement: "info" },
    { code_site: "FR43099", nom_site: "Kawéni Nord", code_polluant: "PM10", horodatage: "2026-07-02T20:00:00+00:00", jour: "2026-07-02", valeur: 91.2, unite: "ug/m3", depassement: "alerte" },
    { code_site: "FR03080", nom_site: "Marseille Longchamp", code_polluant: "O3", horodatage: "2026-07-02T15:00:00+00:00", jour: "2026-07-02", valeur: 194.0, unite: "ug/m3", depassement: "info" },
  ],
};
