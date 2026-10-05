import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/screens/chats/chats_page.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'package:bastion_meshtastic/services/messaging/chat_history.dart';

void main() {
  testWidgets('offline history stays usable and transmission stays disabled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final history = ChatHistory();
    await history.load();
    final session = RadioSession();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatsPage(
      session: session, history: history))));
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.text('Offline · saved history'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await history.saved;
    history.dispose();
    session.dispose();
  });
}
