import 'dart:collection';
import 'dart:io' as io;

import 'package:relic/relic.dart';
import 'package:relic/src/method/request_method.dart';

class Headers extends UnmodifiableMapView<String, List<String>> {
  /// Request Headers
  static const acceptHeader = "accept";
  static const acceptEncodingHeader = "accept-encoding";
  static const acceptLanguageHeader = "accept-language";
  static const authorizationHeader = "authorization";
  static const expectHeader = "expect";
  static const fromHeader = "from";
  static const hostHeader = "host";
  static const ifMatchHeader = "if-match";
  static const ifModifiedSinceHeader = "if-modified-since";
  static const ifNoneMatchHeader = "if-none-match";
  static const ifRangeHeader = "if-range";
  static const ifUnmodifiedSinceHeader = "if-unmodified-since";
  static const maxForwardsHeader = "max-forwards";
  static const proxyAuthorizationHeader = "proxy-authorization";
  static const rangeHeader = "range";
  static const teHeader = "te";
  static const upgradeHeader = "upgrade";
  static const userAgentHeader = "user-agent";
  static const accessControlRequestHeadersHeader =
      'access-control-request-headers';
  static const accessControlRequestMethodHeader =
      'access-control-request-method';

  /// Response Headers
  static const accessControlAllowCredentialsHeader =
      'access-control-allow-credentials';
  static const accessControlAllowOriginHeader = 'access-control-allow-origin';
  static const accessControlExposeHeadersHeader =
      'access-control-expose-headers';
  static const accessControlMaxAgeHeader = 'access-control-max-age';
  static const ageHeader = "age";
  static const allowHeader = "allow";
  static const cacheControlHeader = "cache-control";
  static const connectionHeader = "connection";
  static const contentDispositionHeader = "content-disposition";
  static const contentEncodingHeader = "content-encoding";
  static const contentLanguageHeader = "content-language";
  static const contentLocationHeader = "content-location";
  static const contentRangeHeader = "content-range";
  static const etagHeader = "etag";
  static const expiresHeader = "expires";
  static const lastModifiedHeader = "last-modified";
  static const locationHeader = "location";
  static const proxyAuthenticateHeader = "proxy-authenticate";
  static const retryAfterHeader = "retry-after";
  static const trailerHeader = "trailer";
  static const transferEncodingHeader = "transfer-encoding";
  static const varyHeader = "vary";
  static const wwwAuthenticateHeader = "www-authenticate";
  static const xPoweredByHeader = 'x-powered-by';

  /// Common Headers (Used in Both Requests and Responses)
  static const acceptRangesHeader = "accept-ranges";
  static const contentLengthHeader = "content-length";
  static const contentTypeHeader = "content-type";

  /// General Headers
  static const dateHeader = "date";
  static const originHeader = "origin";
  static const refererHeader = "referer";
  static const serverHeader = "server";
  static const viaHeader = "via";
  static const cookieHeader = "cookie";
  static const setCookieHeader = "set-cookie";

  /// Security and Modern Headers
  static const strictTransportSecurityHeader = "strict-transport-security";
  static const contentSecurityPolicyHeader = "content-security-policy";
  static const referrerPolicyHeader = "referrer-policy";
  static const permissionsPolicyHeader = "permissions-policy";
  static const accessControlAllowMethodsHeader = "access-control-allow-methods";
  static const accessControlAllowHeadersHeader = "access-control-allow-headers";
  static const clearSiteDataHeader = "clear-site-data";
  static const secFetchDestHeader = "sec-fetch-dest";
  static const secFetchModeHeader = "sec-fetch-mode";
  static const secFetchSiteHeader = "sec-fetch-site";
  static const crossOriginResourcePolicyHeader = "cross-origin-resource-policy";
  static const crossOriginEmbedderPolicyHeader = "cross-origin-embedder-policy";
  static const crossOriginOpenerPolicyHeader = "cross-origin-opener-policy";

