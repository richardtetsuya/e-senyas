import 'package:flutter/material.dart';
import '../models/detected_sign.dart';
import '../models/history_entry.dart';

/// Application-wide state mirroring the React AppContext.
///
/// Manages dark-mode preference and translation history.
class AppProvider extends ChangeNotifier {
  // ── Dark mode ──
  bool _darkMode = false;
  bool get darkMode => _darkMode;
  void setDarkMode(bool value) {
    _darkMode = value;
    notifyListeners();
  }

  // ── Hand Landmarks & Skeleton Overlay ──
  bool _showHandLandmarks = true;
  bool get showHandLandmarks => _showHandLandmarks;
  void setShowHandLandmarks(bool value) {
    _showHandLandmarks = value;
    notifyListeners();
  }

  // ── History ──
  List<HistoryEntry> _historyItems = [
    HistoryEntry(
      id: 1,
      translatedSentence: 'Kumusta ka?',
      detectedSigns: const [
        DetectedSign(sign: 'Kumusta', confidence: 92),
        DetectedSign(sign: 'ka', confidence: 88),
      ],
      timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
    ),
    HistoryEntry(
      id: 2,
      translatedSentence: 'Magandang umaga',
      detectedSigns: const [
        DetectedSign(sign: 'Magandang', confidence: 95),
        DetectedSign(sign: 'umaga', confidence: 91),
      ],
      timestamp: DateTime.now().subtract(const Duration(minutes: 90)),
    ),
    HistoryEntry(
      id: 3,
      translatedSentence: 'Salamat',
      detectedSigns: const [
        DetectedSign(sign: 'Salamat', confidence: 97),
      ],
      timestamp: DateTime.now().subtract(const Duration(minutes: 180)),
    ),
  ];

  List<HistoryEntry> get historyItems => List.unmodifiable(_historyItems);

  void addHistoryItem({
    required String translatedSentence,
    required List<DetectedSign> detectedSigns,
  }) {
    final entry = HistoryEntry(
      id: DateTime.now().millisecondsSinceEpoch,
      translatedSentence: translatedSentence,
      detectedSigns: detectedSigns,
      timestamp: DateTime.now(),
    );
    _historyItems = [entry, ..._historyItems];
    notifyListeners();
  }

  void deleteHistoryItem(int id) {
    _historyItems = _historyItems.where((e) => e.id != id).toList();
    notifyListeners();
  }

  void clearHistory() {
    _historyItems = [];
    notifyListeners();
  }
}
