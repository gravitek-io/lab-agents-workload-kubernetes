# Design — Article « agents IA = nouveau workload Kubernetes » et son lab

- Date : 2026-11-14
- Statut : brouillon, en attente de validation
- Article cible : blog Gravitek (`gravitek-website/content/blog/`), en français
- Lab : ce repo (`lab-agents-workload-kubernetes`), public, rejouable sur un portable

## 1. Intention

Gravitek publie des articles « cas d'usage entreprise » sur l'IA agentique, chacun illustré par un petit lab
reproductible. Celui-ci est le premier de la série (brief : `~/vault/40-projects/gravitek-blog/`).

Le lecteur visé gère, ou va gérer, une plateforme Kubernetes et voit arriver des agents IA. La thèse :
**un agent n'est pas un microservice**. Il est avec état, il travaille par pics et il attend la plupart du
temps. Le modèle « un pod par agent » gaspille la mémoire et fragilise le plan de contrôle. KubeCon NA 2026
a standardisé une réponse : Agent Substrate (densité, suspend/resume, sandbox gVisor) et kagent 1.0 au-dessus.

L'article explique **pourquoi** ; le lab montre **comment ça marche**, sur un cluster kind, pour que le
lecteur puisse le voir de ses yeux et le rejouer.

## 2. Objectifs, non-objectifs, anti-objectifs

**Objectifs**

- Un article publiable, sobre et sourcé, qui aide un responsable de plateforme à décider quoi regarder.
- Un lab que le lecteur rejoue en une commande par étape, sur macOS (arm64) ou Linux, avec Docker et kind.
- Des figures de l'article tirées de mesures réelles du lab (CSV versionné), pas d'illustrations inventées.

**Non-objectifs**

- Comparer chiffres à l'appui « pod par agent » et Substrate. Décision du 2026-11-14 : le lab ne montre que la
  nouvelle approche ; les chiffres de gain cités viennent de Google et sont attribués comme tels.
- La gouvernance par policy-as-code (Kyverno) : réservée à l'article 2 de la série.
- Un lab de production : pas de haute disponibilité, base PostgreSQL de développement fournie par le CLI kagent.