  /// Managed headers
  /// Headers that are managed by the library
  static const managedHeaders = <String>{
    dateHeader,
    expiresHeader,
    ifModifiedSinceHeader,
    ifUnmodifiedSinceHeader,
    lastModifiedHeader,

    // General Headers
    originHeader,
    serverHeader,
    viaHeader,

    // Request Headers
    acceptEncodingHeader,
    acceptLanguageHeader,
    accessControlRequestHeadersHeader,
    accessControlRequestMethodHeader,
    ageHeader,
    allowHeader,
    authorizationHeader,
    connectionHeader,
    expectHeader,
    fromHeader,
    hostHeader,
    ifMatchHeader,
    ifNoneMatchHeader,
    ifRangeHeader,
    maxForwardsHeader,
    proxyAuthorizationHeader,
    rangeHeader,
    refererHeader,
    teHeader,
    upgradeHeader,
    userAgentHeader,

    // Response Headers
    accessControlAllowCredentialsHeader,
    accessControlAllowOriginHeader,
    accessControlExposeHeadersHeader,
    accessControlMaxAgeHeader,
    cacheControlHeader,
    contentDispositionHeader,
    contentEncodingHeader,
    contentLanguageHeader,
    contentLocationHeader,
    contentRangeHeader,
    etagHeader,
    locationHeader,
    proxyAuthenticateHeader,
    retryAfterHeader,
    trailerHeader,
    transferEncodingHeader,
    varyHeader,
    wwwAuthenticateHeader,
    xPoweredByHeader,

    // Common Headers (Used in Both Requests and Responses)
    acceptHeader,
    acceptRangesHeader,
    cookieHeader,
    setCookieHeader,

    // These headers are not managed by the Headers class but are
    // managed by the body class and applied later to the response.
    contentLengthHeader,
    contentTypeHeader,

    // Security and Modern Headers
    accessControlAllowHeadersHeader,
    accessControlAllowMethodsHeader,
    clearSiteDataHeader,
    contentSecurityPolicyHeader,
    crossOriginEmbedderPolicyHeader,
    crossOriginOpenerPolicyHeader,
    crossOriginResourcePolicyHeader,
    permissionsPolicyHeader,
    referrerPolicyHeader,
    secFetchDestHeader,
    secFetchModeHeader,
    secFetchSiteHeader,
    strictTransportSecurityHeader,
  };

  Headers copyWith({
    Uri? location,
    ContentRangeHeader? contentRange,
    String? xPoweredBy,
    CustomHeaders? custom,
    DateTime? date,
  }) {
    throw UnimplementedError(); // TODO: Should die
  }

  factory Headers.fromHttpRequest(
    io.HttpRequest request, {
    bool strict = false,
    required String? xPoweredBy,
    DateTime? date,
  }) {
    throw UnimplementedError(); // TODO: Should die
  }

  Map<String, List<String>> failedHeadersToParse = {}; // TODO: Should die

  /// Create a new request headers instance
  factory Headers.request({
    // Date-related headers
    DateTime? date,
    DateTime? ifModifiedSince,
    DateTime? ifUnmodifiedSince,

    // Request Headers
    String? xPoweredBy,
    FromHeader? from,
    Uri? host,
    AcceptEncodingHeader? acceptEncoding,
    AcceptLanguageHeader? acceptLanguage,
    List<String>? accessControlRequestHeaders,
    RequestMethod? accessControlRequestMethod,
    int? age,
    AuthorizationHeader? authorization,
    ConnectionHeader? connection,
    ExpectHeader? expect,
    IfMatchHeader? ifMatch,
    IfNoneMatchHeader? ifNoneMatch,
    IfRangeHeader? ifRange,
    int? maxForwards,
    AuthorizationHeader? proxyAuthorization,
    RangeHeader? range,
    Uri? referer,
    String? userAgent,
    CookieHeader? cookie,
    TEHeader? te,
    UpgradeHeader? upgrade,

    // Fetch Metadata Headers
    SecFetchDestHeader? secFetchDest,
    SecFetchModeHeader? secFetchMode,
    SecFetchSiteHeader? secFetchSite,

    // Common Headers (Used in Both Requests and Responses)
    AcceptHeader? accept,
    AcceptRangesHeader? acceptRanges,
    TransferEncodingHeader? transferEncoding,
    CustomHeaders? custom,
  }) {
    throw UnimplementedError();
  }

