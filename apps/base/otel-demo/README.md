# OpenTelemetry Demo

## Tutorial
Deployment, refer to
[Kubernetes](https://opentelemetry.io/docs/demo/kubernetes_deployment/)

Once deployment is completed, run commands in below
```bash
kubectl port-forward svc/otel-demo-frontendproxy -n otel-demo 8080:8080
kubectl port-forward svc/otel-demo-otelcol 4318:4318
```

With the frontendproxy and Collector port-forward set up, you can access:

Webstore: http://localhost:8080/
Grafana: http://localhost:8080/grafana/
Feature Flags UI: http://localhost:8080/feature/
Load Generator UI: http://localhost:8080/loadgen/
Jaeger UI: http://localhost:8080/jaeger/ui/