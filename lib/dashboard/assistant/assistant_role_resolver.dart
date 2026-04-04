/// Resolves the assistant role from user data.
/// Used to customize quick actions and flows based on user's role.
enum AssistantUserRole {
  seller,
  buyer,
  admin,
  guest,
}

class AssistantRoleResolver {
  AssistantRoleResolver._();

  /// Resolves the user's role from their Firestore document data.
  /// Supports multiple field names for backwards compatibility.
  static AssistantUserRole resolveRole(Map<String, dynamic>? userData) {
    if (userData == null || userData.isEmpty) {
      return AssistantUserRole.guest;
    }

    final roleField = (userData['userRole'] ??
            userData['role'] ??
            userData['userType'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();

    if (roleField.isEmpty) {
      return AssistantUserRole.guest;
    }

    if (roleField.contains('seller')) {
      return AssistantUserRole.seller;
    }

    if (roleField.contains('buyer')) {
      return AssistantUserRole.buyer;
    }

    if (roleField.contains('admin')) {
      return AssistantUserRole.admin;
    }

    return AssistantUserRole.guest;
  }

  static bool isSeller(AssistantUserRole role) =>
      role == AssistantUserRole.seller;

  static bool isBuyer(AssistantUserRole role) =>
      role == AssistantUserRole.buyer;

  static bool isGuest(AssistantUserRole role) =>
      role == AssistantUserRole.guest;

  static bool isAdmin(AssistantUserRole role) =>
      role == AssistantUserRole.admin;
}
