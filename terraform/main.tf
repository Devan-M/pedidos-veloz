terraform {
  required_version = ">= 1.0.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Definição declarativa do Namespace via código
resource "kubernetes_namespace" "pedidos_namespace" {
  metadata {
    name = "pedidos-veloz"
    labels = {
      environment = "production"
      managed-by  = "terraform"
    }
  }
}
