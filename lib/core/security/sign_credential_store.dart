/// 运行时验签凭证：优先用 OSS 下发的 kid/secret，避免换密钥就要重打包。
class SignCredentialStore {
  SignCredentialStore._();
  static final SignCredentialStore instance = SignCredentialStore._();

  /// 包内打散兜底 kid
  static const bakedKid = '1';

  String kid = bakedKid;
  String? remoteSecret;

  void applyRemote({required String kid, required String secret}) {
    final k = kid.trim();
    final s = secret.trim();
    if (k.isEmpty || s.isEmpty) return;
    this.kid = k;
    remoteSecret = s;
  }

  void clearRemote() {
    kid = bakedKid;
    remoteSecret = null;
  }

  bool get hasRemote => remoteSecret != null && remoteSecret!.isNotEmpty;
}
