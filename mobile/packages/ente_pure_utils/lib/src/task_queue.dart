import 'dart:async';
import "dart:developer";

import 'package:collection/collection.dart';

/// Class to hold task information
class _QueueItem<T> {
  final T id;
  final Future<void> Function() task;
  final Completer<void> completer;
  int lastUpdated;
  int counter;

  _QueueItem(this.id, this.task)
    : lastUpdated = DateTime.now().millisecondsSinceEpoch,
      counter = 1,
      completer = Completer<void>();

  void updateTimestamp() {
    lastUpdated = DateTime.now().millisecondsSinceEpoch;
    counter++;
  }

  bool isTimedOut(Duration timeout) {
    return (DateTime.now().millisecondsSinceEpoch - lastUpdated) >
        timeout.inMilliseconds;
  }

  Future<void> get future => completer.future;
}

/// Custom exception for task timeout
class TaskQueueTimeoutException implements Exception {
  final dynamic taskId;
  final Duration timeout;

  TaskQueueTimeoutException(this.taskId, this.timeout);

  @override
  String toString() =>
      'Task $taskId timed out after ${timeout.inSeconds} seconds';
}

/// Custom exception for task being discarded due to queue overflow
class TaskQueueOverflowException implements Exception {
  final dynamic taskId;

  TaskQueueOverflowException(this.taskId);

  @override
  String toString() => 'Task $taskId was discarded due to queue overflow';
}

class TaskQueueCancelledException implements Exception {
  final dynamic taskId;

  TaskQueueCancelledException(this.taskId);

  @override
  String toString() => 'Task $taskId was cancelled';
}

/// A generic task queue that can manage tasks with priority, cancellation, and timeout functionality.
class TaskQueue<T> {
  /// Maximum number of tasks that can run concurrently
  final int maxConcurrentTasks;

  /// Timeout duration after which a task is considered stale
  final Duration taskTimeout;

  /// Maximum size of the queue before older tasks are discarded
  final int maxQueueSize;

  /// Map to store tasks for quick lookup by ID
  final _taskMap = <T, _QueueItem>{};

  /// Priority queue to sort tasks by timestamp (most recent first)
  final HeapPriorityQueue<_QueueItem> _priorityQueue;

  /// Set of currently running task ids
  final _runningTasks = <T>{};

  /// Constructor
  TaskQueue({
    this.maxConcurrentTasks = 1,
    this.taskTimeout = const Duration(minutes: 5),
    this.maxQueueSize = 100,
  }) : _priorityQueue = HeapPriorityQueue<_QueueItem>(
         (a, b) => b.lastUpdated.compareTo(a.lastUpdated),
       ); // Reversed for most recent first

  /// Add or update a task in the queue
  Future<void> addTask(T id, Future<void> Function() task) {
    // If the task is already in the queue, update its timestamp to increase priority
    if (_taskMap.containsKey(id)) {
      final item = _taskMap[id]!;

      // We need to remove and re-add to the priority queue to update its position
      _priorityQueue.remove(item);
      item.updateTimestamp();
      _priorityQueue.add(item);

      return item.future;
    } else {
      // Check if we need to make room in the queue
      _enforceQueueSizeLimit();

      // Add new task to the queue
      final queueItem = _QueueItem(id, task);
      _taskMap[id] = queueItem;
      _priorityQueue.add(queueItem);

      // Try to process tasks
      _processQueue();

      return queueItem.future;
    }
  }

  /// Enforce the maximum queue size by discarding older tasks
  void _enforceQueueSizeLimit() {
    // If we're under the limit, no action needed
    if (_taskMap.length < maxQueueSize) {
      return;
    }

    // Create a temporary queue to find oldest items
    // We need this because our main queue is ordered by most recent first
    final tempQueue = PriorityQueue<_QueueItem>(
      (a, b) => a.lastUpdated.compareTo(b.lastUpdated),
    ); // Oldest first

    // Add all items to the temporary queue
    for (var item in _taskMap.values) {
      tempQueue.add(item);
    }

    // Calculate how many items we need to remove
    final excessItems =
        _taskMap.length - maxQueueSize + 1; // +1 to make room for the new item

    // Remove the oldest items
    for (var i = 0; i < excessItems && tempQueue.isNotEmpty; i++) {
      final oldestItem = tempQueue.removeFirst();
      _priorityQueue.remove(oldestItem);
      _taskMap.remove(oldestItem.id);

      // Complete with overflow error
      if (!oldestItem.completer.isCompleted) {
        oldestItem.completer.completeError(
          TaskQueueOverflowException(oldestItem.id),
        );
      }
    }
  }

  /// Remove a task from the queue by its ID
  bool removeTask(T id) {
    // Can only remove tasks that aren't already running
    if (_runningTasks.contains(id)) {
      return false;
    }

    if (_taskMap.containsKey(id)) {
      final item = _taskMap[id]!;
      item.counter--;
      if (item.counter > 0) {
        return false;
      }
      _priorityQueue.remove(item);
      // Complete the future with a cancellation error
      if (!item.completer.isCompleted) {
        item.completer.completeError(TaskQueueCancelledException(id));
      }

      _taskMap.remove(id);
      return true;
    }

    return false;
  }

  /// Get the number of tasks waiting in the queue
  int get pendingTasksCount => _taskMap.length;

  /// Get the number of currently running tasks
  int get runningTasksCount => _runningTasks.length;

  /// Process the queue and execute tasks if possible
  void _processQueue() async {
    // Remove timed out tasks
    _removeTimedOutTasks();

    // If we can't run more tasks, exit
    if (_runningTasks.length >= maxConcurrentTasks || _priorityQueue.isEmpty) {
      return;
    }

    // Get the highest priority task (most recent)
    final queueItem = _priorityQueue.removeFirst();
    final taskId = queueItem.id;

    // Remove from the map
    _taskMap.remove(taskId);

    // Mark this task as running
    _runningTasks.add(taskId);

    try {
      // Execute the task
      await queueItem.task();
      // Complete the future successfully
      if (!queueItem.completer.isCompleted) {
        queueItem.completer.complete();
      }
    } catch (e) {
      // Complete the future with the error
      if (!queueItem.completer.isCompleted) {
        queueItem.completer.completeError(e);
      }
      log('Task error: $e');
    } finally {
      // Mark the task as completed
      _runningTasks.remove(taskId);

      // Process the next task in the queue
      _processQueue();
    }
  }

  /// Remove tasks that have timed out
  void _removeTimedOutTasks() {
    final timedOutIds = <T>[];

    // First pass: identify timed out items
    for (var entry in _taskMap.entries) {
      if (entry.value.isTimedOut(taskTimeout)) {
        timedOutIds.add(entry.key);
      }
    }
    // Second pass: remove them and complete with timeout error
    for (var id in timedOutIds) {
      final item = _taskMap[id]!;
      _priorityQueue.remove(item);

      // Complete the future with a timeout error
      if (!item.completer.isCompleted) {
        item.completer.completeError(
          TaskQueueTimeoutException(id, taskTimeout),
        );
      }

      _taskMap.remove(id);
    }
  }

  /// Clear all pending tasks
  void clear() {
    // Complete all pending tasks with cancellation errors
    for (var entry in _taskMap.entries) {
      if (!entry.value.completer.isCompleted) {
        entry.value.completer.completeError(
          Exception('Task ${entry.key} was cancelled during queue clear'),
        );
      }
    }

    while (_priorityQueue.isNotEmpty) {
      _priorityQueue.removeFirst();
    }
    _taskMap.clear();
  }
}