  factory Headers.response({
    // Date-related headers
    DateTime? date,
    DateTime? expires,
    DateTime? lastModified,

    // General Headers
    Uri? origin,
    String? server,
    List<String>? via,

    // Used from middleware
    FromHeader? from,

    // Response Headers
    List<RequestMethod>? allow,
    Uri? location,
    String? xPoweredBy,
    bool? accessControlAllowCredentials,
    AccessControlAllowOriginHeader? accessControlAllowOrigin,
    AccessControlExposeHeadersHeader? accessControlExposeHeaders,
    int? accessControlMaxAge,
    CacheControlHeader? cacheControl,
    ContentEncodingHeader? contentEncoding,
    ContentLanguageHeader? contentLanguage,
    Uri? contentLocation,
    ContentRangeHeader? contentRange,
    ETagHeader? etag,
    AuthenticationHeader? proxyAuthenticate,
    AuthenticationHeader? wwwAuthenticate,
    RetryAfterHeader? retryAfter,
    List<String>? trailer,
    VaryHeader? vary,
    ContentDispositionHeader? contentDisposition,

    // Common Headers (Used in Both Requests and Responses)
    AcceptHeader? accept,
    AcceptRangesHeader? acceptRanges,
    TransferEncodingHeader? transferEncoding,
    CustomHeaders? custom,

    // Security and Modern Headers
    SetCookieHeader? setCookie,
    StrictTransportSecurityHeader? strictTransportSecurity,
    ContentSecurityPolicyHeader? contentSecurityPolicy,
    ReferrerPolicyHeader? referrerPolicy,
    PermissionsPolicyHeader? permissionsPolicy,
    AccessControlAllowMethodsHeader? accessControlAllowMethods,
    AccessControlAllowHeadersHeader? accessControlAllowHeaders,
    ClearSiteDataHeader? clearSiteData,
    SecFetchDestHeader? secFetchDest,
    SecFetchModeHeader? secFetchMode,
    SecFetchSiteHeader? secFetchSite,
    CrossOriginResourcePolicyHeader? crossOriginResourcePolicy,
    CrossOriginEmbedderPolicyHeader? crossOriginEmbedderPolicy,
    CrossOriginOpenerPolicyHeader? crossOriginOpenerPolicy,
  }) {
    throw UnimplementedError(); // TODO: Should die
  }
}

/// Headers implementation

/// Date-related headers`
DateTime _decodeDate(List<String> value) {
  final date = DateTime.parse(value.single);
  return date;
}

const _date = HeaderFlyWeight<DateTime>(
  Headers.dateHeader,
  HeaderDecoderMulti(_decodeDate),
);
const date = _date;

const _expires = HeaderFlyWeight<DateTime>(
  Headers.expiresHeader,
  HeaderDecoderMulti(_decodeDate),
);
const expires = _expires;

const _lastModified = HeaderFlyWeight<DateTime>(
  Headers.lastModifiedHeader,
  HeaderDecoderMulti(_decodeDate),
);
const lastModified = _lastModified;

const _ifModifiedSince = HeaderFlyWeight<DateTime>(
  Headers.ifModifiedSinceHeader,
  HeaderDecoderMulti(_decodeDate),
);
const ifModifiedSince = _ifModifiedSince;

const _ifUnmodifiedSince = HeaderFlyWeight<DateTime>(
  Headers.ifUnmodifiedSinceHeader,
  HeaderDecoderMulti(_decodeDate),
);
const ifUnmodifiedSince = _ifUnmodifiedSince;

// General Headers
const _origin = HeaderFlyWeight<Uri>(
  Headers.originHeader,
  HeaderDecoderSingle(parseUri),
);
const origin = _origin;

const _server = HeaderFlyWeight<String>(
  Headers.serverHeader,
  HeaderDecoderSingle(parseString),
);
const server = _server;

const _via = HeaderFlyWeight<List<String>>(
  Headers.viaHeader,
  HeaderDecoderMulti(parseStringList),
);
const via = _via;

/// Request Headers
const _from = HeaderFlyWeight<FromHeader>(
  Headers.fromHeader,
  HeaderDecoderMulti(FromHeader.parse),
);
const from = _from;
const _host = HeaderFlyWeight<Uri>(
  Headers.hostHeader,
  HeaderDecoderSingle(parseUri),
);
const host = _host;

const _acceptEncoding = HeaderFlyWeight<AcceptEncodingHeader>(
  Headers.acceptEncodingHeader,
  HeaderDecoderMulti(AcceptEncodingHeader.parse),
);
const acceptEncoding = _acceptEncoding;

const _acceptLanguage = HeaderFlyWeight<AcceptLanguageHeader>(
  Headers.acceptLanguageHeader,
  HeaderDecoderMulti(AcceptLanguageHeader.parse),
);
const acceptLanguage = _acceptLanguage;

const _accessControlRequestHeaders = HeaderFlyWeight<List<String>>(
  Headers.accessControlRequestHeadersHeader,
  HeaderDecoderMulti(parseStringList),
);
const accessControlRequestHeaders = _accessControlRequestHeaders;

const _accessControlRequestMethod = HeaderFlyWeight<RequestMethod>(
  Headers.accessControlRequestMethodHeader,
  HeaderDecoderSingle(RequestMethod.parse),
);
const accessControlRequestMethod = _accessControlRequestMethod;

const _age = HeaderFlyWeight<int>(
  Headers.ageHeader,
  HeaderDecoderSingle(int.parse),
);
const age = _age;

