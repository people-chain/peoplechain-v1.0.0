import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'dart:async';
import 'peoplechain_core/peoplechain_core.dart';
import 'testing/web_test_mode.dart';
import 'testing/testing_dashboard_page.dart';

class HomePage extends StatefulWidget {
  final PeopleChainNode node;
  HomePage({super.key, PeopleChainNode? node}) : node = node ?? PeopleChainNode();

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final PeopleChainNode _node;
  final _peerEdKeyCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _offerOutCtrl = TextEditingController();
  final _offerInCtrl = TextEditingController();
  final _answerInCtrl = TextEditingController();
  StreamSubscription? _txSub;
  StreamSubscription? _openSub;
  StreamSubscription? _peerSub;
  StreamSubscription? _syncSub;
  NodeInfo? _info;
  List<TxModel> _conversation = const [];
  bool _transportOpen = false;
  List<PeerRecord> _peers = const [];
  SyncState? _syncState;
  final Map<String, String> _resolvedTexts = {};
  Timer? _retryResolveTimer;

  @override
  void initState() {
    super.initState();
    _node = widget.node;
    _startAfterInit();
  }

  Future<void> _startAfterInit() async {
    final info = await _node.getNodeInfo();
    setState(() => _info = info);
    // Initialize transport status and subscribe to open events
    setState(() => _transportOpen = _node.isTransportOpen);
    _openSub = _node.onTransportOpen().listen((_) {
      if (mounted) setState(() => _transportOpen = true);
    });
    _syncSub = _node.onSyncState().listen((s) {
      if (mounted) setState(() => _syncState = s);
    });
    // Seed and keep recent peers list updated
    try {
      final list = await _node.recentPeers(limit: 50);
      if (mounted) setState(() => _peers = list);
    } catch (_) {}
    _peerSub = _node.onPeerDiscovered().listen((_) async {
      try {
        final list = await _node.recentPeers(limit: 50);
        if (mounted) setState(() => _peers = list);
      } catch (_) {}
    });
    _txSub = _node.onTxReceived().listen((evt) async {
      final peer = _peerEdKeyCtrl.text.trim();
      if (peer.isEmpty) return;
      if (evt.tx.from == peer || evt.tx.to == peer) {
        final list = await _node.getMessages(withPubKey: peer, limit: 100);
        await _resolveTexts(list);
        if (mounted) setState(() => _conversation = list);
      }
    });
    // Periodically retry resolving any pending encrypted texts (chunks may arrive after the TX)
    _retryResolveTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (_conversation.isEmpty) return;
      bool changed = false;
      for (final tx in _conversation) {
        if (tx.payload.type == 'text' && tx.payload.text == null && tx.payload.chunkRef != null) {
          if (_resolvedTexts[tx.txId] == null) {
            final t = await _node.resolveText(tx);
            if (t != null) {
              _resolvedTexts[tx.txId] = t;
              changed = true;
            }
          }
        }
      }
      if (changed) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _openSub?.cancel();
    _peerSub?.cancel();
    _syncSub?.cancel();
    _retryResolveTimer?.cancel();
    _peerEdKeyCtrl.dispose();
    _messageCtrl.dispose();
    _offerOutCtrl.dispose();
    _offerInCtrl.dispose();
    _answerInCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    final peer = _peerEdKeyCtrl.text.trim();
    if (peer.isEmpty) return;
    final list = await _node.getMessages(withPubKey: peer, limit: 100);
    await _resolveTexts(list);
    setState(() => _conversation = list);
  }

  Future<void> _resolveTexts(List<TxModel> txs) async {
    for (final tx in txs) {
      if (tx.payload.type == 'text' && tx.payload.text == null && tx.payload.chunkRef != null) {
        final t = await _node.resolveText(tx);
        if (t != null) {
          _resolvedTexts[tx.txId] = t;
        }
      }
    }
  }

