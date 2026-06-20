# Interactive Demo — Transcript Platform

Boot the whole digital-transcript platform locally, with a transcript already
waiting in the approval queue, and walk it through registrar → dean approval to a
completed signed PDF/A-3b — all in the browser.

> **Dev-only sandbox.** The realm, the `e2e-dev-secret` client secret, the demo
> user passwords, and `minioadmin` / `admin` are known throwaway values. Never
> reuse them outside a local sandbox.

## Prerequisites

- Docker with the Compose **v2.20+** plugin.
- JDK 21 + Maven, needed once to build the service JARs.
- The sibling service repos checked out alongside `e2e-harness/`:
  `transcript-processing/`, `transcript-orchestrator/`, `transcript-signing/`,
  `transcript-pdf-generation/`, `transcript-approval-ui/`, and
  `etax/eidasremotesigning/`. See the repo `README.md` for the workspace layout.

## Quick start

```bash
# 1. One-time: build service JARs, signing keystores, and the Keycloak realm.
./scripts/prepare.sh

# 2. Boot the stack and seed a batch into the approval queue.
./demo/up.sh
```

`./demo/up.sh` builds the images, starts the 12-container demo stack (the 11-service
base + a one-shot `demo-seed`), and blocks until the seed job has placed one batch
at `PENDING_REGISTRAR`. On a cold start this takes several minutes (Keycloak realm
import + six Spring Boot JVMs).

> **Don't run the demo and `mvn verify` at the same time.** The automated harness
> (`mvn verify`) and this demo share the same topology but both bind host ports
> (`8080`/`8081` from the base; `8095`/`9000`/`9001` from the demo overlay), so
> running them concurrently causes a port clash. Run one at a time — tear the demo
> down with `./demo/down.sh` before `mvn verify`, and vice versa.

## Walkthrough

1. Open the **Approval UI** at <http://localhost:8081> and log in as **`registrar1`**
   (realm `transcript`). The seeded batch is in the queue — click **Approve**. It is
   a one-button approve: the UI sends
   `{"decision":"APPROVE","rejectedDocumentIds":null,"rejectionReason":null}` to the
   role-gated `POST /api/v1/batches/{id}/decision`.
2. Log out, log in as **`dean1`**, and **Approve** the same batch (now at
   `PENDING_DEAN`). The order is enforced server-side — a premature dean click just
   returns a `409`.
3. **Wait a few minutes.** After the dean approval the saga runs signing (XAdES) →
   seal (XAdES + PAdES) → PDF generation. The transition to `COMPLETED` can take up
   to ~2 minutes — not because of a timestamp authority (signing is B-B, no TSA) but
   from cumulative saga cost: several CSC remote-signing round-trips, Kafka hops plus
   the outbox relay poll interval, and the PDF/A-3b render + veraPDF gate. The batch
   is **not** stalled; the UI refreshes to `COMPLETED` when it lands.
4. **Inspect the artifacts** in the **MinIO console** at <http://localhost:9001>
   (`minioadmin` / `minioadmin`): bucket `transcript-pdfs` holds the generated
   PDF/A-3b; `signed-transcripts` holds the sealed XML.
5. **Poke Keycloak** admin at <http://localhost:8080> (`admin` / `admin`) to see the
   realm, users, roles, and the `transcript-e2e` client.

## Ingest your own transcript

```bash
./demo/ingest.sh path/to/YourTranscript.xml
```

This opens and closes a fresh batch for a transcript with a **new**
`<tc:TranscriptID>`, leaving it at `PENDING_REGISTRAR` for you to approve.

**De-duplication:** `transcript-processing` keys each transcript by its
`<tc:TranscriptID>`. Ingesting a transcript whose `TranscriptID` already exists is
reported as a no-op (`already ingested … nothing to do`) and does **not** create a
second batch. To seed another batch, ingest a transcript with a **distinct**
`TranscriptID`. (Running `./demo/ingest.sh` with no argument re-submits the bundled
fixture, which is already in the queue after first boot — so it's a deliberate
no-op.) `./demo/down.sh` clears everything for a fresh start.

**Institution:** the batch is always created under institution **`01110`** (the
demo's fixed institution), regardless of the XML's own institution, so it stays
visible to `registrar1` / `dean1`.

## Verify / tear down

```bash
./demo/smoke.sh   # asserts at least one batch is PENDING_REGISTRAR
./demo/down.sh    # stop the stack and remove volumes
```

## Endpoints & credentials

| Surface | URL | Credentials |
|---------|-----|-------------|
| Approval UI | <http://localhost:8081> | `registrar1` / `dean1` (realm `transcript`) |
| Keycloak admin | <http://localhost:8080> | `admin` / `admin` |
| MinIO console | <http://localhost:9001> | `minioadmin` / `minioadmin` |
| Orchestrator API | <http://localhost:8095/api/v1/batches> | bearer (client `transcript-e2e`, secret `e2e-dev-secret`) |

## How it works

`demo/docker-compose.demo.yml` is an **overlay** on the repo's base
`docker-compose.yml` — it only adds host port mappings and the one-shot
`demo-seed` container; the 11-service topology is inherited unchanged. `demo-seed`
runs `demo/seed.sh`, which ingests the transcript, mints a `transcript-e2e`
client-credentials token, and opens + closes a batch — stopping at
`PENDING_REGISTRAR` so the approvals are left for you. All wrappers run
`docker compose -f docker-compose.yml -f demo/docker-compose.demo.yml` from the
repo root.