const _authorization = HeaderFlyWeight<AuthorizationHeader>(
  Headers.authorizationHeader,
  HeaderDecoderSingle(AuthorizationHeader.parse),
);
const authorization = _authorization;

const _connection = HeaderFlyWeight<ConnectionHeader>(
  Headers.connectionHeader,
  HeaderDecoderMulti(ConnectionHeader.parse),
);
const connection = _connection;

const _contentLength = HeaderFlyWeight<int>(
  Headers.contentLengthHeader,
  HeaderDecoderSingle(parseInt),
);
const contentLength = _contentLength;

const _expect = HeaderFlyWeight<ExpectHeader>(
  Headers.expectHeader,
  HeaderDecoderSingle(ExpectHeader.parse),
);
const expect = _expect;

const _ifMatch = HeaderFlyWeight<IfMatchHeader>(
  Headers.ifMatchHeader,
  HeaderDecoderMulti(IfMatchHeader.parse),
);
const ifMatch = _ifMatch;

const _ifNoneMatch = HeaderFlyWeight<IfNoneMatchHeader>(
  Headers.ifNoneMatchHeader,
  HeaderDecoderMulti(IfNoneMatchHeader.parse),
);
const ifNoneMatch = _ifNoneMatch;

const _ifRange = HeaderFlyWeight<IfRangeHeader>(
  Headers.ifRangeHeader,
  HeaderDecoderSingle(IfRangeHeader.parse),
);
const ifRange = _ifRange;

const _maxForwards = HeaderFlyWeight<int>(
  Headers.maxForwardsHeader,
  HeaderDecoderSingle(int.parse),
);
const maxForwards = _maxForwards;

const _proxyAuthorization = HeaderFlyWeight<AuthorizationHeader>(
  Headers.proxyAuthorizationHeader,
  HeaderDecoderSingle(AuthorizationHeader.parse),
);
const proxyAuthorization = _proxyAuthorization;

const _range = HeaderFlyWeight<RangeHeader>(
  Headers.rangeHeader,
  HeaderDecoderSingle(RangeHeader.parse),
);
const range = _range;

const _referer = HeaderFlyWeight<Uri>(
  Headers.refererHeader,
  HeaderDecoderSingle(parseUri),
);
const referer = _referer;

const _userAgent = HeaderFlyWeight<String>(
  Headers.userAgentHeader,
  HeaderDecoderSingle(parseString),
);
const userAgent = _userAgent;

const _te = HeaderFlyWeight<TEHeader>(
  Headers.teHeader,
  HeaderDecoderMulti(TEHeader.parse),
);
const te = _te;

const _upgrade = HeaderFlyWeight<UpgradeHeader>(
  Headers.upgradeHeader,
  HeaderDecoderMulti(UpgradeHeader.parse),
);
const upgrade = _upgrade;

/// Response Headers

const _location = HeaderFlyWeight<Uri>(
  Headers.locationHeader,
  HeaderDecoderSingle(Uri.parse),
);
const location = _location;

const _xPoweredBy = HeaderFlyWeight<String>(
  Headers.xPoweredByHeader,
  HeaderDecoderSingle(parseString),
);
const xPoweredBy = _xPoweredBy;

const _accessControlAllowOrigin =
    HeaderFlyWeight<AccessControlAllowOriginHeader>(
  Headers.accessControlAllowOriginHeader,
  HeaderDecoderSingle(AccessControlAllowOriginHeader.parse),
);
const accessControlAllowOrigin = _accessControlAllowOrigin;

const _accessControlExposeHeaders =
    HeaderFlyWeight<AccessControlExposeHeadersHeader>(
  Headers.accessControlExposeHeadersHeader,
  HeaderDecoderMulti(AccessControlExposeHeadersHeader.parse),
);
const accessControlExposeHeaders = _accessControlExposeHeaders;

const _accessControlMaxAge = HeaderFlyWeight<int>(
  Headers.accessControlMaxAgeHeader,
  HeaderDecoderSingle(parseInt),
);
const accessControlMaxAge = _accessControlMaxAge;

const _allow = HeaderFlyWeight<List<RequestMethod>>(
  Headers.allowHeader,
  HeaderDecoderMulti(parseMethodList),
);
const allow = _allow;

const _cacheControl = HeaderFlyWeight<CacheControlHeader>(
  Headers.cacheControlHeader,
  HeaderDecoderMulti(CacheControlHeader.parse),
);
const cacheControl = _cacheControl;

