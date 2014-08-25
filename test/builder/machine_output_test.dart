

import 'package:unittest/unittest.dart';

import 'package:protoc_plugin/protoc_builder.dart';

void main() {
  group('machine output', () {
    MachineOutput machineOut;

    setUp(() {
      machineOut = new MachineOutput(null, null);
    });

    test('should generate an appropriate list of machine messages for a compiler error', () {
      var compilerError = new CompilerError("""
core/utils.proto:25:28: Reached end of input in message definition (missing '}').
core/price.proto: Import "core/utils.proto" was not found or had errors""");

      expect(machineOut.parseCompilerError(compilerError),
          [ { 'method': 'error',
              'params': {
                  'file': 'core/utils.proto', 'line': 25,
                  'message': "Reached end of input in message definition (missing '}')."
              }
            },
            { 'method': 'error',
              'params': {
                  'file': 'core/price.proto',
                  'line': 1,
                  'message': 'Import "core/utils.proto" was not found or had errors'
              }
            } ]
      );
    });
  });
}