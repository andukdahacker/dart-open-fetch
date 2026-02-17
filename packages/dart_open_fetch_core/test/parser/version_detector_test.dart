import 'package:dart_open_fetch_core/src/parser/version_detector.dart';
import 'package:test/test.dart';

void main() {
  group('VersionDetector', () {
    final detector = VersionDetector();

    test('detects 3.0.x', () {
      expect(
        detector.detect({'openapi': '3.0.3'}),
        OpenApiVersion.v3_0,
      );
    });

    test('detects 3.1.x', () {
      expect(
        detector.detect({'openapi': '3.1.0'}),
        OpenApiVersion.v3_1,
      );
    });

    test('normalizes 3.1 type array [string, null] to nullable string', () {
      final schema = <String, dynamic>{
        'openapi': '3.1.0',
        'components': {
          'schemas': {
            'Test': {
              'type': ['string', 'null'],
            },
          },
        },
      };

      detector.normalize(schema, OpenApiVersion.v3_1);

      final testSchema =
          (schema['components'] as Map)['schemas']['Test'] as Map;
      expect(testSchema['type'], 'string');
      expect(testSchema['nullable'], true);
    });

    test('normalizes 3.1 multi-type [string, integer] to oneOf', () {
      final schema = <String, dynamic>{
        'openapi': '3.1.0',
        'components': {
          'schemas': {
            'Test': {
              'type': ['string', 'integer'],
            },
          },
        },
      };

      detector.normalize(schema, OpenApiVersion.v3_1);

      final testSchema =
          (schema['components'] as Map)['schemas']['Test'] as Map;
      expect(testSchema.containsKey('type'), false);
      expect(testSchema['oneOf'], isA<List>());
      expect((testSchema['oneOf'] as List).length, 2);
    });

    test('normalizes 3.1 [T1, T2, null] to oneOf + nullable', () {
      final schema = <String, dynamic>{
        'openapi': '3.1.0',
        'components': {
          'schemas': {
            'Test': {
              'type': ['string', 'integer', 'null'],
            },
          },
        },
      };

      detector.normalize(schema, OpenApiVersion.v3_1);

      final testSchema =
          (schema['components'] as Map)['schemas']['Test'] as Map;
      expect(testSchema['nullable'], true);
      expect(testSchema['oneOf'], isA<List>());
      expect((testSchema['oneOf'] as List).length, 2);
    });

    test('does not modify 3.0 schemas', () {
      final schema = <String, dynamic>{
        'openapi': '3.0.3',
        'components': {
          'schemas': {
            'Test': {
              'type': 'string',
              'nullable': true,
            },
          },
        },
      };

      detector.normalize(schema, OpenApiVersion.v3_0);

      final testSchema =
          (schema['components'] as Map)['schemas']['Test'] as Map;
      expect(testSchema['type'], 'string');
      expect(testSchema['nullable'], true);
    });
  });
}
