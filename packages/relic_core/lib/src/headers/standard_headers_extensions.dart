import 'dart:collection';

import 'package:relic_headers/relic_headers.dart';

import '../body/body.dart';
import '../router/method.dart';
import 'header_accessor.dart';
import 'headers.dart';
import 'typed/typed_headers.dart';

extension HeadersEx on HeaderValues {
  DateTime? get date => this(Headers.date);
  DateTime? get expires => this(Headers.expires);
  DateTime? get lastModified => this(Headers.lastModified);
  DateTime? get ifModifiedSince => this(Headers.ifModifiedSince);
  DateTime? get ifUnmodifiedSince => this(Headers.ifUnmodifiedSince);
  Uri? get origin => this(Headers.origin);
  String? get server => this(Headers.server);
  List<String>? get via => this(Headers.via);
  FromHeader? get from => this(Headers.from);
  HostHeader? get host => this(Headers.host);
  AcceptEncodingHeader? get acceptEncoding => this(Headers.acceptEncoding);
  AcceptLanguageHeader? get acceptLanguage => this(Headers.acceptLanguage);
  List<String>? get accessControlRequestHeaders =>
      this(Headers.accessControlRequestHeaders);
  Method? get accessControlRequestMethod =>
      this(Headers.accessControlRequestMethod);
  int? get age => this(Headers.age);
  AuthorizationHeader? get authorization => this(Headers.authorization);
  ConnectionHeader? get connection => this(Headers.connection);
  int? get contentLength => this(Headers.contentLength);

  /// The parsed Content-Type header.
  ///
  /// Set Content-Type through the body, such as with the `mimeType` argument
  /// of [Body.fromString]. On a request, read [Body.bodyType] instead. It
  /// changes with `copyWith(body: ...)`, and this header does not.
  ContentTypeHeader? get contentType => this(_contentType);

  ExpectHeader? get expect => this(Headers.expect);
  IfMatchHeader? get ifMatch => this(Headers.ifMatch);
  IfNoneMatchHeader? get ifNoneMatch => this(Headers.ifNoneMatch);
  IfRangeHeader? get ifRange => this(Headers.ifRange);
  int? get maxForwards => this(Headers.maxForwards);
  AuthorizationHeader? get proxyAuthorization =>
      this(Headers.proxyAuthorization);
  RangeHeader? get range => this(Headers.range);
  Uri? get referer => this(Headers.referer);
  String? get userAgent => this(Headers.userAgent);
  TEHeader? get te => this(Headers.te);
  UpgradeHeader? get upgrade => this(Headers.upgrade);
  Uri? get location => this(Headers.location);
  String? get xPoweredBy => this(Headers.xPoweredBy);
  AccessControlAllowOriginHeader? get accessControlAllowOrigin =>
      this(Headers.accessControlAllowOrigin);
  AccessControlExposeHeadersHeader? get accessControlExposeHeaders =>
      this(Headers.accessControlExposeHeaders);
  int? get accessControlMaxAge => this(Headers.accessControlMaxAge);
  Set<Method>? get allow => this(Headers.allow);
  CacheControlHeader? get cacheControl => this(Headers.cacheControl);
  ContentEncodingHeader? get contentEncoding => this(Headers.contentEncoding);
  ContentLanguageHeader? get contentLanguage => this(Headers.contentLanguage);
  Uri? get contentLocation => this(Headers.contentLocation);
  ContentRangeHeader? get contentRange => this(Headers.contentRange);
  ETagHeader? get etag => this(Headers.etag);
  AuthenticationHeader? get proxyAuthenticate =>
      this(Headers.proxyAuthenticate);
  RetryAfterHeader? get retryAfter => this(Headers.retryAfter);
  List<String>? get trailer => this(Headers.trailer);
  VaryHeader? get vary => this(Headers.vary);
  AuthenticationHeader? get wwwAuthenticate => this(Headers.wwwAuthenticate);
  ContentDispositionHeader? get contentDisposition =>
      this(Headers.contentDisposition);
  AcceptHeader? get accept => this(Headers.accept);
  AcceptRangesHeader? get acceptRanges => this(Headers.acceptRanges);
  TransferEncodingHeader? get transferEncoding =>
      this(Headers.transferEncoding);
  CookieHeader? get cookie => this(Headers.cookie);
  SetCookieHeader? get setCookie => this(Headers.setCookie);
  StrictTransportSecurityHeader? get strictTransportSecurity =>
      this(Headers.strictTransportSecurity);
  ContentSecurityPolicyHeader? get contentSecurityPolicy =>
      this(Headers.contentSecurityPolicy);
  ReferrerPolicyHeader? get referrerPolicy => this(Headers.referrerPolicy);
  PermissionsPolicyHeader? get permissionsPolicy =>
      this(Headers.permissionsPolicy);
  bool? get accessControlAllowCredentials =>
      this(Headers.accessControlAllowCredentials);
  AccessControlAllowMethodsHeader? get accessControlAllowMethods =>
      this(Headers.accessControlAllowMethods);
  AccessControlAllowHeadersHeader? get accessControlAllowHeaders =>
      this(Headers.accessControlAllowHeaders);
  ClearSiteDataHeader? get clearSiteData => this(Headers.clearSiteData);
  SecFetchDestHeader? get secFetchDest => this(Headers.secFetchDest);
  SecFetchModeHeader? get secFetchMode => this(Headers.secFetchMode);
  SecFetchSiteHeader? get secFetchSite => this(Headers.secFetchSite);
  CrossOriginResourcePolicyHeader? get crossOriginResourcePolicy =>
      this(Headers.crossOriginResourcePolicy);
  CrossOriginEmbedderPolicyHeader? get crossOriginEmbedderPolicy =>
      this(Headers.crossOriginEmbedderPolicy);
  CrossOriginOpenerPolicyHeader? get crossOriginOpenerPolicy =>
      this(Headers.crossOriginOpenerPolicy);
  ForwardedHeader? get forwarded => this(Headers.forwarded);
  XForwardedForHeader? get xForwardedFor => this(Headers.xForwardedFor);
}

