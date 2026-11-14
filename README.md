# Lab : les agents IA, nouveau workload de Kubernetes

Ce lab accompagne un article du blog [Gravitek](https://gravitek.io/blog). Il fait tourner
[kagent](https://kagent.dev) 1.0 sur Agent Substrate dans un cluster [kind](https://kind.sigs.k8s.io) local,
pour observer de ses propres yeux ce qui change quand on héberge des agents IA : des dizaines de conversations
sans pods supplémentaires, des agents qui dorment et se réveillent depuis un snapshot, une isolation gVisor
et un egress fermé par défaut.

> En construction : le guide complet arrive avec la première version du lab.

## Licence

Copyright 2026 Gravitek. Distribué sous licence [Apache 2.0](LICENSE).
