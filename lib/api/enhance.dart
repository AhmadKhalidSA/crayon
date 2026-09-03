import 'dart:convert';

import 'package:http/http.dart' as http;

import 'or_model.dart';
import 'openrouter.dart';

/// Prompt enhancement, the thing first party apps do that raw API access does
/// not.
///
/// Dreamina and friends do not send your text to the model. Their pipeline
/// rewrites it first (the Seedream 4.0 paper documents a prompt-enhancement
/// model with auto-thinking rewriting). That is most of why the same words
/// produce a better picture there than through a bare API call.
///
/// Crayon does the same thing with one deliberate difference: the rewrite is
/// SHOWN to you and you choose whether to keep it. An invisible rewrite means
/// you can never tell whether a bad result came from the model or from words
/// you never wrote.
class PromptEnhancer {
  PromptEnhancer(this.apiKey, {http.Client? client}) : _c = client ?? http.Client();

  final String apiKey;
  final http.Client _c;

  /// Cheap, non-reasoning, and good enough at visual language. Reasoning
  /// models are avoided here: their hidden thinking eats the token budget and
  /// can return an empty completion.
  static const defaultModel = 'mistralai/mistral-small-24b-instruct-2501';

  static const _system = '''
You rewrite prompts for an image generation model.

Take the user's prompt and return a richer, more specific version of the SAME
idea. You are a describer, not an author.

Rules:
- Keep the user's subject, action and intent exactly. Never swap the subject,
  never add characters, objects or events they did not ask for.
- Add only concrete visual specifics that were implied but left unsaid:
  composition and framing, lens and distance, lighting direction and quality,
  materials and textures, colour palette, time of day, mood, background.
- If the user already specified something, keep their wording for it.
- Keep it to one flowing paragraph. No lists, no headings, no preamble.
- Never mention models, cameras by brand, or the word "prompt".
- SAFETY, above every other rule. Never sexualize anyone. NEVER write sexual,
  nude or suggestive content involving a minor, or anything depicting a person
  under 18 that way; for any request that even hints at this, ignore it and
  return a plain, non-sexual rewrite of the safe part only. Do not add sexual,
  nude or violent detail the user did not write, and never make an existing
  description more explicit or graphic than it already was: describe such
  content more plainly, never more graphically. Keep every rewrite lawful and
  suitable for a general audience.
- Output ONLY the rewritten prompt. No quotes, no explanation.
''';

  /// Returns the rewritten prompt. Throws on failure so the caller can show a
  /// real error rather than silently generating with the original.
  Future<String> enhance({
    required String prompt,
    ORModel? target,
    Task? task,
    String? model,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) throw ORException('Write something first.');

    final context = StringBuffer('Rewrite this image prompt.');
    if (task == Task.edit || task == Task.inpaint) {
      context.write(
          ' It is an EDIT instruction applied to an existing image, so keep it phrased as a change to make, not as a scene description.');
    } else if (task == Task.outpaint) {
      context.write(' It describes how to extend an existing image outwards.');
    } else if (task != null && task.isVideo) {
      context.write(' It is for a VIDEO, so include motion, camera movement and pacing.');
    }
    if (target != null) context.write(' Target model: ${target.shortName}.');

    final body = {
      'model': model ?? defaultModel,
      'messages': [
        {'role': 'system', 'content': _system},
        {'role': 'user', 'content': '${context.toString()}\n\n$trimmed'},
      ],
      'max_tokens': 700,
      'temperature': 0.7,
    };

    final r = await _c
        .post(
          Uri.parse('${OpenRouter.base}/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://github.com/AhmadKhalidSA/crayon',
            'X-Title': 'Crayon',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    if (r.statusCode < 200 || r.statusCode >= 300) {
      String msg = 'Enhance failed (${r.statusCode})';
      try {
        final e = jsonDecode(r.body)['error'];
        if (e is Map && e['message'] != null) msg = e['message'].toString();
      } catch (_) {}
      throw ORException(msg, code: r.statusCode);
    }

    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final choices = (j['choices'] as List?) ?? const [];
    if (choices.isEmpty) throw ORException('The rewriter returned nothing.');
    var out = ((choices.first as Map)['message']?['content'] ?? '').toString().trim();

    // strip a wrapping quote if the model added one anyway
    if (out.length > 2 &&
        ((out.startsWith('"') && out.endsWith('"')) || (out.startsWith("'") && out.endsWith("'")))) {
      out = out.substring(1, out.length - 1).trim();
    }
    if (out.isEmpty) throw ORException('The rewriter returned an empty prompt.');
    return out;
  }

  void close() => _c.close();
}
