import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/pomodoro/data/pomodoro_settings_repository.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late PomodoroSettingsRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    repo = PomodoroSettingsRepository(db: firestore, auth: auth);
  });

  test('未設定なら read() は既定値を返す', () async {
    final settings = await repo.read();
    expect(settings.workMinutes, PomodoroSettings.defaultWorkMinutes);
  });

  test('save() 後に read() で同じ値が読める', () async {
    const settings = PomodoroSettings(
      workMinutes: 50,
      shortBreakMinutes: 10,
      setCount: 2,
      longBreakMinutes: 30,
      bgmWork: PomodoroBgm.fire,
      bgmShortBreak: PomodoroBgm.birds,
      bgmLongBreak: PomodoroBgm.waves,
      soundWorkStart: PomodoroChime.bell,
      soundShortBreakStart: PomodoroChime.trumpet,
      soundLongBreakStart: PomodoroChime.drum,
    );
    await repo.save(settings);

    final read = await repo.read();
    expect(read.workMinutes, 50);
    expect(read.setCount, 2);
    expect(read.bgmWork, PomodoroBgm.fire);
    expect(read.soundWorkStart, PomodoroChime.bell);

    final data = await firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('pomodoro')
        .get();
    expect(data.data(), isNotNull);
    expect(data.data()!['workMinutes'], 50);
  });

  test('save() 後に watch() のストリームへ反映される', () async {
    const settings = PomodoroSettings(
      workMinutes: 45,
      shortBreakMinutes: 5,
      setCount: 4,
      longBreakMinutes: 15,
      bgmWork: PomodoroBgm.waves,
      bgmShortBreak: PomodoroBgm.river,
      bgmLongBreak: PomodoroBgm.birds,
      soundWorkStart: PomodoroChime.drum,
      soundShortBreakStart: PomodoroChime.bell,
      soundLongBreakStart: PomodoroChime.trumpet,
    );
    await repo.save(settings);

    final result = await repo.watch().first;
    expect(result.workMinutes, 45);
  });

  test('未認証で watch() すると既定値を流す', () async {
    final auth = _MockFirebaseAuth();
    when(() => auth.currentUser).thenReturn(null);
    final unauth = PomodoroSettingsRepository(db: firestore, auth: auth);
    final result = await unauth.watch().first;
    expect(result.workMinutes, PomodoroSettings.defaultWorkMinutes);
  });
}
