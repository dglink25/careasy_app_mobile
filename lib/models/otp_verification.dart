// models/otp_verification.dart
class OtpVerification {
  final String identifier;
  final String type;
  final String? verifyToken;
  final String? masked;
  final int? expiresIn;
  final int? resendAfter;

  OtpVerification({
    required this.identifier,
    required this.type,
    this.verifyToken,
    this.masked,
    this.expiresIn,
    this.resendAfter,
  });

  factory OtpVerification.fromSendResponse(Map<String, dynamic> json) {
    return OtpVerification(
      identifier: '',
      type: '',
      masked: json['masked'],
      expiresIn: json['expires_in'],
      resendAfter: json['resend_after'],
    );
  }

  factory OtpVerification.fromCheckResponse(Map<String, dynamic> json) {
    return OtpVerification(
      identifier: '',
      type: '',
      verifyToken: json['verify_token'],
      expiresIn: json['expires_in'],
    );
  }
}