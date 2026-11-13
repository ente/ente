import 'dart:async';
import "dart:developer";

import 'package:collection/collection.dart';

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

class TaskQueueTimeoutException implements Exception {
  final dynamic taskId;
  final Duration timeout;

  TaskQueueTimeoutException(this.taskId, this.timeout);

  @override
  String toString() =>
      'Task $taskId timed out after ${timeout.inSeconds} seconds';
}

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

class TaskQueue<T> {
  final int maxConcurrentTasks;

  final Duration taskTimeout;

  final int maxQueueSize;

  final _taskMap = <T, _QueueItem>{};

  final HeapPriorityQueue<_QueueItem> _priorityQueue;

  final _runningTasks = <T>{};

  // Most recently updated tasks run first.
  TaskQueue({
    this.maxConcurrentTasks = 1,
    this.taskTimeout = const Duration(minutes: 5),
    this.maxQueueSize = 100,
  }) : _priorityQueue = HeapPriorityQueue<_QueueItem>(
         (a, b) => b.lastUpdated.compareTo(a.lastUpdated),
       );

  Future<void> addTask(T id, Future<void> Function() task) {
    if (_taskMap.containsKey(id)) {
      final item = _taskMap[id]!;

      _priorityQueue.remove(item);
      item.updateTimestamp();
      _priorityQueue.add(item);

      return item.future;
    } else {
      _enforceQueueSizeLimit();

      final queueItem = _QueueItem(id, task);
      _taskMap[id] = queueItem;
      _priorityQueue.add(queueItem);

      _processQueue();

      return queueItem.future;
    }
  }

  void _enforceQueueSizeLimit() {
    if (_taskMap.length < maxQueueSize) {
      return;
    }

    final tempQueue = PriorityQueue<_QueueItem>(
      (a, b) => a.lastUpdated.compareTo(b.lastUpdated),
    );

    for (var item in _taskMap.values) {
      tempQueue.add(item);
    }

    final excessItems = _taskMap.length - maxQueueSize + 1;

    for (var i = 0; i < excessItems && tempQueue.isNotEmpty; i++) {
      final oldestItem = tempQueue.removeFirst();
      _priorityQueue.remove(oldestItem);
      _taskMap.remove(oldestItem.id);

      if (!oldestItem.completer.isCompleted) {
        oldestItem.completer.completeError(
          TaskQueueOverflowException(oldestItem.id),
        );
      }
    }
  }

  bool removeTask(T id) {
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
      if (!item.completer.isCompleted) {
        item.completer.completeError(TaskQueueCancelledException(id));
      }

      _taskMap.remove(id);
      return true;
    }

    return false;
  }

  int get pendingTasksCount => _taskMap.length;

  int get runningTasksCount => _runningTasks.length;

  void _processQueue() async {
    _removeTimedOutTasks();

    if (_runningTasks.length >= maxConcurrentTasks || _priorityQueue.isEmpty) {
      return;
    }

    final queueItem = _priorityQueue.removeFirst();
    final taskId = queueItem.id;

    _taskMap.remove(taskId);

    _runningTasks.add(taskId);

    try {
      await queueItem.task();
      if (!queueItem.completer.isCompleted) {
        queueItem.completer.complete();
      }
    } catch (e) {
      if (!queueItem.completer.isCompleted) {
        queueItem.completer.completeError(e);
      }
      log('Task error: $e');
    } finally {
      _runningTasks.remove(taskId);

      _processQueue();
    }
  }

  void _removeTimedOutTasks() {
    final timedOutIds = <T>[];

    for (var entry in _taskMap.entries) {
      if (entry.value.isTimedOut(taskTimeout)) {
        timedOutIds.add(entry.key);
      }
    }
    for (var id in timedOutIds) {
      final item = _taskMap[id]!;
      _priorityQueue.remove(item);

      if (!item.completer.isCompleted) {
        item.completer.completeError(
          TaskQueueTimeoutException(id, taskTimeout),
        );
      }

      _taskMap.remove(id);
    }
  }

  void clear() {
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
