// ============================================
// FILE: lib/services/gemini_service.dart
// ============================================
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/secrets.dart';

class GeminiService {
  static const String _apiKey = Secrets.geminiApiKey;
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';
  static final Map<String, List<Map<String, String>>> _cache = {};

  static String _cacheKey(String module, String level) => '${module}_$level';

  static Future<List<Map<String, String>>> personalizeContent({
    required String moduleName,
    required String baseContent,
    required String level,
  }) async {
    final key = _cacheKey(moduleName, level);

    // ── 1. In-memory cache (current session) ─────────────────────────────────
    if (_cache.containsKey(key)) return _cache[key]!;

    // ── 2. Firestore persistent cache (across sessions) ───────────────────────
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final cacheDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('contentCache')
            .doc(key)
            .get();
        if (cacheDoc.exists) {
          final raw = cacheDoc.data()?['sections'];
          if (raw is List && raw.isNotEmpty) {
            final parsed = raw.map<Map<String, String>>((s) => {
              'heading': (s['heading'] ?? '') as String,
              'body': (s['body'] ?? '') as String,
            }).toList();
            _cache[key] = parsed;
            debugPrint('Gemini: served from Firestore cache ($key)');
            return parsed;
          }
        }
      } catch (e) {
        debugPrint('Firestore cache read error: $e');
      }
    }

    // ── Helper: save parsed result to both caches ─────────────────────────────
    void saveToCache(List<Map<String, String>> parsed) {
      _cache[key] = parsed;
      if (uid != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('contentCache')
            .doc(key)
            .set({
          'sections': parsed,
          'generatedAt': FieldValue.serverTimestamp(),
          'level': level,
          'module': moduleName,
        }).catchError((e) => debugPrint('Firestore cache write error: $e'));
      }
    }

    final prompt = _buildPrompt(moduleName, baseContent, level);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.4,
            'maxOutputTokens': 8192,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
        debugPrint('RAW GEMINI RESPONSE: $text'); // temp debug
        final parsed = _parseResponse(text);
        saveToCache(parsed);
        return parsed;
      } else if (response.statusCode == 503) {
        debugPrint('Gemini 503 — retrying in 3s...');
        await Future.delayed(const Duration(seconds: 3));
        final retry = await http.post(
          Uri.parse('$_baseUrl?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.4,
              'maxOutputTokens': 8192,
            },
          }),
        );
        if (retry.statusCode == 200) {
          final data = jsonDecode(retry.body);
          final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
          debugPrint('RAW GEMINI RESPONSE (retry): $text');
          final parsed = _parseResponse(text);
          saveToCache(parsed);
          return parsed;
        } else {
          debugPrint('Gemini retry error ${retry.statusCode}: ${retry.body}');
          throw Exception('Gemini API error: ${retry.statusCode}');
        }
      } else {
        debugPrint('Gemini error ${response.statusCode}: ${response.body}');
        throw Exception('Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch personalized content: $e');
    }
  }

  static String _buildPrompt(String module, String baseContent, String level) {
    final levelInstructions = {
      'Beginner': '''
You are a friendly computer science teacher explaining to a student who has NEVER studied programming before.

RULES:
- Use very simple, warm, and encouraging language — like talking to a friend
- Every technical word MUST be explained immediately in plain everyday English
- Use fun real-life analogies (e.g. a stack = a pile of plates, a queue = people standing in line)
- Short sentences. Short paragraphs. Easy words only.
- After each concept write: "Think of it like: ..." with a simple analogy
- No code at all. Just plain explanations.
- Make the student feel smart and capable, not confused
- Tone: friendly, simple, encouraging
''',
      'Intermediate': '''
You are a computer science teacher explaining to a student who knows the basics and wants to go deeper.

RULES:
- Use clear simple English — explain every technical term when you first use it
- Explain WHY things work, not just WHAT they are
- Use simple pseudocode examples (write them in plain readable style, not complex syntax)
- Compare with things the student already knows (arrays, simple loops, etc.)
- Mention time complexity (O(1), O(n)) but explain what it means in plain words
- Give real examples of where this is used in real apps or software
- Tone: clear, friendly, educational — like a good university professor
''',
      'Advanced': '''
You are a computer science teacher explaining advanced concepts to a motivated student.

RULES:
- Cover deep and advanced topics — memory internals, trade-offs, edge cases, complexity analysis
- Always use clear simple English — even the most complex ideas must be easy to read
- Explain every concept fully in plain words — no jargon without explanation
- DO NOT include any code, pseudocode, or programming syntax anywhere — explain everything in words only
- Cover time and space complexity but explain what it means in everyday English
- Mention real-world uses in apps, operating systems, databases, interviews
- Compare different approaches and explain which is better and WHY in simple words
- Tone: thorough, detailed, clear — like a great teacher explaining to a smart student
''',
    };

    return '''
${levelInstructions[level]}

TASK:
Rewrite the following $module module content for a $level level student.

OUTPUT FORMAT (strictly follow this JSON format, no markdown, no extra text):
[
  {
    "heading": "Section Title Here",
    "body": "Full section content here. Use \\n for new lines."
  },
  {
    "heading": "Next Section Title",
    "body": "Next section content."
  }
]

REQUIREMENTS:
- Generate EXACTLY 5 sections
- Each heading must be natural and conversational — like a chapter title a student would actually enjoy reading (e.g. "What Even Is a Stack?" or "Why Stacks Are So Fast"). Never use boring or overly technical headings.
- Each body must be 5-7 sentences — detailed enough to fully explain the concept but not overwhelming
- Do NOT include code blocks, Python code, or multi-line code anywhere in the body text
- Do NOT include any text outside the JSON array
- Do NOT use markdown, asterisks, or hashtags inside the JSON values
- Write in a flowing, readable paragraph style — not bullet points

BASE CONTENT TO REWRITE:
$baseContent
''';
  }

  static List<Map<String, String>> _parseResponse(String text) {
    try {
      String cleaned = text.trim();
      // Remove markdown fences
      cleaned = cleaned.replaceAll(RegExp(r'```json|```'), '').trim();
      // Extract JSON array between first [ and last ]
      final startIndex = cleaned.indexOf('[');
      final endIndex = cleaned.lastIndexOf(']');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        cleaned = cleaned.substring(startIndex, endIndex + 1);
      }
      final List<dynamic> parsed = jsonDecode(cleaned);
      return parsed.map<Map<String, String>>((item) => {
        'heading': item['heading']?.toString() ?? '',
        'body': item['body']?.toString() ?? '',
      }).toList();
    } catch (e) {
      debugPrint('Parse error: $e');
      return [{'heading': 'Content', 'body': text}];
    }
  }

  static void clearCache() => _cache.clear();
}