# Hedera Backend (Express + @hashgraph/sdk)

## Setup
1) Install Node 18+
2) `npm install`
3) Copy `.env` from `.env.sample` and set your Testnet OPERATOR_ID and OPERATOR_KEY
4) `npm run dev`

## Routes
- `POST /api/convert` body `{ playerId, points, wallet, rate }`
- `POST /api/redeem` body `{ wallet, bars }`  (HBAR_PER_BAR controls conversion)
- `GET /api/balance/:accountId`

## Notes
- Keep the private key ONLY on the server.
- Start on Testnet, then switch `NETWORK=mainnet` after audits.
