# Projet de fin de semaine — Plateforme Data Lakehouse autour des données Vélib

Ce dépôt contient la réalisation du projet Data Lakehouse basé sur les données de disponibilité des stations Vélib en temps réel.

## 1. Contexte métier

**Besoin traité** : L'optimisation du rééquilibrage de la flotte de vélos (mécaniques et électriques) en temps réel. Les opérateurs ou les mairies d'arrondissement ont besoin de savoir quelles stations sont en situation de "famine" (zéro vélo disponible) ou de "saturation" (zéro place libre pour se garer).
**Intérêt des données** : Les données de l'API OpenData Paris offrent une vue de la capacité totale, du nombre de vélos disponibles par type (électrique/mécanique), et du nombre de bornettes libres par station.
**Valeur apportée** : La solution met en place un pipeline automatisé qui ingère les données, les stocke, les consolide dans une base analytique, permet un suivi via dashboard, et envoie des alertes sur Telegram lorsque le seuil critique d'une station est atteint (complètement vide ou pleine).

## 2. Architecture Globale

- **Ingestion & Workflow** : `n8n` orchestre l'appel à l'API Vélib, la transformation des JSON, l'écriture sur le MinIO, l'insertion en base PostgreSQL, et l'envoi de messages Telegram.
- **Stockage Objets (Data Lake)** : `MinIO` sert de Data Lake avec trois zones (buckets).
- **Base de données Relationnelle & Data Warehouse** : `PostgreSQL` structure les données à travers des schémas (`staging`, `curated`, `analytics`).
- **Data Visualisation** : `Metabase` lit la couche `analytics` de PostgreSQL pour afficher un tableau de bord.
- **Webhook & ChatBot** : Intégration Telegram (via n8n) avec tunnel HTTPS (ngrok) pour les commandes interactives.

## 3. Organisation MinIO

- `raw` : Stockage du JSON brut tel que renvoyé par l'API (historisation brute).
- `staging` : Données aplaties/filtrées prêtes à l'intégration.
- `curated` : Archives structurées (parquet ou json final) représentant la vérité historique si besoin (en redondance avec PostgreSQL).

## 4. Structure SQL (PostgreSQL)

La base `velib_db` possède 4 schémas (voir `init.sql`) :
- `raw` : Schéma de sécurité (optionnel, principalement géré par MinIO).
- `staging` : Table `velib_stations` pour le landing des données (nettoyage intermédiaire).
- `curated` : 
  - `dim_station` (Dimension des stations, SCD Type 1/2) 
  - `fact_station_status` (Table de faits historisant les statuts des stations toutes les X minutes).
- `analytics` : Vues SQL orientées métier.

## 5. Couche Analytique (KPIs)

- **Disponibilité globale** : Nombre total de vélos disponibles, mécaniques, et électriques.
- **Stations Critiques** : Liste des stations actuellement vides et des stations pleines pour intervention immédiate.
- **Taux de remplissage moyen par arrondissement** : Identifier les zones les plus denses.

## 6. Dashboard (Metabase)

Un dashboard connecté à PostgreSQL met en évidence :
- Des compteurs (Total vélos dispos, vélos électriques).
- Un tableau/carte géographique des "Stations Critiques".
- Un graphique en barres du "Taux de remplissage par arrondissement".

## 7. Automatisation & Pipeline (n8n)

**Workflow Principal (Cron - Toutes les 15 min)** :
1. Fetch API OpenData de Paris.
2. Écrire le payload JSON dans le bucket MinIO `raw`.
3. Transformer/split les données (Item Lists).
4. Insérer dans PostgreSQL (`curated.fact_station_status` et Upsert sur `curated.dim_station`).
5. Vérifier une condition : Y a-t-il une station "Critique" importante ? (ex: Arrondissement de test).
6. Si oui, envoyer une Alerte Telegram.

## 8. Intégration Telegram

Le bot Telegram (lié via ngrok à un webhook n8n) propose de recevoir :
- **Alertes automatiques** : Déclenchées par le Workflow Principal si des stations atteignent un niveau d'alerte.
- **Commandes manuelles** : Un webhook n8n écoute les messages `/kpi` ou `/kpi [Arrondissement]` et requête PostgreSQL pour répondre avec le nombre de vélos disponibles sur la zone demandée.

---

### Commandes pour lancer l'infrastructure :

```bash
docker-compose up -d
```
Les services exposés :
- MinIO: UI sur `http://localhost:9001`
- n8n: UI sur `http://localhost:5678`
- Metabase: UI sur `http://localhost:3000`
- PostgreSQL: `localhost:5432`
