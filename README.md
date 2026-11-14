# Lab : les agents IA, nouveau workload de Kubernetes

Ce lab accompagne un article du blog [Gravitek](https://gravitek.io/blog). Il fait tourner
[kagent](https://kagent.dev) 1.0 sur Agent Substrate dans un cluster [kind](https://kind.sigs.k8s.io) local,
pour observer de ses propres yeux ce qui change quand on héberge des agents IA : des dizaines de conversations
sans pods supplémentaires, des agents qui dorment et se réveillent depuis un snapshot, une isolation gVisor
et un egress fermé par défaut.

L'article explique pourquoi un agent IA n'est pas un microservice et pourquoi le modèle « un pod par agent »
ne tient pas ; ce dépôt montre comment Agent Substrate y répond, étape par étape. Le lien vers l'article sera
ajouté à sa publication.

## En un coup d'œil

| Étape | Commande | Ce qu'on observe |
| --- | --- | --- |
| Installer | `mise run up` | kind 1.37, kagent 1.0, Agent Substrate, un pool de workers gVisor |
| Brancher le modèle | `mise run model` | OpenRouter, trois agents, une première réponse |
| Densité | `mise run density` | 30 conversations, 30 acteurs endormis, 1 seul pod worker |
| Suspend/resume | `mise run resume` | un agent restauré depuis son snapshot en ~100 ms |
| Isolation | `mise run isolation` | gVisor, egress fermé, clé injectée hors de l'agent |
| Tout d'un coup | `mise run all` | les cinq étapes à la suite (environ 6 minutes) |

Les mesures de référence, prises sur un MacBook Pro (Apple Silicon) avec Docker Desktop, sont dans
`results/`.

## Prérequis

- **Docker** (Docker Desktop sur macOS) avec au moins **6 Go de mémoire** et **10 Go de disque libre** dans
  sa machine virtuelle. Le lab complet occupe environ 1,8 Go de mémoire une fois installé ; la marge sert aux
  tours d'agents qui tournent en même temps. Le lab vérifie les deux avant de créer le cluster. Si le disque manque,
  `docker builder prune` libère souvent plusieurs gigaoctets de cache de build.
- **[mise](https://mise.jdx.dev/)**, qui installe tous les autres outils aux versions épinglées dans
  `mise.toml` : kind, kubectl, helm, le CLI kagent, le plugin `kubectl-ate`, jq, grpcurl…
- Un accès Internet : les images et le runtime gVisor sont téléchargés au premier démarrage.

Testé sur macOS (Apple Silicon) avec Docker Desktop. Les scripts n'utilisent que des commandes portables et
doivent aussi fonctionner sous Linux.

## Démarrer

```bash
mise install
```

```bash
mise run up
```

`up` crée un cluster kind **Kubernetes 1.37** (la version minimale d'Agent Substrate), installe
metrics-server, puis kagent 1.0 et Agent Substrate avec leur base PostgreSQL de développement et leur stockage
objet. Il attend enfin que le pool de workers gVisor soit prêt. La commande est rejouable : relancée sur un
cluster existant, elle ne recrée rien.

À la fin, le pool de workers est prêt :

```text
NAME             DESIRED   REPLICAS   READY   SANDBOXCONFIG    RESOLVED   AGE
kagent-default   1         1          1       gvisor-default   True       3m
```

## Vérifier l'isolation gVisor

```bash
mise run gvisor-check
```

Le script démarre une sandbox Substrate autonome sur le même pool de workers que les agents, lit son noyau de
l'intérieur et le compare à celui de l'hôte. Aucun modèle n'intervient, le résultat est donc reproductible :

```text
host kernel:     6.12.76-linuxkit
sandbox kernel:  4.19.0-gvisor
sandbox dmesg:   [   0.000000] Starting gVisor...
gVisor: OK
```

Le code de la sandbox ne parle jamais au noyau de l'hôte : ses appels système sont traités par le noyau
applicatif de gVisor, en espace utilisateur.

## Brancher le modèle

Les agents appellent un modèle via [OpenRouter](https://openrouter.ai), déclaré comme fournisseur compatible
OpenAI. Créez votre fichier `.env` à la racine du lab, puis renseignez votre clé (`OPENROUTER_API_KEY`) :

```bash
cp .env.example .env
```

```bash
mise run model
```

Le script range la clé dans un Secret Kubernetes, crée le `ModelConfig` OpenRouter, le harness, le modèle
d'agent `lab-assistant` et trois agents (`lab-agent-1` à `lab-agent-3`), puis pose une question à l'un d'eux :

```text
==> smoke test: one question to lab-agent-1
prêt.
==> model connected (session 01a1dc1d-…)
```

Le premier lancement prend une à deux minutes : Substrate construit le snapshot initial de chaque agent.

**La clé ne quitte jamais le Secret.** Elle n'est ni affichée ni passée en argument de commande, et les agents
ne la voient pas : la passerelle d'egress de Substrate l'ajoute aux requêtes sortantes vers OpenRouter.

**Le routeur automatique.** Par défaut, `OPENROUTER_MODEL=openrouter/auto` laisse OpenRouter choisir un modèle
pour chaque requête, parmi ceux qui savent appeler des outils. kagent ne transmet ni en-tête ni paramètre propre
à OpenRouter, et il ne remonte que le nombre de tokens, pas le nom du modèle choisi. Pour voir quel modèle a
répondu, ouvrez la page **Activity** de votre compte OpenRouter. Pour encadrer les choix du routeur, réglez le
palier de coût (`low` suffit pour ce lab) et la liste des modèles autorisés dans la page **Routing**, section
*Auto Router*. Pour fixer un modèle, remplacez la valeur de `OPENROUTER_MODEL` par son identifiant OpenRouter :
il doit accepter les appels d'outils.

## Densité : des conversations, pas des pods

```bash
mise run density
```

Le script ouvre 1, puis 10, puis 30 conversations (des *sessions*), réparties sur les trois agents, et prend une
mesure après chaque palier. Dans kagent 1.0, chaque session devient un **acteur** Substrate : son état (fichiers,
historique) existe, mais tant qu'il ne travaille pas, il est endormi et n'occupe aucun worker.

```text
timestamp,sessions,actors_total,actors_suspended,actors_running,worker_pods,worker_memory_mib
2026-11-14T22:25:48Z,1,1,1,0,1,14
2026-11-14T22:25:51Z,10,10,10,0,1,14
2026-11-14T22:25:56Z,30,30,30,0,1,18
```

Trente conversations, trente acteurs endormis, et toujours **un seul pod worker**, qui n'occupe qu'une
quinzaine de mégaoctets. Le premier palier part de la conversation ouverte par `mise run model` ; si vous
relancez le script, il repart des conversations existantes. Avec un pod par agent, on aurait trente pods qui attendent. Le nombre de pods ne dépend que du nombre
de répliques du `WorkerPool`, à dimensionner pour les tours qui tournent en même temps, pas pour le nombre
d'agents ou de conversations.

Les mesures sont écrites dans `results/density.csv` (le fichier est réécrit à chaque lancement). Pour voir
les acteurs eux-mêmes :

```bash
kubectl ate get actors --atespace kagent
```

Un acteur endormi affiche `ACTOR_STATE_SUSPENDED` et `<none>` comme pod worker.

## Suspend/resume : dormir sans coûter

```bash
mise run resume
```

Le script envoie un message à cinq conversations endormies. Pour chacune, Substrate attribue un worker à
l'acteur, le restaure depuis son snapshot, l'agent répond, puis l'acteur se rendort dès la fin du tour :

```text
==> session 01a1dc1d-…: ACTOR_STATE_SUSPENDED, no worker pod
    reply: réveillé.
==> restored in 82 ms, back to ACTOR_STATE_SUSPENDED
…
==> snapshot of the last session (only the /data volume, no process memory):
SNAPSHOT_FIDELITY_VOLUMES  s3://ate-snapshots/kagent/atespaces/kagent/actors/…/snapshots/…
```

Le temps mesuré est celui de la restauration, lu dans l'enregistrement « Restore timing breakdown » du
worker ; il n'inclut pas l'appel au modèle. Sur un MacBook Pro (Apple Silicon) avec Docker Desktop, nous avons mesuré entre 74 et 138 ms
selon les essais.
Les mesures sont écrites dans `results/resume.csv`.

**Ce que contient le snapshot.** Dans kagent 1.0, le snapshot ne garde que le volume `/data` de l'agent
(`SNAPSHOT_FIDELITY_VOLUMES`), pas la mémoire de son processus : à chaque réveil, le conteneur redémarre et
relit son état sur disque. Il n'y a pas non plus de délai d'inactivité : kagent endort l'acteur à **chaque
fin de tour**, si bien que chaque message paie une restauration. Les snapshots sont rangés dans le stockage
objet installé avec Substrate (rustfs, un volume de 1 Go non durable, prévu pour l'évaluation).

## Isolation : le noyau n'est pas la frontière

```bash
mise run isolation
```

Les trois premières vérifications passent par la sandbox sonde, sans modèle : elles donnent toujours le même
résultat. La dernière montre un vrai agent au travail.

```text
==> 1/4 gVisor
sandbox kernel:  4.19.0-gvisor
gVisor: OK
==> 2/4 egress closed by default
https://example.com -> curl: (6) Could not resolve host: example.com
==> 3/4 one EgressPolicy opens one origin
https://example.com -> 200
https://www.google.com -> curl: (6) Could not resolve host: www.google.com
==> egress gateway log for the allowed request:
endpoint=example.com:443 http.host=example.com http.status=200
==> 4/4 an agent at work (illustration, depends on the model using its tool)
4.19.0-gvisor
clé vue par l agent : kagent-credential-injected
agent illustration: OK
```

1. **gVisor** : les appels système de la sandbox sont traités par le noyau applicatif de gVisor, pas par celui
   de l'hôte.
2. **Egress fermé par défaut** : une destination non autorisée ne se résout même pas. Un agent n'atteint que ce
   que son modèle d'agent déclare (le fournisseur de modèle, ses serveurs MCP…).
3. **Une `EgressPolicy` ouvre une origine, et une seule** (`kagent/egress-policy.yaml`). La requête autorisée
   passe par la passerelle d'egress de Substrate, qui la journalise ; le reste d'Internet reste fermé. La
   politique est retirée à la fin du script.
4. **L'agent ne détient pas la clé** : il exécute lui-même `uname -r` avec son outil `bash`, puis affiche sa
   variable `OPENAI_API_KEY`, qui ne contient qu'un leurre (`kagent-credential-injected`). La passerelle
   remplace cet en-tête par la vraie clé OpenRouter à la sortie. Cette étape dépend de la bonne volonté du
   modèle à utiliser son outil : si elle échoue, le script le signale sans s'arrêter.

## Arrêter

```bash
mise run down
```

Supprime le cluster et tout ce qu'il contient.

## Dépannage

- **PostgreSQL redémarre en boucle (`No space left on device`)** : le disque de la VM Docker est plein.
  Libérez de la place (`docker builder prune`), puis `mise run down && mise run up`.
- **`kagent sandbox exec` ne rend jamais la main** : l'image `sandbox-guest` ne correspond pas à la version du
  contrôleur. Le lab épingle celle de la version 1.0.0 dans `kagent/kagent-values.yaml` ; la documentation
  « latest » de kagent affiche un digest plus récent, incompatible avec la 1.0.0.
- **Des sandboxes restent en `RUNTIME_STATE_CREATING`** : le worker est plein (4 Go de limite, 1 Go par
  sandbox ou par tour en cours). Listez et supprimez les sandboxes oubliées avec `kagent sandbox list` puis
  `kagent sandbox delete <id>`.
- **Chaque échange échoue avec une erreur 400 du fournisseur** : le modèle choisi dans `OPENROUTER_MODEL`
  n'accepte pas les appels d'outils. Revenez à `openrouter/auto` ou choisissez un modèle qui les accepte.
- **`kagent API not reachable on localhost:18083`** : le port local est déjà pris. Choisissez-en un autre avec
  la variable `LAB_API_PORT` (par exemple `LAB_API_PORT=28083 mise run density`).
- **Les scripts échouent sur une syntaxe bash** : ils sont écrits pour le bash 3.2 livré avec macOS ;
  signalez-le, c'est un bug.

## Licence

Copyright 2026 Gravitek. Distribué sous licence [Apache 2.0](LICENSE).