const _contentEncoding = HeaderFlyWeight<ContentEncodingHeader>(
  Headers.contentEncodingHeader,
  HeaderDecoderMulti(ContentEncodingHeader.parse),
);
const contentEncoding = _contentEncoding;

const _contentLanguage = HeaderFlyWeight<ContentLanguageHeader>(
  Headers.contentLanguageHeader,
  HeaderDecoderMulti(ContentLanguageHeader.parse),
);
const contentLanguage = _contentLanguage;

const _contentLocation = HeaderFlyWeight<Uri>(
  Headers.contentLocationHeader,
  HeaderDecoderSingle(parseUri),
);
const contentLocation = _contentLocation;

const _contentRange = HeaderFlyWeight<ContentRangeHeader>(
  Headers.contentRangeHeader,
  HeaderDecoderSingle(ContentRangeHeader.parse),
);
const contentRange = _contentRange;

const _etag = HeaderFlyWeight<ETagHeader>(
  Headers.etagHeader,
  HeaderDecoderSingle(ETagHeader.parse),
);
const etag = _etag;

const _proxyAuthenticate = HeaderFlyWeight<AuthenticationHeader>(
  Headers.proxyAuthenticateHeader,
  HeaderDecoderSingle(AuthenticationHeader.parse),
);
const proxyAuthenticate = _proxyAuthenticate;

const _retryAfter = HeaderFlyWeight<RetryAfterHeader>(
  Headers.retryAfterHeader,
  HeaderDecoderSingle(RetryAfterHeader.parse),
);
const retryAfter = _retryAfter;

const _trailer = HeaderFlyWeight<List<String>>(
  Headers.trailerHeader,
  HeaderDecoderMulti(parseStringList),
);
const trailer = _trailer;

const _vary = HeaderFlyWeight<VaryHeader>(
  Headers.varyHeader,
  HeaderDecoderMulti(VaryHeader.parse),
);
const vary = _vary;

const _wwwAuthenticate = HeaderFlyWeight<AuthenticationHeader>(
  Headers.wwwAuthenticateHeader,
  HeaderDecoderSingle(AuthenticationHeader.parse),
);
const wwwAuthenticate = _wwwAuthenticate;

const _contentDisposition = HeaderFlyWeight<ContentDispositionHeader>(
  Headers.contentDispositionHeader,
  HeaderDecoderSingle(ContentDispositionHeader.parse),
);
const contentDisposition = _contentDisposition;

/// Common Headers (Used in Both Requests and Responses)

const _accept = HeaderFlyWeight<AcceptHeader>(
  Headers.acceptHeader,
  HeaderDecoderMulti(AcceptHeader.parse),
);
const accept = _accept;

const _acceptRanges = HeaderFlyWeight<AcceptRangesHeader>(
  Headers.acceptRangesHeader,
  HeaderDecoderSingle(AcceptRangesHeader.parse),
);
const acceptRanges = _acceptRanges;

const _transferEncoding = HeaderFlyWeight<TransferEncodingHeader>(
  Headers.transferEncodingHeader,
  HeaderDecoderMulti(TransferEncodingHeader.parse),
);
const transferEncoding = _transferEncoding;

const _cookie = HeaderFlyWeight<CookieHeader>(
  Headers.cookieHeader,
  HeaderDecoderSingle(CookieHeader.parse),
);
const cookie = _cookie;

const _setCookie = HeaderFlyWeight<SetCookieHeader>(
  Headers.setCookieHeader,
  HeaderDecoderSingle(SetCookieHeader.parse),
);
const setCookie = _setCookie;

/// Security and Modern Headers

const _strictTransportSecurity = HeaderFlyWeight<StrictTransportSecurityHeader>(
  Headers.strictTransportSecurityHeader,
  HeaderDecoderSingle(StrictTransportSecurityHeader.parse),
);
const strictTransportSecurity = _strictTransportSecurity;

const _contentSecurityPolicy = HeaderFlyWeight<ContentSecurityPolicyHeader>(
  Headers.contentSecurityPolicyHeader,
  HeaderDecoderSingle(ContentSecurityPolicyHeader.parse),
);
const contentSecurityPolicy = _contentSecurityPolicy;

const _referrerPolicy = HeaderFlyWeight<ReferrerPolicyHeader>(
  Headers.referrerPolicyHeader,
  HeaderDecoderSingle(ReferrerPolicyHeader.parse),
);
const referrerPolicy = _referrerPolicy;

const _permissionsPolicy = HeaderFlyWeight<PermissionsPolicyHeader>(
  Headers.permissionsPolicyHeader,
  HeaderDecoderSingle(PermissionsPolicyHeader.parse),
);
const permissionsPolicy = _permissionsPolicy;

