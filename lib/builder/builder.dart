part of protoc_builder;

class Builder extends ProtobufContainer {

  /// The standard file extension for protobuffer templates
  static const PROTO_EXTENSION = '.proto';

  /**
   * The directory which contains all the protobuffers.
   */
  final Uri templateRoot;
  /**
   * An absolutely specified directory under which all mapped sources
   * will be generated.
   */
  final String projectRoot;
  final BuildArgs buildArgs;
  final Map<String,String> sourceMap;

  final String pathToProtoc;

  final GenerationOptions options;
  OutputConfiguration get outputConfiguration =>
      new MappedOutputConfiguration(sourceMap, projectRoot: projectRoot);

  Builder(Uri this.templateRoot,
          Map<String,String> this.sourceMap,
          BuildArgs this.buildArgs,
          String this.pathToProtoc,
          { String this.projectRoot: null,
            this.options: const GenerationOptions(const <String,String>{})});

  Uri _relativeToTemplateRoot(String filePath) {
    var pathBuilder = path.url;
    var rootPath = pathBuilder.fromUri(templateRoot);
    return pathBuilder.toUri(pathBuilder.relative(filePath, from: rootPath));
  }

  bool _isProtobufferTemplate(String filePath) {
    var pathBuilder = path.url;
    var rootPath = pathBuilder.fromUri(templateRoot);
    return !filePath.contains('packages') &&
           path.extension(filePath) == PROTO_EXTENSION &&
           pathBuilder.isWithin(rootPath, filePath);
  }

  Set<Uri> _allProtobufferTemplates;
  Set<Uri> _changedTemplates;
  Set<Uri> _removedTemplates;
  Set<Uri> _modifiedTemplates;

  /// Returns all protobuffer files in the template directory as uris specified
  /// relative to the protobuffer root.
  Set<Uri> get allProtobufferTemplates {
    if (_allProtobufferTemplates == null) {
      var pathBuilder = path.url;
      var rootPath = pathBuilder.fromUri(templateRoot);
      _allProtobufferTemplates = new Directory(rootPath).listSync(recursive: true)
          .where((entry) => _isProtobufferTemplate(entry.path))
          .map((entry) => _relativeToTemplateRoot(entry.path))
          .toSet();
    }
    return _allProtobufferTemplates;
  }


  Set<Uri> get changedTemplates {
    if (_changedTemplates == null) {
      var builder = path.url;
      var rootPath = builder.fromUri(templateRoot);
      if (buildArgs.full || buildArgs.clean) {
        _changedTemplates = allProtobufferTemplates;
      } else {
        _changedTemplates = buildArgs.changed
            .where(_isProtobufferTemplate)
            .map(_relativeToTemplateRoot)
            .toSet();
      }
    }
    return _changedTemplates;
  }

  Iterable<Uri> get removedTemplates {
    if (_removedTemplates == null) {
      var builder = path.url;
      var rootPath = builder.fromUri(templateRoot);

      if (buildArgs.full || buildArgs.clean) {
        _removedTemplates = allProtobufferTemplates;
      } else {
        _removedTemplates = buildArgs.changed
            .where(_isProtobufferTemplate)
            .map(_relativeToTemplateRoot)
            .toSet();
      }
    }
    return _removedTemplates;
  }

  Set<Uri> get modifiedTemplates {
    if (_modifiedTemplates == null) {
      _modifiedTemplates = new Set()
          ..addAll(changedTemplates)
          ..addAll(removedTemplates);
    }
    return _modifiedTemplates;
  }

  Future build() {
    MachineOutput machineOutput = null;
    if (buildArgs.machineOut) {
      machineOutput = new MachineOutput(templateRoot, outputConfiguration);
    }

    return deleteRemovedFiles(removedTemplates)
        .then((_) => runProtocCompiler(changedTemplates)
                     .then((descriptorSet) => compileChangedFiles(descriptorSet, changedTemplates)
        ))
        .then((_) => generateManifests(modifiedTemplates))
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
            for (var mapping in machineOutput.generateFileMappings(changedTemplates)) {
              print('[${JSON.encode(mapping)}]');
            }
          }
        });
  }


  Future deleteRemovedFiles(Iterable<Uri> removedFiles) {
    var builder = path.url;
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

  Future compileChangedFiles(FileDescriptorSet descriptorSet, Iterable<Uri> changedFiles) {
    var generationContext = new GenerationContext(options,outputConfiguration);
    var generators = <FileGenerator>[];
    for (var file in descriptorSet.file) {
      generators.add(new FileGenerator(file, this, generationContext));
    }

    return _forEachAsync(descriptorSet.file, (file) {
      var filePath = new Uri.file(file.name);
      if (!changedFiles.contains(filePath)) {
        //The file was just imported by one of the changed protobuffers.
        //It hasn't itself changed.
        return new Future.value();
      }
      var targetFile = outputConfiguration.outputPathFor(filePath);
      var fileGen = generationContext.lookupFile(file.name);
      var writer = new FileWriter(
          outputConfiguration.outputPathFor(new Uri.file(file.name))
      );
      fileGen.generate(new IndentingWriter('  ', writer));

      return writer.toFile();
    });
  }

  Future<FileDescriptorSet> runProtocCompiler(Iterable<Uri> templatesToCompile) {
    if (templatesToCompile.isEmpty)
      return new Future.value(new FileDescriptorSet());
    //TODO: This should be directed to a temp file.
    var protocArgs = [
        '--descriptor_set_out=/dev/stdout',
        '--include_imports'
    ]..addAll(templatesToCompile.map((uri) => uri.toFilePath(windows: Platform.isWindows)));
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