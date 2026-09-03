import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'character.dart';
import 'gen_record.dart';

/// Local history. Every generation ever run lives here, including failures,
/// so the spend screen can reconcile against OpenRouter's own total.
class Db {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'crayon.db'),
      version: 5,
      onUpgrade: (d, from, to) async {
        if (from < 2) await _createSavedPrompts(d);
        if (from < 3) {
          await d.execute('alter table generations add column mask_path text');
        }
        if (from < 4) {
          await d.execute('alter table generations add column category text');
          await d.execute('alter table generations add column character_ids text');
          // _createCharacters below already includes the v5 sheet columns, so a
          // pre-v4 upgrade must NOT also run the from<5 alters (duplicate column).
          await _createCharacters(d);
        }
        if (from >= 4 && from < 5) {
          await d.execute('alter table characters add column model_sheet_path text');
          await d.execute('alter table characters add column sheet_prompt text');
        }
      },
      onCreate: (d, _) async {
        await d.execute('''
          create table generations(
            id text primary key,
            kind text not null,
            model_id text not null,
            model_name text,
            task text,
            prompt text,
            params text,
            ref_paths text,
            status text,
            job_id text,
            file_path text,
            width integer default 0,
            height integer default 0,
            duration_sec integer default 0,
            cost real default 0,
            error text,
            created_at integer not null,
            completed_at integer,
            favorite integer default 0,
            group_id text,
            mask_path text,
            category text,
            character_ids text
          )
        ''');
        await d.execute('create index gen_created_idx on generations(created_at desc)');
        await d.execute('create index gen_kind_idx on generations(kind)');
        await d.execute('create index gen_status_idx on generations(status)');
        await _createSavedPrompts(d);
        await _createCharacters(d);
      },
    );
    return _db!;
  }

  static Future<void> _createSavedPrompts(Database d) async {
    await d.execute('''
      create table if not exists saved_prompts(
        id integer primary key autoincrement,
        text text not null,
        title text,
        created_at integer not null,
        last_used_at integer,
        use_count integer default 0
      )
    ''');
    await d.execute('create index if not exists sp_created_idx on saved_prompts(created_at desc)');
  }

  static Future<void> _createCharacters(Database d) async {
    await d.execute('''
      create table if not exists characters(
        id text primary key,
        name text not null,
        cover_path text,
        created_at integer not null,
        model_sheet_path text,
        sheet_prompt text
      )
    ''');
    await d.execute('''
      create table if not exists character_images(
        id text primary key,
        char_id text not null,
        path text not null,
        created_at integer not null
      )
    ''');
    await d.execute('create index if not exists ci_char_idx on character_images(char_id)');
  }

  // ---------------- characters ----------------

  static Future<List<Character>> characters() async {
    final d = await instance;
    final rows = await d.query('characters', orderBy: 'created_at desc');
    final out = <Character>[];
    for (final r in rows) {
      final id = r['id'] as String;
      final imgs = await d.query('character_images',
          where: 'char_id = ?', whereArgs: [id], orderBy: 'created_at asc');
      final paths = imgs.map((e) => e['path'] as String).toList();
      final cnt = await d.rawQuery(
          "select count(*) c from generations where character_ids like ?", ['%"$id"%']);
      out.add(Character.fromRow(r,
          imagePaths: paths, genCount: (cnt.first['c'] as num?)?.toInt() ?? 0));
    }
    return out;
  }

  static Future<Character?> character(String id) async {
    final d = await instance;
    final r = await d.query('characters', where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    final imgs = await d.query('character_images',
        where: 'char_id = ?', whereArgs: [id], orderBy: 'created_at asc');
    return Character.fromRow(r.first, imagePaths: imgs.map((e) => e['path'] as String).toList());
  }

  static Future<void> upsertCharacter(Character c) async {
    final d = await instance;
    await d.insert('characters', c.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> renameCharacter(String id, String name) async {
    final d = await instance;
    await d.update('characters', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> setCharacterCover(String id, String path) async {
    final d = await instance;
    await d.update('characters', {'cover_path': path}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> addCharacterImage(String charId, String path) async {
    final d = await instance;
    await d.insert('character_images', {
      'id': '${DateTime.now().microsecondsSinceEpoch}',
      'char_id': charId,
      'path': path,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> removeCharacterImage(String charId, String path) async {
    final d = await instance;
    await d.delete('character_images', where: 'char_id = ? and path = ?', whereArgs: [charId, path]);
  }

  static Future<void> setCharacterModelSheet(String id, String? path) async {
    final d = await instance;
    await d.update('characters', {'model_sheet_path': path}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> setCharacterSheetPrompt(String id, String prompt) async {
    final d = await instance;
    await d.update('characters', {'sheet_prompt': prompt}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteCharacter(String id) async {
    final d = await instance;
    await d.delete('character_images', where: 'char_id = ?', whereArgs: [id]);
    await d.delete('characters', where: 'id = ?', whereArgs: [id]);
  }

  /// Overwrite the characters tagged on a generation (used for backfill).
  static Future<void> setGenCharacters(String genId, List<String> charIds) async {
    final d = await instance;
    await d.update('generations', {'character_ids': _encodeIds(charIds)},
        where: 'id = ?', whereArgs: [genId]);
  }

  static String _encodeIds(List<String> ids) =>
      ids.isEmpty ? '[]' : '[${ids.map((e) => '"$e"').join(',')}]';

  // ---------------- categories ----------------

  static Future<void> setCategory(String genId, String? category) async {
    final d = await instance;
    await d.update('generations', {'category': (category?.trim().isEmpty ?? true) ? null : category!.trim()},
        where: 'id = ?', whereArgs: [genId]);
  }

  /// Distinct category names in use, alphabetical.
  static Future<List<String>> categories() async {
    final d = await instance;
    final r = await d.rawQuery(
        "select distinct category from generations where category is not null and category != '' order by category collate nocase");
    return r.map((e) => e['category'] as String).toList();
  }

  // ---------------- saved prompts ----------------

  static Future<int> savePrompt(String text, {String? title}) async {
    final d = await instance;
    final t = text.trim();
    if (t.isEmpty) return -1;
    // saving the same text twice just refreshes it rather than piling up dupes
    final existing = await d.query('saved_prompts', where: 'text = ?', whereArgs: [t], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await d.update('saved_prompts', {'created_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return d.insert('saved_prompts', {
      'text': t,
      'title': title,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'use_count': 0,
    });
  }

  static Future<List<Map<String, Object?>>> savedPrompts({String? search}) async {
    final d = await instance;
    if (search != null && search.trim().isNotEmpty) {
      return d.query('saved_prompts',
          where: 'text like ? or title like ?',
          whereArgs: ['%${search.trim()}%', '%${search.trim()}%'],
          orderBy: 'created_at desc');
    }
    return d.query('saved_prompts', orderBy: 'created_at desc');
  }

  static Future<void> deleteSavedPrompt(int id) async {
    final d = await instance;
    await d.delete('saved_prompts', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> markPromptUsed(int id) async {
    final d = await instance;
    await d.rawUpdate(
        'update saved_prompts set use_count = use_count + 1, last_used_at = ? where id = ?',
        [DateTime.now().millisecondsSinceEpoch, id]);
  }

  static Future<bool> isPromptSaved(String text) async {
    final d = await instance;
    final r = await d.query('saved_prompts', where: 'text = ?', whereArgs: [text.trim()], limit: 1);
    return r.isNotEmpty;
  }

  static Future<void> upsert(GenRecord g) async {
    final d = await instance;
    await d.insert('generations', g.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Newest first, paged. [kindFilter] null = everything.
  static Future<List<GenRecord>> page({
    required int offset,
    int limit = 30,
    String? kindFilter,
    bool favouritesOnly = false,
    String? search,
    String? category,
    String? characterId,
  }) async {
    final d = await instance;
    final where = <String>[];
    final args = <Object?>[];
    if (kindFilter != null) {
      where.add('kind = ?');
      args.add(kindFilter);
    }
    if (favouritesOnly) where.add('favorite = 1');
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    if (characterId != null && characterId.isNotEmpty) {
      where.add('character_ids like ?');
      args.add('%"$characterId"%');
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(prompt like ? or model_name like ?)');
      args..add('%${search.trim()}%')..add('%${search.trim()}%');
    }
    final rows = await d.query(
      'generations',
      where: where.isEmpty ? null : where.join(' and '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at desc',
      limit: limit,
      offset: offset,
    );
    return rows.map(GenRecord.fromRow).toList();
  }

  static Future<GenRecord?> byId(String id) async {
    final d = await instance;
    final r = await d.query('generations', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : GenRecord.fromRow(r.first);
  }

  /// Jobs that were mid-flight when the app was killed.
  static Future<List<GenRecord>> unfinished() async {
    final d = await instance;
    final r = await d.query('generations',
        where: 'status in (?, ?)', whereArgs: ['queued', 'running'], orderBy: 'created_at asc');
    return r.map(GenRecord.fromRow).toList();
  }

  static Future<void> delete(String id) async {
    final d = await instance;
    await d.delete('generations', where: 'id = ?', whereArgs: [id]);
  }

  static Future<double> totalSpend() async {
    final d = await instance;
    final r = await d.rawQuery('select coalesce(sum(cost),0) c from generations');
    return (r.first['c'] as num?)?.toDouble() ?? 0;
  }

  static Future<int> count({String? kindFilter}) async {
    final d = await instance;
    final r = kindFilter == null
        ? await d.rawQuery('select count(*) c from generations')
        : await d.rawQuery('select count(*) c from generations where kind = ?', [kindFilter]);
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Spend grouped by model, biggest first.
  static Future<List<Map<String, Object?>>> spendByModel() async {
    final d = await instance;
    return d.rawQuery('''
      select model_name, model_id, kind, count(*) n, coalesce(sum(cost),0) total
      from generations where cost > 0
      group by model_id order by total desc
    ''');
  }

  /// Spend per day for the last [days] days, oldest first.
  static Future<List<Map<String, Object?>>> spendByDay({int days = 30}) async {
    final d = await instance;
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return d.rawQuery('''
      select date(created_at/1000,'unixepoch','localtime') day,
             coalesce(sum(cost),0) total, count(*) n
      from generations where created_at >= ?
      group by day order by day asc
    ''', [since]);
  }
}
