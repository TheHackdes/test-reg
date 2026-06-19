# rocky8-kasmvnc — Image KasmVNC + LDAP

Image Rocky Linux 8 + KasmVNC + XFCE pour Kasm Workspaces, avec authentification
LDAP (SSSD). Quand un utilisateur se connecte au portail Kasm avec son compte
LDAP, le bureau s'ouvre **en tant que cet utilisateur LDAP** (et non le
`kasm-user` générique).

---

## 1. Build de l'image

Build depuis la racine du dépôt (les scripts `scripts/` et `env/` doivent être
accessibles) :

```bash
docker build -f rocky8-kasmvnc.Dockerfile -t rocky8-kasmvnc:latest .
```

Pousser ensuite l'image dans votre registry et faire un re-pull côté Kasm après
chaque modification.

---

## 2. Configuration Kasm Workspaces

Toute la configuration runtime se fait dans le **Docker Run Config Override** du
Workspace (Admin → Workspaces → votre workspace → champ *Docker Run Config
Override*).

### Configuration à coller

```json
{
  "user": "root",
  "environment": {
    "KASM_USER": "{username}",
    "LDAP_ENABLED": "true",
    "LDAP_URI": "ldap://10.32.14.211",
    "LDAP_SEARCH_BASE": "dc=mondomaine,dc=local",
    "LDAP_SCHEMA": "rfc2307",
    "LDAP_TLS_REQCERT": "never",
    "LDAP_HOME_DIR_TEMPLATE": "/home/%u",
    "LDAP_DEFAULT_SHELL": "/bin/bash"
  }
}
```

Adaptez `LDAP_URI` et `LDAP_SEARCH_BASE` à votre annuaire.

### Pourquoi chaque clé

| Clé | Rôle |
|-----|------|
| `"user": "root"` | **Obligatoire.** Kasm lance le conteneur en uid 1000 par défaut. Or SSSD (démon privilégié) et le changement vers l'uid LDAP nécessitent root au démarrage. L'entrypoint redescend ensuite vers l'utilisateur LDAP (le bureau ne tourne donc **pas** en root). |
| `KASM_USER: "{username}"` | Injecte le nom de l'utilisateur du portail dans le conteneur. `{username}` est résolu par Kasm vers le compte connecté. L'entrypoint l'utilise pour ouvrir la session sous cet utilisateur. |
| `LDAP_ENABLED: "true"` | Active SSSD. **Doit être défini ici** (env du conteneur au démarrage), pas seulement dans l'environnement de session. |
| `LDAP_URI` | URI du serveur LDAP. `ldap://` = non chiffré, `ldaps://` recommandé en prod. |
| `LDAP_SEARCH_BASE` | Base DN des recherches (ex. `dc=example,dc=com`). |

### Variables LDAP supplémentaires (optionnelles)

Toutes définissables dans `environment`. Valeurs par défaut dans
[`env/global.env`](env/global.env).

| Variable | Défaut | Description |
|----------|--------|-------------|
| `LDAP_SCHEMA` | `rfc2307` | `rfc2307` (OpenLDAP posix), `rfc2307bis`, ou `ad` (Active Directory). |
| `LDAP_DEFAULT_BIND_DN` | *(vide)* | Compte de service pour le bind. Vide = bind anonyme. |
| `LDAP_DEFAULT_AUTHTOK` | *(vide)* | Mot de passe du compte de service. |
| `LDAP_TLS_REQCERT` | `never` | `demand` / `allow` / `never`. |
| `LDAP_TLS_CACERT` | *(vide)* | Chemin du bundle CA. |
| `LDAP_ID_USE_START_TLS` | `false` | StartTLS sur une connexion `ldap://`. Ignoré pour `ldaps://`. |
| `LDAP_USER_SEARCH_BASE` | *(dérivé)* | Override de la base de recherche des utilisateurs. |
| `LDAP_GROUP_SEARCH_BASE` | *(dérivé)* | Override de la base de recherche des groupes. |
| `LDAP_ACCESS_FILTER` | *(vide)* | Filtre LDAP restreignant qui peut se connecter (ex. `(memberOf=cn=kasm,ou=groups,dc=example,dc=com)`). |
| `LDAP_HOME_DIR_TEMPLATE` | `/home/%u` | Modèle de home (`%u` = username). |
| `LDAP_DEFAULT_SHELL` | `/bin/bash` | Shell forcé pour les utilisateurs LDAP. |

