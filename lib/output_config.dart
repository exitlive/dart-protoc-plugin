// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of protoc;

/// Configures where output of the protoc compiler should be placed and how to
/// import one generated file from another.
abstract class OutputConfiguration {

  /// Returns [filePath] with it's extension replaced with '.pb.dart'.
  String replacePathExtension(String filePath) =>
      '${path.withoutExtension(filePath)}.pb.dart';

  /// Returns [file] with it's extension replaced with '.pb.dart'.
  Uri replaceUriExtension(Uri file) =>
      path.url.toUri(replacePathExtension(path.url.fromUri(file)));

  /// Resolves an import URI. Both [source] and [target] are .proto files,
  /// where [target] is imported from [source]. The result URI can be used to
  /// import [target]'s .pb.dart output from [source]'s .pb.dart output.
  Uri resolveImport(Uri target, Uri source);

  /// Returns the path, under the output folder, where the code will be
  /// generated for [inputPath]. The input is expected to be a .proto file,
  /// while the output is expected to be a .pb.dart file.
  Uri outputPathFor(Uri inputPath);
}

/// Default [OutputConfiguration] that uses the same path as the input
/// file for the output file (just replaces the extension), and that uses
/// relative paths to resolve imports.
class DefaultOutputConfiguration extends OutputConfiguration {

  Uri outputPathFor(Uri input) => replaceUriExtension(input);

  Uri resolveImport(Uri target, Uri source) {
    var builder = path.url;
    var targetPath = builder.fromUri(target);
    var sourceDir = builder.dirname(builder.fromUri(source));
    return builder.toUri(replacePathExtension(
        builder.relative(targetPath, from: sourceDir)));
  }
}

/// A [SourceMap] output configuration maps protobuffer
class MappedOutputConfiguration extends OutputConfiguration {

  final String projectRoot;

  /// Map all protobuffer templates in a subdirectory of the protobuffer
  /// root to a specific directory.
  Map<String,String> sourceMap;

  MappedOutputConfiguration(this.sourceMap, {this.projectRoot: null});

  Uri _replaceMappedDirectory(String keyDir, Uri uri) {
    var builder = path.url;
    var filePath = builder.fromUri(uri);

    var mappedPath = sourceMap[keyDir];
    if (mappedPath == null) {
      throw 'Entry in source map cannot be `null`';
    }

    var targetPath = (projectRoot != null)
        ? path.join(projectRoot, mappedPath)
        : mappedPath;

    assert(builder.isWithin(keyDir, filePath));
    var relPath = builder.relative(filePath, from: keyDir);

    return builder.toUri(builder.join(targetPath, relPath));
  }

  Uri mostSpecificMappedSource(Uri uri) {
    var builder = path.url;
    var sourceDirPath;
    var filePath = builder.fromUri(uri);
    for (var key in sourceMap.keys) {
      if (builder.isWithin(key, filePath)) {
        if (sourceDirPath == null ||
            builder.isWithin(sourceDirPath, key))
          sourceDirPath = key;
      }
    }
    if (sourceDirPath == null)
      throw new ArgumentError('No mapped location for $uri');
    return builder.toUri(sourceDirPath);
  }

  /**
   * Returns the path, under the mapped output folder for the most specific
   * key which matches the uri path.
   *
   * Raises an exception if no mapping can be found for the uri.
   */
  Uri outputPathFor(Uri uri) {
    var sourceDir = mostSpecificMappedSource(uri);
    return replaceUriExtension(_replaceMappedDirectory(sourceDir.path, uri));
  }

  @override
  Uri resolveImport(Uri target, Uri source) {
    var builder = path.url;
    var sourceDir = builder.dirname(builder.fromUri(outputPathFor(source)));
    var targetPath = builder.fromUri(outputPathFor(target));
    return builder.toUri(
        builder.relative(targetPath, from: sourceDir)
    );
  }
}