  Future<void> _sendText() async {
    final peer = _peerEdKeyCtrl.text.trim();
    final text = _messageCtrl.text.trim();
    if (peer.isEmpty || text.isEmpty) return;
    final res = await _node.sendMessage(toPubKey: peer, text: text);
    if (!mounted) return;
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: ${res.error}')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent')));
    }
    _messageCtrl.clear();
    await _loadConversation();
  }

  Widget _identityCard() {
    final keys = _info?.keys;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Node', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_info != null) ...[
              Text('Node ID: ${_info!.nodeId}', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('ed25519: ${keys!.ed25519}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text('x25519: ${keys.x25519}', style: Theme.of(context).textTheme.bodySmall),
            ] else ...[
              const Text('Initializing...'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _peerAndCompose() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _peerEdKeyCtrl,
              decoration: const InputDecoration(labelText: 'Peer ed25519 public key'),
              onSubmitted: (_) => _loadConversation(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    decoration: const InputDecoration(labelText: 'Type a message...'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sendText,
                  icon: const Icon(Icons.send, color: Colors.white),
                  label: const Text('Send', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _loadConversation,
                icon: const Icon(Icons.refresh, color: Colors.blue),
                label: const Text('Refresh'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationList() {
    final me = _info?.keys.ed25519;
    return ListView.separated(
      itemCount: _conversation.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final tx = _conversation[i];
        final mine = tx.from == me;
        final align = mine ? Alignment.centerRight : Alignment.centerLeft;
        final bg = mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface;
        final fg = mine ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface;
        String text;
        if (tx.payload.type == 'text') {
          text = tx.payload.text ?? _resolvedTexts[tx.txId] ?? (tx.payload.chunkRef != null ? 'Encrypted message' : '');
        } else {
          text = '[${tx.payload.type}] ${tx.payload.mime ?? ''}';
        }
        return Align(
          alignment: align,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: fg)),
                const SizedBox(height: 4),
                Text(
                  DateTime.fromMillisecondsSinceEpoch(tx.timestampMs).toLocal().toIso8601String(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _availablePeersCard() {
    if (_peers.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Available peers (recent)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._peers.take(10).map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline, color: Colors.blue),
                  title: Text(p.alias ?? p.nodeId, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(p.ed25519PubKey, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Wrap(spacing: 8, children: [
                    IconButton(
                      tooltip: 'Use key',
                      onPressed: () {
                        _peerEdKeyCtrl.text = p.ed25519PubKey;
                        _loadConversation();
                      },
                      icon: const Icon(Icons.input, color: Colors.blue),
                    ),
                    IconButton(
                      tooltip: 'Copy key',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: p.ed25519PubKey));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Peer key copied')));
                      },
                      icon: const Icon(Icons.copy, color: Colors.blue),
                    ),
                  ]),
                )),
          ],
        ),
      ),
    );
  }

  Widget _webrtcPanel() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WebRTC Manual Handshake', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _transportOpen
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(children: [
                    Icon(_transportOpen ? Icons.link : Icons.link_off,
                        color: _transportOpen
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurface,
                        size: 18),
                    const SizedBox(width: 6),
                    Text(_transportOpen ? 'Channel: Open' : 'Channel: Closed',
                        style: Theme.of(context).textTheme.labelSmall),
                  ]),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    final r = await _node.measureTransportRtt();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(r == null ? 'Ping timeout' : 'RTT: ${r.inMilliseconds} ms')),
                    );
                  },
                  icon: const Icon(Icons.speed, color: Colors.blue),
                  label: const Text('Test Ping'),
                ),
              ],
            ),
            const SizedBox(height: 8),
                Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: const StadiumBorder(),
                      splashFactory: NoSplash.splashFactory,
                    ),
                    onPressed: () async {
                      final payload = await _node.createOfferPayload();
                      _offerOutCtrl.text = payload;
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer created. Use "Copy Out" to share.')));
                      }
                    },
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Create Offer'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Connection state chips
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(children: [
                    Icon(
                      _syncState == SyncState.synced
                          ? Icons.cloud_done
                          : _syncState == SyncState.handshaking
                              ? Icons.cloud_sync
                              : Icons.cloud_queue,
                      color: Colors.blue,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _syncState == SyncState.synced
                          ? 'Synced'
                          : _syncState == SyncState.handshaking
                              ? 'Handshaking'
                              : 'Connecting',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _offerOutCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Offer/Answer (out)'),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    if (_offerOutCtrl.text.isEmpty) return;
                    try {
                      await Clipboard.setData(ClipboardData(text: _offerOutCtrl.text));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied out payload')));
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.copy, color: Colors.blue),
                  label: const Text('Copy Out'),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _offerInCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Offer (in)'),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final data = await Clipboard.getData('text/plain');
                      final txt = data?.text?.trim();
                      if (txt == null || txt.isEmpty) return;
                      _offerInCtrl.text = txt;
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer pasted into input')));
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Paste failed: $e')));
                    }
                  },
                  icon: const Icon(Icons.paste, color: Colors.blue),
                  label: const Text('Paste Offer'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (_offerInCtrl.text.trim().isEmpty) return;
                    try {
                      final ans = await _node.acceptOfferAndCreateAnswer(_offerInCtrl.text.trim());
                      _offerOutCtrl.text = ans;
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer accepted. Answer is ready in "Out" field.')));
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Accept offer failed: $e')));
                    }
                  },
                  icon: const Icon(Icons.download, color: Colors.blue),
                  label: const Text('Accept Offer'),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _answerInCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Answer (in)'),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final data = await Clipboard.getData('text/plain');
                      final txt = data?.text?.trim();
                      if (txt == null || txt.isEmpty) return;
                      _answerInCtrl.text = txt;
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Answer pasted into input')));
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Paste failed: $e')));
                    }
                  },
                  icon: const Icon(Icons.paste, color: Colors.blue),
                  label: const Text('Paste Answer'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (_answerInCtrl.text.trim().isEmpty) return;
                    try {
                      await _node.acceptAnswer(_answerInCtrl.text.trim());
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Answer accepted (or already applied)')));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to accept answer: $e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.upload, color: Colors.blue),
                  label: const Text('Accept Answer'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PeopleChain'),
        centerTitle: true,
        actions: [
          if (kIsWeb)
            IconButton(
              tooltip: 'Activate Web Test Mode',
              onPressed: () {
                WebTestMode.activate();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => TestingDashboardPage(node: _node)));
              },
              icon: const Icon(Icons.science, color: Colors.blue),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth >= 960;
            final maxContentWidth = 1400.0;
            if (isWide) {
              // Two-column adaptive layout; make the left column independently scrollable.
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _identityCard(),
                                const SizedBox(height: 8),
                                _webrtcPanel(),
                                const SizedBox(height: 8),
                                _availablePeersCard(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _peerAndCompose(),
                              const SizedBox(height: 8),
                              // Conversation fills remaining height and scrolls.
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _conversationList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Narrow layout: use a single scrollable viewport to prevent overflows.
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: CustomScrollView(
                  slivers: [
                    const SliverPadding(padding: EdgeInsets.all(12)),
                    SliverToBoxAdapter(child: _identityCard()),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(child: _peerAndCompose()),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    // Conversation list as a sliver for smooth, unified scrolling
                    SliverList.separated(
                      itemCount: _conversation.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final me = _info?.keys.ed25519;
                        final tx = _conversation[i];
                        final mine = tx.from == me;
                        final align = mine ? Alignment.centerRight : Alignment.centerLeft;
                        final bg = mine
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surface;
                        final fg = mine
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurface;
                        final text = tx.payload.type == 'text'
                            ? (tx.payload.text ?? _resolvedTexts[tx.txId] ?? (tx.payload.chunkRef != null ? 'Encrypted message' : ''))
                            : '[${tx.payload.type}] ${tx.payload.mime ?? ''}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Align(
                            alignment: align,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(text, style: TextStyle(color: fg)),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateTime.fromMillisecondsSinceEpoch(tx.timestampMs)
                                        .toLocal()
                                        .toIso8601String(),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: _webrtcPanel())),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: _availablePeersCard())),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
