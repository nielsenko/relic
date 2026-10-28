//! The http_load.dart routes on bare hyper, as a floor for the Dart
//! servers. One tokio runtime over every core, HTTP/1.1 keep-alive.
//!
//!   cargo run --release -- 8090
//!   dart run bin/http_load.dart --targets=hyper=http://127.0.0.1:8090

use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::Arc;

use bytes::Bytes;
use http_body_util::Full;
use hyper::body::Incoming;
use hyper::header::{CACHE_CONTROL, CONTENT_TYPE, ETAG};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use rustls_pki_types::pem::PemObject;
use rustls_pki_types::{CertificateDer, PrivateKeyDer};
use tokio::net::TcpListener;
use tokio_rustls::TlsAcceptor;

const ETAG_VALUE: &str = "\"relic-browser-1\"";

fn items() -> String {
    let mut out = String::from("[");
    for i in 0..20 {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&format!(
            "{{\"id\":{i},\"name\":\"item {i}\",\"tags\":[\"new\",\"sale\"],\"price\":{}}}",
            100 + i
        ));
    }
    out.push(']');
    out
}

fn header<'a>(req: &'a Request<Incoming>, name: &str) -> Option<&'a str> {
    req.headers().get(name).and_then(|v| v.to_str().ok())
}

fn cookie<'a>(header: Option<&'a str>, name: &str) -> Option<&'a str> {
    let header = header?;
    header.split(';').find_map(|pair| {
        let (k, v) = pair.split_once('=')?;
        (k.trim() == name).then(|| v.trim())
    })
}

fn json_string(value: Option<&str>) -> String {
    match value {
        None => "null".to_string(),
        Some(s) => {
            let mut out = String::with_capacity(s.len() + 2);
            out.push('"');
            for c in s.chars() {
                match c {
                    '"' => out.push_str("\\\""),
                    '\\' => out.push_str("\\\\"),
                    c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
                    c => out.push(c),
                }
            }
            out.push('"');
            out
        }
    }
}

fn text(body: String) -> Response<Full<Bytes>> {
    Response::builder()
        .header(CONTENT_TYPE, "text/plain; charset=utf-8")
        .body(Full::new(Bytes::from(body)))
        .unwrap()
}

async fn handle(req: Request<Incoming>, items: &'static str) -> Result<Response<Full<Bytes>>, Infallible> {
    let response = match req.uri().path() {
        "/plaintext" => text("Hello, World!".to_string()),
        "/headers" => {
            let agent = header(&req, "user-agent").unwrap_or("");
            let languages = header(&req, "accept-language")
                .map(|v| v.split(',').count())
                .unwrap_or(0);
            let session = cookie(header(&req, "cookie"), "session");
            text(format!(
                "{} {} {}",
                agent.len(),
                languages,
                session.map(str::len).unwrap_or(0)
            ))
        }
        "/browser" => {
            let host = header(&req, "host");
            let session = cookie(header(&req, "cookie"), "session");
            if header(&req, "if-none-match") == Some(ETAG_VALUE) {
                Response::builder()
                    .status(StatusCode::NOT_MODIFIED)
                    .header(ETAG, ETAG_VALUE)
                    .body(Full::new(Bytes::new()))
                    .unwrap()
            } else {
                let body = format!(
                    "{{\"host\":{},\"session\":{},\"items\":{}}}",
                    json_string(host),
                    json_string(session),
                    items
                );
                Response::builder()
                    .header(CONTENT_TYPE, "application/json; charset=utf-8")
                    .header(ETAG, ETAG_VALUE)
                    .header(CACHE_CONTROL, "private, max-age=60")
                    .body(Full::new(Bytes::from(body)))
                    .unwrap()
            }
        }
        _ => Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(Full::new(Bytes::new()))
            .unwrap(),
    };
    Ok(response)
}

fn tls_acceptor(cert_path: &str, key_path: &str) -> Result<TlsAcceptor, Box<dyn std::error::Error + Send + Sync>> {
    let certs = CertificateDer::pem_file_iter(cert_path)?.collect::<Result<Vec<_>, _>>()?;
    let key = PrivateKeyDer::from_pem_file(key_path)?;
    let config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)?;
    Ok(TlsAcceptor::from(Arc::new(config)))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let args: Vec<String> = std::env::args().collect();
    let port: u16 = args.get(1).map(|p| p.parse()).transpose()?.unwrap_or(8090);
    let acceptor = match (args.get(2), args.get(3)) {
        (Some(cert), Some(key)) => Some(tls_acceptor(cert, key)?),
        (Some(_), None) => return Err("key path missing".into()),
        _ => None,
    };
    let items: &'static str = Box::leak(items().into_boxed_str());
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let listener = TcpListener::bind(addr).await?;
    println!("listening on {}://{addr}/", if acceptor.is_some() { "https" } else { "http" });
    loop {
        let (stream, _) = listener.accept().await?;
        let acceptor = acceptor.clone();
        tokio::spawn(async move {
            let service = service_fn(move |req| handle(req, items));
            let result = match acceptor {
                None => http1::Builder::new().serve_connection(TokioIo::new(stream), service).await,
                Some(acceptor) => match acceptor.accept(stream).await {
                    Ok(tls) => http1::Builder::new().serve_connection(TokioIo::new(tls), service).await,
                    Err(err) => {
                        eprintln!("tls: {err}");
                        return;
                    }
                },
            };
            if let Err(err) = result {
                eprintln!("connection: {err}");
            }
        });
    }
}
