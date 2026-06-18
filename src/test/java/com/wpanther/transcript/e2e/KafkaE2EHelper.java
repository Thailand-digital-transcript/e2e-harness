package com.wpanther.transcript.e2e;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.testcontainers.containers.Container.ExecResult;
import org.testcontainers.containers.ContainerState;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Base64;
import java.util.function.Predicate;

/**
 * Kafka producer + consumer for the e2e harness that drives the broker by
 * exec-ing the Kafka console tools <em>inside</em> the Kafka container, using
 * the broker's own {@code localhost:9092} listener.
 *
 * <p>Testcontainers' {@code ComposeContainer} runs in containerised mode (an
 * ambassador with ephemeral host ports), which cannot satisfy Kafka's
 * advertised-listener contract for a host-side client. Exec-ing in-container
 * side-steps host networking entirely: the test never opens a Kafka socket from
 * the host. Payloads are base64-encoded in Java and decoded in the container so
 * arbitrary JSON survives the shell intact.
 */
public class KafkaE2EHelper {

    private final ContainerState kafka;
    private final ObjectMapper mapper;

    public KafkaE2EHelper(ContainerState kafka, ObjectMapper mapper) {
        this.kafka  = kafka;
        this.mapper = mapper;
    }

    /** Serialize {@code payload} to JSON and produce one record to {@code topic}. */
    public void send(String topic, String key, Object payload) {
        try {
            String json = mapper.writeValueAsString(payload);
            // Append a newline so kafka-console-producer flushes the record, then
            // base64 the lot to keep the shell away from the JSON's quotes.
            String b64 = Base64.getEncoder()
                    .encodeToString((json + "\n").getBytes(StandardCharsets.UTF_8));
            String cmd = "echo " + b64 + " | base64 -d | "
                    + "kafka-console-producer --bootstrap-server localhost:9092 --topic " + topic;
            ExecResult r = kafka.execInContainer("/bin/sh", "-c", cmd);
            if (r.getExitCode() != 0) {
                throw new RuntimeException("Kafka produce to " + topic + " failed (exit "
                        + r.getExitCode() + "): " + r.getStderr());
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException("Kafka send failed on topic " + topic, e);
        }
    }

    /**
     * Consume {@code topic} from the beginning (waiting up to {@code timeout} for
     * traffic) and return the first record deserialised to {@code type} that
     * matches {@code predicate}, or throw on timeout.
     */
    public <T> T pollFor(String topic, Class<T> type, Predicate<T> predicate, Duration timeout) {
        try {
            String cmd = "kafka-console-consumer --bootstrap-server localhost:9092 --topic " + topic
                    + " --from-beginning --timeout-ms " + timeout.toMillis();
            // console-consumer exits non-zero when --timeout-ms elapses; the
            // consumed values are still on stdout, so don't gate on the exit code.
            ExecResult r = kafka.execInContainer("/bin/sh", "-c", cmd);
            for (String line : r.getStdout().split("\n")) {
                if (line.isBlank()) continue;
                T msg = mapper.readValue(line, type);
                if (predicate.test(msg)) return msg;
            }
            throw new AssertionError("No matching message on " + topic + " within " + timeout
                    + " (consumed: " + r.getStdout().lines().count() + " records)");
        } catch (AssertionError e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
