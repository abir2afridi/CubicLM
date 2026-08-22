import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/task_controller.dart';
import '../core/colors.dart';
import '../models/task_model.dart';

class TaskView extends GetView<TaskController> {
  const TaskView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
        title: Text('Tasks', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: Obx(() {
        if (controller.currentTask.value != null) return _buildTaskDetail(context, controller.currentTask.value!, isDark);
        return _buildTaskList(context, isDark);
      }),
      floatingActionButton: Obx(() {
        if (controller.currentTask.value != null) return const SizedBox.shrink();
        return FloatingActionButton(
          onPressed: () => _showCreateDialog(context, isDark),
          child: const Icon(Icons.add_rounded),
        );
      }),
    );
  }

  Widget _buildTaskList(BuildContext context, bool isDark) {
    if (controller.tasks.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 60, height: 60,
          decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.bolt_rounded, size: 30, color: AppColors.secondary)),
        const SizedBox(height: 16),
        Text('No Tasks Yet', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
        const SizedBox(height: 6),
        Text('Create a task and the AI will plan\nand execute it autonomously', textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 15, color: Theme.of(context).hintColor)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: controller.tasks.length,
      itemBuilder: (_, i) => _buildTaskCard(context, controller.tasks[i], isDark),
    );
  }

  Widget _buildTaskCard(BuildContext context, TaskModel task, bool isDark) {
    final statusColor = _statusColor(context, task.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1C1C1E) : Colors.white, borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => controller.currentTask.value = task,
        borderRadius: BorderRadius.circular(14),
        child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Container(width: 38, height: 38,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(_statusIcon(task.status), color: statusColor, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.goal, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${task.steps.length} steps · ${task.status.toUpperCase()}', style: GoogleFonts.inter(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500)),
          ])),
          IconButton(icon: Icon(Icons.delete_outline_rounded, size: 18, color: Theme.of(context).hintColor), onPressed: () => controller.deleteTask(task.id)),
        ])),
      ),
    );
  }

  Widget _buildTaskDetail(BuildContext context, TaskModel task, bool isDark) {
    return Column(children: [
      // Header
      Container(padding: const EdgeInsets.all(16), child: Row(children: [
        GestureDetector(
          onTap: () => controller.currentTask.value = null,
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: isDark ? Colors.white : Colors.black)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(task.goal, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ])),
      Divider(height: 0.5, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),

      // Steps
      Expanded(child: Obx(() {
        final current = controller.currentTask.value;
        if (current == null) return const SizedBox.shrink();
        if (controller.isPlanning.value) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: isDark ? const Color(0xFF0A84FF) : AppColors.primary),
            const SizedBox(height: 16),
            Text('AI is planning steps…', style: GoogleFonts.inter(color: Theme.of(context).hintColor)),
          ]));
        }
        if (current.steps.isEmpty) return Center(child: Text('No steps generated.', style: GoogleFonts.inter(color: Theme.of(context).hintColor)));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: current.steps.length,
          itemBuilder: (_, i) => _buildStepTile(context, current.steps[i], isDark),
        );
      })),

      // Execute
      Obx(() {
        final current = controller.currentTask.value;
        if (current == null || current.steps.isEmpty) return const SizedBox.shrink();
        if (current.status == 'completed') {
          return Container(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success),
            const SizedBox(width: 8),
            Text('Task Completed', style: GoogleFonts.inter(color: AppColors.success, fontWeight: FontWeight.w600)),
          ]));
        }
        if (current.status == 'planning') return const SizedBox.shrink();

        return SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: controller.isExecuting.value ? null : () => controller.executeTask(current),
            icon: controller.isExecuting.value
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(controller.isExecuting.value ? 'Executing…' : 'Execute All Steps'),
          ),
        )));
      }),
    ]);
  }

  Widget _buildStepTile(BuildContext context, TaskStep step, bool isDark) {
    final statusColor = _statusColor(context, step.status);
    final isRunning = step.status == 'running';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isRunning ? Border.all(color: isDark ? const Color(0xFF0A84FF) : AppColors.primary, width: 1) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _stepStatusIcon(context, step.status, isDark),
          const SizedBox(width: 10),
          Expanded(child: Text(step.description, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: isDark ? Colors.white : Colors.black))),
        ]),
        if (step.command != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
            child: Text(step.command!, style: GoogleFonts.firaCode(fontSize: 12, color: isDark ? const Color(0xFF0A84FF) : AppColors.primary)),
          ),
        ],
        if (step.output != null && step.output!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(step.output!, style: GoogleFonts.inter(fontSize: 12, color: statusColor), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }

  Widget _stepStatusIcon(BuildContext context, String status, bool isDark) {
    switch (status) {
      case 'running': return SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? const Color(0xFF0A84FF) : AppColors.primary));
      case 'done': return const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success);
      case 'failed': return const Icon(Icons.error_rounded, size: 18, color: AppColors.error);
      default: return Icon(Icons.circle_outlined, size: 18, color: Theme.of(context).hintColor);
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'running': return Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0A84FF) : AppColors.primary;
      case 'completed': case 'done': return AppColors.success;
      case 'failed': return AppColors.error;
      default: return Theme.of(context).hintColor;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'running': return Icons.sync_rounded;
      case 'completed': return Icons.check_circle_rounded;
      case 'failed': return Icons.error_rounded;
      case 'planning': return Icons.auto_awesome_rounded;
      default: return Icons.circle_outlined;
    }
  }

  void _showCreateDialog(BuildContext context, bool isDark) {
    final textCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('New Task', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      content: TextField(
        controller: textCtrl, autofocus: true, maxLines: 3,
        style: GoogleFonts.inter(fontSize: 15),
        decoration: const InputDecoration(hintText: 'Describe what you want the AI to do…'),
      ),
      actions: [
        TextButton(onPressed: () { textCtrl.dispose(); Navigator.pop(ctx); }, child: Text('Cancel', style: GoogleFonts.inter(color: Theme.of(ctx).hintColor))),
        ElevatedButton(onPressed: () {
          if (textCtrl.text.trim().isNotEmpty) { controller.createTask(textCtrl.text.trim()); }
          textCtrl.dispose();
          Navigator.pop(ctx);
        }, child: const Text('Create')),
      ],
    ));
  }
}
