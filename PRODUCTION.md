# Production Hardening & Operational Guide

This document outlines recommended production practices for the Hedera NFT backend.

## Keys & Signing
- Never store private keys in plaintext on the server or source control.
- Use a **Hardware Security Module (HSM)** or cloud key management service (KMS):
  - AWS CloudHSM / AWS KMS with custom key stores
  - Google Cloud HSM / KMS
  - Azure Key Vault HSM
- Alternative: use a remote signing service. Construct and freeze transactions in the application, then forward the transaction bytes to the signer (HSM) for signing.

## Key Rotation
- Maintain a key rotation policy (e.g., rotate supplyKey every 6-12 months).
- When rotating supply/treasury keys, follow Hedera recommended steps: update keys in contract (token update) and coordinate with ops to avoid downtime.
- Keep audit logs of key usage and rotate API keys (nft.storage, mirror node access) regularly.

## Rate limiting & Abuse Prevention
- Protect `/mint` and other state-changing endpoints with:
  - Authentication (JWT / session tied to game account)
  - Rate limiting (per-IP and per-account)
  - CAPTCHA for public mint pages
  - Limits on metadata size and number of minted items per request
- Implement billing or payment checks if minting has cost.

## Metadata & IPFS
- Validate metadata JSON schema before pinning. Use Hedera HIP-412 / HIP-766 recommended fields.
- Keep metadata size small — avoid putting large binary data into metadata. Pin images separately and reference by `ipfs://CID`.
- Consider pinning to multiple providers (nft.storage + Pinata) for redundancy.

## Indexing & DB schema
- Mirror Node is the source of truth for on-chain events. Mirror Node REST API can be polled or use webhooks if available.
- Maintain a local DB (Postgres) for fast lookups and to serve game queries:
  - `accounts` table: id, hedera_account_id, user_id, created_at
  - `tokens` table: id, token_id, name, symbol, max_supply, metadata_uri, created_at
  - `nfts` table: id, token_id, serial, owner_account_id, metadata_uri, minted_at, transferred_at
  - `mint_events` table: id, token_id, serial, tx_id, metadata_uri, minted_by, timestamp

## Monitoring & Alerts
- Monitor node errors, failed transactions, and mirror node sync status.
- Alert on unusual mint volumes, repeated failures, or signature errors.

## Deployment
- Containerize the server (Docker) and deploy behind a load balancer.
- Use managed secrets (AWS Secrets Manager / HashiCorp Vault).
- Ensure containers run as non-root user and have minimal permissions.

## Backup & Recovery
- Regularly backup the DB and store backups encrypted.
- Have a disaster recovery plan for key compromise (revoke/rotate keys, notify users if necessary).

## Legal & Compliance
- Be aware of jurisdictional regulations concerning NFTs, virtual assets, and KYC/AML if you provide fiat on/off ramps.
