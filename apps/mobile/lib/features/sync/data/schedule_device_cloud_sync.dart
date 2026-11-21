import 'dart:async';

import '../../idle_jobs/idle_job_queue.dart';
import '../../idle_jobs/idle_job_scheduler.dart';

/// Debounce local study edits into a single idle cloud push+pull.
void scheduleDeviceCloudSync({String key = 'device'}) {
  if (!idleJobsEnabled()) return;
  unawaited(
    IdleJobQueue.shared.enqueue(kind: IdleJobKind.cloudSync, key: key),
  );
  unawaited(scheduleIdleJobs());
}
