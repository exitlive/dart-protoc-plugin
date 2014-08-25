part of protoc_builder;

class Builder extends ProtobufContainer {

  final Uri templateRoot;
  final BuildArgs buildArgs;
  final Map<Uri,Uri> sourceMap;

  final String pathToProtoc;

  final GenerationOptions options;
  OutputConfiguration get outputConfiguration =>
      new MappedOutputConfiguration(sourceMap);

  Builder(Uri this.templateRoot,
          Map<Uri,Uri> this.sourceMap,
          BuildArgs this.buildArgs,
          String this.pathToProtoc,
         {this.options: const GenerationOptions(const <String,String>{})});

  Iterable<Uri> get changedFiles {
    var builder = path.url;
    var rootPath = builder.fromUri(templateRoot);
    var files;
    if (buildArgs.full) {
      files = new Directory(rootPath)
          .listSync(recursive: true)
          .where((entry) => entry is File &&
                            !entry.path.contains('packages') &&
                            path.extension(entry.path) == '.proto'
          ).map((entry) => entry.path);
    } else {
      files = buildArgs.changed
          .where((filePath) =>
              builder.isWithin(rootPath, filePath) &&
              path.extension(filePath) == '.proto'
      );
    }
    return files
        .map((f) => builder.toUri(builder.relative(f, from: rootPath)));
  }

  Iterable<Uri> get removedFiles {
    var builder = path.url;
    var rootPath = builder.fromUri(templateRoot);

    var files;
    if (buildArgs.full || buildArgs.clean) {
      files = new Directory(rootPath)
          .listSync(recursive: true)
          .where((entry) => entry is File &&
                            !entry.path.contains('packages') &&
                            path.extension(entry.path) == '.proto'
          ).map((entry) => entry.path);
    } else {
      files = buildArgs.removed
          .where((filePath) =>
              builder.isWithin(rootPath, filePath) &&
              path.extension(filePath) == '.proto');
    }
    return files
        .map((f) => builder.toUri(builder.relative(f, from: rootPath)));
  }

  Iterable<Uri> get modifiedFiles {
    return new Set()
        ..addAll(changedFiles)
        ..addAll(removedFiles);
  }

  Future build() {
    MachineOutput machineOutput = null;
    if (buildArgs.machineOut) {
      machineOutput = new MachineOutput(templateRoot, outputConfiguration);
    }

    print('Building');
    return deleteRemovedFiles(removedFiles)
        .then((_) => compileChangedFiles(changedFiles))
        .then((_) => generateManifests(modifiedFiles))
        .catchError((err, stackTrace) {
            if (machineOutput != null) {
              for (var compilerError in machineOutput.parseCompilerError(err)) {
                print('[${JSON.encode(compilerError)}]');
              }
            }
            throw err;
        }, test: (err) => err is CompilerError)
        .then((_) {
          if (machineOutput != null) {
            for (var mapping in machineOutput.generateFileMappings(changedFiles)) {
              print('[${JSON.encode(mapping)}]');
            }
          }
        });
  }


  Future deleteRemovedFiles(Iterable<Uri> removedFiles) {
    var builder = path.url;
    print('Removing files: $removedFiles');
    return _forEachAsync(removedFiles, (filePath) {
      var file = new File.fromUri(outputConfiguration.outputPathFor(filePath));
      if (!file.existsSync()) {
        return new Future.value();
      }
      return file.delete().then((file) {
        var isEmpty = file.parent.listSync().isEmpty;
        if (isEmpty) {
          return file.parent.delete();
        }
      });
    });
  }

  Future generateManifests(Set<Uri> modifiedFiles) {
    var manifestGenerator = new ManifestGenerator(sourceMap, templateRoot: templateRoot);
    return manifestGenerator.generate(modifiedFiles);
  }

  Future compileChangedFiles(Iterable<Uri> changedFiles) {
    var generationContext = new GenerationContext(options,outputConfiguration);
    return runProtocCompiler().then((FileDescriptorSet descriptorSet) {
      var generators = <FileGenerator>[];
      for (var file in descriptorSet.file) {
        generators.add(new FileGenerator(file, this, generationContext));
      }

      return forEachAsync(descriptorSet.file, (file) {
        var filePath = new Uri.file(file.name);
        if (!changedFiles.contains(filePath)) {
          //The file was just imported by one of the changed protobuffers.
          //It hasn't itself changed.
          return new Future.value();
        }
        var targetFile = outputConfiguration.outputPathFor(filePath);
        print('Writing $targetFile');
        var fileGen = generationContext.lookupFile(file.name);
        var writer = new FileWriter(
            outputConfiguration.outputPathFor(new Uri.file(file.name))
        );
        fileGen.generate(new IndentingWriter('  ', writer));

        return writer.toFile();
      });
    });
  }

  Future<FileDescriptorSet> runProtocCompiler() {
    var changedFiles = this.changedFiles;
    print('Changed: $changedFiles');
    if (changedFiles.isEmpty) {
      return new Future.value(new FileDescriptorSet());
    }
    //TODO: This should be directed to a temp file.
    var protocArgs = [
        '--descriptor_set_out=/dev/stdout',
        '--include_imports'
    ]..addAll(changedFiles.map((uri) => uri.toFilePath(windows: Platform.isWindows)));
    return Process.run(pathToProtoc, protocArgs,
        workingDirectory: templateRoot.toFilePath(windows: Platform.isWindows),
        stdoutEncoding: null
    ).then((result) {
      if (result.exitCode != 0)
        throw new CompilerError(result.stderr);
      return new FileDescriptorSet.fromBuffer(result.stdout);
    });
  }


  @override
  String get classname => null;

  @override
  String get fqname => '';

  @override
  String get package => '';
}