# Guide d'installation — Infrastructure & VM CesiZEN

Procédure pas-à-pas pour initialiser et configurer l'environnement d'hébergement complet sur l'hôte Cloud cible.

## 1. Prérequis

- **Machine Virtuelle Azure** : SKU *Standard B2s* sous Ubuntu LTS, localisée dans la région **Switzerland North**.
- **Adresse IP publique statique** : `74.161.40.57`
- **Nom de domaine (FQDN Azure)** : `cesizen-baptiste.switzerlandnorth.cloudapp.azure.com`
- **Accès SSH** : Clé privée d'administration configurée.
- **Compte GitHub** : Organisation ou compte utilisateur `langbapt` contenant les dépôts du projet.

---

## 2. Préparation du système hôte (VM)

Connecte-toi à la VM en SSH et exécute les commandes suivantes pour mettre à jour le système et installer le moteur d'exécution :

```bash
# 2.1 Mise à jour des paquets système
sudo apt update && sudo apt upgrade -y

# 2.2 Installation de Docker via le script officiel
curl -fsSL [https://get.docker.com](https://get.docker.com) | sh
sudo usermod -aG docker "$USER" # Déconnecte-toi et reconnecte-toi pour appliquer

# 2.3 Sécurisation réseau locale via le pare-feu UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

> 💡 **Sécurité des outils de monitoring** : Le port `3001` d'Uptime Kuma n'est volontairement pas ouvert sur l'extérieur. L'accès à son interface se fait de manière sécurisée en passant par le reverse-proxy Traefik ou via un tunnel SSH local :  
> `ssh -L 3001:localhost:3001 user@74.161.40.57`

### Compatibilité de l'API Docker Engine (Traefik v3)
Pour éviter l'erreur de socket `client version 1.24 is too old` avec les versions récentes de Docker, force la version minimale de l'API via un drop-in systemd :

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/min-api.conf >/dev/null <<'EOF'
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF
sudo systemctl daemon-reload && sudo systemctl restart docker
```

---

## 3. Configuration DNS & Réseau

Le projet utilise le nom de domaine DNS fourni nativement par l'infrastructure Azure. 

1. Dans le portail Azure, configure l'étiquette de nom DNS (*DNS name label*) de l'adresse IP publique sur `cesizen-baptiste`.
2. Vérifie la bonne résolution depuis ton poste local :
```bash
dig +short cesizen-baptiste.switzerlandnorth.cloudapp.azure.com
# Doit renvoyer impérativement : 74.161.40.57
```

---

## 4. Initialisation des répertoires de déploiement

Crée l'arborescence standardisée sur la VM et récupère le dépôt d'infrastructure :

```bash
sudo mkdir -p /opt/cesizen && sudo chown "$USER" /opt/cesizen
cd /opt/cesizen
git clone [https://github.com/langbapt/cesizen-deploy.git](https://github.com/langbapt/cesizen-deploy.git) .
```

---

## 5. Lancement de la brique de supervision et routage (Traefik + Uptime Kuma)

1. Crée le réseau virtuel externe Docker qui servira de pont entre Traefik et les applications :
```bash
docker network create web
```

2. Prépare et configure les variables d'environnement de la stack de supervision :
```bash
cp traefik/.env.example traefik/.env
# Édite le fichier pour y inscrire ton adresse e-mail (Let's Encrypt)
```

3. Génère la chaîne d'authentification forte (Basic Auth) pour sécuriser l'accès au tableau de bord Traefik :
```bash
sudo apt install -y apache2-utils
htpasswd -nbB admin 'TonMotDePasseTresSecurise' | sed -e 's/\$/\$\$/g'
# Copie la chaîne générée et colle-la dans la variable TRAEFIK_DASHBOARD_AUTH du fichier traefik/.env
```

4. Déploie les conteneurs de l'infrastructure persistante :
```bash
docker compose -f docker-compose.monitoring.yml up -d
docker compose -f docker-compose.monitoring.yml logs -f traefik
```

---

## 6. Installation du Runner GitHub Actions (Self-hosted)

Pour permettre le déploiement GitOps automatisé sans ouvrir de port SSH sur le monde, installe le runner applicatif local :

1. Sur GitHub, accède à ton dépôt `cesizen-deploy` -> *Settings* -> *Actions* -> *Runners* -> *New self-hosted runner*.
2. Exécute la séquence d'installation générée sur la VM dans le dossier dédié :