extension MutableHeadersEx on MutableHeaders {
  set date(final DateTime? value) => assign(Headers.date, value);
  set expires(final DateTime? value) => assign(Headers.expires, value);
  set lastModified(final DateTime? value) =>
      assign(Headers.lastModified, value);
  set ifModifiedSince(final DateTime? value) =>
      assign(Headers.ifModifiedSince, value);
  set ifUnmodifiedSince(final DateTime? value) =>
      assign(Headers.ifUnmodifiedSince, value);
  set origin(final Uri? value) => assign(Headers.origin, value);
  set server(final String? value) => assign(Headers.server, value);
  set via(final List<String>? value) => assign(Headers.via, value);
  set from(final FromHeader? value) => assign(Headers.from, value);
  set host(final HostHeader? value) => assign(Headers.host, value);
  set acceptEncoding(final AcceptEncodingHeader? value) =>
      assign(Headers.acceptEncoding, value);
  set acceptLanguage(final AcceptLanguageHeader? value) =>
      assign(Headers.acceptLanguage, value);
  set accessControlRequestHeaders(final List<String>? value) =>
      assign(Headers.accessControlRequestHeaders, value);
  set accessControlRequestMethod(final Method? value) =>
      assign(Headers.accessControlRequestMethod, value);
  set age(final int? value) => assign(Headers.age, value);
  set authorization(final AuthorizationHeader? value) =>
      assign(Headers.authorization, value);
  set connection(final ConnectionHeader? value) =>
      assign(Headers.connection, value);
  set contentLength(final int? value) => assign(Headers.contentLength, value);
  set expect(final ExpectHeader? value) => assign(Headers.expect, value);
  set ifMatch(final IfMatchHeader? value) => assign(Headers.ifMatch, value);
  set ifNoneMatch(final IfNoneMatchHeader? value) =>
      assign(Headers.ifNoneMatch, value);
  set ifRange(final IfRangeHeader? value) => assign(Headers.ifRange, value);
  set maxForwards(final int? value) => assign(Headers.maxForwards, value);
  set proxyAuthorization(final AuthorizationHeader? value) =>
      assign(Headers.proxyAuthorization, value);
  set range(final RangeHeader? value) => assign(Headers.range, value);
  set referer(final Uri? value) => assign(Headers.referer, value);
  set userAgent(final String? value) => assign(Headers.userAgent, value);
  set te(final TEHeader? value) => assign(Headers.te, value);
  set upgrade(final UpgradeHeader? value) => assign(Headers.upgrade, value);
  set location(final Uri? value) => assign(Headers.location, value);
  set xPoweredBy(final String? value) => assign(Headers.xPoweredBy, value);
  set accessControlAllowOrigin(final AccessControlAllowOriginHeader? value) =>
      assign(Headers.accessControlAllowOrigin, value);
  set accessControlExposeHeaders(
    final AccessControlExposeHeadersHeader? value,
  ) => assign(Headers.accessControlExposeHeaders, value);
  set accessControlMaxAge(final int? value) =>
      assign(Headers.accessControlMaxAge, value);
  set allow(final Set<Method>? value) => assign(
    Headers.allow,
    value != null ? SplayTreeSet.of(value, Enum.compareByIndex) : null,
  );
  set cacheControl(final CacheControlHeader? value) =>
      assign(Headers.cacheControl, value);
  set contentEncoding(final ContentEncodingHeader? value) =>
      assign(Headers.contentEncoding, value);
  set contentLanguage(final ContentLanguageHeader? value) =>
      assign(Headers.contentLanguage, value);
  set contentLocation(final Uri? value) =>
      assign(Headers.contentLocation, value);
  set contentRange(final ContentRangeHeader? value) =>
      assign(Headers.contentRange, value);
  set etag(final ETagHeader? value) => assign(Headers.etag, value);
  set proxyAuthenticate(final AuthenticationHeader? value) =>
      assign(Headers.proxyAuthenticate, value);
  set retryAfter(final RetryAfterHeader? value) =>
      assign(Headers.retryAfter, value);
  set trailer(final List<String>? value) => assign(Headers.trailer, value);
  set vary(final VaryHeader? value) => assign(Headers.vary, value);
  set wwwAuthenticate(final AuthenticationHeader? value) =>
      assign(Headers.wwwAuthenticate, value);
  set contentDisposition(final ContentDispositionHeader? value) =>
      assign(Headers.contentDisposition, value);
  set accept(final AcceptHeader? value) => assign(Headers.accept, value);
  set acceptRanges(final AcceptRangesHeader? value) =>
      assign(Headers.acceptRanges, value);
  set transferEncoding(final TransferEncodingHeader? value) =>
      assign(Headers.transferEncoding, value);
  set cookie(final CookieHeader? value) => assign(Headers.cookie, value);
  set setCookie(final SetCookieHeader? value) =>
      assign(Headers.setCookie, value);
  set strictTransportSecurity(final StrictTransportSecurityHeader? value) =>
      assign(Headers.strictTransportSecurity, value);
  set contentSecurityPolicy(final ContentSecurityPolicyHeader? value) =>
      assign(Headers.contentSecurityPolicy, value);
  set referrerPolicy(final ReferrerPolicyHeader? value) =>
      assign(Headers.referrerPolicy, value);
  set permissionsPolicy(final PermissionsPolicyHeader? value) =>
      assign(Headers.permissionsPolicy, value);
  set accessControlAllowCredentials(final bool? value) =>
      assign(Headers.accessControlAllowCredentials, value);
  set accessControlAllowMethods(final AccessControlAllowMethodsHeader? value) =>
      assign(Headers.accessControlAllowMethods, value);
  set accessControlAllowHeaders(final AccessControlAllowHeadersHeader? value) =>
      assign(Headers.accessControlAllowHeaders, value);
  set clearSiteData(final ClearSiteDataHeader? value) =>
      assign(Headers.clearSiteData, value);
  set secFetchDest(final SecFetchDestHeader? value) =>
      assign(Headers.secFetchDest, value);
  set secFetchMode(final SecFetchModeHeader? value) =>
      assign(Headers.secFetchMode, value);
  set secFetchSite(final SecFetchSiteHeader? value) =>
      assign(Headers.secFetchSite, value);
  set crossOriginResourcePolicy(final CrossOriginResourcePolicyHeader? value) =>
      assign(Headers.crossOriginResourcePolicy, value);
  set crossOriginEmbedderPolicy(final CrossOriginEmbedderPolicyHeader? value) =>
      assign(Headers.crossOriginEmbedderPolicy, value);
  set crossOriginOpenerPolicy(final CrossOriginOpenerPolicyHeader? value) =>
      assign(Headers.crossOriginOpenerPolicy, value);
  set forwarded(final ForwardedHeader? value) =>
      assign(Headers.forwarded, value);
  set xForwardedFor(final XForwardedForHeader? value) =>
      assign(Headers.xForwardedFor, value);