const _accessControlAllowCredentials = HeaderFlyWeight<bool>(
  Headers.accessControlAllowCredentialsHeader,
  HeaderDecoderSingle(parseBool),
);
const accessControlAllowCredentials = _accessControlAllowCredentials;

const _accessControlAllowMethods =
    HeaderFlyWeight<AccessControlAllowMethodsHeader>(
  Headers.accessControlAllowMethodsHeader,
  HeaderDecoderMulti(AccessControlAllowMethodsHeader.parse),
);
const accessControlAllowMethods = _accessControlAllowMethods;

const _accessControlAllowHeaders =
    HeaderFlyWeight<AccessControlAllowHeadersHeader>(
  Headers.accessControlAllowHeadersHeader,
  HeaderDecoderMulti(AccessControlAllowHeadersHeader.parse),
);
const accessControlAllowHeaders = _accessControlAllowHeaders;

const _clearSiteData = HeaderFlyWeight<ClearSiteDataHeader>(
  Headers.clearSiteDataHeader,
  HeaderDecoderMulti(ClearSiteDataHeader.parse),
);
const clearSiteData = _clearSiteData;

const _secFetchDest = HeaderFlyWeight<SecFetchDestHeader>(
  Headers.secFetchDestHeader,
  HeaderDecoderSingle(SecFetchDestHeader.parse),
);
const secFetchDest = _secFetchDest;

const _secFetchMode = HeaderFlyWeight<SecFetchModeHeader>(
  Headers.secFetchModeHeader,
  HeaderDecoderSingle(SecFetchModeHeader.parse),
);
const secFetchMode = _secFetchMode;

const _secFetchSite = HeaderFlyWeight<SecFetchSiteHeader>(
  Headers.secFetchSiteHeader,
  HeaderDecoderSingle(SecFetchSiteHeader.parse),
);
const secFetchSite = _secFetchSite;

const _crossOriginResourcePolicy =
    HeaderFlyWeight<CrossOriginResourcePolicyHeader>(
  Headers.crossOriginResourcePolicyHeader,
  HeaderDecoderSingle(CrossOriginResourcePolicyHeader.parse),
);
const setCrossOriginResourcePolicy = _crossOriginResourcePolicy;

const _crossOriginEmbedderPolicy =
    HeaderFlyWeight<CrossOriginEmbedderPolicyHeader>(
  Headers.crossOriginEmbedderPolicyHeader,
  HeaderDecoderSingle(CrossOriginEmbedderPolicyHeader.parse),
);
const setCrossOriginEmbedderPolicy = _crossOriginEmbedderPolicy;

const _crossOriginOpenerPolicy = HeaderFlyWeight<CrossOriginOpenerPolicyHeader>(
  Headers.crossOriginOpenerPolicyHeader,
  HeaderDecoderSingle(CrossOriginOpenerPolicyHeader.parse),
);
const setCrossOriginOpenerPolicy = _crossOriginOpenerPolicy;

extension TypedHeadersEx on Headers {
  Header<DateTime> get date_ => _date[this];
  DateTime? get date => date_();

  Header<DateTime> get expires_ => _expires[this];
  DateTime? get expires => expires_();

  Header<DateTime> get lastModified_ => _lastModified[this];
  DateTime? get lastModified => lastModified_();

  Header<DateTime> get ifModifiedSince_ => _ifModifiedSince[this];
  DateTime? get ifModifiedSince => ifModifiedSince_();

  Header<DateTime> get ifUnmodifiedSince_ => _ifUnmodifiedSince[this];
  DateTime? get ifUnmodifiedSince => ifUnmodifiedSince_();

  Header<Uri> get origin_ => _origin[this];
  Uri? get origin => origin_();

  Header<String> get server_ => _server[this];
  String? get server => server_();

  Header<List<String>> get via_ => _via[this];
  List<String>? get via => via_();

  Header<FromHeader> get from_ => _from[this];
  FromHeader? get from => from_();

  Header<Uri> get host_ => _host[this];
  Uri? get host => host_();

  Header<AcceptEncodingHeader> get acceptEncoding_ => _acceptEncoding[this];
  AcceptEncodingHeader? get acceptEncoding => acceptEncoding_();

  Header<AcceptLanguageHeader> get acceptLanguage_ => _acceptLanguage[this];
  AcceptLanguageHeader? get acceptLanguage => acceptLanguage_();

  Header<List<String>> get accessControlRequestHeaders_ =>
      _accessControlRequestHeaders[this];
  List<String>? get accessControlRequestHeaders =>
      accessControlRequestHeaders_();