```bash
mkdir -p /opt/actions-runner && cd /opt/actions-runner
# Télécharge et extrait le binaire selon les instructions fournies par l'interface GitHub
./config.sh --url [https://github.com/langbapt/cesizen-deploy](https://github.com/langbapt/cesizen-deploy) --token <TON_TOKEN_GITHUB> --labels cesizen
sudo ./svc.sh install && sudo ./svc.sh start
```

---

## 7. Configuration des Secrets GitHub

Afin d'alimenter les pipelines de déploiement continu (CD), configure les secrets d'action dans tes dépôts GitHub (*Settings* -> *Secrets and variables* -> *Actions*).

### Dans le dépôt `cesizen-deploy` :
- `GHCR_USER` : `langbapt`
- `GHCR_TOKEN` : Ton *Personal Access Token (PAT)* GitHub doté du droit `read:packages`.
- `ENV_STAGING` : Contenu complet des variables d'environnement pour la recette.
- `ENV_PROD` : Contenu complet des variables d'environnement pour la production.
- `DISCORD_WEBHOOK_URL` : L'URL du salon Discord pour recevoir les rapports de déploiement et alertes de sécurité.

---

## 8. Premier déploiement et validation du routage

Déclenche le workflow de déploiement depuis l'onglet *Actions* de ton dépôt via `workflow_dispatch` ou en effectuant un push sur les branches cibles (`develop` pour le Staging, `main` pour la Production).

Vérifie l'accessibilité des environnements selon la stratégie de routage par préfixes de chemins configurée dans Traefik :

| Environnement | URL du Front-end (Backoffice/App) | URL de l'API (Health Check) |
|---|---|---|
| **Production** | `https://cesizen-baptiste.switzerlandnorth.cloudapp.azure.com/` | `https://cesizen-baptiste.switzerlandnorth.cloudapp.azure.com/api/health` |
| **Staging** | `https://cesizen-baptiste.switzerlandnorth.cloudapp.azure.com/staging` | `https://cesizen-baptiste.switzerlandnorth.cloudapp.azure.com/staging-api/health` |

---

## 9. Initialisation et population des bases de données (Seed)

Le processus de CD applique automatiquement les schémas structurels via Prisma (`migrate deploy`), mais n'injecte pas les jeux de données de démonstration. Pour peupler les tables fonctionnelles (**badges, articles informationnels et exercices de respiration** uniquement), exécute le script pré-compilé dans le conteneur applicatif :

```bash
# Définir l'environnement ciblé : 'prod' ou 'staging'
ENV=prod

# Récupération automatique de l'ID du conteneur API actif
API_CT=$(docker ps --filter "label=com.docker.compose.project=cesizen-${ENV}" \
                   --filter "label=com.docker.compose.service=api" -q)

# Exécution du script de peuplement
docker exec "$API_CT" node dist-seed/prisma/seed.js
```

> ⚠️ **Sécurité & Idempotence** : Le script utilise des requêtes de type `upsert`. Il peut être rejoué en toute sécurité sans risque de duplication ou de corruption des exercices de respiration ou des structures de gamification.

Les comptes d'accès par défaut générés lors du seed sont :
- **Profil Admin** : `admin@cesizen.fr` / `Admin1234!`
- **Profil Utilisateur** : `user@cesizen.fr` / `User1234!`

---

## 10. Automatisation des sauvegardes (Cron)

Planifie l'exécution automatique du script de sauvegarde de la base de données PostgreSQL de Production pour assurer la résilience des données :

```bash
# Injecte une tâche cron planifiée tous les jours à 03h00 du matin
( crontab -l 2>/dev/null; echo "0 3 * * * /opt/cesizen/scripts/backup-db.sh prod" ) | crontab -
```

---

## 11. Procédures de dépannage rapide (Runbook)

| Symptôme observé | Cause probable | Action corrective |
| :--- | :--- | :--- |
| **Erreur `502 Bad Gateway`** | Le conteneur API ciblé est arrêté ou en boucle de crash. | Analyser les logs de l'application via `docker compose -p cesizen-prod logs -f api`. |
| **Certificat SSL non émis** | Blocage par les quotas Let's Encrypt ou port `80` fermé localement. | Vérifier les règles `ufw status` et inspecter les logs de Traefik. |
| **Échec des migrations Prisma** | La chaîne de connexion `DATABASE_URL` est incorrecte ou inaccessible. | Valider les variables d'environnement injectées dans le fichier `.env` de l'environnement correspondant. |
| **Le déploiement CI/CD n'aboutit pas** | Le scan **Gitleaks** a détecté un secret ou une clé en clair dans le dernier commit. | Nettoyer l'historique Git, révoquer le secret exposé et ré-initier la pipeline. |
````</TON_TOKEN_GITHUB>