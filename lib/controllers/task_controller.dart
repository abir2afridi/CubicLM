import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../models/task_model.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/cloud_service.dart';

class TaskController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final _uuid = const Uuid();

  final tasks = <TaskModel>[].obs;
  final currentTask = Rxn<TaskModel>();
  final isPlanning = false.obs;
  final isExecuting = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadTasks();
  }

  void loadTasks() {
    final raw = _hive.getAllTasks();
    tasks.value = raw.map((m) => TaskModel.fromMap(m)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Create a new task: send goal to LLM to get a plan with steps.
  Future<void> createTask(String goal) async {
    if (goal.trim().isEmpty) return;

    final taskId = _uuid.v4();
    var task = TaskModel(id: taskId, goal: goal, status: 'planning');
    tasks.insert(0, task);
    _hive.saveTask(taskId, task.toMap());
    currentTask.value = task;
    isPlanning.value = true;

    try {
      final planPrompt = '''You are an Android automation planner. Given a user's goal, break it down into individual ADB shell commands to execute on an Android phone.

Output ONLY a numbered list of steps. Each step must have:
- A short description
- The exact ADB shell command (prefixed with CMD:)

Example:
1. Enable Do Not Disturb mode
CMD: settings put global zen_mode 1
2. Reduce screen brightness to 30%
CMD: settings put system screen_brightness 77
3. Enable dark mode
CMD: cmd uimode night yes

User Goal: $goal

Steps:''';

      String response;
      final mode = _hive.getSetting(AppConstants.keyInferenceMode,
              defaultValue: 'local') ??
          'local';

      if (mode == 'local') {
        final inference = Get.find<InferenceService>();
        response = await inference.generate(prompt: planPrompt);
      } else {
        final cloud = Get.find<CloudService>();
        response = await cloud.sendMessage(messages: [
          {'role': 'user', 'content': planPrompt},
        ]);
      }

      // Parse steps from response
      final steps = _parseSteps(response);

      if (steps.isEmpty) {
        task = task.copyWith(
          status: 'failed',
          steps: [
            TaskStep(
              index: 0,
              description: 'Failed to generate plan. Raw output: $response',
              status: 'failed',
            ),
          ],
        );
      } else {
        task = task.copyWith(status: 'pending', steps: steps);
      }

      currentTask.value = task;
      final idx = tasks.indexWhere((t) => t.id == taskId);
      if (idx >= 0) tasks[idx] = task;
      _hive.saveTask(taskId, task.toMap());
    } catch (e) {
      task = task.copyWith(status: 'failed');
      currentTask.value = task;
      final idx = tasks.indexWhere((t) => t.id == taskId);
      if (idx >= 0) tasks[idx] = task;
      _hive.saveTask(taskId, task.toMap());
    }

    isPlanning.value = false;
  }

  /// Exports the plan as a runnable ADB shell script via the share sheet.
  ///
  /// On-device shell execution is impossible for stock apps (no shell
  /// privileges — `settings put global` etc. need signature-level rights),
  /// so the previous "Execute" button always failed. The honest flow is:
  /// plan here, run from a PC with `adb shell`.
  Future<void> exportPlan(TaskModel task) async {
    if (isExecuting.value) return;
    isExecuting.value = true;
    // Short file-safe id (uuids are 36 chars; custom ids may be shorter).
    final taskIdShort =
        task.id.length >= 8 ? task.id.substring(0, 8) : task.id;
    try {
      final buf = StringBuffer()
        ..writeln('#!/system/bin/sh')
        ..writeln('# CubicLM plan: ${task.goal}')
        ..writeln('# Run from a PC connected over ADB:')
        ..writeln('#   adb shell < $taskIdShort.sh')
        ..writeln('set -e');
      var count = 0;
      for (final step in task.steps) {
        final cmd = (step.command ?? '').trim();
        if (cmd.isEmpty) continue;
        count++;
        buf.writeln();
        buf.writeln('# Step $count: ${step.description}');
        buf.writeln(cmd);
      }
      if (count == 0) {
        Get.snackbar('Nothing to export', 'This plan has no commands.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/cubiclm_task_$taskIdShort.sh');
      await file.writeAsString(buf.toString(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/x-sh')],
        text: 'CubicLM ADB plan ($count steps): ${task.goal}',
        subject: 'CubicLM ADB plan',
      );
      final updatedTask = task.copyWith(status: 'exported');
      _updateTask(updatedTask);
    } catch (e) {
      Get.snackbar('Export failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isExecuting.value = false;
    }
  }

  /// Backwards-compatible alias (old UI called executeTask).
  Future<void> executeTask(TaskModel task) => exportPlan(task);

  void deleteTask(String id) {
    _hive.deleteTask(id);
    tasks.removeWhere((t) => t.id == id);
    if (currentTask.value?.id == id) {
      currentTask.value = null;
    }
  }

  void _updateTask(TaskModel task) {
    currentTask.value = task;
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) tasks[idx] = task;
    _hive.saveTask(task.id, task.toMap());
  }

  /// Parse numbered steps from LLM output.
  List<TaskStep> _parseSteps(String raw) {
    final steps = <TaskStep>[];
    final lines = raw.trim().split('\n');

    String? currentDesc;
    int stepIndex = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Check for step description (numbered line)
      final numMatch = RegExp(r'^\d+[\.\)]\s*(.+)').firstMatch(trimmed);
      if (numMatch != null) {
        currentDesc = numMatch.group(1)?.trim();
        continue;
      }

      // Check for CMD: line
      if (trimmed.startsWith('CMD:')) {
        final cmd = trimmed.substring(4).trim();
        steps.add(TaskStep(
          index: stepIndex++,
          description: currentDesc ?? 'Step $stepIndex',
          command: cmd,
        ));
        currentDesc = null;
      }
    }

    return steps;
  }
}
