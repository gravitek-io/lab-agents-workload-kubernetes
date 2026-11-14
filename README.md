# Lab : les agents IA, nouveau workload de Kubernetes

Ce lab accompagne un article du blog [Gravitek](https://gravitek.io/blog). Il fait tourner
[kagent](https://kagent.dev) 1.0 sur Agent Substrate dans un cluster [kind](https://kind.sigs.k8s.io) local,
pour observer de ses propres yeux ce qui change quand on héberge des agents IA : des dizaines de conversations
sans pods supplémentaires, des agents qui dorment et se réveillent depuis un snapshot, une isolation gVisor
et un egress fermé par défaut.

> En construction : les étapes suivantes (modèle, densité, suspend/resume, isolation) arrivent au fil des
> versions du lab.

## Prérequis

- **Docker** (Docker Desktop sur macOS) avec au moins **6 Go de mémoire** et **10 Go de disque libre** dans
  sa machine virtuelle. Le lab vérifie les deux avant de créer le cluster. Si le disque manque,
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
2026-11-14T22:13:43Z,2,2,2,0,1,17
2026-11-14T22:13:46Z,10,10,10,0,1,17
2026-11-14T22:13:51Z,30,30,30,0,1,17
```

Trente conversations, trente acteurs endormis, et toujours **un seul pod worker**, qui n'occupe que quelques
mégaoctets. Avec un pod par agent, on aurait trente pods qui attendent. Le nombre de pods ne dépend que du nombre
de répliques du `WorkerPool`, à dimensionner pour les tours qui tournent en même temps, pas pour le nombre
d'agents ou de conversations.

Les mesures sont écrites dans `results/density.csv` (le fichier est réécrit à chaque lancement). Pour voir
les acteurs eux-mêmes :

```bash
kubectl ate get actors --atespace kagent
```

Un acteur endormi affiche `ACTOR_STATE_SUSPENDED` et `<none>` comme pod worker.

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

## Licence

Copyright 2026 Gravitek. Distribué sous licence [Apache 2.0](LICENSE).
