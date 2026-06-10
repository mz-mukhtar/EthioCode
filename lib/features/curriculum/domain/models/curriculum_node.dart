// lib/features/curriculum/domain/models/curriculum_node.dart
//
// Domain model for the static JSON curriculum roadmap.
// Defines tasks, puzzle nodes (Syntax Sniper, Parsons Puzzles), and unlocks.
//
// Responsibilities:
//   • Provide safe fromJson mapping using typed try-catch parsing.
//   • Validate requirement criteria against database progress.

import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Curriculum Types
// ─────────────────────────────────────────────────────────────────────────────
enum NodeType {
  lesson,
  syntaxSniper,  // Find the bug type tasks
  parsonsPuzzle, // Drag and drop code tasks
  codingChallenge
}

NodeType _parseNodeType(String type) {
  switch (type.toLowerCase()) {
    case 'lesson':          return NodeType.lesson;
    case 'syntax_sniper':   return NodeType.syntaxSniper;
    case 'parsons_puzzle':  return NodeType.parsonsPuzzle;
    case 'challenge':       return NodeType.codingChallenge;
    default:                return NodeType.lesson;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CurriculumNode
// ─────────────────────────────────────────────────────────────────────────────
@immutable
class CurriculumNode {
  final String id;
  final String title;
  final NodeType type;
  final String description;

  /// IDs of nodes that must be 'is_completed = 1' before this node unlocks.
  final List<String> requiredNodeIds;

  /// JSON payload defining the specific task (e.g. the code snippet with a bug).
  final Map<String, dynamic> taskData;

  const CurriculumNode({
    required this.id,
    required this.title,
    required this.type,
    required this.description,
    required this.requiredNodeIds,
    required this.taskData,
  });

  factory CurriculumNode.fromJson(Map<String, dynamic> json) {
    try {
      final rawReqs = json['requires'] as List<dynamic>? ?? [];
      
      return CurriculumNode(
        id:          json['id'] as String? ?? 'unknown_id',
        title:       json['title'] as String? ?? 'Untitled Task',
        type:        _parseNodeType(json['type'] as String? ?? 'lesson'),
        description: json['description'] as String? ?? '',
        requiredNodeIds: rawReqs.map((e) => e.toString()).toList(),
        taskData:    (json['task_data'] as Map<String, dynamic>?) ?? {},
      );
    } catch (e) {
      debugPrint('[CurriculumNode.fromJson] Failed to parse: $e');
      // Return a safe fallback node to prevent total JSON parsing failure.
      return const CurriculumNode(
        id: 'error_node',
        title: 'Corrupted Data',
        type: NodeType.lesson,
        description: 'Failed to load task. Please check app update.',
        requiredNodeIds: [],
        taskData: {},
      );
    }
  }

  /// Checks if this node is unlocked, given a list of already completed node IDs.
  bool canUnlock(Set<String> completedNodeIds) {
    if (requiredNodeIds.isEmpty) return true; // Start nodes.
    return requiredNodeIds.every((req) => completedNodeIds.contains(req));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CurriculumBundle
// ─────────────────────────────────────────────────────────────────────────────
/// Top-level model representing the entire roadmap.json file.
@immutable
class CurriculumBundle {
  final String version;
  final List<CurriculumNode> nodes;

  const CurriculumBundle({
    required this.version,
    required this.nodes,
  });

  factory CurriculumBundle.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'] as List<dynamic>? ?? [];
    return CurriculumBundle(
      version: json['version'] as String? ?? '1.0.0',
      nodes: rawNodes
          .map((n) => CurriculumNode.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }
}
