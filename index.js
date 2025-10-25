require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const { Client, PrivateKey, TokenCreateTransaction, TokenMintTransaction, TokenType, TokenSupplyType, TransferTransaction } = require('@hashgraph/sdk');
const { NFTStorage, File } = require('nft.storage');
const fetch = require('node-fetch');

const app = express();
app.use(bodyParser.json({ limit: '15mb' }));

const HEDERA_NETWORK = process.env.HEDERA_NETWORK || 'testnet';
const OPERATOR_ID = process.env.OPERATOR_ID;
const OPERATOR_KEY = process.env.OPERATOR_KEY;
const NFT_STORAGE_KEY = process.env.NFT_STORAGE_KEY || '';

if (!OPERATOR_ID || !OPERATOR_KEY) {
  console.error('OPERATOR_ID and OPERATOR_KEY must be set in .env');
  process.exit(1);
}

const client = Client.forName(HEDERA_NETWORK);
client.setOperator(OPERATOR_ID, OPERATOR_KEY);

const nftStorage = NFT_STORAGE_KEY ? new NFTStorage({ token: NFT_STORAGE_KEY }) : null;

// Helper: pin image and metadata to nft.storage
async function pinImageAndJson(imageBase64, metadataObj) {
  if (!nftStorage) throw new Error('NFT_STORAGE_KEY not configured');
  const imgBuffer = Buffer.from(imageBase64, 'base64');
  const imageFile = new File([imgBuffer], `${metadataObj.name || 'image'}.png`, { type: 'image/png' });
  const imageCid = await nftStorage.storeBlob(imageFile);
  const imageUri = `ipfs://${imageCid}`;
  const fullMeta = { ...metadataObj, image: imageUri };
  const metaBlob = new File([Buffer.from(JSON.stringify(fullMeta))], 'metadata.json', { type: 'application/json' });
  const metaCid = await nftStorage.storeBlob(metaBlob);
  return { imageUri, metadataUri: `ipfs://${metaCid}` };
}

// Create a NON_FUNGIBLE_UNIQUE token (collection)
app.post('/create-collection', async (req, res) => {
  try {
    const { name, symbol, maxSupply = 0, memo = '' } = req.body;
    // Using operator key as supplyKey for simplicity. In prod, use HSM or a dedicated supply key.
    const supplyKey = PrivateKey.fromString(OPERATOR_KEY);

    const tx = await new TokenCreateTransaction()
      .setTokenName(name)
      .setTokenSymbol(symbol)
      .setTokenType(TokenType.NonFungibleUnique)
      .setTokenMemo(memo)
      .setTreasuryAccountId(OPERATOR_ID)
      .setInitialSupply(0)
      .setSupplyType(maxSupply > 0 ? TokenSupplyType.Finite : TokenSupplyType.Infinite)
      .setMaxSupply(maxSupply > 0 ? maxSupply : undefined)
      .setSupplyKey(supplyKey.publicKey)
      .execute(client);

    const receipt = await tx.getReceipt(client);
    const tokenId = receipt.tokenId.toString();
    res.json({ tokenId, receipt });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.toString() });
  }
});

// Check whether an account is associated with a token (mirror node)
app.post('/associate-check', async (req, res) => {
  try {
    const { accountId, tokenId } = req.body;
    if (!accountId || !tokenId) return res.status(400).json({ error: 'accountId and tokenId required' });

    const network = HEDERA_NETWORK === 'mainnet' ? 'mainnet-public' : 'testnet-public';
    const mirrorBase = `https://${network}.mirrornode.hedera.com/api/v1/accounts/${accountId}/tokens`;
    const r = await fetch(mirrorBase);
    const json = await r.json();
    const associated = (json.tokens || []).some(t => t.token_id === tokenId);
    res.json({ associated, tokens: json.tokens || [] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.toString() });
  }
});

// Mint one or multiple NFTs and transfer to recipient
app.post('/mint', async (req, res) => {
  try {
    const { tokenId, toAccountId, metadataJson, imageBase64 } = req.body;
    if (!tokenId || !toAccountId || !metadataJson) return res.status(400).json({ error: 'tokenId, toAccountId, metadataJson required' });

    let metadataUri;
    if (imageBase64) {
      const pinned = await pinImageAndJson(imageBase64, metadataJson);
      metadataUri = pinned.metadataUri;
    } else if (metadataJson.image && typeof metadataJson.image === 'string' && metadataJson.image.startsWith('ipfs://')) {
      metadataUri = JSON.stringify(metadataJson); // we'll send raw JSON if already contains ipfs URL
    } else {
      metadataUri = JSON.stringify(metadataJson);
    }

    // Hedera expects metadata as bytes per serial; we will send the metadataUri string bytes
    const metaBytes = Buffer.from(metadataUri);

    const mintTx = await new TokenMintTransaction()
      .setTokenId(tokenId)
      .setMetadata([metaBytes])
      .execute(client);

    const mintReceipt = await mintTx.getReceipt(client);
    const serials = mintReceipt.serials.map(s => s.toString());

    // Transfer the first serial to recipient (recipient must be associated already)
    const serialToTransfer = mintReceipt.serials[0];
    const transferTx = await new TransferTransaction()
      .addNftTransfer(tokenId, serialToTransfer, OPERATOR_ID, toAccountId)
      .execute(client);

    const transferReceipt = await transferTx.getReceipt(client);

    res.json({ mintedSerials: serials, metadataUri, transferTx: transferReceipt.transactionId.toString() });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.toString() });
  }
});

// Mirror node account proxy
app.get('/mirror/account/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const network = HEDERA_NETWORK === 'mainnet' ? 'mainnet-public' : 'testnet-public';
    const mirrorBase = `https://${network}.mirrornode.hedera.com/api/v1/accounts/${accountId}`;
    const r = await fetch(mirrorBase);
    const json = await r.json();
    res.json(json);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.toString() });
  }
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Hedera NFT backend running on ${PORT}`));
