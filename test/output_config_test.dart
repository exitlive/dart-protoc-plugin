
import 'package:unittest/unittest.dart';

import 'package:protoc_plugin/protoc.dart';

void main() {
  group('mapped configuration', () {
    OutputConfiguration outputConfig;

    setUp(() {
      var sourceMap = new Map()
          ..[Uri.parse('f1/')] = Uri.parse('out/package1')
          ..[Uri.parse('f1/sf1/')] = Uri.parse('out/package1/subpackage1')
          ..[Uri.parse('f1/sf2/')] = Uri.parse('out/package2');


      outputConfig = new MappedOutputConfiguration(sourceMap);
    });

    test("should choose the most specific matching directory", () {
      expect(
          outputConfig.outputPathFor(Uri.parse('f1/file.proto')),
          Uri.parse('out/package1/file.pb.dart')
      );
      expect(
          outputConfig.outputPathFor(Uri.parse('f1/sf1/file.proto')),
          Uri.parse('out/package1/subpackage1/file.pb.dart')
      );

    });

    test("should fail if there is no output path for uri", () {
      expect(
          () => outputConfig.outputPathFor(Uri.parse('f2/file.proto')),
          throws
      );
    });

    test("should default to the value of the `'.'` key in the source map", () {
      (outputConfig as MappedOutputConfiguration)
          ..sourceMap[Uri.parse('.')] = Uri.parse('out/default_package');
      expect(
          outputConfig.outputPathFor(Uri.parse('f2/file.proto')).toString(),
          'out/default_package/f2/file.pb.dart'
      );
    });

    test("should resolve correct import path", () {
      var source = Uri.parse('f1/sf1/file1.proto');
      var target = Uri.parse('f1/sf2/file2.proto');
      expect(
          outputConfig.resolveImport(target, source),
          Uri.parse('../../package2/file2.pb.dart')
      );
    });


  });

}