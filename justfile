set dotenv-load

registry := env("REGISTRY_URL", "docker-registry.jeremymeek.dev")
user := env("REGISTRY_USER", "")
pass := env("REGISTRY_PASS", "")

pg_hybrid_image := registry / "postgres-hybrid-search"
pg_hybrid_tag := "17-latest"

login:
    echo "{{pass}}" | docker login {{registry}} -u {{user}} --password-stdin

build-pg-hybrid:
    docker build -t {{pg_hybrid_image}}:{{pg_hybrid_tag}} postgres-hybrid-search/

push-pg-hybrid: login
    docker push {{pg_hybrid_image}}:{{pg_hybrid_tag}}

deploy-pg-hybrid: (build-pg-hybrid) (push-pg-hybrid)
