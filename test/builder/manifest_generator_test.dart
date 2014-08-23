library manifest_generator_test;

import 'dart:io';

import 'package:unittest/unittest.dart';
import 'package:protoc_plugin/protoc.dart';
import 'package:protoc_plugin/protoc_builder.dart';

void main() {
  group('manifest generator', () {
    var manifestGen;
    var package1 = Uri.parse('protos');
    var package2 = Uri.parse('protos/google');

    setUp(() {
      bool isProjectRoot(Directory dir) =>
        dir.listSync()
            .any((entry) => entry.path.endsWith('pubspec.yaml'));

      while (!isProjectRoot(Directory.current)) {
        Directory.current = Directory.current.parent;
      }

      var sourceMap = <Uri,Uri>{}
          ..[package1] = Uri.parse('out/protos')
          ..[package2] = Uri.parse('out/protos/google');

      manifestGen = new ManifestGenerator(sourceMap,
          templateRoot: Uri.parse('test'));
    });

    test("should be able to build the manifest library name", () {
      expect(manifestGen.manifestLibraryName(package1), 'protos');
      expect(manifestGen.manifestLibraryName(package2), 'protos_google');
    });

    test("should be able to build the manifest library path", () {
      expect(
          manifestGen.manifestLibraryPath(package1),
          Uri.parse('out/protos/protos.pbmanifest.dart')
      );
      expect(
          manifestGen.manifestLibraryPath(package2),
          Uri.parse('out/protos/google/protos_google.pbmanifest.dart')
      );
    });

    test('should export paths which aren\'t in a more specific manifest file', () {
      expect(manifestGen.exportedPaths(package1).map((uri) => '$uri'), [
        'duplicate_names_import.pb.dart',
        'multiple_files_test.pb.dart',
        'nested_extension.pb.dart',
        'non_nested_extension.pb.dart',
        'package1.pb.dart',
        'package2.pb.dart',
        'package3.pb.dart',
        'reserved_names.pb.dart',
        'toplevel.pb.dart',
        'toplevel_import.pb.dart'
      ]);
    });

    test('should export recursively if there are files in a subdirectory which aren\'t in another manifest', () {
      expect(manifestGen.exportedPaths(package2).map((path) => '$path'), [
        'empty_file.pb.dart',
        'protobuf/unittest.pb.dart',
        'protobuf/unittest_import.pb.dart',
        'protobuf/unittest_optimize_for.pb.dart',
      ]);
    });

    test('should be able to generate a manifest file', () {
      var writer = new MemoryWriter();
      manifestGen.generateManifestFile(new IndentingWriter('  ', writer), package2);
      expect(writer.toString(), """
///
//  Generated code. Do not modify.
///

library protos_google;

export 'empty_file.pb.dart';
export 'protobuf/unittest.pb.dart';
export 'protobuf/unittest_import.pb.dart';
export 'protobuf/unittest_optimize_for.pb.dart';

""");

    });
  });



}