  Header<RequestMethod> get accessControlRequestMethod_ =>
      _accessControlRequestMethod[this];
  RequestMethod? get accessControlRequestMethod =>
      accessControlRequestMethod_();

  Header<int> get age_ => _age[this];
  int? get age => age_();

  Header<AuthorizationHeader> get authorization_ => _authorization[this];
  AuthorizationHeader? get authorization => authorization_();

  Header<ConnectionHeader> get connection_ => _connection[this];
  ConnectionHeader? get connection => connection_();

  Header<int> get contentLength_ => _contentLength[this];
  int? get contentLength => contentLength_();

  Header<ExpectHeader> get expect_ => _expect[this];
  ExpectHeader? get expect => expect_();

  Header<IfMatchHeader> get ifMatch_ => _ifMatch[this];
  IfMatchHeader? get ifMatch => ifMatch_();

  Header<IfNoneMatchHeader> get ifNoneMatch_ => _ifNoneMatch[this];
  IfNoneMatchHeader? get ifNoneMatch => ifNoneMatch_();

  Header<IfRangeHeader> get ifRange_ => _ifRange[this];
  IfRangeHeader? get ifRange => ifRange_();

  Header<int> get maxForwards_ => _maxForwards[this];
  int? get maxForwards => maxForwards_();

  Header<AuthorizationHeader> get proxyAuthorization_ =>
      _proxyAuthorization[this];
  AuthorizationHeader? get proxyAuthorization => proxyAuthorization_();

  Header<RangeHeader> get range_ => _range[this];
  RangeHeader? get range => range_();

  Header<Uri> get referer_ => _referer[this];
  Uri? get referer => referer_();

  Header<String> get userAgent_ => _userAgent[this];
  String? get userAgent => userAgent_();

  Header<TEHeader> get te_ => _te[this];
  TEHeader? get te => te_();

  Header<UpgradeHeader> get upgrade_ => _upgrade[this];
  UpgradeHeader? get upgrade => upgrade_();

  Header<Uri> get location_ => _location[this];
  Uri? get location => location_();

  Header<String> get xPoweredBy_ => _xPoweredBy[this];
  String? get xPoweredBy => xPoweredBy_();

  Header<AccessControlAllowOriginHeader> get accessControlAllowOrigin_ =>
      _accessControlAllowOrigin[this];
  AccessControlAllowOriginHeader? get accessControlAllowOrigin =>
      accessControlAllowOrigin_();

  Header<AccessControlExposeHeadersHeader> get accessControlExposeHeaders_ =>
      _accessControlExposeHeaders[this];
  AccessControlExposeHeadersHeader? get accessControlExposeHeaders =>
      accessControlExposeHeaders_();

  Header<int> get accessControlMaxAge_ => _accessControlMaxAge[this];
  int? get accessControlMaxAge => accessControlMaxAge_();

  Header<List<RequestMethod>> get allow_ => _allow[this];
  List<RequestMethod>? get allow => allow_();

  Header<CacheControlHeader> get cacheControl_ => _cacheControl[this];
  CacheControlHeader? get cacheControl => cacheControl_();

  Header<ContentEncodingHeader> get contentEncoding_ => _contentEncoding[this];
  ContentEncodingHeader? get contentEncoding => contentEncoding_();

  Header<ContentLanguageHeader> get contentLanguage_ => _contentLanguage[this];
  ContentLanguageHeader? get contentLanguage => contentLanguage_();

  Header<Uri> get contentLocation_ => _contentLocation[this];
  Uri? get contentLocation => contentLocation_();

  Header<ContentRangeHeader> get contentRange_ => _contentRange[this];
  ContentRangeHeader? get contentRange => contentRange_();

  Header<ETagHeader> get etag_ => _etag[this];
  ETagHeader? get etag => etag_();

  Header<AuthenticationHeader> get proxyAuthenticate_ =>
      _proxyAuthenticate[this];
  AuthenticationHeader? get proxyAuthenticate => proxyAuthenticate_();

  Header<RetryAfterHeader> get retryAfter_ => _retryAfter[this];
  RetryAfterHeader? get retryAfter => retryAfter_();

  Header<List<String>> get trailer_ => _trailer[this];
  List<String>? get trailer => trailer_();

  Header<VaryHeader> get vary_ => _vary[this];
  VaryHeader? get vary => vary_();

  Header<AuthenticationHeader> get wwwAuthenticate_ => _wwwAuthenticate[this];
  AuthenticationHeader? get wwwAuthenticate => wwwAuthenticate_();

