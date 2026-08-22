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
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
        title: Text('Autonomous Agent', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
      ),
      body: Obx(() {
        if (controller.currentTask.value != null) return _buildTaskDetail(context, controller.currentTask.value!, isDark);
        return _buildTaskList(context, isDark);
      }),
      floatingActionButton: Obx(() {
        if (controller.currentTask.value != null) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          onPressed: () => _showCreateDialog(context, isDark),
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text('New Objective', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        );
      }),
    );
  }

  Widget _buildTaskList(BuildContext context, bool isDark) {
    if (controller.tasks.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 2)
          ),
          child: const Icon(Icons.auto_awesome_rounded, size: 36, color: AppColors.primary)),
        const SizedBox(height: 24),
        Text('Agent Idle', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
        const SizedBox(height: 10),
        Text('Instruct the AI to plan and execute\ncomplex multi-step operations.', textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(fontSize: 15, color: Theme.of(context).hintColor, fontWeight: FontWeight.w500)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: controller.tasks.length,
      itemBuilder: (_, i) => _buildTaskCard(context, controller.tasks[i], isDark),
    );
  }

  Widget _buildTaskCard(BuildContext context, TaskModel task, bool isDark) {
    final statusColor = _statusColor(context, task.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04), blurRadius: 10, offset: const Offset(0, 4))
        ]
      ),
      child: InkWell(
        onTap: () => controller.currentTask.value = task,
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
            child: Icon(_statusIcon(task.status), color: statusColor, size: 22)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.goal, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${task.steps.length} operational steps · ${task.status.toUpperCase()}', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: statusColor, fontWeight: FontWeight.w700)),
          ])),
          IconButton(icon: Icon(Icons.delete_rounded, size: 20, color: AppColors.error.withValues(alpha: 0.5)), onPressed: () => controller.deleteTask(task.id)),
        ])),
      ),
    );
  }

  Widget _buildTaskDetail(BuildContext context, TaskModel task, bool isDark) {
    return Column(children: [
      // Header
      Container(padding: const EdgeInsets.all(20), child: Row(children: [
        GestureDetector(
          onTap: () => controller.currentTask.value = null,
          child: Container(width: 40, height: 40,
            decoration: BoxDecoration(color: isDark ? AppColors.surface : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode)),
            child: Icon(Icons.chevron_left_rounded, size: 24, color: isDark ? Colors.white : Colors.black)),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(task.goal, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ])),
      Divider(height: 1, color: isDark ? AppColors.border : AppColors.borderLightMode),

      // Steps
      Expanded(child: Obx(() {
        final current = controller.currentTask.value;
        if (current == null) return const SizedBox.shrink();
        if (controller.isPlanning.value) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(height: 20),
            Text('Synthesizing operational plan…', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Theme.of(context).hintColor)),
          ]));
        }
        if (current.steps.isEmpty) return Center(child: Text('No logic units generated.', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Theme.of(context).hintColor)));

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          itemCount: current.steps.length,
          itemBuilder: (_, i) => _buildStepTile(context, current.steps[i], isDark),
        );
      })),

      // Execute
      Obx(() {
        final current = controller.currentTask.value;
        if (current == null || current.steps.isEmpty) return const SizedBox.shrink();
        if (current.status == 'completed') {
          return Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
              const SizedBox(width: 10),
              Text('Objective Reached', style: GoogleFonts.plusJakartaSans(color: AppColors.success, fontWeight: FontWeight.w800)),
            ]));
        }
        if (current.status == 'planning') return const SizedBox.shrink();

        return SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(20), child: SizedBox(width: double.infinity, height: 56,
          child: ElevatedButton.icon(
            onPressed: controller.isExecuting.value ? null : () => controller.executeTask(current),
            icon: controller.isExecuting.value
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.rocket_launch_rounded),
            label: Text(controller.isExecuting.value ? 'In Progress' : 'Execute Operation', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          ),
        )));
      }),
    ]);
  }

  Widget _buildStepTile(BuildContext context, TaskStep step, bool isDark) {
    final statusColor = _statusColor(context, step.status);
    final isRunning = step.status == 'running';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isRunning ? AppColors.primary : (isDark ? AppColors.border : AppColors.borderLightMode), width: isRunning ? 1.5 : 1),
        boxShadow: [
          if (isRunning) BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 8)
        ]
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _stepStatusIcon(context, step.status, isDark),
          const SizedBox(width: 12),
          Expanded(child: Text(step.description, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black))),
        ]),
        if (step.command != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: isDark ? AppColors.bg : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10), border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode)),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(step.command!, style: GoogleFonts.firaCode(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary))),
              ],
            ),
          ),
        ],
        if (step.output != null && step.output!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(step.output!, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500), maxLines: 5, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }

  Widget _stepStatusIcon(BuildContext context, String status, bool isDark) {
    switch (status) {
      case 'running': return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary));
      case 'done': return const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success);
      case 'failed': return const Icon(Icons.error_rounded, size: 20, color: AppColors.error);
      default: return Icon(Icons.circle_outlined, size: 20, color: Theme.of(context).hintColor);
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'running': return AppColors.primary;
      case 'completed': case 'done': return AppColors.success;
      case 'failed': return AppColors.error;
      default: return Theme.of(context).hintColor;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'running': return Icons.sync_rounded;
      case 'completed': return Icons.verified_rounded;
      case 'failed': return Icons.report_problem_rounded;
      case 'planning': return Icons.architecture_rounded;
      default: return Icons.radio_button_unchecked_rounded;
    }
  }

  void _showCreateDialog(BuildContext context, bool isDark) {
    final textCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('Initialize Objective', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: textCtrl, autofocus: true, maxLines: 4,
        style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: const InputDecoration(
          hintText: 'Describe the complex goal for the autonomous agent to solve…',
          contentPadding: EdgeInsets.all(16)
        ),
      ),
      actions: [
        TextButton(onPressed: () { textCtrl.dispose(); Navigator.pop(ctx); }, child: Text('Discard', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Theme.of(ctx).hintColor))),
        ElevatedButton(onPressed: () {
          if (textCtrl.text.trim().isNotEmpty) { controller.createTask(textCtrl.text.trim()); }
          textCtrl.dispose();
          Navigator.pop(ctx);
        }, child: Text('Initialize', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800))),
      ],
    ));
  }
}
