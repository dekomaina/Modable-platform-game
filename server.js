import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import fetch from "node-fetch";
import { Client, AccountId, PrivateKey, Hbar, TransferTransaction } from "@hashgraph/sdk";

dotenv.config();
const app = express();
app.use(cors());
app.use(express.json());

const operatorId = AccountId.fromString(process.env.OPERATOR_ID);
const operatorKey = PrivateKey.fromString(process.env.OPERATOR_KEY);
const network = (process.env.NETWORK || "testnet").toLowerCase();
const client = (network === "mainnet" ? Client.forMainnet() : Client.forTestnet()).setOperator(operatorId, operatorKey);

// Health check
app.get("/", (_req, res) => res.json({ ok: true, network }));

// Convert POINTS -> HBAR
// body: { playerId, points, wallet, rate }
app.post("/api/convert", async (req, res) => {
  try {
    const { playerId, points, wallet, rate } = req.body || {};
    if (!wallet || points == null || !rate) {
      return res.status(400).json({ error: "Missing wallet/points/rate" });
    }
    const hbarAmount = Number(points) / Number(rate);
    if (hbarAmount <= 0) return res.status(400).json({ error: "Zero or negative amount" });

    const tx = await new TransferTransaction()
      .addHbarTransfer(operatorId, new Hbar(-hbarAmount))
      .addHbarTransfer(wallet, new Hbar(hbarAmount))
      .execute(client);

    const rx = await tx.getReceipt(client);
    return res.json({
      status: "success",
      playerId,
      points,
      hbarAmount,
      transactionId: tx.transactionId.toString(),
      consensusStatus: rx.status.toString()
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: String(e) });
  }
});

// Redeem "bars" -> HBAR
// body: { wallet, bars }
const HBAR_PER_BAR = Number(process.env.HBAR_PER_BAR || 0.1);
app.post("/api/redeem", async (req, res) => {
  try {
    const { wallet, bars } = req.body || {};
    if (!wallet || bars == null) return res.status(400).json({ error: "Missing wallet/bars" });
    const hbarAmount = Number(bars) * HBAR_PER_BAR;
    if (hbarAmount <= 0) return res.status(400).json({ error: "Zero or negative amount" });

    const tx = await new TransferTransaction()
      .addHbarTransfer(operatorId, new Hbar(-hbarAmount))
      .addHbarTransfer(wallet, new Hbar(hbarAmount))
      .execute(client);

    const rx = await tx.getReceipt(client);
    return res.json({
      status: "success",
      barsSpent: Number(bars),
      hbarAmount,
      transactionId: tx.transactionId.toString(),
      consensusStatus: rx.status.toString()
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: String(e) });
  }
});

// Get HBAR balance via Mirror Node
app.get("/api/balance/:accountId", async (req, res) => {
  try {
    const { accountId } = req.params;
    const r = await fetch(`https://${network}.mirrornode.hedera.com/api/v1/accounts/${accountId}`);
    const j = await r.json();
    return res.json(j);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: String(e) });
  }
});

const PORT = Number(process.env.PORT || 5000);
app.listen(PORT, () => console.log(`✅ Hedera backend listening on :${PORT} (${network})`));