  // We have to repeat these read props, since dart cannot have getter and setter defined on two different
  // classes as extensions
  DateTime? get date => this(Headers.date);
  DateTime? get expires => this(Headers.expires);
  DateTime? get lastModified => this(Headers.lastModified);
  DateTime? get ifModifiedSince => this(Headers.ifModifiedSince);
  DateTime? get ifUnmodifiedSince => this(Headers.ifUnmodifiedSince);
  Uri? get origin => this(Headers.origin);
  String? get server => this(Headers.server);
  List<String>? get via => this(Headers.via);
  FromHeader? get from => this(Headers.from);
  HostHeader? get host => this(Headers.host);
  AcceptEncodingHeader? get acceptEncoding => this(Headers.acceptEncoding);
  AcceptLanguageHeader? get acceptLanguage => this(Headers.acceptLanguage);
  List<String>? get accessControlRequestHeaders =>
      this(Headers.accessControlRequestHeaders);
  Method? get accessControlRequestMethod =>
      this(Headers.accessControlRequestMethod);
  int? get age => this(Headers.age);
  AuthorizationHeader? get authorization => this(Headers.authorization);
  ConnectionHeader? get connection => this(Headers.connection);
  int? get contentLength => this(Headers.contentLength);

  /// The parsed Content-Type header.
  ///
  /// Read-only. Set Content-Type through the body, such as with the
  /// `mimeType` argument of [Body.fromString]. On a request, read
  /// [Body.bodyType] instead. It changes with `copyWith(body: ...)`, and this
  /// header does not.
  ContentTypeHeader? get contentType => this(_contentType);

