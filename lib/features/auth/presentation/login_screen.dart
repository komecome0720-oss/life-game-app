import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isRegistering = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleApple() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithApple();
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogle() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('メールアドレスとパスワードを入力してください');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      if (_isRegistering) {
        await repo.createUserWithEmail(email, password);
      } else {
        await repo.signInWithEmail(email, password);
      }
    } catch (e) {
      if (mounted) _showError(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    showAppSnackBar(
      context,
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  String _localizeError(String error) {
    if (error.contains('user-not-found') || error.contains('wrong-password') || error.contains('invalid-credential')) {
      return 'メールアドレスまたはパスワードが正しくありません';
    }
    if (error.contains('email-already-in-use')) return 'このメールアドレスは既に使用されています';
    if (error.contains('weak-password')) return 'パスワードは6文字以上にしてください';
    if (error.contains('invalid-email')) return 'メールアドレスの形式が正しくありません';
    return 'エラーが発生しました';
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: MessageGuard(
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videogame_asset, size: 64, color: color.primary),
                const SizedBox(height: 8),
                Text('ライフゲーム', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: color.primary)),
                const SizedBox(height: 40),

                // Appleでログイン
                _SocialButton(
                  onPressed: _isLoading ? null : _handleApple,
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  icon: Icons.apple,
                  label: 'Appleでログイン',
                ),
                const SizedBox(height: 12),

                // Googleでログイン
                _SocialButton(
                  onPressed: _isLoading ? null : _handleGoogle,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  icon: Icons.g_mobiledata,
                  label: 'Googleでログイン',
                  border: true,
                ),
                const SizedBox(height: 24),

                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('または', style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 24),

                // メール入力
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'パスワード',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _handleEmailAuth,
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isRegistering ? 'アカウント作成' : 'ログイン'),
                  ),
                ),
                const SizedBox(height: 12),

                TextButton(
                  onPressed: () => setState(() => _isRegistering = !_isRegistering),
                  child: Text(_isRegistering ? 'すでにアカウントをお持ちの方はこちら' : 'アカウントを作成する'),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    this.border = false,
  });

  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String label;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: foregroundColor),
        label: Text(label, style: TextStyle(color: foregroundColor, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          elevation: 0,
          side: border ? const BorderSide(color: Colors.black26) : BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
