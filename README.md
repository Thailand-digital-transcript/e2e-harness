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
- **Docker** with the Compose v2 plugin (the integration tests boot a 9-container
  stack via [Testcontainers](https://java.testcontainers.org/))
- Enough CPU/RAM for ~6 Spring Boot JVMs + Postgres + Kafka + MinIO concurrently
- The sibling service repositories checked out alongside this one (below)

## Workspace layout

The build scripts package service JARs from sibling checkouts. Clone this repo and
the five service repos as siblings under one parent directory:

```
digital_transcript/                 # ← parent workspace
├── e2e-harness/                    # ← this repo
├── transcript-processing/
├── transcript-orchestrator/
├── transcript-signing/
├── transcript-pdf-generation/
└── etax/                           # CSC / eIDAS remote signing service
    └── eidasremotesigning/
```

`scripts/build-jars.sh` resolves each service at these relative paths, so the
layout above is required.

---

## Quick start

Three steps: generate signing keystores, build the service JARs, then run the
integration test (which boots the whole stack itself).

```bash
# 1. One-time: generate the BCFKS signing keystores CSC relies on
./scripts/gen-keystores.sh        # → infra/csc/keystores/*.bfks

# 2. Build all five service JARs from the sibling repos
./scripts/build-jars.sh           # → services/<svc>/app.jar

# 3. Run the end-to-end integration test (boots the compose stack)
mvn verify
```

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
docker compose up --build
```

> **Order matters:** `mvn verify` requires the keystores and JARs to be present
> first, or the compose stack will fail to start.

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
└── csc/{seed.sql, keystores/}     # CSC credentials + signing keystores
docker-compose.yml                 # the 9-container stack
scripts/{build-jars.sh, gen-keystores.sh}
```

### The compose stack (9 containers)

| Service | Image / build | Port | Role |
|---------|---------------|------|------|
| `postgres` | `postgres:16` | 5432 | Shared DB; `infra/postgres/init.sh` seeds databases |
| `kafka` | `confluentinc/cp-kafka:7.6.0` (KRaft) | 9092 | Event broker |
| `minio` | `minio/minio` | 9000 (api), 9001 (console) | S3-compatible object store |
| `minio-init` | `minio/mc` | — | One-shot: creates the three buckets |
| `csc` | built (`eidasremotesigning`) | 9000 | eIDAS / remote signing service |
| `csc-seed` | `postgres:16` | — | One-shot: loads CSC credentials |
| `transcript-processing` | built | 8085 | Ingests transcript XML |
| `transcript-orchestrator` | built | 8095 | Saga orchestration + REST API |
| `transcript-signing` | built | 8088 | XAdES/PAdES signing via CSC |
| `transcript-pdf-generation` | built | 8090 | Renders the signed PDF |

### Defaults / credentials

| | Value |
|--|-------|
| Orchestrator API key (`X-API-Key`) | `test-key` |
| Institution code (from fixture) | `01110` |
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

- **Stack won't start / `mvn verify` fails early** — keystores or JARs missing.
  Re-run `./scripts/gen-keystores.sh` and `./scripts/build-jars.sh` first.
- **Stale service behavior after rebuilding JARs** — the integration test forces
  image rebuilds (`withBuild(true)`), but a manual `docker compose up` reuses
  cached images. Use `docker compose up --build`.
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