**Anti-objectifs** (ce qui ferait échouer l'article même si tout fonctionne)

- Présenter des chiffres de fournisseur comme des mesures indépendantes.
- Un lab qui ne passe que sur la machine de l'auteur (versions non épinglées, étapes manuelles cachées).
- Une clé d'API qui fuit dans le repo, les logs, les captures ou les CSV.
- Un ton « vendeur » de kagent : l'article dit aussi ce que la solution ne règle pas (style maison).

## 3. Contraintes

- **Kubernetes ≥ 1.37** (Agent Substrate dépend de `PodCertificateRequest` et `ClusterTrustBundle`, GA en 1.37).
  Image `kindest/node:v1.37.0`, **kind ≥ v0.32.0** (la machine de l'auteur a v0.30.0, à mettre à jour).
- **macOS arm64 + Docker Desktop** comme cible principale. Les images `ateworker-gvisor:v1.0.0` et
  `kindest/node:v1.37.0` existent en arm64 (vérifié). gVisor dans un nœud kind sous Docker Desktop n'est
  **pas encore vérifié** : c'est le premier risque à lever (voir § 7).
- **Modèle** : OpenRouter, déclaré comme fournisseur compatible OpenAI (`ModelConfig`, `provider: OpenAI`,
  `openAI.baseUrl: https://openrouter.ai/api/v1`). Le modèle choisi **doit accepter les appels d'outils**
  (kagent envoie la liste de ses outils intégrés à chaque tour).
- **Modèle par défaut : le routeur automatique d'OpenRouter** (`openrouter/auto`, demande de Thomas, 2026-11-14),
  pour observer quels modèles il choisit selon les prompts. Le routeur ne retient que les modèles capables de
  traiter la requête (appels d'outils compris) et facture le tarif du modèle choisi, sans surcoût.
  Limite : le `ModelConfig` de kagent n'accepte ni en-têtes ni paramètres propres à OpenRouter, donc ni
  `X-OpenRouter-Metadata` (raison du choix) ni `cost_tier` par requête. On règle le palier de coût et la liste des
  modèles autorisés dans les préférences du compte OpenRouter (page Routing, section Auto Router), et on lit le
  modèle choisi pour chaque requête dans la page Activity d'OpenRouter. Ne pas fixer `reasoningEffort` : le routeur
  le choisit. Ce sujet reste dans le README du lab ; il n'entre pas dans l'article 1.
- **Secrets** : la clé OpenRouter vit dans un `.env` ignoré par git ; le Secret Kubernetes est créé depuis la
  variable d'environnement ; aucun script ne l'affiche. `.env.example` documente la variable sans valeur.
- **Versions épinglées** partout : kind, image de nœud, kagent CLI et charts (`v1.0.0` / `1.0.0`), Substrate.
- Code et commentaires en anglais ; README et textes destinés au lecteur en français (public du blog).

## 4. Approches envisagées

| Approche | Principe | Pour | Contre |
| --- | --- | --- | --- |
| A. Même image, deux hébergements | Un agent maison déployé en pods classiques puis sur Substrate | Comparaison juste | Harness « conteneur à soi » peu documenté ; deux fois plus de lab |
| B. Harness kagent vs agent comparable | Harness intégré côté Substrate, agent proche en pods | Chemin balisé | Comparaison biaisée par deux codes différents |
| C. Substrate seul, baseline calculée | N × mémoire d'un pod estimée | Simple | Point de départ non mesuré |
| **D. Substrate seul, sans baseline (retenue)** | L'article explique le pourquoi ; le lab rend le mécanisme visible | Le plus simple ; chemin le mieux documenté ; aucune image à construire | Pas de mesure indépendante du gain |

Choix de Thomas (2026-11-14) : **D**. L'argument « pod par agent » repose sur l'explication et sur des chiffres
sourcés ; le lab montre ce qu'un pod par agent ne peut pas faire (agents qui se multiplient sans pods
supplémentaires, agent endormi restauré depuis un snapshot, isolation gVisor, egress fermé).

Cluster : **kind** plutôt que k3d, parce que c'est l'outil le plus répandu pour ce genre de démo et que la
documentation kagent 1.0 le prend comme cible locale.

## 5. Le lab

### 5.1 Déroulé (une étape = une section de l'article)

1. **Installer** — cluster kind 1.37, kagent 1.0 + Agent Substrate via le CLI kagent (base PostgreSQL de dev),
   `ModelConfig` OpenRouter. Vérification : pods `ate-system` et `kagent` prêts, `WorkerPool` prête.
2. **Densité** — ouvrir 1, puis 10, puis 30 conversations (sessions), réparties sur quelques agents. Chaque
   session est un acteur Substrate ; le nombre d'acteurs monte, le nombre de pods reste celui du pool de
   workers (1 réplique), et un acteur endormi n'occupe aucun worker.
3. **Suspend/resume** — envoyer un message dans une session endormie : l'acteur est restauré, répond, puis se
   rendort à la fin du tour. Mesurer le temps de restauration ; montrer l'emplacement des snapshots.
4. **Isolation** — demander à l'agent d'exécuter une commande avec son outil `bash` pour montrer le noyau gVisor ;
   un appel vers un hôte non autorisé est refusé (et tracé par la passerelle d'egress) ; la clé OpenRouter
   n'est pas dans l'environnement de l'agent, qui n'envoie qu'un en-tête factice remplacé à la sortie.
5. **Mesurer** — un script relève, à chaque palier, le nombre d'acteurs par état, le nombre de pods workers et
   leur mémoire, dans un CSV versionné. Les figures de l'article en sont tirées.

### 5.2 Détails techniques par étape

Sources : documentation kagent 1.0 (installation, premier agent, suspend/resume, sandboxing, réseau et egress,
egress policies, métriques, télémétrie Substrate, réglage de Substrate), lue le 2026-11-14.

**Ce que la doc corrige dans notre modèle mental** (à refléter dans l'article) :

- **Un acteur par session, pas par agent.** Un `Agent` se compile en `ActorTemplate` ; chaque `Session`
  (conversation) crée un acteur nommé `session-<id>`, créé suspendu. La densité se mesure donc en sessions.
- **Le snapshot de kagent ne contient que le volume `/data`, pas la mémoire du processus.** À la reprise, les
  conteneurs redémarrent. Substrate sait aussi faire des snapshots mémoire, mais ce n'est pas ce qu'utilise
  kagent 1.0 par défaut. L'article ne doit pas promettre une reprise « à chaud » de la mémoire.
- **Pas de délai d'inactivité** : kagent suspend l'acteur à chaque fin de tour, dès que rien ne tourne dans la
  session. Chaque message paie donc une restauration.
- **Le nombre de pods = le nombre de répliques du `WorkerPool`**, la seule variable de capacité. On le
  dimensionne pour les tours simultanés, pas pour le nombre d'agents. Un worker annonce une capacité de
  1000 acteurs (la doc se contredit dans son glossaire : « au plus un acteur à la fois ») ; le lab tranchera.

**Étape 1 — Installer**

- `kind create cluster --image kindest/node:v1.37.0` (kind ≥ v0.32.0), puis CLI kagent `v1.0.0` et
  `kagent --config kagent-config.yaml install --namespace kagent`, avec `config.server.grpcReflection: true`
  (nécessaire au relevé de l'étape 5).
- Plugin `kubectl-ate` `v1.0.0` pour lire les acteurs.
- `ModelConfig` (`api.kagent.dev/v1alpha3`) : `provider: OpenAI`, `openAI.baseUrl: https://openrouter.ai/api/v1`,
  `model: <modèle OpenRouter>`, `apiKeySecret` / `apiKeySecretKey` pointant le Secret créé depuis `.env`.
- Point à vérifier : `kagent install` lit une clé de fournisseur et crée `default-model-config` pour OpenAI.
  Trouver comment l'installer sans clé OpenAI (option, ou `ModelConfig` remplacé ensuite) **sans jamais passer
  la clé OpenRouter là où elle serait envoyée à OpenAI**.
- Workers : fixer `substrateWorkerPool.template.resources` (requests et limits), sinon un worker annonce toute
  la capacité du nœud et les mesures de mémoire n'ont pas de sens.
- Vérification : pods `ate-system` et `kagent` prêts, `kubectl get workerpools -n kagent` à `READY 1`.

**Étape 2 — Densité**

- `Harness` (`spec.kagent: {}`, image du harness épinglée par digest comme dans la doc,
  `spec.substrate.workerPoolRef.name: kagent-default`, `spec.substrate.snapshotPolicy.location` obligatoire),
  `AgentTemplate` (`modelConfig.name` → notre `ModelConfig`, `systemPrompt`), quelques `Agent`.
- Sessions : `kagent agent session create --agent <agent> -o json`.
- Observation : `kubectl ate get actors --atespace kagent` (état, `WORKER POD <none>` pour un acteur suspendu) et
  gRPC `kagent.api.v1.SystemService/GetSubstrateSummary` (`actorCount`, `workerCount`, `actorStatusCounts`).

**Étape 3 — Suspend/resume**

- `kagent agent invoke --session <id> --task "..."`, puis relire l'état de l'acteur : `RESUMING` → `RUNNING` →
  `SUSPENDING` → `SUSPENDED`.
- Temps de restauration : écart entre les enregistrements `Actor restoring` et `Actor restored` dans les logs
  du worker (la doc n'en publie aucun chiffre de référence). Ne pas utiliser le temps total de `invoke`, qui
  inclut l'appel au modèle.
- Snapshots : `SystemService/ListSubstrateActors` → `snapshotUri`
  (`s3://ate-snapshots/kagent/atespaces/<atespace>/actors/<actor-uid>/snapshots/<snapshot-uid>`).

**Étape 4 — Isolation**

- gVisor : faire exécuter `dmesg` / `uname -a` par l'agent via son outil `bash` ; en complément, montrer
  `kubectl get sandboxconfig gvisor-default -o yaml`. L'image d'exécution n'a pas `curl`.
- Egress : fermé par défaut, seules les destinations dérivées de l'`AgentTemplate` (le modèle, etc.) sont
  ouvertes. Test refusé : `/dev/tcp` vers un hôte non autorisé via `bash` ; preuve côté plateforme dans
  `kubectl logs -n ate-system deploy/atenet-egress -c agentgateway` (`http.status=403 … reason=Authorization`).
  Puis montrer qu'une `EgressPolicy` (`spec.destinations[].origin`, référencée par `spec.egressPolicyRefs`)
  ouvre une destination précise.
- Clé : faire afficher l'environnement par l'agent (sans fuite possible, puisque la clé n'y est pas) ; l'agent
  n'envoie qu'un en-tête factice, remplacé par la passerelle.

**Étape 5 — Mesurer**

- Pas de pile Prometheus/OpenTelemetry : les métriques Substrate ne sortent qu'en OTLP, ce qui alourdirait le
  lab. Le script interroge `GetSubstrateSummary` (grpcurl via port-forward 8083) et `kubectl top pods` sur les
  workers (metrics-server), et écrit une ligne CSV par palier :
  `timestamp, sessions, actors_total, actors_suspended, actors_running, worker_pods, worker_memory_mib`.
- Les temps de restauration de l'étape 3 vont dans un second CSV.

### 5.3 Organisation du repo (proposition)

```
README.md                 # parcours du lecteur, étape par étape (FR)
.env.example              # OPENROUTER_API_KEY=, OPENROUTER_MODEL=
mise.toml                 # outils épinglés + tâches : mise run up / density / resume / isolation / measure / down
kind/cluster.yaml         # cluster kind 1.37
kagent/                   # kagent-values.yaml, kagent-config.yaml, ModelConfig, modèle d'agent
scripts/                  # un script par étape, idempotent, `set -euo pipefail`
results/                  # CSV de mesures versionnés (aucun secret)
docs/                     # ce design, puis notes d'exploitation
```

**Outillage : [mise](https://mise.jdx.dev/)** (demande de Thomas, 2026-11-14). `mise.toml` épingle les outils
du lab (kind ≥ 0.32, kubectl, helm, jq, grpcurl, shellcheck, et si possible le CLI kagent et `kubectl-ate` via
un backend GitHub) et déclare une tâche par étape, qui appelle le script correspondant. Le lecteur installe mise,
lance `mise install`, puis `mise run <étape>` : plus besoin de Makefile ni d'installer les outils à la main.
`.env` est chargé par mise (`[env] _.file`), et reste ignoré par git. Si le CLI kagent ou `kubectl-ate` ne
s'installent pas proprement via mise, une tâche `mise run tools` les télécharge à la version épinglée.

Pas de tests unitaires pour des scripts shell de démo ; à la place, chaque script vérifie ses préconditions et
échoue avec un message clair, et `mise run check` lance `shellcheck`.

## 6. L'article

- Titre de travail : « Un agent IA n'est pas un microservice : le traiter comme un workload Kubernetes ».
- Frontmatter : `author: thomas-perelle`, `category: Engineering`, tags existants du blog à vérifier
  (« Agents IA » et « Kubernetes » existent déjà), `draft: true` jusqu'à publication par Thomas.
- Plan (repris du brief, ajusté au choix D) :
  1. Un agent n'est pas un microservice (état, pics, attente ; pourquoi le pod par agent casse).
  2. Ce que KubeCon NA 2026 a acté (Agent Substrate 1.0, kagent 1.0, Mirantis Agent Platform).
  3. Densité : des conversations, pas des pods (lab étape 2).
  4. Dormir sans coûter : suspend/resume, et ce que le snapshot contient vraiment (lab étape 3).
  5. Isoler : le noyau n'est pas la frontière (gVisor, egress fermé, clés injectées ; lab étape 4).
  6. Ce que ça change pour votre plateforme (checklist).
  7. Ce que ça ne règle pas (chiffres de fournisseur, jeunesse du projet, limites documentées, gouvernance → article 2).
  8. Pour aller plus loin (liens groupés par thème).
- Illustrations : un SVG par idée, code couleur commun, style des articles existants (cartes pastel, system-ui) ;
  1 ou 2 graphiques tirés du CSV ; captures du lab sans aucun secret. Couverture 1500×837 JPG fournie par Thomas.
- **Une seule source pour l'article : le blog Gravitek.** Le repo du lab ne contient pas l'article ; son README
  est un guide d'exécution (prérequis, étapes, résultats attendus, dépannage) qui renvoie vers l'article pour le
  pourquoi. L'article renvoie vers le repo pour le comment. Pas de double publication : deux copies divergeraient
  et dupliqueraient le contenu pour les moteurs de recherche.
- Le lien vers le repo du lab suppose qu'il soit public sur GitHub avant publication (voir § 8).

## 7. Risques et ce qui reste au builder

- **gVisor dans kind sur Docker Desktop arm64** : à vérifier en tout premier (essai jetable) ; s'il échoue, on
  documente l'alternative (VM Linux, ou cluster cloud ≥ 1.37) avant d'aller plus loin.
- **Accès sortant** : les nœuds téléchargent l'artefact gVisor depuis une URL publique ; le lab exige Internet.
- **Contradiction de la doc sur la capacité d'un worker** (1000 acteurs vs un à la fois) : le lab mesure ce qui
  se passe avec des tours simultanés sur une seule réplique, et l'article rapporte ce qu'on a observé.
- **Ressources du portable** : Substrate + kagent + PostgreSQL + rustfs + 30 agents ; mémoire Docker Desktop
  à dimensionner et à indiquer dans le README.
- Laissé au builder : choix exact du modèle OpenRouter (avec appels d'outils, peu coûteux), noms des scripts,
  format du CSV.

## 8. Décisions prises sans Thomas (à vérifier à la relecture)

- **Si gVisor ne tourne pas dans kind sur Docker Desktop**, le builder s'arrête et revient vers Thomas avec le
  diagnostic et deux options chiffrées (VM Linux type Lima/Colima, ou cluster cloud ≥ 1.37). Il ne choisit pas
  seul : chaque option change la cible du lab et l'origine des mesures publiées.
- **Étape 4 déterministe d'abord.** Les preuves d'isolation (noyau gVisor, egress refusé) passent par une
  sandbox autonome de Substrate (`SandboxTemplate`, `kagent sandbox exec`), sur le même pool gVisor : pas de
  dépendance au bon vouloir du modèle. L'agent qui exécute lui-même `dmesg` ou affiche son en-tête factice sert
  d'illustration dans l'article, avec un script qui vérifie la sortie et réessaie. Si la sandbox autonome ne
  partage pas le même runtime que les agents, l'article le dit.
- **Chiffres de l'argumentaire.** Le brief et le wiki ne concordent pas : « 65 agents/nœud au lieu de 1 »
  (brief) contre « ~10× de densité, 250 agents sur 8 pods, reprise < 500 ms » (wiki, source Google). Le builder
  remonte aux sources primaires (annonces Google / Solo.io, talk KubeCon) avant d'en citer un seul, et chaque
  chiffre est attribué à son auteur. Le « ~70 % du trafic d'inférence vient d'agents » suit la même règle.
- **Longueur de l'article** : comparable à l'article golden path (environ 2 000 à 2 500 mots hors code).
- **Publication du lab** : repo public dans l'organisation GitHub `gravitek-io` (comme `gravitek-website`),
  licence Apache 2.0 (comme CalMirror). Créer le repo distant et pousser demandent l'accord explicite de Thomas :
  c'est un point d'arrêt du plan, avant la sortie de `draft: true`.
