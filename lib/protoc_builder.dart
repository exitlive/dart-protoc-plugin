library protoc_builder;

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:io';

import 'package:quiver/async.dart';
import 'package:path/path.dart' as path;
import 'src/descriptor.pb.dart';
import 'protoc.dart';

part 'builder/build_args.dart';
part 'builder/builder.dart';
part 'builder/machine_output.dart';
part 'builder/manifest_generator.dart';

/**
 * Scans the [:templateRoot:] directory and compiles them to [:outDir:],
 * preserving the directory structure.
 *
 * [:pathToProtoc:] is the location of the [:protoc:] compiler on the filesystem.
 * In a unix environment, this can be left `null` to scan the user's `$PATH` for
 * the `protoc` executable. It must be provided in a windows environment.
 *
 * [:fieldNameOverrides:] is a map of fields names to override when generating
 * the protobuffer messages. See `README.md` for more information.
 *
 * [:buildArgs:] is a list of arguments that would be passed
 * to `build.dart` by the editor. The accepted arguments that
 * can be passed in via this method are:
 *   `--changed=<file>`: Recompile the file, if located within [:templateRoot:]
 *   `--clean`: clean the [:out:] directory
 *   `--full`: Clean [:out:] and recompile all files in the [:templateRoot:] directory
 *   `--machine`: Enables machine reporting of errors
 *   `--removed=<file>`: Remove any files generated from <file>
 */

Future build(String outDir,
             {String templateRoot: 'proto',
              String pathToProtoc: null,
              List<String> buildArgs: const ['--full'],
              Map<String,String> fieldNameOverrides: const {}
             }) {
  var sourceMap = { '.': outDir};
  return buildMapped(
      sourceMap,
      fieldNameOverrides: fieldNameOverrides,
      templateRoot: templateRoot,
      pathToProtoc: pathToProtoc,
      buildArgs: buildArgs
  );
}

/**
 * Compiles protobuffer files to the specified locations.
 *
 * [:sourceMap:] maps directories (expressed relative to [:templateRoot:]) to
 * output directories (expressed relative to the project root). When compiling
 * a protobuffer template, the file location will be mapped to the most specific
 * output directory which contains the file.
 *
 * The key '.' in the source map represents the [:templateRoot:] directory.
 * Other than a single key '.', it is an error if a source contains either '.'
 * or '..' in the path.
 *
 * A `*.pbmanifest.dart` library, which reexports all files located under the
 * key is written for each key in the map.
 *
 * [:templateRoot:] is a directory (specified relative to the project root) which
 * contains the protobuffer templates. Defaults to `proto/`.
 *
 * eg. With a directory structure
 *
 *      /
 *      |- lib
 *      |  |- core
 *      |  |  `- messages
 *      |  |- services
 *      |  `- proto
 *      |- proto
 *      |  |- core
 *      |  |- services
 *      |  | |- messages
 *      |  | `- messages_base
 *      |  `-test
 *      `- test
 *          `- messages
 *
 * And a source Map
 *      { '.': 'lib/proto',
 *        'core': 'lib/core/messages',
 *        'services': 'lib/services/messages',
 *        'services/base': 'lib/services/messages_base'
 *        'test' : 'test/messages'
 *      }
 *
 * The following mappings would hold
 *      'proto/file.proto' -> 'lib/proto/file.proto'
 *      'core/file.proto' -> 'lib/core/messages/file.proto'
 *      'services/file.proto' -> 'lib/services/messages/file.proto'
 *      'services/base/file.proto' -> 'lib/services/messages_base/file.proto'
 *      'test/file.proto' -> 'test/messages/file.proto'
 *
 * [:pathToProtoc:] is the location of the [:protoc:] compiler on the filesystem.
 * In a unix environment, this can be left `null` to scan the user's `$PATH` for
 * the `protoc` executable. It must be provided in a windows environment.
 *
 * [:fieldNameOverrides:] is a map of fields names to override when generating
 * the protobuffer messages. See `README.md` for more information.
 *
 * [:buildArgs:] is a list of arguments that would be passed
 * to `build.dart` by the editor. The accepted arguments that
 * can be passed in via this method are:
 *   `--changed=<file>`: Recompile the file, if located within [:templateRoot:]
 *   `--clean`: clean the [:out:] directory
 *   `--full`: Clean [:out:] and recompile all files in the [:templateRoot:] directory
 *   `--machine`: Enables machine reporting of errors
 *   `--removed=<file>`: Remove any files generated from <file>
 */
Future buildMapped(Map<String,String> sourceMap,
                   {  String templateRoot: 'proto',
                      String pathToProtoc: null,
                     List<String> buildArgs: const ['--full'],
                     Map<String,String> fieldNameOverrides: const {}}) {
  return new Future.sync(() {
    if (pathToProtoc == null) {
      pathToProtoc = _getProtocFromPath();
    }
    var args = BuildArgs.parse(buildArgs);
    var options = new GenerationOptions(fieldNameOverrides);

    var pathBuilder = path.url;
    var rootUri = pathBuilder.toUri(templateRoot);

    var builder = new Builder(
        rootUri,
        sourceMap,
        args,
        pathToProtoc,
        options: options
    );
    return builder.build();
  });
}

class CompilerError extends Error {
  final String message;

  CompilerError(this.message);

  toString() => 'CompilerError: $message';
}

String _getProtocFromPath() {
  //TODO: Support windows.
  var sysPath = Platform.environment['PATH'].split(':');
  for (var elem in sysPath.where((elem) => elem != '')) {
    var dir = new Directory(elem);
    var protoc = dir.listSync()
        .firstWhere(
            (entry) => entry is File && path.basename(entry.path) == 'protoc',
            orElse: () => null
        );
    if (protoc != null) {
      return protoc.path;
    }
  }
  throw 'protoc not found on \$PATH';

}

Map<Uri,Uri> _toUriMap(Map<String,String> sourceMap) {
  var pathBuilder = path.url;
  var uriMap = <Uri,Uri>{};
  sourceMap.forEach((k,v) {
    if (k != '.' && k.contains('.')) {
      throw 'Only template root key in sourceMap can contain a \'.\' ($k)';
    }
    uriMap[pathBuilder.toUri(k)] = pathBuilder.toUri(sourceMap[k]);
  });
  return uriMap;
}

_forEachAsync(Iterable iterable, Future action(dynamic value)) {
  if (iterable.isEmpty) return new Future.value();
  return forEachAsync(iterable, action);
}
