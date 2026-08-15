# Observabilidade

## Métricas

Prometheus coleta métricas e Grafana apresenta dashboards.

Métricas mínimas:

- taxa de requisições;
- latência;
- erros HTTP;
- uso de CPU e memória;
- estado dos pods;
- disponibilidade dos serviços.

## Logs

Os serviços devem emitir logs estruturados em stdout. A coleta deve ser feita por um agente do cluster, como Fluent Bit ou Vector, encaminhando os registros para Loki ou Elasticsearch.

## Tracing

Para tracing distribuído, recomenda-se OpenTelemetry:

1. instrumentar os serviços;
2. propagar o contexto entre chamadas;
3. enviar spans para um OpenTelemetry Collector;
4. armazenar no Jaeger ou Tempo;
5. visualizar traces no Grafana.

A configuração do collector e do backend depende do ambiente Kubernetes utilizado.
