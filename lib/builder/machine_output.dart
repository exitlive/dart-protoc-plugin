part of protoc_builder;

class MachineOutput {
  static final RegExp _COMPILER_ERROR =
      new RegExp(
          r'(.*?):([0-9]+:)?([0-9]+:)? (.*)$'
      );

  final Uri templateRoot;
  final OutputConfiguration outputConfiguration;

  MachineOutput(this.templateRoot, this.outputConfiguration);

  Uri fqFile(Uri uri) {
    var builder = path.url;
    return builder.toUri(builder.join(
        builder.fromUri(templateRoot),
        builder.fromUri(uri)
    ));
  }

  Iterable<Map<String,dynamic>> generateFileMappings(Iterable<Uri> changedFiles) {
    return changedFiles.map((file) {
      var target = outputConfiguration.outputPathFor(file);
      return {
          'method': 'mapping',
          'params': {
              'from': '${fqFile(file)}',
              'to': '$target'
          }
      };
    });
  }

  Iterable<Map<String,dynamic>> parseCompilerError(CompilerError compilerError) {
    var messages = compilerError.message.trim().split('\n');
    int msgNo = 0;
    return messages.map((message) {
      print('message number: ${++msgNo}');
      print(message);
      var match = _COMPILER_ERROR.matchAsPrefix(message);
      if (match == null) {
        print('No match: ($message)');
      }
      var filePath = new Uri.file(match.group(1));
      var rowNum = 1;
      if (match.group(2) != null) {
        var rowMatch = match.group(2);
        rowMatch = rowMatch.substring(0, rowMatch.indexOf(':'));
        rowNum = int.parse(rowMatch);
      }
      //Don't care about the column number (yet).
      //colNum = match.group(3);
      var errMsg = match.group(4);

      return {
          'method': 'error',
          'params': {
              'file': '${fqFile(filePath)}',
              'line': rowNum,
              'message' : errMsg
          }
      };
    });
  }

}