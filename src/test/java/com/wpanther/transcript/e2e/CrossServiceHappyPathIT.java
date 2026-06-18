package com.wpanther.transcript.e2e;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.awaitility.Awaitility;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.ComposeContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;

import java.io.File;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;

@Testcontainers
class CrossServiceHappyPathIT {

    // ── Service names as defined in docker-compose.yml ─────────────────────
    private static final String PROCESSING        = "transcript-processing";
    private static final String ORCHESTRATOR      = "transcript-orchestrator";
    private static final String PDF_GEN           = "transcript-pdf-generation";
    private static final String MINIO_SVC         = "minio";
    private static final String KAFKA_SVC         = "kafka";

    private static final int PROCESSING_PORT  = 8085;
    private static final int ORCHESTRATOR_PORT = 8095;
    private static final int PDF_GEN_PORT     = 8090;
    private static final int MINIO_PORT       = 9000;
    private static final int KAFKA_PORT       = 9092;

    // ── Kafka topics ────────────────────────────────────────────────────────
    private static final String TOPIC_REGISTRAR_APPROVAL = "approval.registrar";
    private static final String TOPIC_DEAN_APPROVAL      = "approval.dean";
    private static final String TOPIC_BATCH_COMPLETED    = "transcript.batch.completed";

    // ── Test credentials ────────────────────────────────────────────────────
    private static final String API_KEY          = "test-key";
    private static final String INSTITUTION_CODE = "01110";  // from <tc:OrganizationID> in fixture XML

    @Container
    @SuppressWarnings("resource")
    static ComposeContainer ENV = new ComposeContainer(new File("docker-compose.yml"))
            .withExposedService(PROCESSING,   PROCESSING_PORT,   Wait.forHealthcheck())
            .withExposedService(ORCHESTRATOR, ORCHESTRATOR_PORT, Wait.forHealthcheck())
            .withExposedService(PDF_GEN,      PDF_GEN_PORT,      Wait.forHealthcheck())
            .withExposedService(MINIO_SVC,    MINIO_PORT,        Wait.forHealthcheck())
            .withExposedService(KAFKA_SVC,    KAFKA_PORT,        Wait.forListeningPort())
            .withStartupTimeout(Duration.ofMinutes(10));

    // ── Shared test infrastructure ──────────────────────────────────────────

    private static final ObjectMapper MAPPER = new ObjectMapper()
            .registerModule(new JavaTimeModule());

    private static final HttpClient HTTP = HttpClient.newHttpClient();

    // ── DTOs (fields match actual JSON; @JsonIgnoreProperties absorbs extras) ─

    @JsonIgnoreProperties(ignoreUnknown = true)
    record ProcessingResponse(String id, String documentId, String status) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    record TranscriptItemSummary(String id, String transcriptId, String documentId,
                                 String institutionCode, String transcriptType,
                                 String status, String batchId) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    record CreateBatchResponse(String batchId, String name, String status) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    record BatchDetail(String id, String name, String institutionCode,
                       String status, int itemCount) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    record BatchCompletedEvent(String batchId, String institutionCode,
                               int itemCount, Instant completedAt) {}

    record ApprovalEvent(String batchId, String decision, String institutionCode,
                         String approvedBy, Instant approvedAt,
                         List<String> rejectedDocumentIds, String rejectionReason) {}

    // ── The test ────────────────────────────────────────────────────────────

