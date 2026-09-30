/// Process-wide device-class flag. Computed once at startup from the native
/// `isTv` channel and registered in GetIt. Read via `sl<AppMode>().isTv`.
/// On a phone this is always false, so every `if (isTv)` branch is skipped.
class AppMode {
  final bool isTv;
  final bool isDesktop;
  const AppMode({
    required this.isTv,
    this.isDesktop = false,
  });
}
