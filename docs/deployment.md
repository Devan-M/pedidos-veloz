# Operação e deploy

## Ambiente local

```bash
cp .env.example .env
docker compose up -d --build
docker compose ps
```

## Encerramento

```bash
docker compose down
```

## Kubernetes

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/infrastructure.yaml
kubectl apply -f k8s/services.yaml
kubectl apply -f k8s/monitoring.yaml
kubectl apply -f k8s/autoscaling/hpa.yaml
kubectl apply -f k8s/security/network-policy.yaml
kubectl apply -f k8s/resilience/pdb.yaml
```

## Pré-requisitos do HPA

O cluster precisa possuir Metrics Server:

```bash
kubectl top nodes
kubectl top pods -n pedidos-veloz
```

## Estratégia

Os Deployments devem usar RollingUpdate com readinessProbe, livenessProbe, requests e limits. O pipeline publica imagens imutáveis usando o SHA do commit.