    @Test
    void fullHappyPath() throws Exception {
        // ── Wire helpers ──────────────────────────────────────────────────
        String processingBase   = base(PROCESSING,   PROCESSING_PORT);
        String orchestratorBase = base(ORCHESTRATOR, ORCHESTRATOR_PORT);

        String kafkaBrokers = ENV.getServiceHost(KAFKA_SVC, KAFKA_PORT)
                + ":" + ENV.getServicePort(KAFKA_SVC, KAFKA_PORT);
        KafkaE2EHelper kafka = new KafkaE2EHelper(kafkaBrokers, MAPPER);

        String minioHost = ENV.getServiceHost(MINIO_SVC, MINIO_PORT);
        int    minioPort = ENV.getServicePort(MINIO_SVC, MINIO_PORT);
        S3Client s3 = S3Client.builder()
                .endpointOverride(URI.create("http://" + minioHost + ":" + minioPort))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create("minioadmin", "minioadmin")))
                .region(Region.US_EAST_1)
                .forcePathStyle(true)
                .build();

        // ── Step 1: POST transcript XML to processing service ─────────────
        String xmlBody = new String(CrossServiceHappyPathIT.class
                .getResourceAsStream("/fixtures/Transcript_v2.0.xml")
                .readAllBytes());

        HttpResponse<String> postResp = HTTP.send(
                HttpRequest.newBuilder()
                        .uri(URI.create(processingBase + "/api/v1/transcripts"))
                        .header("Content-Type", "application/xml")
                        .POST(HttpRequest.BodyPublishers.ofString(xmlBody))
                        .build(),
                HttpResponse.BodyHandlers.ofString());

        assertThat(postResp.statusCode())
                .as("Processing POST should return 202 Accepted; body: %s", postResp.body())
                .isEqualTo(202);

        ProcessingResponse processingResp = MAPPER.readValue(postResp.body(), ProcessingResponse.class);
        String documentId = processingResp.documentId();
        assertThat(documentId).as("documentId must not be null").isNotNull();

        // ── Step 2: Poll orchestrator until the TranscriptItem appears ────
        // The processing service publishes InboundStartSagaCommand to Kafka;
        // the orchestrator consumes it and creates a TranscriptItem.
        String[] itemId = new String[1];
        Awaitility.await("TranscriptItem appears in orchestrator")
                .atMost(30, TimeUnit.SECONDS)
                .pollInterval(2, TimeUnit.SECONDS)
                .untilAsserted(() -> {
                    HttpResponse<String> listResp = HTTP.send(
                            HttpRequest.newBuilder()
                                    .uri(URI.create(orchestratorBase + "/api/v1/transcripts"))
                                    .header("X-API-Key", API_KEY)
                                    .GET()
                                    .build(),
                            HttpResponse.BodyHandlers.ofString());
                    assertThat(listResp.statusCode()).isEqualTo(200);

                    List<TranscriptItemSummary> items = MAPPER.readValue(listResp.body(),
                            MAPPER.getTypeFactory().constructCollectionType(List.class, TranscriptItemSummary.class));
                    TranscriptItemSummary match = items.stream()
                            .filter(i -> documentId.equals(i.documentId()))
                            .findFirst()
                            .orElseThrow(() -> new AssertionError("Item with documentId=" + documentId + " not found yet"));
                    itemId[0] = match.id();
                });

        // ── Step 3: Create batch, assign item, close batch ────────────────
        HttpResponse<String> createBatchResp = HTTP.send(
                HttpRequest.newBuilder()
                        .uri(URI.create(orchestratorBase + "/api/v1/batches"))
                        .header("Content-Type", "application/json")
                        .header("X-API-Key", API_KEY)
                        .POST(HttpRequest.BodyPublishers.ofString(
                                MAPPER.writeValueAsString(Map.of(
                                        "name", "E2E-Batch",
                                        "institutionCode", INSTITUTION_CODE,
                                        "createdBy", "e2e-test"))))
                        .build(),
                HttpResponse.BodyHandlers.ofString());

        assertThat(createBatchResp.statusCode())
                .as("Create batch should return 201; body: %s", createBatchResp.body())
                .isEqualTo(201);
        CreateBatchResponse batchInfo = MAPPER.readValue(createBatchResp.body(), CreateBatchResponse.class);
        String batchId = batchInfo.batchId();

        HTTP.send(
                HttpRequest.newBuilder()
                        .uri(URI.create(orchestratorBase + "/api/v1/batches/" + batchId + "/items"))
                        .header("Content-Type", "application/json")
                        .header("X-API-Key", API_KEY)
                        .POST(HttpRequest.BodyPublishers.ofString(
                                MAPPER.writeValueAsString(Map.of("itemIds", List.of(itemId[0])))))
                        .build(),
                HttpResponse.BodyHandlers.ofString());

        HttpResponse<String> closeResp = HTTP.send(
                HttpRequest.newBuilder()
                        .uri(URI.create(orchestratorBase + "/api/v1/batches/" + batchId + "/close"))
                        .header("Content-Type", "application/json")
                        .header("X-API-Key", API_KEY)
                        .header("X-Closed-By", "e2e-test")
                        .POST(HttpRequest.BodyPublishers.noBody())
                        .build(),
                HttpResponse.BodyHandlers.ofString());

        assertThat(closeResp.statusCode())
                .as("Close batch; body: %s", closeResp.body())
                .isIn(200, 204);

        // ── Step 4: Publish registrar approval ────────────────────────────
        // The orchestrator transitions to PENDING_REGISTRAR on close, then
        // dispatches a signing command. When signing finishes it transitions
        // to PENDING_DEAN. Publish the registrar approval to advance the saga.
        kafka.send(TOPIC_REGISTRAR_APPROVAL, batchId,
                new ApprovalEvent(batchId, "APPROVE", INSTITUTION_CODE,
                        "e2e-registrar", Instant.now(), List.of(), null));

        // ── Step 5: Gate on PENDING_DEAN before publishing dean approval ──
        // CRITICAL: do NOT publish the dean approval before this gate passes.
        // BatchStateMachine.deanApprove() is a silent no-op when status ≠ PENDING_DEAN.
        // If the event is consumed before the state machine reaches PENDING_DEAN,
        // the Kafka offset is committed and the message is permanently lost.
        Awaitility.await("Batch reaches PENDING_DEAN after registrar approval")
                .atMost(60, TimeUnit.SECONDS)
                .pollInterval(2, TimeUnit.SECONDS)
                .untilAsserted(() -> {
                    BatchDetail detail = getBatchDetail(orchestratorBase, batchId);
                    assertThat(detail.status())
                            .as("Expected PENDING_DEAN, got %s", detail.status())
                            .isEqualTo("PENDING_DEAN");
                });

        // ── Step 6: Publish dean approval ────────────────────────────────
        kafka.send(TOPIC_DEAN_APPROVAL, batchId,
                new ApprovalEvent(batchId, "APPROVE", INSTITUTION_CODE,
                        "e2e-dean", Instant.now(), List.of(), null));

        // ── Step 7: Gate on COMPLETED ─────────────────────────────────────
        // Remaining work: DEAN signing (XAdES), SEAL signing (XAdES + PAdES),
        // PDF generation, outbox relay. 120 s covers signing latency + freetsa.org TSP call.
        Awaitility.await("Batch reaches COMPLETED")
                .atMost(120, TimeUnit.SECONDS)
                .pollInterval(2, TimeUnit.SECONDS)
                .untilAsserted(() -> {
                    BatchDetail detail = getBatchDetail(orchestratorBase, batchId);
                    assertThat(detail.status())
                            .as("Expected COMPLETED, got %s", detail.status())
                            .isEqualTo("COMPLETED");
                });

        // ── Step 8: Assert BatchCompletedEvent on transcript.batch.completed ─
        BatchCompletedEvent completed = kafka.pollFor(
                TOPIC_BATCH_COMPLETED,
                BatchCompletedEvent.class,
                e -> batchId.equals(e.batchId()),
                Duration.ofSeconds(30));

        assertThat(completed.batchId()).isEqualTo(batchId);
        assertThat(completed.itemCount()).isEqualTo(1);
        assertThat(completed.institutionCode()).isEqualTo(INSTITUTION_CODE);

        // ── Step 9: Assert signed PDF in transcript-pdfs bucket ──────────
        ListObjectsV2Response pdfObjects = s3.listObjectsV2(
                ListObjectsV2Request.builder().bucket("transcript-pdfs").build());
        assertThat(pdfObjects.contents())
                .as("transcript-pdfs bucket must have at least one object")
                .isNotEmpty();
        assertThat(pdfObjects.contents().get(0).size())
                .as("PDF object must not be empty")
                .isGreaterThan(0);

        // ── Step 10: Assert sealed XML in signed-transcripts bucket ───────
        ListObjectsV2Response xmlObjects = s3.listObjectsV2(
                ListObjectsV2Request.builder().bucket("signed-transcripts").build());
        assertThat(xmlObjects.contents())
                .as("signed-transcripts bucket must have at least one object")
                .isNotEmpty();
        assertThat(xmlObjects.contents().get(0).size())
                .as("Sealed XML object must not be empty")
                .isGreaterThan(0);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private String base(String service, int port) {
        return "http://" + ENV.getServiceHost(service, port)
                + ":" + ENV.getServicePort(service, port);
    }

    private BatchDetail getBatchDetail(String orchestratorBase, String batchId) throws Exception {
        HttpResponse<String> r = HTTP.send(
                HttpRequest.newBuilder()
                        .uri(URI.create(orchestratorBase + "/api/v1/batches/" + batchId))
                        .header("X-API-Key", API_KEY)
                        .GET()
                        .build(),
                HttpResponse.BodyHandlers.ofString());
        assertThat(r.statusCode()).isEqualTo(200);
        return MAPPER.readValue(r.body(), BatchDetail.class);
    }
}
