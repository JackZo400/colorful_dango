import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:colorful_dango/p2p/connection_manager.dart';

void main() {
  test('P2P offer ↔ answer handshake', () async {
    final alice = P2PConnectionManager();
    final bob = P2PConnectionManager();

    // Track connection state
    bool aliceConnected = false, bobConnected = false;
    final aliceMessages = <Uint8List>[], bobMessages = <Uint8List>[];

    alice.onStateChanged = (s) { if (s == P2PConnectionState.connected) aliceConnected = true; };
    bob.onStateChanged = (s) { if (s == P2PConnectionState.connected) bobConnected = true; };
    alice.onMessageReceived = (d) => aliceMessages.add(d);
    bob.onMessageReceived = (d) => bobMessages.add(d);

    // Alice creates offer
    final offer = await alice.createOffer();
    print('[TEST] Offer created (${offer.length} chars)');

    // Bob creates answer
    final answer = await bob.createAnswer(offer);
    print('[TEST] Answer created (${answer.length} chars)');

    // Exchange
    await alice.setRemoteAnswer(answer);
    print('[TEST] Remote answer set on Alice');

    // Wait for connection
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (aliceConnected && bobConnected) break;
    }
    print('[TEST] Alice connected: $aliceConnected, Bob connected: $bobConnected');

    expect(aliceConnected, isTrue, reason: 'Alice should connect');
    expect(bobConnected, isTrue, reason: 'Bob should connect');

    // Send test message
    final msg = Uint8List.fromList(utf8.encode('hello'));
    alice.sendMessage(msg);
    await Future.delayed(const Duration(seconds: 1));
    print('[TEST] Bob received: ${bobMessages.length} messages');
    expect(bobMessages.length, greaterThan(0));

    await alice.dispose();
    await bob.dispose();
  });
}
