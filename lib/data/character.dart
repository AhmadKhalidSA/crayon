import 'dart:io';

import 'files.dart';

/// A named person/subject with one or more reference images. Generations can be
/// tagged with the characters they used, so a character's whole body of work is
/// browsable in one place, not just the flat gallery.
class Character {
  Character({
    required this.id,
    required this.name,
    this.coverPath,
    required this.createdAt,
    this.imagePaths = const [],
    this.genCount = 0,
    this.modelSheetPath,
    this.sheetPrompt,
  });

  final String id;
  final String name;
  final String? coverPath;
  final int createdAt;

  /// Reference images stored for this character (relative paths).
  final List<String> imagePaths;

  /// How many generations are tagged with this character (for the card).
  final int genCount;

  /// The baked 360 turnaround / model sheet (relative path). Once set,
  /// this single image is the cheap, consistent reference for new generations.
  final String? modelSheetPath;

  /// The last prompt used to bake this character's sheet (so a re-bake reuses it).
  final String? sheetPrompt;

  File? get cover => Files.fileFor(
      modelSheetPath ?? coverPath ?? (imagePaths.isNotEmpty ? imagePaths.first : null));

  File? get modelSheet => Files.fileFor(modelSheetPath);
  bool get hasSheet {
    final f = modelSheet;
    return f != null && f.existsSync();
  }

  List<File> get images => imagePaths
      .map(Files.fileFor)
      .whereType<File>()
      .where((f) => f.existsSync())
      .toList();

  Map<String, Object?> toRow() =>
      {'id': id, 'name': name, 'cover_path': coverPath, 'created_at': createdAt};

  factory Character.fromRow(Map<String, Object?> r,
          {List<String> imagePaths = const [], int genCount = 0}) =>
      Character(
        id: r['id'] as String,
        name: r['name'] as String? ?? '',
        coverPath: r['cover_path'] as String?,
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        imagePaths: imagePaths,
        genCount: genCount,
        modelSheetPath: r['model_sheet_path'] as String?,
        sheetPrompt: r['sheet_prompt'] as String?,
      );
}
