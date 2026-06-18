# Registre des traitements & conformité RGPD — CesiZEN

## 1. Contexte & responsabilités

- **Responsable de traitement** : le Ministère (commanditaire) — *à confirmer*.
- **Sous-traitant** (art. 28) : le prestataire qui héberge et opère la solution (un contrat / DPA encadre la relation).
- **DPO / point de contact** : *à désigner* — adresse dédiée pour l'exercice des droits.
- 🛡️ **Minimisation des données** : Suite au choix architectural d'intégrer un **module de respiration** à la place d'un suivi d'humeur, l'application ne collecte **aucune donnée sensible** ou relative à la santé mentale. Elle échappe ainsi aux contraintes lourdes des catégories particulières (**art. 9 RGPD**). Les profils se limitent au strict nécessaire fonctionnel.

## 2. Registre des activités de traitement (art. 30)

| # | Traitement | Finalité | Base légale | Catégories de données | Destinataires | Conservation |
|---|---|---|---|---|---|---|
| T1 | **Comptes utilisateurs** | Création/gestion du compte, authentification | Exécution du contrat (CGU) | Email, pseudo, mot de passe **haché Argon2**, rôle | Prestataire (hébergeur) | Durée d'utilisation + 24 mois d'inactivité puis suppression définitive |
| T2 | **Module Respiration** | Suivi personnel des séances et de l'historique | Exécution du contrat (CGU) | Type d'exercice, durée de la session, horodatage | Utilisateur lui-même uniquement | Données détruites à la suppression du compte ||
| T3 | **Suivi de lecture d'articles** | Attribution d'XP, éviter la duplication des gains | Intérêt légitime | Association utilisateur ↔ article lu, date de lecture | Prestataire | Liées au compte (idem T1) |
| T4 | **Sécurité & journalisation** | Anti brute-force, rate-limiting, détection d'intidents | Intérêt légitime (sécurité) | Tentatives de connexion échouées, blocage temporaire, **adresse IP** (logs), refresh tokens hachés | Prestataire | Logs : **6 mois** ; refresh tokens : **7 jours** |
| T5 | **Sauvegardes** | Continuité d'activité / restauration en cas de crash | Intérêt légitime | Copie compressée (`pg_dump`/gzip) de la base, sur volume hébergé en UE | Prestataire | **14 jours** glissants (rotation automatique) |

## 3. Durées de conservation (synthèse)

| Donnée | Durée | Référence |
|---|---|---|
| Compte actif | Durée d'utilisation nominale | T1 |
| Compte inactif | Suppression définitive après **24 mois** sans interaction (alerte par email en amont) | T1 |
| Historique de respiration | Tant que le compte existe (effacé en même temps) | T2 |
| Logs de sécurité (dont IP) | **6 mois** (alignement sur les recommandations CNIL) | T5 |
| Refresh tokens | **7 jours** | T5 |
| Sauvegardes (Backups) | **14 jours** | T6 |

## 4. Droits des personnes (art. 15-22) & exercice

| Droit | Mise en œuvre dans CesiZEN | Statut |
|---|---|---|
| Accès / Portabilité | Export complet des données de profil et d'exercices en **JSON** | ✅ implémenté |
| Effacement (« droit à l'oubli ») | Suppression autonome du compte entraînant une **suppression en cascade** en base | ✅ implémenté |
| Rectification | Mise à jour des informations du profil (pseudo, email) via | ✅ implémenté |
| Consentement | Validation explicite des **CGU obligatoire** lors de la phase d'inscription | ✅ implémenté |
| Opposition / retrait | La suppression de l'espace personnel vaut retrait immédiat du consentement | ✅ implémenté |

**Exercice** : Accessible directement en autonomie via l'interface utilisateur ou sur demande écrite au DPO ; traitement sous **1 mois** maximum (art. 12).

## 5. Respect de la minimisation — Absence de données de santé

- **Zéro donnée médicale** : Le module de respiration quantifie uniquement l'usage de l'outil (temps passé, exercices complétés) sans jamais demander ou déduire l'état psychologique ou physique de l'usager.
- **Cloisonnement applicatif** : L'accès aux statistiques de l'historique de respiration fait l'objet d'un contrôle strict de propriété au niveau de l'API (un utilisateur ne peut requêter que ses propres identifiants).
- **Finalité exclusive** : Aucune donnée d'usage n'est partagée, externalisée ou exploitée à des fins de profilage publicitaire.

## 6. Hébergement, sous-traitants & transferts

- **Souveraineté européenne** : Infrastructure intégralement provisionnée au sein de l'Union Européenne → **aucun transfert de données hors UE** (art. 44 et suivants).
- Sous-traitants : **Microsoft Azure** (fournisseur Cloud, encadré par un DPA) ; **GitHub/GHCR** (stockage du code source et du registre d'images Docker anonymes).
- **Let's Encrypt** : Automatisation des certificats SSL (aucune métrique utilisateur transmise).

## 7. Sécurité des données (renvoi)

L'ensemble des protections techniques est détaillé dans le [plan de sécurisation](03-plan-securisation.md) : hachage irréversible des mots de passe via **Argon2**, isolation réseau des conteneurs, **flux chiffrés HTTPS via Traefik (TLS 1.3)**, étanchéité absolue des secrets d'infrastructure injectés au déploiement, et purges régulières des images résiduelles.

## 8. Violation de données

En cas d'anomalie ou d'intrusion détectée sur la base PostgreSQL, la procédure définie dans le [plan de sécurisation §3](03-plan-securisation.md#3-gestion-de-crise-incident-de-sécurité) est immédiatement enclenchée : isolation des environnements, qualification de l'impact, **notification officielle à la CNIL sous 72 h** (art. 33) et avertissement direct des utilisateurs si un risque pour la confidentialité de leurs identifiants est avéré (art. 34).

---
**À compléter (décisions métier) :** Identité définitive du responsable de traitement ministériel, mise en ligne de la politique de confidentialité textuelle, validation juridique des délais de purge des comptes inactifs.