# idp-platform-config
A GitOps-driven provisioning and deployment platform with a portal interface

kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret   -o jsonpath="{.data.password}" | base64 -d && echo

$ curl -4 -H "Host: whoami.local" http://127.0.0.1:18080

service:
  name: payments-api
  type: stateless
  runtime: python
  port: 8080
  replicas: 2
  public: true


service:
  name: payments-db
  type: stateful
  engine: postgres
  version: "16"
  port: 5432
  storage:
    size: 20Gi
    class: local-path
  resources:
    profile: db-small
  public: false
