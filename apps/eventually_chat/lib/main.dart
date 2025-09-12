import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/name_input_screen.dart';
import 'services/chat_service.dart';

void main() {
  runApp(const EventuallyChatApp());
}

class EventuallyChatApp extends StatelessWidget {
  const EventuallyChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ChatService(),
      child: MaterialApp(
        title: 'Eventually Chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ),
        home: const NameInputScreen(),
      ),
    );
  }
}
