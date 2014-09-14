part of protoc_builder;

/**
 * The standard arguments accepted by `build.dart`
 */
class BuildArgs {
  static final _changedPattern = new RegExp(r'--changed=(.*)$');
  static final _removedPattern = new RegExp(r'--removed=(.*)$');

  static BuildArgs parse(List<String> buildArgs) {
    BuildArgs args = new BuildArgs();

    if (buildArgs.any((arg) => arg.startsWith('--machine')))
        args.machineOut = true;

    if (buildArgs.any((arg) => arg.startsWith('--full'))) {
      args.full = true;
      return args;
    }

    if (buildArgs.any((arg) => arg.startsWith('--clean'))) {
      args.clean = true;
      return args;
    }

    for (var arg in buildArgs) {
      var changedMatch = _changedPattern.matchAsPrefix(arg);
      if (changedMatch != null) {
        args.changed.add(changedMatch.group(1));
      }
      var removedMatch = _changedPattern.matchAsPrefix(arg);
      if (removedMatch != null) {
        args.removed.add(removedMatch.group(1));
      }
    }

    return args;
  }

  final Set<String> removed = new Set<String>();
  final Set<String> changed = new Set<String>();

  bool clean = false;

  bool _full = false;
  bool get full => _full;
  set full(bool value) {
    if (value)
      clean = value;
    _full = value;
  }

  bool machineOut = false;
}

