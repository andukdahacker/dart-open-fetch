import 'package:flutter/material.dart';

import 'pet_list_page.dart';

void main() {
  runApp(const PetstoreApp());
}

class PetstoreApp extends StatelessWidget {
  const PetstoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Petstore Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const PetListPage(),
    );
  }
}
