import 'package:http/http.dart' as http;

import 'platform_http_client_io.dart'
    if (dart.library.html) 'platform_http_client_web.dart';

http.Client createPlatformHttpClient() => createHttpClient();
