package com.wpanther.transcript.e2e;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;

import java.time.Duration;
import java.util.List;
import java.util.Properties;
import java.util.UUID;
import java.util.function.Predicate;

/**
 * Minimal Kafka producer + consumer for the e2e harness.
 * Constructed once per test class with the Testcontainers-mapped broker address.
 */
public class KafkaE2EHelper {

    private final String brokers;
    private final ObjectMapper mapper;

    public KafkaE2EHelper(String brokers, ObjectMapper mapper) {
        this.brokers = brokers;
        this.mapper  = mapper;
    }

    /** Serialize {@code payload} to JSON and send synchronously to {@code topic}. */
    public void send(String topic, String key, Object payload) {
        try (KafkaProducer<String, String> p = producer()) {
            p.send(new ProducerRecord<>(topic, key, mapper.writeValueAsString(payload))).get();
        } catch (Exception e) {
            throw new RuntimeException("Kafka send failed on topic " + topic, e);
        }
    }

    /**
     * Subscribe to {@code topic} with a unique group id and poll until a record
     * deserialised to {@code type} matches {@code predicate}, or throw on timeout.
     */
    public <T> T pollFor(String topic, Class<T> type, Predicate<T> predicate, Duration timeout) {
        String groupId = "e2e-" + UUID.randomUUID();
        try (KafkaConsumer<String, String> c = consumer(groupId)) {
            c.subscribe(List.of(topic));
            long deadline = System.currentTimeMillis() + timeout.toMillis();
            while (System.currentTimeMillis() < deadline) {
                for (var rec : c.poll(Duration.ofMillis(500))) {
                    T msg = mapper.readValue(rec.value(), type);
                    if (predicate.test(msg)) return msg;
                }
            }
            throw new AssertionError("No matching message on " + topic + " within " + timeout);
        } catch (AssertionError e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private KafkaProducer<String, String> producer() {
        Properties p = new Properties();
        p.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, brokers);
        p.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        p.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        return new KafkaProducer<>(p);
    }

    private KafkaConsumer<String, String> consumer(String groupId) {
        Properties p = new Properties();
        p.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, brokers);
        p.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        p.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        p.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        p.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        return new KafkaConsumer<>(p);
    }
}
