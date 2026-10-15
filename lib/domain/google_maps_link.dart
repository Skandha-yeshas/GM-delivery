/// Validates a saved Maps link without resolving redirects or extracting GPS.
Uri googleMapsUri(String value) {
  final uri = Uri.tryParse(value.trim());
  const hosts = {
    'google.com',
    'www.google.com',
    'maps.google.com',
    'google.co.in',
    'www.google.co.in',
    'maps.google.co.in',
    'maps.app.goo.gl',
    'goo.gl',
  };
  if (uri == null ||
      uri.scheme != 'https' ||
      !hosts.contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      value.trim().length > 4096 ||
      RegExp(r'\s').hasMatch(value.trim()) ||
      (uri.host == 'goo.gl' && !uri.path.startsWith('/maps/')) ||
      (!uri.host.startsWith('maps.') &&
          uri.host != 'goo.gl' &&
          !uri.path.startsWith('/maps'))) {
    throw const FormatException(
      'Paste a Google Maps HTTPS link, or leave it empty.',
    );
  }
  return uri;
}

bool isGoogleMapsLink(String value) {
  try {
    googleMapsUri(value);
    return true;
  } on FormatException {
    return false;
  }
}
