part of protoc_builder;

class ManifestGenerator {
  final Uri templateRoot;
  final Map<String,String> sourceMap;

  MappedOutputConfiguration get outputConfiguration =>
      new MappedOutputConfiguration(sourceMap);

  ManifestGenerator(Map<String,String> this.sourceMap, {Uri templateRoot}):
      this.templateRoot = (templateRoot != null) ? templateRoot : Uri.parse('proto');

  String _libraryRootName(String sourcePath) {
    var builder = path.url;
    if ('$sourcePath' == '.') {
      //If the templates are in the root of the directory, name the library 'messages'.
      return 'messages';
    }
    return sourcePath.replaceAll(builder.separator, '_');
  }

  String manifestLibraryName(String sourceDir) {
     return _libraryRootName(sourceDir) + '_proto';
  }

  Uri manifestLibraryPath(String sourceDir) {
    var targetDir = sourceMap[sourceDir];
    var builder = path.url;
    return builder.toUri(builder.join(
        builder.fromUri(targetDir),
        '${_libraryRootName(sourceDir)}.pbmanifest.dart'
    ));
  }

  Iterable<Uri> _listSourceDir(String sourcePath) {
    var pathBuilder = path.url;
    var rootPath = pathBuilder.fromUri(templateRoot);
    var sourceDir = new Directory(pathBuilder.join(rootPath, sourcePath));
    return sourceDir.listSync(recursive: true)
        .where((entry) {
          return entry is File &&
                 pathBuilder.extension(entry.path) == Builder.PROTO_EXTENSION &&
                 !entry.path.contains('packages');
         })
         .map((entry) => pathBuilder.toUri(pathBuilder.relative(entry.path, from: rootPath)));
  }

  Iterable<Uri> exportedPaths(String sourcePath) {
    var builder = path.url;
    var targetDirPath = builder.fromUri(sourceMap[sourcePath]);

    return _listSourceDir(sourcePath)
        .where((path) => outputConfiguration.mostSpecificMappedSource(path) == new Uri.file(sourcePath))
        .map((path) => outputConfiguration.outputPathFor(path))
        .map((path) => builder.toUri(
            builder.relative(builder.fromUri(path), from: targetDirPath)
        ));
  }

  bool manifestChanged(String sourcePath, Iterable<Uri> modifiedFiles) {
    var pathBuilder = path.url;
    return modifiedFiles.fold(
        false,
        (manifestChanged, uri) =>
            manifestChanged || pathBuilder.isWithin(sourcePath, pathBuilder.fromUri(uri))
    );
  }

  /**
   * Regenerate any manifests where one of [:modifiedFiles:] has been either
   * changed or removed
   */
  Future generate(Set<Uri> modifiedFiles) {
    return forEachAsync(sourceMap.keys, (sourcePath) {
      var builder = path.url;
      if (!manifestChanged(sourcePath, modifiedFiles)) {
        return new Future.value();
      }
      var manifestPath = manifestLibraryPath(sourcePath);
      var fileWriter = new FileWriter(manifestPath);
      generateManifestFile(new IndentingWriter('  ', fileWriter), sourcePath);
      return fileWriter.toFile();
    },
    maxTasks: 5);
  }

  void generateManifestFile(IndentingWriter out, String sourcePath) {
    out.println(
        '///\n'
        '//  Generated code. Do not modify.\n'
        '///\n'
        '\n'
        'library ${manifestLibraryName(sourcePath)};\n'
    );
    var targetDir = sourceMap[sourcePath];

    for (var path in exportedPaths(sourcePath)) {
      out.println("export '$path';");
    }
    out.println();
  }
}