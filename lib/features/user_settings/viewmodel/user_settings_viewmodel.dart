import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';

class UserSettingsState {
  const UserSettingsState({
    this.settings = const UserSettings(),
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  final UserSettings settings;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  UserSettingsState copyWith({
    UserSettings? settings,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
  }) {
    return UserSettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
    );
  }
}

class UserSettingsViewModel extends Notifier<UserSettingsState> {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  String? _lastLoadedUid;
  UserSettings? _cachedSettings;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  String? get _uid => _auth.currentUser?.uid;

  @override
  UserSettingsState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });

    final uid = ref.watch(
      authStateProvider.select((async) => async.asData?.value?.uid),
    );
    if (uid == null) {
      _lastLoadedUid = null;
      _cachedSettings = null;
      return const UserSettingsState();
    }

    final hasCache = _lastLoadedUid == uid && _cachedSettings != null;
    Future.microtask(() => _subscribe(uid));

    if (hasCache) {
      return UserSettingsState(settings: _cachedSettings!);
    }
    return const UserSettingsState(isLoading: true);
  }

  void _subscribe(String uid) {
    _sub?.cancel();
    _sub = _db.collection('users').doc(uid).snapshots().listen(
      (doc) {
        if (_uid != uid) return;
        final settings = UserSettings.fromFirestore(doc);
        _lastLoadedUid = uid;
        _cachedSettings = settings;
        state = state.copyWith(settings: settings, isLoading: false);
      },
      onError: (Object error) {
        if (_uid != uid) return;
        if (_cachedSettings != null) {
          state = state.copyWith(isLoading: false);
        } else {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'データの読み込みに失敗しました: $error',
          );
        }
      },
    );
  }

  void update(UserSettings settings) {
    _cachedSettings = settings;
    state = state.copyWith(settings: settings);
  }

  Future<String?> uploadAvatar(File file) async {
    final uid = _uid;
    if (uid == null) return null;
    final ref = _storage.ref('avatars/$uid.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  Future<bool> adjustBalance(
    int delta, {
    AdventureEntryType type = AdventureEntryType.manualAdjusted,
    String title = '所持金を手動調整',
    String? sourceId,
    String? note,
  }) async {
    if (delta == 0) return true;
    state = state.copyWith(isSaving: true);
    try {
      final result = await ref.read(economyRepositoryProvider).adjustBalance(
            deltaYen: delta,
            type: type,
            title: title,
            sourceId: sourceId,
            note: note,
          );
      final updated = state.settings.copyWith(
        totalEarned: result.balanceAfterYen,
      );
      _cachedSettings = updated;
      state = state.copyWith(settings: updated, isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: '保存に失敗しました: $e');
      return false;
    }
  }

  Future<bool> save() async {
    final uid = _uid;
    if (uid == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      await _db
          .collection('users')
          .doc(uid)
          .set(state.settings.toFirestore(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
      state = state.copyWith(isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: '保存に失敗しました: $e');
      return false;
    }
  }

  /// 一般・ToDo・カレンダーの環境設定を部分的に永続化する。
  /// 全体 [save] と違い `totalEarned` などを書き戻さないため、
  /// 設定画面の自動保存で残高等を stale 値に上書きしない。
  Future<bool> savePreferences({
    String? themeMode,
    int? weekStartDay,
    int? defaultTodoEstimatedMinutes,
    int? defaultCalendarDurationMinutes,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
      if (themeMode != null) data['themeMode'] = themeMode;
      if (weekStartDay != null) data['weekStartDay'] = weekStartDay;
      if (defaultTodoEstimatedMinutes != null) {
        data['defaultTodoEstimatedMinutes'] = defaultTodoEstimatedMinutes;
      }
      if (defaultCalendarDurationMinutes != null) {
        data['defaultCalendarDurationMinutes'] = defaultCalendarDurationMinutes;
      }
      await _db
          .collection('users')
          .doc(uid)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
      state = state.copyWith(isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: '保存に失敗しました: $e');
      return false;
    }
  }

  /// 瞑想トグルのみを部分的に永続化する（永続設定・日替り切替不可）。
  /// 全体 [save] と違い他フィールドを書き戻さないため、フォーム入力中でも安全に呼べる。
  Future<bool> saveMeditationEnabled(bool enabled) async {
    final uid = _uid;
    if (uid == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      await _db.collection('users').doc(uid).set(
        {
          'meditationEnabled': enabled,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));
      final updated = state.settings.copyWith(meditationEnabled: enabled);
      _cachedSettings = updated;
      state = state.copyWith(settings: updated, isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: '保存に失敗しました: $e');
      return false;
    }
  }

  /// オンボーディング完了フラグのみを部分的に永続化する。
  /// 全体 [save] と違い他フィールドを書き戻さないため、ウィザードや設定画面の保存で
  /// このフラグを stale 値に巻き戻さない。
  Future<bool> saveOnboardingCompleted() async {
    final uid = _uid;
    if (uid == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      await _db.collection('users').doc(uid).set(
        {
          'onboardingCompleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));
      final updated = state.settings.copyWith(onboardingCompleted: true);
      _cachedSettings = updated;
      state = state.copyWith(settings: updated, isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: '保存に失敗しました: $e');
      return false;
    }
  }
}

final userSettingsProvider =
    NotifierProvider<UserSettingsViewModel, UserSettingsState>(
  UserSettingsViewModel.new,
);
