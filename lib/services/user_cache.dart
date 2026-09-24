// Lightweight invalidation token used to coordinate data freshness across tabs.
// Screens track which version they last loaded; writes bump the version so the
// next refreshData() call skips the 3-minute throttle and re-fetches from Firestore.
class UserCache {
  UserCache._();
  static final UserCache instance = UserCache._();

  int _version = 0;

  // Call after any Firestore write that affects displayed data
  // (quiz save, reading session save, profile update, etc.)
  void invalidate() => _version++;

  int get version => _version;
}
