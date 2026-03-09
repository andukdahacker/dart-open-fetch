import 'package:dart_console_example/petstore/swagger_petstore_openapi_3_0.dart';
import 'package:dart_console_example/src/logging_middleware.dart';
import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';

Future<void> main() async {
  // 1. Create the HTTP adapter and middleware.
  final adapter = HttpClientAdapter();
  final logging = LoggingMiddleware();

  // 2. Create the generated PetClient with middleware.
  final petClient = PetClient(
    adapter: adapter,
    middleware: [logging],
  );

  try {
    // 3. Find pets by status — returns a typed List<Pet>.
    print('=== Finding available pets ===');
    final available = await petClient.findPetsByStatus(status: 'available');
    final pets = available.data;
    print('Found ${pets.length} available pets');

    if (pets.isNotEmpty) {
      final first = pets.first;
      print('First pet: ${first.name} (id: ${first.id})');

      // 4. Get a single pet by ID — returns a typed Pet.
      print('\n=== Getting pet by ID ===');
      final detail = await petClient.getPetById(petId: first.id!);
      final pet = detail.data;
      print('Pet details:');
      print('  Name:     ${pet.name}');
      print('  Status:   ${pet.status}');
      print('  Category: ${pet.category?.name ?? 'none'}');
      print('  Tags:     ${pet.tags?.map((t) => t.name).join(', ') ?? 'none'}');
    }

    // 5. Demonstrate error handling with a non-existent pet.
    print('\n=== Error handling: non-existent pet ===');
    await petClient.getPetById(petId: -999999);
  } on ApiException catch (e) {
    print('ApiException: status ${e.statusCode}, body: ${e.body}');
  } finally {
    // 6. Clean up.
    adapter.close();
  }
}
