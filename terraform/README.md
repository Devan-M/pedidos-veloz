# Terraform

Este diretório representa a camada de infraestrutura Kubernetes como código.

O esqueleto cria o namespace `pedidos-veloz`. Os demais manifests continuam sendo aplicados pelo GitHub Actions ou por `kubectl`.

Uso:

```bash
terraform init
terraform plan
terraform apply
```

O kubeconfig não deve ser versionado. Para um ambiente de produção, recomenda-se substituir o provider genérico pelo provider do provedor de nuvem e provisionar também rede, cluster, nós, observabilidade e políticas de acesso.
