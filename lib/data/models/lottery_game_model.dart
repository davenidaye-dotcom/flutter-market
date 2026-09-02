import 'package:flutter/foundation.dart';

enum LotteryStatus { open, sealed, drawing, maintenance, closed }

class LotteryGameModel {
  const LotteryGameModel({
    required this.id,
    required this.name,
    required this.currentIssue,
    this.previousIssue,
    this.countdownSeconds = 0,
    this.status = LotteryStatus.open,
    this.previousResults = const [],
    this.isDrawing = false,
    this.openAtEpochMs,
  });

  final String id;
  final String name;
  final String currentIssue;
  final String? previousIssue;
  final int countdownSeconds;
  final LotteryStatus status;
  final List<int> previousResults;
  final bool isDrawing;
  /// 服务端当前期开奖时刻（ms），用于对齐剩余倒计时
  final int? openAtEpochMs;

  LotteryGameModel copyWith({
    String? id,
    String? name,
    String? currentIssue,
    String? previousIssue,
    int? countdownSeconds,
    LotteryStatus? status,
    List<int>? previousResults,
    bool? isDrawing,
    int? openAtEpochMs,
  }) {
    return LotteryGameModel(
      id: id ?? this.id,
      name: name ?? this.name,
      currentIssue: currentIssue ?? this.currentIssue,
      previousIssue: previousIssue ?? this.previousIssue,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      status: status ?? this.status,
      previousResults: previousResults ?? this.previousResults,
      isDrawing: isDrawing ?? this.isDrawing,
      openAtEpochMs: openAtEpochMs ?? this.openAtEpochMs,
    );
  }

  String get statusText => switch (status) {
        LotteryStatus.open => _formatCountdown(countdownSeconds),
        LotteryStatus.sealed => '等待开奖',
        LotteryStatus.drawing => '开奖中',
        LotteryStatus.maintenance => '维护中',
        LotteryStatus.closed => '已关闭',
      };

  String _formatCountdown(int seconds) {
    if (seconds <= 0) return '00:00';
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  bool operator ==(Object other) {
    return other is LotteryGameModel &&
        id == other.id &&
        name == other.name &&
        currentIssue == other.currentIssue &&
        previousIssue == other.previousIssue &&
        countdownSeconds == other.countdownSeconds &&
        status == other.status &&
        isDrawing == other.isDrawing &&
        openAtEpochMs == other.openAtEpochMs &&
        listEquals(previousResults, other.previousResults);
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        currentIssue,
        previousIssue,
        countdownSeconds,
        status,
        isDrawing,
        openAtEpochMs,
        Object.hashAll(previousResults),
      );

  static const mockList = [
    LotteryGameModel(
      id: 'speed_racing',
      name: '极速赛车',
      currentIssue: '34089569',
      previousIssue: '34089569',
      status: LotteryStatus.drawing,
      isDrawing: true,
    ),
    LotteryGameModel(
      id: 'aus_lucky10',
      name: '澳洲幸运10',
      currentIssue: '21343314',
      previousIssue: '21343313',
      countdownSeconds: 241,
      previousResults: [10, 2, 9, 4, 8, 5, 7, 3, 6, 1],
    ),
    LotteryGameModel(
      id: 'bingo_racing_a',
      name: '宾果赛车A',
      currentIssue: '115040681',
      previousIssue: '115040680',
      countdownSeconds: 428,
      previousResults: [10, 2, 9, 4, 8, 5, 7, 3, 6, 1],
    ),
    LotteryGameModel(
      id: 'bingo_racing_b',
      name: '宾果赛车B',
      currentIssue: '115040682',
      previousIssue: '115040681',
      countdownSeconds: 512,
      previousResults: [1, 3, 5, 7, 9, 2, 4, 6, 8, 10],
    ),
    LotteryGameModel(
      id: 'speed_boat',
      name: '极速飞艇',
      currentIssue: '88001234',
      previousIssue: '88001233',
      countdownSeconds: 180,
      previousResults: [8, 5, 2, 10, 1, 4, 7, 3, 9, 6],
    ),
  ];
}
