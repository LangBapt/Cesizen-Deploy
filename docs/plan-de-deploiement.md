# Plan de déploiement — CesiZEN

## 1. Contexte & contraintes

Projet porté (en simulation) par le Ministère de la Santé : application grand public avec une **forte exigence de disponibilité et de sécurité**. Conformément au principe de **Minimisation des données (Privacy by Design)**, le projet a écarté la collecte de données de santé au profit d'un module de respiration, limitant les données stockées au strict minimum (pseudo, email). 

L'infrastructure impose un chiffrement **HTTPS systématique**, un hébergement localisé en Europe (Suisse) et un budget maîtrisé. La solution retenue est entièrement **conteneurisée (Docker)** et **hautement automatisée (GitOps via GitHub Actions)** pour réduire les coûts d'exploitation et éliminer les interventions manuelles sur le serveur.

## 2. Architecture cible

- **VM Azure (Hôte unique)** : Située dans la région **Switzerland North**, elle centralise l'ensemble de la topologie. Les environnements de Staging (recette) et de Production y sont co-hébergés mais isolés de manière étanche par des réseaux Docker internes distincts.
- **Traefik v3 (Reverse-Proxy / Frontal)** : Gère la terminaison TLS avec génération automatique de certificats valides via **Let's Encrypt**. Il orchestre le routage du trafic entrant vers les bons conteneurs en se basant sur les préfixes de chemins (ex: `/api` pour la prod, `/staging-api` pour le staging). Il applique également une redirection automatique du HTTP vers le HTTPS.
- **Registre GHCR (GitHub Packages)** : Utilisé comme registre d'images privé. Les images Docker de l'API et du Backoffice y sont poussées à la fin de la CI applicative.
- **Runner GitHub Actions Auto-Hébergé (Self-hosted)** : Installé directement sur la VM Azure, il écoute les ordres de déploiement et exécute les commandes au plus près du démon Docker de l'hôte, évitant d'exposer inutilement des accès SSH ou des clés API de déploiement vers l'extérieur.

## 3. Les trois environnements

| Environnement | Rôle | Hébergement | Déclenchement | Gestion des données |
|---|---|---|---|---|
| **Développement** | Codage, tests unitaires et intégration locale. | Postes locaux des développeurs (Docker Compose). | Manuel (`docker compose up`) | Base locale éphémère alimentée par un script de Seed Prisma. |
| **Staging** | Recette, validation des fonctionnalités et tests d'infrastructure. | VM Azure (`Switzerland North`), branche `develop`. | Automatisé via un signal `repository_dispatch` ou déclenchement manuel. | Base PostgreSQL isolée contenant un jeu de fausses données réalistes. |
| **Production** | Service final rendu aux utilisateurs finaux. | VM Azure (`Switzerland North`), branche `main`. | Automatisé via un signal `repository_dispatch` ou déclenchement manuel. | Base PostgreSQL persistante contenant les vrais comptes utilisateurs. |

## 4. Ressources et dimensionnement

### 4.1 Infrastructure globale
- **Hébergement informatique** : VM Azure sous Ubuntu 22.04 / 24.04 LTS.
- **Adresse IP publique statique** : `74.161.40.57`
- **Nom de domaine (FQDN)** : `cesizen-baptiste.switzerlandnorth.cloudapp.azure.com`
- **SKU Azure sélectionné** : **Standard B2s** (2 vCPU, 4 Go de RAM). Ce dimensionnement est optimal pour mutualiser la Prod, la Staging, Traefik, Uptime Kuma et le Runner GitHub sans surcoût.

### 4.2 Topologie des conteneurs (Allocation indicative)

| Conteneur | Image source | CPU (Max) | RAM (Moyenne) | Persistance / Volumes |
|---|---|---|---|---|
| **traefik** | `traefik:v3` | 0.2 vCPU | 128 Mo | Volume local `letsencrypt` (certificats) |
| **uptime-kuma** | `louislam/uptime-kuma:1` | 0.1 vCPU | 128 Mo | Volume local `uptime-kuma-data` (config) |
| **api-prod** | `ghcr.io/langbapt/cesizen-api:prod` | 0.3 vCPU | 300 Mo | Éphémère |
| **postgres-prod** | `postgres:16-alpine` | 0.3 vCPU | 256 Mo | Volume local `postgres_data_prod` |
| **backoffice-prod** | `ghcr.io/langbapt/cesizen-backoffice:prod` | 0.1 vCPU | 64 Mo | Éphémère (Nginx statique) |
| **api-staging** | `ghcr.io/langbapt/cesizen-api:staging` | 0.3 vCPU | 300 Mo | Éphémère |
| **postgres-staging** | `postgres:16-alpine` | 0.3 vCPU | 256 Mo | Volume local `postgres_data_staging` |
| **backoffice-staging** | `ghcr.io/langbapt/cesizen-backoffice:staging` | 0.1 vCPU | 64 Mo | Éphémère (Nginx statique) |

