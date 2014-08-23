library protoc_builder;

import 'dart:async';
import 'dart:io';

import 'package:quiver/async.dart';
import 'package:path/path.dart' as path;
import 'src/descriptor.pb.dart';
import 'protoc.dart';

part 'builder/build_args.dart';
part 'builder/builder.dart';
part 'builder/manifest_generator.dart';

var _pathToProtoc = null;

/**
 * The path to the [:protoc:] executable in the filesystem.
 * If not set in a `POSIX` environment, will scan the users
 * `$PATH` for the executable file.
 */
String get pathToProtoc {
  if (_pathToProtoc == null) {
    _pathToProtoc = _getProtocFromPath();
  }
  return _pathToProtoc;
}
void set pathToProtoc(String path) {
  _pathToProtoc = path;
}

/**
 * Scans the directory [:templateRoot:] for *.proto files.
 * For each files, generates the file corresponding to the
 * file in a file relative to the [:out:] directory.
 *
 * If [:manifestLib:] is provided and non-null a file will be generated in the
 * [:out:] directory which re-exports any libraries written to the [:out:]
 * directory.
 *
 * [:importPath:] is a list of directories in which protobuffers imported
 * by .proto files in [:templateOut:] can be located. All paths in the [:importPath:]
 * are expect to either be absolute paths, or specified relative to the root
 * of the project (the directory which contains the 'pubspec.yaml' file).
 *
 * [:fieldNameOverrides:] is a map of field names to replace in the generated
 * output. See `README.md` for more info.
 *
 * [:buildArgs:] is a list of arguments that would be passed
 * to `build.dart` by the editor. The accepted arguments that
 * can be passed in via this method are:
 *   `--changed=<file>`: Recompile the file, if located in [:templateRoot:]
 *   `--clean`: clean the [:out:] directory
 *   `--full`: Clean [:out:] and recompile all files in the [:templateRoot:] directory
 *   `--machine`: Enables machine reporting of errors
 *   `--removed=<file>`: Remove any files generated from <file>
 */
Future buildMapped(String templateRoot,
                   Map<String,String> sourceMap,
                   { List<String> buildArgs: const ['--full'] }) {
  return new Future.sync(() {
    var args = BuildArgs.parse(buildArgs);
    //TODO: Field name overrides.
    var options = new GenerationOptions(<String,String>{});
    var pathBuilder = path.url;
    var rootUri = pathBuilder.toUri(templateRoot);
    var sourceUriMap = new Map.fromIterable(
        sourceMap.keys,
        key: pathBuilder.toUri,
        value: (k) => pathBuilder.toUri(sourceMap[k])
    );
    var builder = new Builder(rootUri, sourceUriMap, args, options: options);
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

_forEachAsync(Iterable iterable, Future action(dynamic value)) {
  if (iterable.isEmpty) return new Future.value();
  return forEachAsync(iterable, action);
}
