class ExportInquiry {
  const ExportInquiry({
    required this.buyerId,
    required this.commodity,
    required this.quantity,
    required this.userName,
    required this.phone,
    required this.message,
    required this.timestamp,
  });

  final String buyerId;
  final String commodity;
  final String quantity;
  final String userName;
  final String phone;
  final String message;
  final DateTime timestamp;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'buyerId': buyerId,
      'commodity': commodity,
      'quantity': quantity,
      'userName': userName,
      'phone': phone,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
