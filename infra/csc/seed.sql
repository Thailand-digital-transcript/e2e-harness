-- OAuth2 client used by transcript-signing to obtain access tokens.
INSERT INTO oauth2_clients
    (id, client_id, client_secret, client_name, active, created_at)
VALUES
    ('e2e-client-id',
     'e2e-client',
     '$2a$10$qGjGsqCPmbCUcjH5aNlwjeE1WTi8mRv0Mem4QPfdH7bIfbYH95xQC',
     'E2E Test Client',
     true,
     NOW());

-- oauth2_client_scopes.client_id is a FK to oauth2_clients(id) — use the PK 'e2e-client-id'.
INSERT INTO oauth2_client_scopes (client_id, scope)
VALUES ('e2e-client-id', 'signing');

-- oauth2_client_grant_types.client_id is a FK to oauth2_clients(id) — use the PK 'e2e-client-id'.
INSERT INTO oauth2_client_grant_types (client_id, grant_type)
VALUES ('e2e-client-id', 'client_credentials');

-- Three credentials, one per signer role.
-- signing_certificates.client_id is a FK to oauth2_clients(client_id) — use the unique key 'e2e-client'.
INSERT INTO signing_certificates
    (id, storage_type, certificate_alias, keystore_path, keystore_password,
     active, client_id, created_at)
VALUES
    ('e2e-registrar-cred', 'BCFKS', 'signing-key',
     '/app/keystores/registrar.bfks', 'e2e-registrar-2024',
     true, 'e2e-client', NOW()),
    ('e2e-dean-cred',      'BCFKS', 'signing-key',
     '/app/keystores/dean.bfks',      'e2e-dean-2024',
     true, 'e2e-client', NOW()),
    ('e2e-seal-cred',      'BCFKS', 'signing-key',
     '/app/keystores/seal.bfks',      'e2e-seal-2024',
     true, 'e2e-client', NOW());