  ExpectHeader? get expect => this(Headers.expect);
  IfMatchHeader? get ifMatch => this(Headers.ifMatch);
  IfNoneMatchHeader? get ifNoneMatch => this(Headers.ifNoneMatch);
  IfRangeHeader? get ifRange => this(Headers.ifRange);
  int? get maxForwards => this(Headers.maxForwards);
  AuthorizationHeader? get proxyAuthorization =>
      this(Headers.proxyAuthorization);
  RangeHeader? get range => this(Headers.range);
  Uri? get referer => this(Headers.referer);
  String? get userAgent => this(Headers.userAgent);
  TEHeader? get te => this(Headers.te);
  UpgradeHeader? get upgrade => this(Headers.upgrade);
  Uri? get location => this(Headers.location);
  String? get xPoweredBy => this(Headers.xPoweredBy);
  AccessControlAllowOriginHeader? get accessControlAllowOrigin =>
      this(Headers.accessControlAllowOrigin);
  AccessControlExposeHeadersHeader? get accessControlExposeHeaders =>
      this(Headers.accessControlExposeHeaders);
  int? get accessControlMaxAge => this(Headers.accessControlMaxAge);
  Set<Method>? get allow => this(Headers.allow);
  CacheControlHeader? get cacheControl => this(Headers.cacheControl);
  ContentEncodingHeader? get contentEncoding => this(Headers.contentEncoding);
  ContentLanguageHeader? get contentLanguage => this(Headers.contentLanguage);
  Uri? get contentLocation => this(Headers.contentLocation);
  ContentRangeHeader? get contentRange => this(Headers.contentRange);
  ETagHeader? get etag => this(Headers.etag);
  AuthenticationHeader? get proxyAuthenticate =>
      this(Headers.proxyAuthenticate);
  RetryAfterHeader? get retryAfter => this(Headers.retryAfter);
  List<String>? get trailer => this(Headers.trailer);
  VaryHeader? get vary => this(Headers.vary);
  AuthenticationHeader? get wwwAuthenticate => this(Headers.wwwAuthenticate);
  ContentDispositionHeader? get contentDisposition =>
      this(Headers.contentDisposition);
  AcceptHeader? get accept => this(Headers.accept);
  AcceptRangesHeader? get acceptRanges => this(Headers.acceptRanges);
  TransferEncodingHeader? get transferEncoding =>
      this(Headers.transferEncoding);
  CookieHeader? get cookie => this(Headers.cookie);
  SetCookieHeader? get setCookie => this(Headers.setCookie);
  StrictTransportSecurityHeader? get strictTransportSecurity =>
      this(Headers.strictTransportSecurity);
  ContentSecurityPolicyHeader? get contentSecurityPolicy =>
      this(Headers.contentSecurityPolicy);
  ReferrerPolicyHeader? get referrerPolicy => this(Headers.referrerPolicy);
  PermissionsPolicyHeader? get permissionsPolicy =>
      this(Headers.permissionsPolicy);
  bool? get accessControlAllowCredentials =>
      this(Headers.accessControlAllowCredentials);
  AccessControlAllowMethodsHeader? get accessControlAllowMethods =>
      this(Headers.accessControlAllowMethods);
  AccessControlAllowHeadersHeader? get accessControlAllowHeaders =>
      this(Headers.accessControlAllowHeaders);
  ClearSiteDataHeader? get clearSiteData => this(Headers.clearSiteData);
  SecFetchDestHeader? get secFetchDest => this(Headers.secFetchDest);
  SecFetchModeHeader? get secFetchMode => this(Headers.secFetchMode);
  SecFetchSiteHeader? get secFetchSite => this(Headers.secFetchSite);
  CrossOriginResourcePolicyHeader? get crossOriginResourcePolicy =>
      this(Headers.crossOriginResourcePolicy);
  CrossOriginEmbedderPolicyHeader? get crossOriginEmbedderPolicy =>
      this(Headers.crossOriginEmbedderPolicy);
  CrossOriginOpenerPolicyHeader? get crossOriginOpenerPolicy =>
      this(Headers.crossOriginOpenerPolicy);
  ForwardedHeader? get forwarded => this(Headers.forwarded);
  XForwardedForHeader? get xForwardedFor => this(Headers.xForwardedFor);
}

const _contentType = HeaderAccessor(
  HeaderName.contentType,
  ContentTypeHeader.codec,
);
