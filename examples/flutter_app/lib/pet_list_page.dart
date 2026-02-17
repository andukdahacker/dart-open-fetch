import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:flutter/material.dart';

import 'petstore/swagger_petstore_openapi_3_0.dart';
import 'src/http_client_adapter.dart';
import 'src/logging_middleware.dart';

class PetListPage extends StatefulWidget {
  const PetListPage({super.key});

  @override
  State<PetListPage> createState() => _PetListPageState();
}

class _PetListPageState extends State<PetListPage> {
  late final HttpClientAdapter _adapter;
  late final PetClient _petClient;

  List<Pet>? _pets;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _adapter = HttpClientAdapter();
    _petClient = PetClient(
      adapter: _adapter,
      middleware: [LoggingMiddleware()],
    );
    _loadPets();
  }

  Future<void> _loadPets() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _petClient.findPetsByStatus(status: 'available');
      setState(() {
        _pets = response.data;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = 'API error ${e.statusCode}: ${e.body}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _adapter.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Petstore')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPets,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final pets = _pets ?? [];
    return RefreshIndicator(
      onRefresh: _loadPets,
      child: ListView.builder(
        itemCount: pets.length,
        itemBuilder: (context, index) {
          final pet = pets[index];
          return ListTile(
            title: Text(pet.name),
            subtitle: Text(pet.status ?? 'unknown'),
            leading: CircleAvatar(child: Text('${pet.id ?? '?'}')),
          );
        },
      ),
    );
  }
}
