import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/name_input_screen.dart';
import 'services/eventually_chat_service.dart';
import 'services/modern_chat_service.dart';

void main() {
  // Set to true to use the modern transport interface
  // Set to false to use the legacy transport interface
  const useModernTransport = true;

  print('🚀 Starting Eventually Chat');
  print('📡 Transport: ${useModernTransport ? 'Modern' : 'Legacy'}');

  runApp(EventuallyChatApp(useModernTransport: useModernTransport));
}

class EventuallyChatApp extends StatelessWidget {
  const EventuallyChatApp({super.key, required this.useModernTransport});

  final bool useModernTransport;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        if (useModernTransport) {
          print('✨ Creating ModernChatService with new Transport interface');
          return ModernChatService();
        } else {
          print('🔧 Creating EventuallyChatService with legacy interface');
          return EventuallyChatService();
        }
      },
      child: MaterialApp(
        title: useModernTransport
            ? 'Eventually Chat (Modern)'
            : 'Eventually Chat (Legacy)',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: useModernTransport ? Colors.deepPurple : Colors.blue,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: useModernTransport
                ? Colors.deepPurple
                : Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        home: const NameInputScreen(),
      ),
    );
  }
}
