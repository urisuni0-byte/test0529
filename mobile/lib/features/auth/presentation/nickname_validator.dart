/// Shared nickname validation used by OnboardingScreen and SettingsScreen.
///
/// Rules: Korean precomposed syllables (가–힣), English letters, digits; 2–15 chars.
final nicknameRegex = RegExp(r'^[가-힣a-zA-Z0-9]{2,15}$');

/// Returns an error message string, or null if [value] is valid.
///
/// **Empty string returns null** (no error) — the caller is responsible for
/// checking that the value is non-empty before accepting it as valid.
/// Use [isNicknameSubmittable] when the empty-string check must be implicit.
String? validateNickname(String value) {
  if (value.isEmpty) return null;
  if (value.length < 2) return '닉네임은 2자 이상이어야 합니다.';
  if (value.length > 15) return '닉네임은 15자 이하여야 합니다.';
  if (!nicknameRegex.hasMatch(value)) return '한글, 영문, 숫자만 사용할 수 있습니다.';
  return null;
}

/// Returns true when [value] is non-empty AND passes all format rules.
/// Use this as the submit guard instead of combining isNotEmpty with validateNickname.
bool isNicknameSubmittable(String value) =>
    value.isNotEmpty && validateNickname(value) == null;
