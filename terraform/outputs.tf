output "namespace" {
  value = kubernetes_namespace.pedidos_veloz.metadata[0].name
}