---

## 3. Comment ça marche

Au démarrage, `scripts/startup/entrypoint.sh` (en root) :

1. charge les défauts depuis `env/global.env` (l'environnement injecté par Kasm
   est prioritaire) ;
2. rend `/etc/sssd/sssd.conf` à partir des variables `LDAP_*` et démarre SSSD ;
3. résout l'utilisateur de session (`KASM_USER`) ; si le nom porte un suffixe
   `@domaine` non résolu, réessaie avec la partie locale ;
4. crée son répertoire home au premier login ;
5. ajoute le groupe `kasmvnc-cert` aux groupes supplémentaires de l'utilisateur
   (nécessaire pour lire le certificat TLS de KasmVNC) ;
6. abandonne les privilèges (`setpriv`) et lance `vnc_startup.sh` **en tant que
   l'utilisateur LDAP**.

Le bureau KasmVNC + XFCE tourne donc sans privilèges, sous l'identité LDAP.

### Repli sans root

Si Kasm lance malgré tout le conteneur en non-root, l'entrypoint tente d'élever
**uniquement** le démarrage de SSSD via `sudo` (règle `NOPASSWD` limitée à
`entrypoint.sh --sssd-only`, posée par `scripts/build/install-ldap.sh`). Dans ce
mode, les utilisateurs LDAP sont résolus (`id user`) mais le bureau reste en
`kasm-user` — le passage vers l'utilisateur LDAP exige root. Pour un bureau sous
l'identité LDAP, utilisez `"user": "root"`.

---

## 4. Vérification

Sur l'hôte Docker du serveur Kasm, après connexion d'un utilisateur LDAP :

```bash
# Le conteneur est nommé <username>_<id>
docker logs <conteneur> 2>&1 | grep -iE 'sssd|ldap|session|groups'

# SSSD configuré (fichier non vide)
docker exec <conteneur> cat /etc/sssd/sssd.conf

# L'utilisateur LDAP est résolu
docker exec <conteneur> id <username>

# Le bureau tourne bien sous l'utilisateur LDAP
docker exec <conteneur> ps -o uid,user,cmd -C Xvnc
```

---

## 5. Dépannage

| Symptôme | Cause probable | Correctif |
|----------|----------------|-----------|
| `/etc/sssd/sssd.conf` vide | Conteneur démarré non-root **et** SSSD non élevé, ou `LDAP_ENABLED` ≠ `true` au boot | Mettre `"user": "root"` + `LDAP_ENABLED: "true"` dans le Docker Run Config Override. |
| `Session user '...' not found` | Le nom du portail ne correspond à aucun compte LDAP | Vérifier le mapping username Kasm ↔ attribut LDAP. Le suffixe `@domaine` est strippé automatiquement en repli. |
| `certificate isn't readable` (kasmvnc.pem) | Utilisateur LDAP absent du groupe `kasmvnc-cert` | Géré automatiquement par l'entrypoint (groupe ajouté au drop). Rebuild l'image si l'erreur persiste. |
| `no shared cipher` (handshake TLS) | KasmVNC pointé sur un PEM sans clé privée | Utiliser le certificat système (cert + clé). Ne pas passer `-cert` vers un PEM cert-seul. |
| `xfsettingsd: No such file or directory` | Paquet XFCE manquant | Cosmétique. Ajouter `xfce4-settings` dans `install-desktop.sh` si besoin. |

---

## Structure du dépôt

```
rocky8-kasmvnc.Dockerfile     Orchestrateur du build
env/global.env                Défauts runtime (DNS, locale, LDAP)
scripts/build/                Étapes de build (une par responsabilité)
  install-base.sh
  install-desktop.sh
  install-kasmvnc.sh
  install-ldap.sh             Paquets SSSD/sudo + NSS + sudoers
  setup-user.sh
  cleanup.sh
scripts/startup/
  entrypoint.sh               Init root : SSSD + résolution user + drop privilèges
  vnc_startup.sh              Démarrage KasmVNC + XFCE (en tant qu'utilisateur)
```
