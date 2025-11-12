import 'dart:async';
import 'dart:convert';

/// Lightweight sync protocol messages exchanged over reliable data channels.
/// JSON envelope with type and payload for forward/backward compatibility.
class SyncMessage {
  final String type;
  final Map<String, dynamic> payload;
  final String? msgId; // optional, used for de-duplication

  SyncMessage({required this.type, required this.payload, this.msgId});

  Map<String, dynamic> toJson() => {
        'type': type,
        'payload': payload,
        if (msgId != null) 'msg_id': msgId,
      };

  factory SyncMessage.fromJson(Map<String, dynamic> map) =>
      SyncMessage(type: map['type'] as String, payload: (map['payload'] as Map).cast<String, dynamic>(), msgId: map['msg_id'] as String?);
}

/// Abstract transport used by SyncEngine so we can run tests without WebRTC.
abstract class SyncTransport {
  /// Emits decoded SyncMessage objects from the remote peer.
  Stream<SyncMessage> messages();

  /// Emits when the underlying transport is open and ready (e.g., data channel open).
  Stream<void> onOpen();

  /// Whether the transport is currently open.
  bool get isOpen;

  /// Sends a SyncMessage to the remote peer.
  Future<void> send(SyncMessage message);
}

/// A simple in-memory pipe transport for unit testing; links two endpoints.
class InMemoryPipeTransport implements SyncTransport {
  final StreamController<SyncMessage> _inCtrl = StreamController.broadcast();
  final StreamController<void> _openCtrl = StreamController.broadcast();
  late InMemoryPipeTransport _peer;
  bool _isOpen = false;

  InMemoryPipeTransport() {
    // Lazy; call open() to simulate channel ready
  }

  void linkPeer(InMemoryPipeTransport other) {
    _peer = other;
  }

  void open() {
    if (_isOpen) return;
    _isOpen = true;
    _openCtrl.add(null);
  }

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<SyncMessage> messages() => _inCtrl.stream;

  @override
  Stream<void> onOpen() => _openCtrl.stream;

  @override
  Future<void> send(SyncMessage message) async {
    if (!_isOpen) return;
    // Deliver to peer
    _peer._inCtrl.add(message);
  }
}
