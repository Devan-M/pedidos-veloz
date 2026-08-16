variable "kubeconfig_path" {
  description = "Caminho do kubeconfig usado pelo provider Kubernetes"
  type        = string
  default     = "~/.kube/config"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}
