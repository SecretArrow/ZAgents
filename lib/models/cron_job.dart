/// Scheduled-task (cron job) model — v1.49.9.
///
/// A [CronJob] is ONE user-defined automation: a cron-style schedule plus
/// the action to fire when the schedule is due. The repository stores an
/// UNBOUNDED list of jobs (the user can create as many as they want);
/// each job keeps its own enabled flag, last-run result and next-run
/// timestamp so the manager screen can show everything at a glance.
///
/// Actions:
/// * [CronActionKind.telegram] — sends [messageText] through the Telegram
///   Bot API using the job's own bot token + chat id (stored per job).
/// * [CronActionKind.notification] — posts a local Android notification
///   ([notifTitle] / [notifText]) through the existing platform channel.
/// * [CronActionKind.agent] — runs the prompt as a headless fan-of-
///   subagents task (full agent toolset: workspace, browser contexts,
///   web fetch, node, git) and delivers the final answer as a local
///   notification; when the optional telegram fields are filled the
///   answer is relayed to that chat as well.
library;

/// What a cron job does when it fires.
enum CronActionKind { telegram, notification, agent }

/// Resolves a wire name to [CronActionKind]; unknown spellings fall back
/// to [CronActionKind.notification] (the least-surprising default).
CronActionKind cronActionKindFromName(String? name) {
  switch (name) {
    case 'telegram':
      return CronActionKind.telegram;
    case 'agent':
      return CronActionKind.agent;
    case 'notification':
    default:
      return CronActionKind.notification;
  }
}

/// One persisted automation ("job").
class CronJob {
  const CronJob({
    required this.id,
    required this.name,
    required this.expression,
    this.action = CronActionKind.notification,
    this.telegramToken = '',
    this.telegramChatId = '',
    this.messageText = '',
    this.notifTitle = '',
    this.notifText = '',
    this.agentPrompt = '',
    this.enabled = true,
    required this.createdAtMs,
    this.lastRunAtMs,
    this.lastResult = '',
    this.lastResultOk = true,
    this.nextRunAtMs,
  });

  final String id;
  final String name;

  /// 5-field cron expression (minute hour day-of-month month day-of-week),
  /// or one of the @shortcuts (@hourly, @daily, @weekly, @monthly,
  /// @yearly). Validated by [CronExpression] on save.
  final String expression;

  final CronActionKind action;

  /// Telegram Bot API token (`123456:ABC-…`) — required for the telegram
  /// action, optional relay target for the agent action.
  final String telegramToken;

  /// Telegram chat id (numeric or `@channelname`).
  final String telegramChatId;

  /// Text sent by the telegram action.
  final String messageText;

  /// Local notification title (notification action; agent action falls
  /// back to the job name when empty).
  final String notifTitle;

  /// Local notification body (notification action).
  final String notifText;

  /// Prompt executed by the agent (fan-of-subagents) action.
  final String agentPrompt;

  final bool enabled;
  final int createdAtMs;

  /// Bookkeeping (updated by the scheduler, not editable in the UI).
  final int? lastRunAtMs;
  final String lastResult;
  final bool lastResultOk;

  /// Cached next fire time (recomputed on save and after every run).
  final int? nextRunAtMs;

  /// Sentinel for "keep the current value" in copyWith — passing an
  /// explicit null CLEARS the field (needed when an expression becomes
  /// invalid and the cached next-run must be dropped).
  static const Object _unset = Object();

