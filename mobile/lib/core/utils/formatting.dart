/// 경과 시간 포맷 — intl 패키지 없이 직접 구현.
/// 서버 클럭 스큐로 미래 날짜가 오면 '방금 전' 처리.
String timeAgo(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.isNegative || diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 30) return '${diff.inDays}일 전';
  return '${diff.inDays ~/ 30}달 전';
}

/// 가격 포맷 — intl 패키지 없이 직접 구현.
String formatPrice(int price) {
  if (price < 0) return '-${formatPrice(-price)}';
  final s = price.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${buf.toString()}원';
}
