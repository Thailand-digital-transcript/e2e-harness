# Transcript Platform — Cross-Service E2E Harness

A Java 21 / Maven test harness that spins up the **entire digital-transcript
microservice platform** in Docker and drives a full happy-path saga end to end —
transcript ingest → batching → multi-party signing → PDF generation — asserting on
both Kafka events and the resulting S3/MinIO artifacts.

This repository contains **only the harness**: the JUnit/Testcontainers test code,
the `docker-compose.yml` topology, per-service Dockerfiles, and infrastructure
seeding scripts. The service source code lives in **sibling repositories** (see
[Workspace layout](#workspace-layout)).

---

## Prerequisites

- **JDK 21** and **Maven** (to compile and run the harness)
- **Docker** with the Compose v2 plugin (the integration tests boot an 11-container
  stack via [Testcontainers](https://java.testcontainers.org/))
- Enough CPU/RAM for ~6 Spring Boot JVMs + Postgres + Kafka + MinIO + Keycloak
  concurrently
- The sibling service repositories checked out alongside this one (below),
  including the `transcript-approval-ui` repo (Keycloak realm source of truth)

## Workspace layout

The build scripts package service JARs from sibling checkouts. Clone this repo and
the six sibling repos (five services + the approval UI) as siblings under one
parent directory:

```
digital_transcript/                 # ← parent workspace
├── e2e-harness/                    # ← this repo
├── transcript-processing/
├── transcript-orchestrator/
├── transcript-signing/
├── transcript-pdf-generation/
├── transcript-approval-ui/         # Keycloak realm source of truth + UI service
└── etax/                           # CSC / eIDAS remote signing service
    └── eidasremotesigning/
```

`scripts/build-jars.sh` resolves each service at these relative paths, so the
layout above is required.

---

## Quick start

Two steps: prepare the prerequisites (keystores, service JARs, Keycloak realm),
then run the integration test (which boots the whole stack itself).

```bash
# 1. One-time (per fresh checkout or after sibling changes): keystores + jars + realm
./scripts/prepare.sh              # wraps gen-keystores.sh + build-jars.sh + sync-realm.sh

# 2. Run the end-to-end integration test (boots the compose stack)
mvn verify
```

`./scripts/prepare.sh` chains three sub-steps:

- `./scripts/gen-keystores.sh` — generates the BCFKS signing keystores CSC relies on
  (writes to `infra/csc/keystores/*.bfks`).
- `./scripts/build-jars.sh` — builds all five service JARs from the sibling repos
  (copies the `-exec.jar` into `services/<svc>/app.jar`).
- `./scripts/sync-realm.sh` — syncs the Keycloak dev realm from
  `../transcript-approval-ui/keycloak/realm-export.json` into
  `infra/keycloak/realm-export.json` (strips `organizationsEnabled` for 24.0.5
  compatibility).

Run a single integration test:

```bash
mvn verify -Dit.test=CrossServiceHappyPathIT -DfailIfNoTests=false
```

Unit tests only (fast, no Docker):

```bash
mvn test                          # surefire; excludes *IT.java
```

Bring the stack up manually for poking around (services stay up, no test run):

```bash
./scripts/dev-up.sh --build
# or, equivalently:
# docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

To exercise the full saga through the UI manually: `dev-up.sh --build`,
browse `http://localhost:8081`, log in as `registrar1` (password
`password` — see infra/keycloak/realm-export.json), then render and approve
a batch through the UI.

The base `docker-compose.yml` is intentionally port-less so the same stack
can boot under Testcontainers (`mvn verify`) without colliding with a manual
dev session. `docker-compose.dev.yml` re-adds the host bindings for the
manual workflow. `dev-up.sh` is just a wrapper that loads both files.

> **Order matters:** `mvn verify` requires the keystores, JARs, and synced realm
> to be present first, or the compose stack will fail to start.

---

## What the happy-path test does

`CrossServiceHappyPathIT.fullHappyPath()` exercises the complete saga:

1. **Ingest** — POST a transcript XML fixture to `transcript-processing` (expects `202`).
2. **Orchestrate** — `processing` emits an `InboundStartSagaCommand` to Kafka;
   the orchestrator consumes it and creates a `TranscriptItem`.
3. **Batch** — create a batch, assign the item, and close it.
4. **Registrar approval** — publish an `APPROVE` on `approval.registrar`; the
   saga advances to `PENDING_DEAN`.
5. **Dean approval** — publish an `APPROVE` on `approval.dean` (only after the
   batch reaches `PENDING_DEAN`).
6. **Signing & seal** — DEAN signs (XAdES), then SEAL signs (XAdES + PAdES).
7. **PDF generation** + outbox relay; the batch reaches `COMPLETED`.
8. **Assertions** — a `BatchCompletedEvent` on `transcript.batch.completed`, a
   signed PDF in the `transcript-pdfs` bucket, and sealed XML in
   `signed-transcripts`.

---

## Architecture of this repo

```
src/test/java/com/wpanther/transcript/e2e/
├── CrossServiceHappyPathIT.java   # the end-to-end test
├── KafkaE2EHelper.java            # Kafka produce/consume via in-container exec
└── KeystoreGenerator.java         # generates the BCFKS signing keystores
src/test/resources/fixtures/
└── Transcript_v2.0.xml            # input fixture (institution 01110)
services/<svc>/                     # one Dockerfile + built app.jar per service
infra/
├── postgres/init.sh               # creates per-service databases
├── csc/{seed.sql, keystores/}     # CSC credentials + signing keystores
└── keycloak/realm-export.json     # dev realm (synced from UI repo by prepare.sh)
docker-compose.yml                 # the 11-container stack
scripts/{prepare.sh, build-jars.sh, gen-keystores.sh, sync-realm.sh}
```

### The compose stack (11 containers)

| Service | Image / build | Port | Role |
|---------|---------------|------|------|
| `postgres` | `postgres:16` | 5432 | Shared DB; `infra/postgres/init.sh` seeds databases |
| `kafka` | `confluentinc/cp-kafka:7.6.0` (KRaft) | 9092 | Event broker |
| `minio` | `minio/minio` | 9000 (api), 9001 (console) | S3-compatible object store |
| `minio-init` | `minio/mc` | — | One-shot: creates the three buckets |
| `keycloak` | `quay.io/keycloak/keycloak:24.0.5` | 8080 | OIDC issuer; realm `transcript` imported on boot |
| `csc` | built (`eidasremotesigning`) | 9000 | eIDAS / remote signing service |
| `csc-seed` | `postgres:16` | — | One-shot: loads CSC credentials |
| `transcript-processing` | built | 8085 | Ingests transcript XML |
| `transcript-orchestrator` | built | 8095 | Saga orchestration + REST API (JWT-protected) |
| `transcript-signing` | built | 8088 | XAdES/PAdES signing via CSC |
| `transcript-pdf-generation` | built | 8090 | Renders the signed PDF |
| `transcript-approval-ui` | built (`../transcript-approval-ui`) | 8081 | React/Nginx SPA for registrar + dean approval |

### Defaults / credentials

| | Value |
|--|-------|
| Institution code (from fixture) | `01110` |
| Keycloak | realm `transcript` · client `transcript-e2e` (secret `e2e-dev-secret`, dev-only) · demo users `registrar1`/`dean1` (inst `01110`), `dual1` (inst `99999`) |
| Postgres | `postgres` / `postgres` |
| MinIO | `minioadmin` / `minioadmin` |
| Kafka topics | `approval.registrar`, `approval.dean`, `transcript.batch.completed` |
| MinIO buckets | `transcripts`, `signed-transcripts`, `transcript-pdfs` |

---

## How the tests drive Kafka

Testcontainers Compose exposes services through an ambassador with **ephemeral host
ports**, which breaks Kafka's advertised-listener contract for a host-side client.
`KafkaE2EHelper` side-steps this by `exec`-ing `kafka-console-producer` /
`kafka-console-consumer` **inside the kafka container** on `localhost:9092`, and
base64-encodes payloads so arbitrary JSON survives the shell.

## Troubleshooting

- **Stack won't start / `mvn verify` fails early** — keystores, JARs, or the
  Keycloak realm are missing. Re-run `./scripts/prepare.sh` first (it chains
  gen-keystores + build-jars + sync-realm).
- **Stale service behavior after rebuilding JARs** — the integration test forces
  image rebuilds (`withBuild(true)`), but a manual `./scripts/dev-up.sh` reuses
  cached images. Use `./scripts/dev-up.sh --build`.
- **`./scripts/list-batches.sh` returns "API unavailable"** — the manual
  stack is up but without host port mappings (e.g. you ran `docker compose up`
  instead of `./scripts/dev-up.sh`). Re-run via the wrapper, or layer in
  `docker-compose.dev.yml` manually.
- **Keycloak never becomes healthy** — the realm import can take a while on a
  cold start; the healthcheck allows a 30s `start_period` and 20 retries
  (≈3.5 min). If it still fails, check `docker compose logs keycloak` for the
  import error (the `organizationsEnabled` field is stripped by
  `sync-realm.sh` for 24.0.5 compat).
- **401 from `transcript-orchestrator`** — the harness now uses Keycloak JWTs;
  ensure `./scripts/prepare.sh` was run so the realm is up, and that the
  orchestrator's `KEYCLOAK_ISSUER` and `KEYCLOAK_JWKS_URI` envs resolve from
  the running stack.
- **Saga stalls at `PENDING_DEAN`** — the dean approval must not be published
  before the batch reaches `PENDING_DEAN`; otherwise the state machine no-ops
  while the Kafka offset is still committed, permanently losing the message.
- **`COMPLETED` assertion times out** — SEAL signing calls the
  [freetsa.org](https://freetsa.org) time-stamp service, adding latency; the test
  allows 120 s. Check network access if it fails.
- **`kafka` container not found** — its name varies by Compose version
  (`kafka-1` / `kafka_1` / `kafka`); the test tries each variant.

---

## Notes

- Service JARs are built with `-Dmaven.test.skip=true` because some sibling
  services have pre-existing test compile errors unrelated to this harness.
- Service runtimes target Java 17 (`eclipse-temurin:17-jre-alpine` in the
  Dockerfiles); the harness itself compiles and runs on Java 21.