  Header<ContentDispositionHeader> get contentDisposition_ =>
      _contentDisposition[this];
  ContentDispositionHeader? get contentDisposition => contentDisposition_();

  Header<AcceptHeader> get accept_ => _accept[this];
  AcceptHeader? get accept => accept_();

  Header<AcceptRangesHeader> get acceptRanges_ => _acceptRanges[this];
  AcceptRangesHeader? get acceptRanges => acceptRanges_();

  Header<TransferEncodingHeader> get transferEncoding_ =>
      _transferEncoding[this];
  TransferEncodingHeader? get transferEncoding => transferEncoding_();

  Header<CookieHeader> get cookie_ => _cookie[this];
  CookieHeader? get cookie => cookie_();

  Header<SetCookieHeader> get setCookie_ => _setCookie[this];
  SetCookieHeader? get setCookie => setCookie_();

  Header<StrictTransportSecurityHeader> get strictTransportSecurity_ =>
      _strictTransportSecurity[this];
  StrictTransportSecurityHeader? get strictTransportSecurity =>
      strictTransportSecurity_();

  Header<ContentSecurityPolicyHeader> get contentSecurityPolicy_ =>
      _contentSecurityPolicy[this];
  ContentSecurityPolicyHeader? get contentSecurityPolicy =>
      contentSecurityPolicy_();

  Header<ReferrerPolicyHeader> get referrerPolicy_ => _referrerPolicy[this];
  ReferrerPolicyHeader? get referrerPolicy => referrerPolicy_();

  Header<PermissionsPolicyHeader> get permissionsPolicy_ =>
      _permissionsPolicy[this];
  PermissionsPolicyHeader? get permissionsPolicy => permissionsPolicy_();

  Header<bool> get accessControlAllowCredentials_ =>
      _accessControlAllowCredentials[this];
  bool? get accessControlAllowCredentials => accessControlAllowCredentials_();

  Header<AccessControlAllowMethodsHeader> get accessControlAllowMethods_ =>
      _accessControlAllowMethods[this];
  AccessControlAllowMethodsHeader? get accessControlAllowMethods =>
      accessControlAllowMethods_();

  Header<AccessControlAllowHeadersHeader> get accessControlAllowHeaders_ =>
      _accessControlAllowHeaders[this];
  AccessControlAllowHeadersHeader? get accessControlAllowHeaders =>
      accessControlAllowHeaders_();

  Header<ClearSiteDataHeader> get clearSiteData_ => _clearSiteData[this];
  ClearSiteDataHeader? get clearSiteData => clearSiteData_();

  Header<SecFetchDestHeader> get secFetchDest_ => _secFetchDest[this];
  SecFetchDestHeader? get secFetchDest => secFetchDest_();

  Header<SecFetchModeHeader> get secFetchMode_ => _secFetchMode[this];
  SecFetchModeHeader? get secFetchMode => secFetchMode_();

  Header<SecFetchSiteHeader> get secFetchSite_ => _secFetchSite[this];
  SecFetchSiteHeader? get secFetchSite => secFetchSite_();

  Header<CrossOriginResourcePolicyHeader> get crossOriginResourcePolicy_ =>
      _crossOriginResourcePolicy[this];
  CrossOriginResourcePolicyHeader? get crossOriginResourcePolicy =>
      crossOriginResourcePolicy_();

  Header<CrossOriginEmbedderPolicyHeader> get crossOriginEmbedderPolicy_ =>
      _crossOriginEmbedderPolicy[this];
  CrossOriginEmbedderPolicyHeader? get crossOriginEmbedderPolicy =>
      crossOriginEmbedderPolicy_();

  Header<CrossOriginOpenerPolicyHeader> get crossOriginOpenerPolicy_ =>
      _crossOriginOpenerPolicy[this];
  CrossOriginOpenerPolicyHeader? get crossOriginOpenerPolicy =>
      crossOriginOpenerPolicy_();
}

void testFoo() {
  final headers = Headers();
  final y = headers.date_.valueOrNull ?? DateTime.now();
  final z = headers.date_.isSet ? headers.date_.value : DateTime.now;
  bool b = headers.date_() == null;

  final s = headers.expires_.raw;
  final s2 = headers[Headers.expiresHeader];
  final d = headers.expires_.value;
  headers.expires_.isSet;
  final e = headers.expires;
  final e2 = headers.expires_.valueOrNull;
  headers.expires_.isValid;
  headers.expires_.value;
  headers.expires_.valueOrNull;

  headers.lastModified == null;
  headers.lastModified_.isValid;
  headers.lastModified_.value;
}
