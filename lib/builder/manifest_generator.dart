part of protoc_builder;

class ManifestGenerator {
  final Uri templateRoot;
  final Map<Uri,Uri> sourceMap;

  MappedOutputConfiguration get outputConfiguration =>
      new MappedOutputConfiguration(sourceMap);

  ManifestGenerator(Map<Uri,Uri> this.sourceMap, {Uri templateRoot}):
      this.templateRoot = (templateRoot != null) ? templateRoot : Uri.parse('proto');

  String _libraryRootName(sourceDir) {
    var builder = path.url;
    var sourcePath = builder.fromUri(sourceDir);
    if ('$sourcePath' == '.') {
      //If the templates are in the root of the directory, name the library 'manifest'.
      return 'messages';
    }
    return sourcePath.replaceAll(builder.separator, '_');
  }

  String manifestLibraryName(Uri sourceDir) {
     return _libraryRootName(sourceDir) + '_proto';
  }

  Uri manifestLibraryPath(Uri sourceDir) {
    var targetDir = sourceMap[sourceDir];
    var builder = path.url;
    return builder.toUri(builder.join(
        builder.fromUri(targetDir),
        '${_libraryRootName(sourceDir)}.pbmanifest.dart'
    ));
  }

  Iterable<Uri> _listSourceDir(Uri sourceDir) {
    var builder = path.url;
    var rootPath = builder.fromUri(templateRoot);
    var sourcePath = builder.join(rootPath, builder.fromUri(sourceDir));
    return new Directory(sourcePath)
        .listSync(recursive: true)
        .where((entry) => entry is File)
        .where((entry) => !entry.path.contains('packages'))
        .where((entry) => path.extension(entry.path) == '.proto')
        .map((entry) => builder.toUri(builder.relative(entry.path, from: rootPath)));
  }

  Iterable<Uri> exportedPaths(Uri sourceDir) {
    var builder = path.url;
    var targetDirPath = builder.fromUri(sourceMap[sourceDir]);

    return _listSourceDir(sourceDir)
        .where((path) => outputConfiguration.mostSpecificMappedSource(path) == sourceDir)
        .map((path) => outputConfiguration.outputPathFor(path))
        .map((path) => builder.toUri(
            builder.relative(builder.fromUri(path), from: targetDirPath)
        ));
  }

  bool manifestChanged(Uri sourceDir, Iterable<Uri> modifiedFiles) {
    var builder = path.url;
    var sourcePath = builder.fromUri(sourceDir);
    return modifiedFiles
        .fold(false, (manifestChanged, uri) =>
            manifestChanged || builder.isWithin(sourcePath, builder.fromUri(uri)));
  }

  /**
   * Regenerate any manifests where one of [:modifiedFiles:] has been either
   * changed or removed
   */
  Future generate(Set<Uri> modifiedFiles) {
    return forEachAsync(sourceMap.keys, (sourceDir) {
      var builder = path.url;
      if (!manifestChanged(sourceDir, modifiedFiles)) {
        return new Future.value();
      }
      var manifestPath = manifestLibraryPath(sourceDir);
      print('Manifest path: $manifestPath');
      var fileWriter = new FileWriter(manifestPath);
      generateManifestFile(new IndentingWriter('  ', fileWriter), sourceDir);
      return fileWriter.toFile();
    },
    maxTasks: 5);
  }

  void generateManifestFile(IndentingWriter out, Uri sourceDir) {
    out.println(
        '///\n'
        '//  Generated code. Do not modify.\n'
        '///\n'
        '\n'
        'library ${manifestLibraryName(sourceDir)};\n'
    );
    var targetDir = sourceMap[sourceDir];

    for (var path in exportedPaths(sourceDir)) {
      out.println("export '$path';");
    }
    out.println();
  }
}