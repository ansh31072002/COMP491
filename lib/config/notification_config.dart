class NotificationConfig {
  static const String EMAILJS_SERVICE_ID = 'service_8x9lgec';
  static const String EMAILJS_TEMPLATE_ID = 'template_v5p25si';
  static const String EMAILJS_USER_ID = 'wDYYxjMLX1OwyDA6w';

  static const String EMAILJS_PRIVATE_KEY = '1vgcz12u1cwYD9dyQuKPm';

  static const String EMAILJS_REQUEST_ORIGIN = '';

  static bool get isConfigured =>
      EMAILJS_SERVICE_ID != 'your_service_id';
}