  CronJob copyWith({
    String? name,
    String? expression,
    CronActionKind? action,
    String? telegramToken,
    String? telegramChatId,
    String? messageText,
    String? notifTitle,
    String? notifText,
    String? agentPrompt,
    bool? enabled,
    int? createdAtMs,
    Object? lastRunAtMs = _unset,
    String? lastResult,
    bool? lastResultOk,
    Object? nextRunAtMs = _unset,
  }) => CronJob(
    id: id,
    name: name ?? this.name,
    expression: expression ?? this.expression,
    action: action ?? this.action,
    telegramToken: telegramToken ?? this.telegramToken,
    telegramChatId: telegramChatId ?? this.telegramChatId,
    messageText: messageText ?? this.messageText,
    notifTitle: notifTitle ?? this.notifTitle,
    notifText: notifText ?? this.notifText,
    agentPrompt: agentPrompt ?? this.agentPrompt,
    enabled: enabled ?? this.enabled,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    lastRunAtMs: lastRunAtMs == _unset ? this.lastRunAtMs : lastRunAtMs as int?,
    lastResult: lastResult ?? this.lastResult,
    lastResultOk: lastResultOk ?? this.lastResultOk,
    nextRunAtMs: nextRunAtMs == _unset ? this.nextRunAtMs : nextRunAtMs as int?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'expression': expression,
    'action': action.name,
    'telegramToken': telegramToken,
    'telegramChatId': telegramChatId,
    'messageText': messageText,
    'notifTitle': notifTitle,
    'notifText': notifText,
    'agentPrompt': agentPrompt,
    'enabled': enabled,
    'createdAtMs': createdAtMs,
    'lastRunAtMs': lastRunAtMs,
    'lastResult': lastResult,
    'lastResultOk': lastResultOk,
    'nextRunAtMs': nextRunAtMs,
  };

  factory CronJob.fromJson(Map<String, dynamic> json) => CronJob(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    expression: json['expression'] as String? ?? '',
    action: cronActionKindFromName(json['action'] as String?),
    telegramToken: json['telegramToken'] as String? ?? '',
    telegramChatId: json['telegramChatId'] as String? ?? '',
    messageText: json['messageText'] as String? ?? '',
    notifTitle: json['notifTitle'] as String? ?? '',
    notifText: json['notifText'] as String? ?? '',
    agentPrompt: json['agentPrompt'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    createdAtMs: json['createdAtMs'] as int? ?? 0,
    lastRunAtMs: json['lastRunAtMs'] as int?,
    lastResult: json['lastResult'] as String? ?? '',
    lastResultOk: json['lastResultOk'] as bool? ?? true,
    nextRunAtMs: json['nextRunAtMs'] as int?,
  );
}

/// One recorded execution of any job (newest first in the repository).
class CronRunEntry {
  const CronRunEntry({
    required this.jobId,
    required this.jobName,
    required this.atMs,
    required this.ok,
    required this.detail,
  });

  final String jobId;
  final String jobName;
  final int atMs;
  final bool ok;

  /// Human-readable outcome ("sent", "HTTP 400: chat not found", the
  /// agent's final answer snippet, …).
  final String detail;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'jobId': jobId,
    'jobName': jobName,
    'atMs': atMs,
    'ok': ok,
    'detail': detail,
  };

  factory CronRunEntry.fromJson(Map<String, dynamic> json) => CronRunEntry(
    jobId: json['jobId'] as String? ?? '',
    jobName: json['jobName'] as String? ?? '',
    atMs: json['atMs'] as int? ?? 0,
    ok: json['ok'] as bool? ?? false,
    detail: json['detail'] as String? ?? '',
  );
}

/// Whole persisted cron store: the (unbounded) job list, the capped run
/// history and the master switch that pauses ALL jobs without deleting
/// them.
class CronState {
  const CronState({
    this.jobs = const <CronJob>[],
    this.history = const <CronRunEntry>[],
    this.enabled = true,
  });

  final List<CronJob> jobs;
  final List<CronRunEntry> history;
  final bool enabled;

  CronState copyWith({
    List<CronJob>? jobs,
    List<CronRunEntry>? history,
    bool? enabled,
  }) => CronState(
    jobs: jobs ?? this.jobs,
    history: history ?? this.history,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'jobs': jobs.map((j) => j.toJson()).toList(),
    'history': history.map((h) => h.toJson()).toList(),
    'enabled': enabled,
  };

  factory CronState.fromJson(Map<String, dynamic> json) => CronState(
    jobs: (json['jobs'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(CronJob.fromJson)
        .toList(),
    history: (json['history'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(CronRunEntry.fromJson)
        .toList(),
    enabled: json['enabled'] as bool? ?? true,
  );
}
