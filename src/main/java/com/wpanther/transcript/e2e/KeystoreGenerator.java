package com.wpanther.transcript.e2e;

import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

import javax.security.auth.x500.X500Principal;
import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.*;
import java.security.cert.X509Certificate;
import java.util.Calendar;
import java.util.Date;

/**
 * Generates 3 RSA-2048 BCFKS keystores for the CSC signer. Two callers:
 * scripts/gen-keystores.sh (via `mvn test-compile exec:java`, local dev/IT
 * paths — output goes to the relative default) and the keystore-init image
 * (this class as ENTRYPOINT, output directory set via KEYSTORE_OUTPUT_DIR
 * to /out, a mounted named volume). Skips files that already exist
 * (idempotent) so a restart within one `up` lifecycle is a no-op.
 */
public class KeystoreGenerator {

    public static void main(String[] args) throws Exception {
        Security.insertProviderAt(new BouncyCastleFipsProvider(), 1);

        Path keystoresDir = Path.of(
                System.getenv().getOrDefault("KEYSTORE_OUTPUT_DIR", "infra/csc/keystores"));
        Files.createDirectories(keystoresDir);

        generate(keystoresDir.resolve("registrar.bfks"), "e2e-registrar-2024");
        generate(keystoresDir.resolve("dean.bfks"),      "e2e-dean-2024");
        generate(keystoresDir.resolve("seal.bfks"),      "e2e-seal-2024");

        System.out.println("Done. Keystores in " + keystoresDir.toAbsolutePath());
    }

    private static void generate(Path path, String password) throws Exception {
        if (Files.exists(path)) {
            System.out.println("Skip (exists): " + path);
            return;
        }

        KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA", "BCFIPS");
        kpg.initialize(2048);
        KeyPair kp = kpg.generateKeyPair();
        X509Certificate cert = selfSigned(kp);

        KeyStore ks = KeyStore.getInstance("BCFKS", "BCFIPS");
        ks.load(null, null);
        ks.setKeyEntry("signing-key", kp.getPrivate(), password.toCharArray(),
                new java.security.cert.Certificate[]{cert});

        try (var out = Files.newOutputStream(path)) {
            ks.store(out, password.toCharArray());
        }
        System.out.println("Generated: " + path);
    }

    private static X509Certificate selfSigned(KeyPair kp) throws Exception {
        X500Principal subject = new X500Principal("CN=E2E Test Signing Key");
        Date notBefore = new Date();
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.YEAR, 10);
        Date notAfter = cal.getTime();

        JcaX509v3CertificateBuilder builder = new JcaX509v3CertificateBuilder(
                subject, BigInteger.ONE, notBefore, notAfter, subject, kp.getPublic());

        ContentSigner signer = new JcaContentSignerBuilder("SHA256WithRSA")
                .setProvider("BCFIPS")
                .build(kp.getPrivate());

        X509CertificateHolder holder = builder.build(signer);
        return new JcaX509CertificateConverter().setProvider("BCFIPS").getCertificate(holder);
    }
}
