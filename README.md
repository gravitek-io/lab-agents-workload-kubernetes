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
