resource "kubernetes_namespace" "pedidos_veloz" {
  metadata {
    name = "pedidos-veloz"
  }
}
