User Guide — Using PeopleChain

1. Starting the app
- On launch you’ll see the Startup screen showing each initialization step. Once complete you’ll arrive at the PeopleChain home.

2. Viewing your identity
- The “Your Node” card shows your Node ID and public keys (ed25519 and x25519). You use the ed25519 key as your public address when connecting to peers.

3. Connecting peers (manual WebRTC pairing)
- Create Offer: On device A, tap Create Offer and copy the output payload (or show as QR in your own UI). Send it to device B via any channel.
- Accept Offer: On device B, paste the Offer to Accept Offer. An Answer payload is generated. Send the Answer back to device A.
- Accept Answer: On device A, paste the Answer to Accept Answer. The data channel will open. The status chip shows “Channel: Open”.

4. Sending a message
- Paste or select the peer’s ed25519 public key in “Peer ed25519 public key”.
- Type a message and press Send. Messages appear in the conversation view; timestamps display in local time.

5. Monitoring and block explorer (Web)
- Click the beaker icon in the top app bar to open the Testing Dashboard. Tabs:
  - Peers: recently discovered peers with copy actions and a Details sheet
  - Chain: live tip/blocks/timeline plus a live Transactions feed
  - Explorer: paginated Blocks and Transactions, with search by height, block id, or tx id
  - API: exposes a postMessage API and a self‑test form

6. Backup and recovery (advanced)
- From the SDK: backupToShards(total, threshold) returns Shamir shares. Store them offline and separated. Any threshold subset can restoreFromShards(shards).

7. Privacy and safety
- Verify peer fingerprints (ed25519/x25519) during pairing to avoid man‑in‑the‑middle attacks.
- Media is chunk‑encrypted using AES‑GCM‑256 derived from x25519 shared secrets.