> **Stratégie de scalabilité (Montée en charge)** : Si l'application connaît une forte hausse d'affluence, la trajectoire DevOps prévoit en phase 1 l'augmentation verticale de la VM (Série B-ms supérieure). En phase 2, une séparation horizontale sera opérée en déportant la Production sur sa propre VM dédiée et en externalisant les bases de données vers un service managé comme *Azure Database for PostgreSQL*.

## 5. Processus de déploiement

### 5.1 Initialisation de l'hôte (Exécuté une seule fois)
1. Provisionnement de la VM Azure et configuration du groupe de sécurité réseau (NSG) : ouverture stricte des ports `80` (HTTP), `443` (HTTPS) et `22` (SSH, restreint par IP).
2. Installation du moteur Docker et du plugin Docker Compose.
3. Déploiement initial de **Traefik** et d'**Uptime Kuma** via le fichier `docker-compose.monitoring.yml`.
4. Installation et enregistrement du Runner GitHub Actions en tant que service d'arrière-plan avec les labels `self-hosted, cesizen`.

### 5.2 Pipeline de Déploiement Continu (CD)
À chaque événement de déploiement (automatique ou manuel via `workflow_dispatch`), le fichier de workflow `deploy.yml` orchestre les étapes suivantes :

1. **Sécurité amont (Le "Videur")** : Lancement immédiat d'un scan **Gitleaks** sur les serveurs de GitHub (`runs-on: ubuntu-latest`). Si un secret (mot de passe, clé) est détecté dans le commit, la pipeline est immédiatement avortée, bloquant le déploiement sur la VM.
2. **Prise de relais par la VM** : Si Gitleaks est au vert, le job `deploy` s'active sur le runner `self-hosted`.
3. **Gestion dynamique des secrets** : Récupération des secrets d'environnement cryptés de GitHub (`SECRETS.ENV_PROD` ou `ENV_STAGING`) pour écrire temporairement un fichier `.env.[environnement]` local sécurisé dans le dossier de configuration.
4. **Mise à jour des conteneurs** : Connexion sécurisée à GHCR, téléchargement des nouvelles versions d'images (`docker compose pull`) et redémarrage à chaud des conteneurs impactés (`docker compose up -d`).
5. **Migrations de la base de données** : Exécution automatique des schémas de base de données à l'aide de la commande `docker exec [api-container] npx prisma migrate deploy`.
6. **Health Check renforcé** : Lancement d'une vérification de l'endpoint `/health`. La validation s'appuie sur une correspondance de mot-clé applicatif pour éviter les faux positifs induits par la redirection automatique des architectures Single Page Application (SPA).
7. **Nettoyage et Notification** : Suppression définitive et immédiate des fichiers `.env` temporaires sur l'hôte (garantie par un bloc `if: always()`). Suppression des anciennes images Docker obsolètes (`docker image prune -f`). Envoi d'un rapport détaillé de succès ou d'échec sur le canal **Discord** via Webhook.

### 5.3 Stratégie de Rollback
En cas d'anomalie critique ou de défaillance non détectée par le Health Check :
- **Applicatif** : Possibilité de relancer manuellement le workflow de déploiement depuis l'interface GitHub Actions en spécifiant le tag d'une image stable antérieure (identifiée par son SHA de commit).
- **Données** : Restauration de l'état précédent de la base de données via l'application des snapshots de sauvegarde générés à intervalle régulier.

## 6. Intégration continue & automatisation de bout en bout

Pour garantir la stabilité de la production, aucune image n'est construite ou déployée sans valider les verrous de la CI situés sur les dépôts applicatifs (`cesizen-api` et `cesizen-backoffice`) :
* **Tests automatisés** : Exécution complète de la suite de tests (Vitest sur l'API) à chaque Pull Request.
* **Qualité du code** : Passage des outils de Lint et de validation des builds de production du Front-end.
* **Scan de vulnérabilités** : Analyse des dépendances npm pour bloquer l'intégration de paquets compromis.

## 7. Outils de versioning et stratégie Git

Le projet applique une philosophie **GitOps** stricte où le dépôt `cesizen-deploy` centralise l'état recherché de l'infrastructure :
* **Branches** : `main` pointe vers l'état de la Production, `develop` modélise l'environnement de Staging. Les développements isolés s'effectuent sur des branches de fonctionnalités `feature/*`.
* **Traçabilité** : Chaque conteneur déployé est tagué avec le SHA unique du commit GitHub ayant provoqué sa création, offrant une traçabilité totale entre le code source et le binaire en exécution.

## 8. Pilotage et Supervision (Monitoring)

La visibilité sur l'état de santé de l'infrastructure est assurée à deux niveaux :
* **Technique (Routage)** : Accès au tableau de bord natif de **Traefik** pour contrôler l'état des routeurs HTTP/HTTPS, la validité des certificats TLS Let's Encrypt et la bonne communication avec les sockets Docker.
* **Fonctionnel (Disponibilité)** : Surveillance active par **Uptime Kuma** (hébergé sur le port `3001`, accessible de manière sécurisée via un tunnel SSH local). L'outil interroge les endpoints de santé toutes les 60 secondes et s'appuie sur une validation de contenu (*Keyword Matching*). Toute dérive de routage ou indisponibilité d'un conteneur API déclenche une alerte instantanée sur le serveur **Discord** de l'équipe technique.